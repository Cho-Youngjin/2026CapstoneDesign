import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/network/api_client.dart';
import '../models/chat_message.dart';

/// 서버 STOMP 연결(`/ws`)을 앱 전체에서 하나만 쓰기 위한 추상화 (Plan D Task 4).
///
/// 채팅(Task 4·7)과 R3의 위치공유(Task 9)가 같은 연결을 공유한다 — 연결이 둘이면 토큰 갱신·재연결
/// 처리도 두 벌이 된다. 화면 코드는 이 인터페이스만 보고, 테스트는 가짜 구현으로 바꾼다.
abstract class ChatSocket {
  /// [destination]을 구독한다. 반환된 스트림을 listen하는 동안 구독이 유지되고, 모든 구독자가
  /// cancel하면 서버 구독도 해제된다. 연결이 끊겼다 다시 붙으면 자동으로 다시 구독한다.
  Stream<Map<String, dynamic>> subscribe(String destination);

  /// [destination]으로 보낸다. 연결이 없으면 버린다 — 위치처럼 몇 초마다 다시 오는 값에만 쓴다.
  /// 채팅 메시지는 성공 여부를 알아야 하므로 STOMP가 아니라 REST(ChatApi.sendText)로 보낸다.
  void send(String destination, Map<String, dynamic> body);

  /// 서버에 접속되고 구독이 다시 걸릴 때마다(첫 접속 포함) 이벤트가 온다. 접속되기 전이나 끊긴 동안
  /// 온 메시지는 실시간으로 오지 않으므로, 듣는 쪽이 이때 REST로 빈 구간을 채워야 한다.
  Stream<void> get connected;
}

/// 방의 새 메시지 스트림 (`/topic/rooms/{roomId}/messages`).
Stream<ChatMessage> roomMessages(ChatSocket socket, int roomId) =>
    socket.subscribe('/topic/rooms/$roomId/messages').map(ChatMessage.fromJson);

/// REST 주소(`http://host:8080`)에서 STOMP 주소(`ws://host:8080/ws`)를 만든다.
String webSocketUrl(String apiBaseUrl) {
  final base = apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;
  final ws = base.startsWith('https://')
      ? 'wss://${base.substring('https://'.length)}'
      : base.startsWith('http://')
          ? 'ws://${base.substring('http://'.length)}'
          : base;
  return '$ws/ws';
}

/// 재연결 대기 시간: 1, 2, 4, 8, 16, 30, 30… 초. 서버가 꺼져 있을 때 계속 두드리지 않게 한다.
Duration reconnectDelay(int failedAttempts) =>
    Duration(seconds: math.min(30, 1 << math.min(failedAttempts, 5)));

class _Subscription {
  _Subscription(this.controller);

  final StreamController<Map<String, dynamic>> controller;

  /// 현재 연결에서의 서버 구독 해제 함수. 연결이 없으면 null.
  StompUnsubscribe? unsubscribe;
}

/// `stomp_dart_client`를 쓰는 실제 구현.
///
/// <b>재연결을 라이브러리에 맡기지 않는 이유</b>: 라이브러리의 자동 재연결은 처음 접속할 때 넣은
/// 헤더(Firebase ID Token)를 그대로 재사용한다. 토큰은 1시간이면 만료되므로, 오래 켜 둔 앱이
/// 재연결하면 서버가 거부한다. 그래서 자동 재연결은 끄고(reconnectDelay: 0), 끊길 때마다
/// <b>새 토큰으로 클라이언트를 새로 만든다.</b> 이때 라이브러리는 구독을 복원하지 않으므로,
/// 구독 목록을 여기서 들고 있다가 접속될 때마다 다시 구독한다.
///
/// 앱이 백그라운드로 가면 연결을 끊고([pause]), 돌아오면 다시 붙인다([resume]) — 배터리를 아끼고,
/// 돌아왔을 때 [connected]로 빈 구간을 채우게 한다.
///
/// <b>주의 — 연결 하나를 모두가 공유한다.</b> 서버는 멤버가 아닌 방을 구독하면 ERROR를 보내고 연결
/// 자체를 끊는다. 그러면 같은 연결의 다른 구독(다른 채팅방, 위치공유)도 함께 끊기고, 재연결 때 같은
/// 구독을 다시 걸어 또 끊기는 일이 반복된다. 그래서 <b>구독은 멤버임이 확인된 방에만 건다</b>
/// (ChatRoomController가 REST 조회 성공 뒤에 구독하는 이유). 재연결 간격을 늘려 가는 것은 마지막 안전장치다.
class StompChatSocket implements ChatSocket {
  StompChatSocket({required this.url, required this.tokenSupplier});

  final String url;
  final Future<String?> Function() tokenSupplier;

  final Map<String, _Subscription> _subscriptions = {};
  final StreamController<void> _connected = StreamController<void>.broadcast();

  StompClient? _client;
  bool _connecting = false;
  bool _paused = false;
  bool _disposed = false;
  int _failedAttempts = 0;
  Timer? _retryTimer;

  @override
  Stream<void> get connected => _connected.stream;

  bool get _isConnected => _client?.connected ?? false;

