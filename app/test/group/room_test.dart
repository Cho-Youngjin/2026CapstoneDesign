import 'package:app/features/group/models/room.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RoomSummary.fromJson', () {
    test('서버 GET /api/rooms 한 줄을 파싱한다', () {
      final room = RoomSummary.fromJson({
        'id': 12,
        'type': 'GROUP',
        'name': '도쿄 여행',
        'inviteCode': 'ABC234',
        'memberCount': 3,
        'lastMessagePreview': '공항 도착!',
        'lastMessageAt': '2026-10-16T14:14:00.000+09:00',
        'unreadCount': 2,
        'dmPeer': null,
      });

      expect(room.id, 12);
      expect(room.type, RoomType.group);
      expect(room.name, '도쿄 여행');
      expect(room.inviteCode, 'ABC234');
      expect(room.memberCount, 3);
      expect(room.lastMessagePreview, '공항 도착!');
      expect(room.lastMessageAt, DateTime.parse('2026-10-16T14:14:00.000+09:00'));
      expect(room.unreadCount, 2);
      expect(room.dmPeer, isNull);
    });

    test('메시지가 없는 방은 미리보기와 시각이 null이다', () {
      final room = RoomSummary.fromJson({
        'id': 1,
        'type': 'GROUP',
        'name': '새 방',
        'inviteCode': 'XYZ789',
        'memberCount': 1,
        'lastMessagePreview': null,
        'lastMessageAt': null,
        'unreadCount': 0,
        'dmPeer': null,
      });

      expect(room.lastMessagePreview, isNull);
      expect(room.lastMessageAt, isNull);
    });

    test('DM은 상대 프로필을 제목으로 쓴다', () {
      final room = RoomSummary.fromJson({
        'id': 5,
        'type': 'DM',
        'name': null,
        'inviteCode': null,
        'memberCount': 2,
        'lastMessagePreview': null,
        'lastMessageAt': null,
        'unreadCount': 0,
        'dmPeer': {'uid': 'uid-b', 'displayName': '영진', 'photoUrl': null, 'lastReadMessageId': null},
      });

      expect(room.type, RoomType.dm);
      expect(room.title, '영진');
    });
  });

  group('RoomSummary.title', () {
    RoomSummary summary({RoomType type = RoomType.group, String? name, RoomMember? peer}) =>
        RoomSummary(
          id: 1,
          type: type,
          name: name,
          memberCount: 2,
          unreadCount: 0,
          dmPeer: peer,
        );

    test('그룹은 방 이름이다', () {
      expect(summary(name: '오사카').title, '오사카');
    });

    test('프로필 이름이 없는 DM 상대는 "알 수 없음"이다', () {
      final peer = RoomMember(uid: 'uid-x');
      expect(summary(type: RoomType.dm, peer: peer).title, '알 수 없음');
    });
  });

  test('모르는 방 종류는 그룹으로 본다 (앱이 죽지 않게)', () {
    expect(RoomType.fromWire('SOMETHING_NEW'), RoomType.group);
  });

  test('RoomDetail.fromJson이 멤버를 참여 순서대로 파싱한다', () {
    final detail = RoomDetail.fromJson({
      'id': 12,
      'type': 'GROUP',
      'name': '도쿄 여행',
      'inviteCode': 'ABC234',
      'members': [
        {'uid': 'uid-a', 'displayName': '성주', 'photoUrl': 'https://x/a.png', 'lastReadMessageId': null},
        {'uid': 'uid-b', 'displayName': null, 'photoUrl': null, 'lastReadMessageId': 7},
      ],
    });

    expect(detail.inviteCode, 'ABC234');
    expect(detail.members.map((m) => m.uid), ['uid-a', 'uid-b']);
    expect(detail.members[0].label, '성주');
    expect(detail.members[1].label, '알 수 없음');
    expect(detail.members[1].lastReadMessageId, 7);
  });
}
