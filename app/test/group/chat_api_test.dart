import 'dart:typed_data';

import 'package:app/features/group/data/chat_api.dart';
import 'package:app/features/group/models/chat_message.dart';
import 'package:app/features/group/models/room.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_http_client_adapter.dart';

const _detailJson = '''
{
  "id": 12,
  "type": "GROUP",
  "name": "도쿄 여행",
  "inviteCode": "ABC234",
  "members": [
    {"uid": "uid-a", "displayName": "성주", "photoUrl": null, "lastReadMessageId": null}
  ]
}
''';

ChatApi _api(StubHttpClientAdapter adapter) =>
    ChatApi(Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter);

void main() {
  test('createRoom이 이름을 POST /api/rooms로 보내고 방 상세를 파싱한다', () async {
    final adapter = StubHttpClientAdapter(path: '/api/rooms', statusCode: 201, body: _detailJson);

    final room = await _api(adapter).createRoom('도쿄 여행');

    expect(room.id, 12);
    expect(room.inviteCode, 'ABC234');
    expect(room.members.single.label, '성주');
    expect(adapter.lastRequest!.method, 'POST');
    expect(adapter.lastRequest!.path, '/api/rooms');
    expect(adapter.lastRequest!.data, {'name': '도쿄 여행'});
  });

  test('joinRoom이 초대 코드를 POST /api/rooms/join으로 보낸다', () async {
    final adapter = StubHttpClientAdapter(path: '/api/rooms/join', statusCode: 200, body: _detailJson);

    final room = await _api(adapter).joinRoom('ABC234');

    expect(room.id, 12);
    expect(adapter.lastRequest!.method, 'POST');
    expect(adapter.lastRequest!.data, {'inviteCode': 'ABC234'});
  });

  group('사진 (Plan D Task 6)', () {
    const imageMessageJson = '''
{"id": 41, "roomId": 1, "senderUid": "uid-a", "type": "IMAGE", "text": null,
 "imageUrl": "/api/rooms/1/images/41", "createdAt": "2026-10-19T09:00:00+09:00"}
''';

    test('sendImage가 사진을 multipart의 file로 POST /api/rooms/{id}/images에 올린다', () async {
      final adapter = StubHttpClientAdapter(path: '/api/rooms/1/images', statusCode: 201, body: imageMessageJson);

      final message = await _api(adapter).sendImage(1, Uint8List.fromList([0xFF, 0xD8, 0xFF]));

      expect(message.type, MessageType.image);
      expect(message.imageUrl, '/api/rooms/1/images/41');
      expect(adapter.lastRequest!.method, 'POST');
      final form = adapter.lastRequest!.data as FormData;
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.length, 3);
    });

    test('너무 큰 사진(413)과 지원하지 않는 형식(415)은 알아볼 수 있는 예외로 바꾼다', () async {
      final tooBig = StubHttpClientAdapter(path: '/api/rooms/1/images', statusCode: 413, body: '');
      final unsupported = StubHttpClientAdapter(path: '/api/rooms/1/images', statusCode: 415, body: '');

      expect(() => _api(tooBig).sendImage(1, Uint8List(1)), throwsA(isA<ChatImageTooLargeException>()));
      expect(() => _api(unsupported).sendImage(1, Uint8List(1)), throwsA(isA<UnsupportedChatImageException>()));
    });

    test('비멤버(404)가 사진을 올리면 RoomNotFoundException', () async {
      final adapter = StubHttpClientAdapter(path: '/api/rooms/1/images', statusCode: 404, body: '');

      expect(() => _api(adapter).sendImage(1, Uint8List(1)), throwsA(isA<RoomNotFoundException>()));
    });

    test('imageBytes가 사진 주소를 받아 바이트로 돌려준다(토큰은 apiClient가 붙인다)', () async {
      final adapter = StubHttpClientAdapter(path: '/api/rooms/1/images/41', statusCode: 200, body: 'abc');

      final bytes = await _api(adapter).imageBytes('/api/rooms/1/images/41');

      expect(bytes, [97, 98, 99]);
      expect(adapter.lastRequest!.method, 'GET');
    });
  });

  test('openDm이 상대 uid를 POST /api/rooms/dm으로 보내고 DM 방을 파싱한다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/rooms/dm',
      statusCode: 200,
      body: '''
{"id": 30, "type": "DM", "name": null, "inviteCode": null,
 "members": [{"uid": "uid-a", "displayName": "성주"}, {"uid": "uid-b", "displayName": "민준"}]}
''',
    );

    final room = await _api(adapter).openDm('uid-b');

    expect(room.id, 30);
    expect(room.type, RoomType.dm);
    expect(room.members.map((m) => m.uid), ['uid-a', 'uid-b']);
    expect(adapter.lastRequest!.method, 'POST');
    expect(adapter.lastRequest!.data, {'peerUid': 'uid-b'});
  });

  test('같은 그룹이 아닌 상대(404)에게 DM을 열면 RoomNotFoundException으로 바꾼다', () async {
    final adapter = StubHttpClientAdapter(path: '/api/rooms/dm', statusCode: 404, body: '');

    expect(() => _api(adapter).openDm('uid-x'), throwsA(isA<RoomNotFoundException>()));
  });

  test('방 목록의 DM은 상대를 dmPeer로 읽고 제목도 상대 이름이다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/rooms',
      statusCode: 200,
      body: '''
[{"id": 30, "type": "DM", "name": null, "inviteCode": null, "memberCount": 2,
  "lastMessagePreview": null, "lastMessageAt": null, "unreadCount": 0,
  "dmPeer": {"uid": "uid-b", "displayName": "민준", "photoUrl": null, "lastReadMessageId": null}}]
''',
    );

    final room = (await _api(adapter).myRooms()).single;

    expect(room.type, RoomType.dm);
    expect(room.dmPeer!.uid, 'uid-b');
    expect(room.title, '민준');
  });

  test('없는 초대 코드(404)는 RoomNotFoundException으로 바꾼다', () async {
    final adapter = StubHttpClientAdapter(path: '/api/rooms/join', statusCode: 404, body: '');

    expect(() => _api(adapter).joinRoom('ZZZZZZ'), throwsA(isA<RoomNotFoundException>()));
  });

  test('myRooms가 GET /api/rooms 목록을 파싱한다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/rooms',
      statusCode: 200,
      body: '''
[
  {"id": 2, "type": "GROUP", "name": "오사카", "inviteCode": "XYZ789", "memberCount": 4,
   "lastMessagePreview": "출발!", "lastMessageAt": "2026-10-16T09:00:00+09:00", "unreadCount": 0, "dmPeer": null},
  {"id": 1, "type": "GROUP", "name": "도쿄", "inviteCode": "ABC234", "memberCount": 1,
   "lastMessagePreview": null, "lastMessageAt": null, "unreadCount": 0, "dmPeer": null}
]
''',
    );

    final rooms = await _api(adapter).myRooms();

    expect(rooms.map((r) => r.name), ['오사카', '도쿄']);
    expect(rooms.first.type, RoomType.group);
    expect(adapter.lastRequest!.method, 'GET');
  });

  test('roomDetail이 GET /api/rooms/{id}를 부른다', () async {
    final adapter = StubHttpClientAdapter(path: '/api/rooms/12', statusCode: 200, body: _detailJson);

    final room = await _api(adapter).roomDetail(12);

    expect(room.name, '도쿄 여행');
    expect(adapter.lastRequest!.path, '/api/rooms/12');
  });

  test('roomDetail이 404면 RoomNotFoundException이다 (멤버가 아니거나 없는 방)', () async {
    final adapter = StubHttpClientAdapter(path: '/api/rooms/99', statusCode: 404, body: '');

    expect(() => _api(adapter).roomDetail(99), throwsA(isA<RoomNotFoundException>()));
  });

  test('putProfile이 이름·사진을 PUT /api/me/profile로 보낸다 (null도 그대로)', () async {
    final adapter = StubHttpClientAdapter(path: '/api/me/profile', statusCode: 204, body: '');

    await _api(adapter).putProfile(displayName: '성주', photoUrl: null);

    expect(adapter.lastRequest!.method, 'PUT');
    expect(adapter.lastRequest!.data, {'displayName': '성주', 'photoUrl': null});
  });

  group('메시지', () {
    const messageJson =
        '{"id": 345, "roomId": 12, "senderUid": "uid-a", "type": "TEXT", "text": "공항 도착!", '
        '"imageUrl": null, "createdAt": "2026-10-17T10:40:12.345+09:00"}';

    test('messages가 GET으로 최신 페이지를 가져온다 (before 없으면 쿼리에도 없다)', () async {
      final adapter = StubHttpClientAdapter(
        path: '/api/rooms/12/messages', statusCode: 200, body: '[$messageJson]');

      final messages = await _api(adapter).messages(12);

      expect(messages.single.id, 345);
      expect(messages.single.text, '공항 도착!');
      expect(messages.single.type, MessageType.text);
      expect(messages.single.createdAt, DateTime.parse('2026-10-17T10:40:12.345+09:00'));
      expect(adapter.lastRequest!.method, 'GET');
      expect(adapter.lastRequest!.queryParameters, {'size': 30});
    });

    test('messages에 before를 주면 쿼리로 보낸다', () async {
      final adapter = StubHttpClientAdapter(path: '/api/rooms/12/messages', statusCode: 200, body: '[]');

      await _api(adapter).messages(12, before: 300, size: 20);

      expect(adapter.lastRequest!.queryParameters, {'size': 20, 'before': 300});
    });

    test('sendText가 POST로 보내고 저장된 메시지를 돌려준다', () async {
      final adapter = StubHttpClientAdapter(
        path: '/api/rooms/12/messages', statusCode: 201, body: messageJson);

      final message = await _api(adapter).sendText(12, '공항 도착!');

      expect(message.id, 345);
      expect(adapter.lastRequest!.method, 'POST');
      expect(adapter.lastRequest!.data, {'text': '공항 도착!'});
    });

    test('멤버가 아닌 방(404)은 RoomNotFoundException이다', () async {
      final adapter = StubHttpClientAdapter(path: '/api/rooms/99/messages', statusCode: 404, body: '');

      expect(() => _api(adapter).messages(99), throwsA(isA<RoomNotFoundException>()));
      expect(() => _api(adapter).sendText(99, '안녕'), throwsA(isA<RoomNotFoundException>()));
    });
  });

  test('404가 아닌 서버 오류는 DioException 그대로 던진다', () async {
    final adapter = StubHttpClientAdapter(path: '/api/rooms', statusCode: 500, body: '');

    expect(() => _api(adapter).myRooms(), throwsA(isA<DioException>()));
  });
}