  @override
  Stream<Map<String, dynamic>> subscribe(String destination) {
    final existing = _subscriptions[destination];
    if (existing != null) return existing.controller.stream;

    late final _Subscription sub;
    sub = _Subscription(StreamController<Map<String, dynamic>>.broadcast(
      onListen: () {
        if (_isConnected) {
          _subscribeOnServer(destination, sub);
        } else {
          _ensureConnected();
        }
      },
      onCancel: () {
        sub.unsubscribe?.call();
        _subscriptions.remove(destination);
        sub.controller.close();
        // 구독이 하나도 없으면 연결을 유지할 이유가 없다.
        if (_subscriptions.isEmpty) _disconnect();
      },
    ));
    _subscriptions[destination] = sub;
    return sub.controller.stream;
  }

  @override
  void send(String destination, Map<String, dynamic> body) {
    final client = _client;
    if (client == null || !client.connected) return;
    client.send(destination: destination, body: jsonEncode(body));
  }

  /// 앱이 백그라운드로 갔을 때.
  void pause() {
    _paused = true;
    _disconnect();
  }

  /// 앱이 다시 앞으로 왔을 때. 구독이 남아 있으면 다시 연결한다.
  void resume() {
    _paused = false;
    if (_subscriptions.isNotEmpty) _ensureConnected();
  }

  void dispose() {
    _disposed = true;
    _disconnect();
    for (final sub in _subscriptions.values) {
      sub.controller.close();
    }
    _subscriptions.clear();
    _connected.close();
  }

  Future<void> _ensureConnected() async {
    if (_disposed || _paused || _connecting || _isConnected || _subscriptions.isEmpty) return;
    _retryTimer?.cancel();
    _connecting = true;
    try {
      final token = await tokenSupplier();
      if (token == null || _disposed || _paused) {
        _connecting = false;
        if (token == null) _scheduleRetry();
        return;
      }
      // 콜백이 "어느 클라이언트의 것인지"를 알 수 있게 클라이언트를 붙잡아 둔다. 백그라운드↔포그라운드를
      // 빠르게 오가면, 이미 버린 이전 클라이언트의 '닫힘' 콜백이 새 연결이 생긴 뒤에 늦게 도착할 수 있다.
      // 그 콜백이 새 연결을 지워 버리지 않도록 현재 클라이언트의 콜백만 처리한다.
      late final StompClient client;
      client = StompClient(
        config: StompConfig(
          url: url,
          stompConnectHeaders: {'Authorization': 'Bearer $token'},
          reconnectDelay: Duration.zero, // 재연결은 여기서 직접 한다(클래스 주석 참고)
          onConnect: (_) => _onConnected(client),
          onWebSocketDone: () => _onClosed(client),
          onWebSocketError: (error) => debugPrint('채팅 소켓 오류: $error'),
          // 비멤버 방 구독 등으로 서버가 ERROR를 보내면 곧이어 연결이 닫히고 _onClosed가 불린다.
          onStompError: (frame) =>
              debugPrint('채팅 소켓 STOMP 오류: ${frame.headers['message'] ?? frame.body}'),
        ),
      );
      _client = client;
      client.activate();
    } catch (e) {
      debugPrint('채팅 소켓 연결 실패: $e');
      _connecting = false;
      _scheduleRetry();
    }
  }

  void _onConnected(StompClient client) {
    if (!identical(client, _client)) return; // 이미 버린 클라이언트
    _connecting = false;
    _failedAttempts = 0;
    _subscriptions.forEach(_subscribeOnServer);
    _connected.add(null);
  }

  void _onClosed(StompClient client) {
    if (!identical(client, _client)) return; // 이미 버린 클라이언트 — 새 연결을 건드리지 않는다
    _connecting = false;
    _client = null;
    for (final sub in _subscriptions.values) {
      sub.unsubscribe = null;
    }
    if (!_disposed && !_paused && _subscriptions.isNotEmpty) _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_disposed || _paused) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(reconnectDelay(_failedAttempts++), _ensureConnected);
  }

  void _subscribeOnServer(String destination, _Subscription sub) {
    final client = _client;
    if (client == null || sub.unsubscribe != null) return;
    sub.unsubscribe = client.subscribe(
      destination: destination,
      callback: (frame) {
        final body = frame.body;
        if (body == null || sub.controller.isClosed) return;
        try {
          sub.controller.add(jsonDecode(body) as Map<String, dynamic>);
        } catch (e) {
          debugPrint('채팅 소켓 메시지 파싱 실패: $e');
        }
      },
    );
  }

  void _disconnect() {
    _retryTimer?.cancel();
    final client = _client;
    _client = null;
    _connecting = false;
    for (final sub in _subscriptions.values) {
      sub.unsubscribe = null;
    }
    client?.deactivate();
  }
}

/// 앱 전체가 공유하는 STOMP 연결. 앱 생명주기에 맞춰 백그라운드에서는 끊고 앞으로 오면 다시 붙인다.
/// 로그인 계정이 바뀌면(uid) 새 연결을 만든다 — 이전 계정의 토큰·구독이 남지 않게.
final chatSocketProvider = Provider<ChatSocket>((ref) {
  ref.watch(currentUidProvider);
  final auth = ref.watch(authRepositoryProvider);
  final socket = StompChatSocket(
    url: webSocketUrl(resolveBaseUrl(isAndroid: !kIsWeb && Platform.isAndroid)),
    tokenSupplier: auth.currentIdToken,
  );
  final lifecycle = AppLifecycleListener(onPause: socket.pause, onResume: socket.resume);
  ref.onDispose(() {
    lifecycle.dispose();
    socket.dispose();
  });
  return socket;
});
