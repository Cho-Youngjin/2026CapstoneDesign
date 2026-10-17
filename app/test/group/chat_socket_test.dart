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
}
