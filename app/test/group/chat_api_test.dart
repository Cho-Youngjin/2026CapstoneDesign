import 'package:app/features/group/data/chat_api.dart';
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

  test('404가 아닌 서버 오류는 DioException 그대로 던진다', () async {
    final adapter = StubHttpClientAdapter(path: '/api/rooms', statusCode: 500, body: '');

    expect(() => _api(adapter).myRooms(), throwsA(isA<DioException>()));
  });
}
