import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import '../models/room.dart';
import 'chat_api.dart';
import 'chat_socket.dart';

/// 올리는 중이거나 올리지 못한 사진(Plan D Task 6). 서버 메시지가 되기 전이라 id가 없어 [localId]로 구분한다.
@immutable
class PendingImage {
  const PendingImage({
    required this.localId,
    required this.clientId,
    required this.bytes,
    this.failed = false,
    this.error,
  });

  final int localId;

  /// 서버에 함께 보내는 업로드 id. 다시 시도해도 같은 값을 써서 서버가 한 번만 저장하게 한다.
  final String clientId;
  final Uint8List bytes;

  /// 올리지 못했다. 화면이 [다시 시도]·[지우기]를 보여준다.
  final bool failed;

  /// 다시 시도해도 안 되는 이유(너무 큼, 형식). 연결 오류처럼 다시 해 볼 만한 실패는 null.
  final String? error;
}

/// 채팅방 화면 상태.
@immutable
class ChatRoomState {
  const ChatRoomState({
    this.messages = const [],
    this.loading = true,
    this.loadError,
    this.hasMore = true,
    this.loadingMore = false,
    this.sending = false,
    this.pendingImages = const [],
  });

  /// 아직 서버 메시지가 되지 않은 내 사진, 보낸 순서. 화면은 목록 맨 아래(가장 최신 자리)에 둔다.
  final List<PendingImage> pendingImages;

  /// 최신순(id 내림차순). 화면은 `ListView(reverse: true)`라 첫 항목이 맨 아래에 온다.
  final List<ChatMessage> messages;

  /// 처음 메시지를 불러오는 중.
  final bool loading;

  /// 처음 불러오기에 실패한 이유. 이미 메시지가 있는 상태에서의 실패(이전 페이지 등)는 여기에 넣지 않는다.
  final Object? loadError;

  /// 더 오래된 메시지가 남아 있을 수 있다.
  final bool hasMore;
  final bool loadingMore;
  final bool sending;

  ChatRoomState copyWith({
    List<ChatMessage>? messages,
    bool? loading,
    Object? loadError,
    bool clearLoadError = false,
    bool? hasMore,
    bool? loadingMore,
    bool? sending,
    List<PendingImage>? pendingImages,
  }) {
    return ChatRoomState(
      messages: messages ?? this.messages,
      loading: loading ?? this.loading,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      sending: sending ?? this.sending,
      pendingImages: pendingImages ?? this.pendingImages,
    );
  }
}

/// 채팅방 하나의 메시지 목록을 관리한다 (Plan D Task 4).
///
/// <b>두 경로로 오는 메시지를 하나로 합친다.</b> 메시지는 REST(처음 목록, 이전 페이지, 내가 보낸 것의
/// 응답)와 STOMP 실시간 구독 양쪽에서 온다. 내가 보낸 메시지는 POST 응답과 브로드캐스트로 <b>두 번</b>
/// 도착하고, 구독 직후 받은 목록과 실시간 메시지도 겹칠 수 있다. 그래서 모든 메시지를 [_merge]로
/// 넣고 id로 중복을 걸러낸다 — 어느 쪽이 먼저 오든 결과가 같다.
///
/// <b>목록을 먼저 불러오고, 성공한 뒤에만 구독한다.</b> REST 조회가 성공했다는 것은 서버가 이 방의
/// 멤버임을 확인했다는 뜻이다. 멤버가 아닌 방을 구독하면 서버가 공유 연결을 통째로 끊어 다른 채팅방과
/// 위치공유까지 끊기므로(ChatSocket 주석 참고), 확인 전에는 구독하지 않는다.
///
/// 이 순서에는 "목록을 받은 직후 ~ 구독이 서버에 걸리기 전"에 온 메시지를 놓칠 틈이 생긴다. 그래서
/// 구독 직후, 그리고 소켓이 접속될 때마다([ChatSocket.connected]) REST로 빈 구간을 다시 채운다.
/// 겹쳐 받은 메시지는 id로 걸러진다.
///
/// 화면을 떠나면(autoDispose) 구독도 해제된다.
class ChatRoomController extends Notifier<ChatRoomState> {
  ChatRoomController(this.roomId);

  final int roomId;

  static const pageSize = 30;

  /// 재연결 후 빈 구간을 채울 때 최대 몇 페이지까지 거슬러 올라갈지.
  /// 오래 끊겨 있어 이보다 많이 쌓였으면, 그보다 오래된 것은 위로 스크롤해서 불러오면 된다.
  static const maxGapPages = 5;

  ChatApi get _api => ref.read(chatApiProvider);

