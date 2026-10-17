import 'dart:async';

import 'package:app/features/group/data/chat_socket.dart';

/// 서버 없이 실시간 수신을 흉내 내는 가짜 소켓. [emit]으로 "서버가 보낸 메시지"를,
/// [emitConnected]로 "서버에 (다시) 접속됨"을 흉내 낸다.
class FakeChatSocket implements ChatSocket {
  final Map<String, StreamController<Map<String, dynamic>>> _topics = {};
  final StreamController<void> _connected = StreamController<void>.broadcast();
  final List<({String destination, Map<String, dynamic> body})> sent = [];

  /// 지금 누군가 구독 중인 목적지.
  Set<String> get activeSubscriptions =>
      {for (final e in _topics.entries) if (e.value.hasListener) e.key};

  StreamController<Map<String, dynamic>> _topic(String destination) =>
      _topics.putIfAbsent(destination, StreamController<Map<String, dynamic>>.broadcast);

  @override
  Stream<Map<String, dynamic>> subscribe(String destination) => _topic(destination).stream;

  @override
  void send(String destination, Map<String, dynamic> body) =>
      sent.add((destination: destination, body: body));

  @override
  Stream<void> get connected => _connected.stream;

  void emit(String destination, Map<String, dynamic> body) => _topic(destination).add(body);

  void emitConnected() => _connected.add(null);

  void dispose() {
    for (final c in _topics.values) {
      c.close();
    }
    _connected.close();
  }
}
