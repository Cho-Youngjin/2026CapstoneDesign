import 'dart:async';
import 'dart:io';

import 'package:app/features/group/data/chat_socket.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('webSocketUrl', () {
    test('http는 ws, https는 wss로 바꾸고 /ws를 붙인다', () {
      expect(webSocketUrl('http://10.0.2.2:8080'), 'ws://10.0.2.2:8080/ws');
      expect(webSocketUrl('https://api.example.com'), 'wss://api.example.com/ws');
    });

    test('끝에 / 가 있어도 한 번만 붙인다', () {
      expect(webSocketUrl('http://192.168.0.5:8080/'), 'ws://192.168.0.5:8080/ws');
    });
  });

  test('재연결 대기는 1초부터 두 배씩 늘고 30초에서 멈춘다', () {
    expect([for (var i = 0; i < 8; i++) reconnectDelay(i).inSeconds], [1, 2, 4, 8, 16, 30, 30, 30]);
  });

  group('StompChatSocket', () {
    test('처음 접속이 실패해도(서버 꺼짐) 포기하지 않고 다시 접속을 시도한다', () async {
      // 비어 있는 포트를 하나 잡았다가 닫는다 — 그 주소로의 접속은 곧바로 거부된다.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      var tokenRequests = 0;
      final retried = Completer<void>();
      final socket = StompChatSocket(
        url: 'ws://127.0.0.1:$port/ws',
        tokenSupplier: () async {
          // 접속을 새로 시도할 때마다 토큰을 새로 받는다 — 두 번째 요청이 곧 재시도다.
          if (++tokenRequests == 2 && !retried.isCompleted) retried.complete();
          return 'token';
        },
      );
      addTearDown(socket.dispose);

      final sub = socket.subscribe('/topic/rooms/1/messages').listen((_) {});
      addTearDown(sub.cancel);

      // 첫 재시도 대기는 1초다(reconnectDelay(0)).
      await retried.future.timeout(const Duration(seconds: 5),
          onTimeout: () => fail('접속 실패 뒤 재시도가 예약되지 않았다 (토큰 요청 $tokenRequests회)'));
    });
  });
}