  /// [_fillGap]이 목록을 줄일 때마다 1씩 오른다. 줄이기 전에 시작한 [loadOlder]는 이제 없는 꼬리를
  /// 커서로 삼았으므로, 응답이 늦게 와도 버린다(합치면 버린 오래된 메시지와 함께 구멍이 다시 생긴다).
  int _windowGeneration = 0;

  StreamSubscription<ChatMessage>? _messageSub;
  StreamSubscription<void>? _connectedSub;

  @override
  ChatRoomState build() {
    ref.onDispose(() {
      _messageSub?.cancel();
      _connectedSub?.cancel();
    });
    // build 안에서는 state를 바꿀 수 없으므로 첫 조회는 다음 이벤트 루프에서 시작한다.
    Future.microtask(_loadLatest);
    return const ChatRoomState();
  }

  /// 처음 목록. 성공하면(= 멤버임이 확인되면) 실시간 구독을 시작한다. 실패하면 [retry]로 다시 부른다.
  Future<void> _loadLatest() async {
    try {
      final page = await _api.messages(roomId, size: pageSize);
      if (!ref.mounted) return;
      _merge(page);
      state = state.copyWith(loading: false, clearLoadError: true, hasMore: page.length == pageSize);
      _startRealtime();
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, loadError: e);
    }
  }

  void _startRealtime() {
    if (_messageSub != null) return; // 이미 구독 중(재시도로 다시 불린 경우)
    final socket = ref.read(chatSocketProvider);
    _connectedSub = socket.connected.listen((_) => _fillGap());
    _messageSub = roomMessages(socket, roomId).listen((m) => _merge([m]));
    // 연결이 이미 열려 있으면 connected 이벤트가 따로 오지 않으므로, 조회~구독 사이의 틈을 지금 메운다.
    _fillGap();
  }

  Future<void> retry() async {
    state = state.copyWith(loading: true, clearLoadError: true);
    await _loadLatest();
  }

  /// 위로 스크롤해서 더 오래된 메시지를 불러온다.
  Future<void> loadOlder() async {
    if (state.loading || state.loadingMore || !state.hasMore || state.messages.isEmpty) return;
    state = state.copyWith(loadingMore: true);
    final generation = _windowGeneration;
    try {
      final page = await _api.messages(roomId, before: state.messages.last.id, size: pageSize);
      if (!ref.mounted) return;
      if (generation != _windowGeneration) {
        // 기다리는 동안 목록이 줄었다 — 다시 스크롤하면 새 꼬리부터 불러온다.
        state = state.copyWith(loadingMore: false);
        return;
      }
      _merge(page);
      state = state.copyWith(loadingMore: false, hasMore: page.length == pageSize);
    } catch (e) {
      if (!ref.mounted) return;
      // 이전 페이지 실패는 화면 전체 오류로 만들지 않는다. 다시 스크롤하면 재시도된다.
      debugPrint('이전 메시지 불러오기 실패: $e');
      state = state.copyWith(loadingMore: false);
    }
  }

  /// 텍스트를 보낸다. 성공하면 true — 화면이 입력창을 비운다.
  /// 실패하면 false를 돌려주고 입력 내용은 화면에 그대로 남겨, 사용자가 다시 보낼 수 있게 한다.
  Future<bool> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.sending) return false;
    state = state.copyWith(sending: true);
    try {
      final message = await _api.sendText(roomId, trimmed);
      if (!ref.mounted) return true;
      _merge([message]);
      state = state.copyWith(sending: false);
      return true;
    } catch (e) {
      debugPrint('메시지 전송 실패: $e');
      if (ref.mounted) state = state.copyWith(sending: false);
      return false;
    }
  }

  int _nextLocalId = 0;

  /// 사진을 보낸다(Plan D Task 6). 올리는 동안 [ChatRoomState.pendingImages]에 자리표시를 두고, 성공하면 그 자리를
  /// 서버 메시지로 바꾼다. 실패하면 자리표시를 실패로 남겨 [retryImage]·[discardImage]를 고르게 한다 — 사진은 다시
  /// 고르기 번거로우므로 글자처럼 그냥 버리지 않는다.
  Future<void> sendImage(Uint8List bytes) async {
    final pending = PendingImage(localId: _nextLocalId++, clientId: _newClientId(), bytes: bytes);
    state = state.copyWith(pendingImages: [...state.pendingImages, pending]);
    await _upload(pending);
  }

  /// 같은 사진·같은 업로드 id로 다시 올린다. 앞선 요청이 서버에는 저장됐는데 응답만 끊긴 경우라도, 서버가 같은 id를
  /// 알아보고 그 메시지를 돌려주므로 사진이 두 장이 되지 않는다.
  Future<void> retryImage(int localId) async {
    final pending = state.pendingImages.where((p) => p.localId == localId).firstOrNull;
    if (pending == null || !pending.failed) return;
    final retrying = PendingImage(localId: localId, clientId: pending.clientId, bytes: pending.bytes);
    _replacePending(retrying);
    await _upload(retrying);
  }

  static final _random = Random.secure();

  /// 서버가 받는 형식(영문·숫자·하이픈 64자 이하)의 무작위 id. 128비트라 겹칠 걱정이 없다.
  static String _newClientId() =>
      [for (var i = 0; i < 16; i++) _random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();

  void discardImage(int localId) {
    state = state.copyWith(pendingImages: [for (final p in state.pendingImages) if (p.localId != localId) p]);
  }

  Future<void> _upload(PendingImage pending) async {
    final localId = pending.localId;
    try {
      final message = await _api.sendImage(roomId, pending.bytes, clientId: pending.clientId);
      if (!ref.mounted) return;
      discardImage(localId);
      _merge([message]);
    } catch (e) {
      debugPrint('사진 전송 실패: $e');
      if (!ref.mounted) return;
      final reason = switch (e) {
        ChatImageTooLargeException() => '사진이 너무 커서 보낼 수 없어요.',
        UnsupportedChatImageException() => '보낼 수 없는 사진 형식이에요.',
        _ => null,
      };
      _replacePending(PendingImage(
        localId: localId,
        clientId: pending.clientId,
        bytes: pending.bytes,
        failed: true,
        error: reason,
      ));
    }
  }

  void _replacePending(PendingImage updated) {
    state = state.copyWith(pendingImages: [
      for (final p in state.pendingImages) p.localId == updated.localId ? updated : p,
    ]);
  }

  /// 연결이 끊겼던 동안의 메시지를 REST로 받아 채운다. 최신 페이지부터 거슬러 올라가며,
  /// 이미 가진 메시지를 만나면 멈춘다(그 앞은 빈 구간이 아니다). [maxGapPages]까지 가도 못 만나면
  /// 목록을 이번에 받은 구간으로 줄여, 목록 중간에 구멍이 남지 않게 한다.
  Future<void> _fillGap() async {
    final knownIds = {for (final m in state.messages) m.id};
    if (knownIds.isEmpty) {
      await _loadLatest();
      return;
    }
    int? before;
    try {
      for (var i = 0; i < maxGapPages; i++) {
        final page = await _api.messages(roomId, before: before, size: pageSize);
        if (!ref.mounted) return;
        _merge(page);
        final reachedKnown = page.any((m) => knownIds.contains(m.id));
        if (reachedKnown || page.length < pageSize) return;
        before = page.last.id;
      }
      // 한도까지 거슬러 올라가도 이미 가진 메시지에 닿지 못했다 — 그 아래에 아직 못 받은 구간이 남아 있다.
      // 그 구간보다 오래된(원래 갖고 있던) 메시지를 목록에서 빼서, 위로 스크롤하면 [loadOlder]가 이번에 받은
      // 가장 오래된 메시지 바로 아래부터 이어서 불러오게 한다. 뺀 메시지는 스크롤하면 다시 받는다.
      final oldestFetched = before;
      if (oldestFetched != null) {
        _windowGeneration++;
        state = state.copyWith(
          messages: [for (final m in state.messages) if (m.id >= oldestFetched) m],
          hasMore: true,
        );
      }
    } catch (e) {
      debugPrint('재연결 후 메시지 보충 실패: $e');
    }
  }

  void _merge(List<ChatMessage> incoming) {
    if (incoming.isEmpty) return;
    final byId = {for (final m in state.messages) m.id: m};
    for (final m in incoming) {
      if (m.roomId == roomId) byId[m.id] = m;
    }
    final merged = byId.values.toList()..sort((a, b) => b.id.compareTo(a.id));
    state = state.copyWith(messages: merged);
  }
}

final chatRoomControllerProvider =
    NotifierProvider.autoDispose.family<ChatRoomController, ChatRoomState, int>(ChatRoomController.new);

/// 방 상세(제목, 멤버 이름). 화면을 떠나면 버린다.
/// `retry`를 끈다: 404(멤버가 아님) 같은 오류를 바로 보여준다.
final roomDetailProvider = FutureProvider.autoDispose.family<RoomDetail, int>(
  (ref, roomId) => ref.watch(chatApiProvider).roomDetail(roomId),
  retry: (_, _) => null,
);
