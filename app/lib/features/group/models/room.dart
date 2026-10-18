/// 채팅방 모델. JSON 모양은 서버 `chat/RoomSummaryResponse.java`, `RoomDetailResponse.java`,
/// `MemberResponse.java`와 필드명까지 맞춘다 (docs/api-spec.md 10절).
library;

/// 서버 `chat/RoomType.java`의 값과 문자 그대로 일치해야 한다.
enum RoomType {
  group('GROUP'),
  dm('DM');

  const RoomType(this.wireValue);

  final String wireValue;

  /// 모르는 값이 오면 앱이 죽지 않도록 그룹으로 본다.
  static RoomType fromWire(String? value) =>
      RoomType.values.firstWhere((t) => t.wireValue == value, orElse: () => RoomType.group);
}

/// 방 멤버. 프로필을 아직 올리지 않은 사용자는 이름·사진이 null이다.
class RoomMember {
  const RoomMember({
    required this.uid,
    this.displayName,
    this.photoUrl,
    this.lastReadMessageId,
  });

  final String uid;
  final String? displayName;
  final String? photoUrl;

  /// 마지막으로 읽은 메시지 id (Plan D Task 7). null이면 아직 아무것도 안 읽음.
  final int? lastReadMessageId;

  /// 화면 표시용 이름.
  String get label =>
      (displayName != null && displayName!.trim().isNotEmpty) ? displayName! : '알 수 없음';

  factory RoomMember.fromJson(Map<String, dynamic> json) => RoomMember(
        uid: json['uid'] as String,
        displayName: json['displayName'] as String?,
        photoUrl: json['photoUrl'] as String?,
        lastReadMessageId: json['lastReadMessageId'] as int?,
      );
}

/// 방 목록의 한 줄 (GET /api/rooms).
class RoomSummary {
  const RoomSummary({
    required this.id,
    required this.type,
    this.name,
    this.inviteCode,
    required this.memberCount,
    this.lastMessagePreview,
    this.lastMessageAt,
    required this.unreadCount,
    this.dmPeer,
  });

  final int id;
  final RoomType type;

  /// GROUP만 값이 있다.
  final String? name;

  /// GROUP만 값이 있다.
  final String? inviteCode;
  final int memberCount;

  /// 메시지가 아직 없는 방은 null.
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;

  /// 읽음 표시(Plan D Task 7) 전까지 서버가 항상 0을 준다.
  final int unreadCount;

  /// DM 방의 상대방 (Plan D Task 5 전까지 항상 null).
  final RoomMember? dmPeer;

  /// 목록에 보이는 방 제목 — 그룹은 방 이름, DM은 상대 이름.
  String get title => switch (type) {
        RoomType.group => name ?? '이름 없는 그룹',
        RoomType.dm => dmPeer?.label ?? '알 수 없음',
      };

  factory RoomSummary.fromJson(Map<String, dynamic> json) => RoomSummary(
        id: json['id'] as int,
        type: RoomType.fromWire(json['type'] as String?),
        name: json['name'] as String?,
        inviteCode: json['inviteCode'] as String?,
        memberCount: json['memberCount'] as int,
        lastMessagePreview: json['lastMessagePreview'] as String?,
        lastMessageAt: json['lastMessageAt'] == null
            ? null
            : DateTime.parse(json['lastMessageAt'] as String),
        unreadCount: json['unreadCount'] as int? ?? 0,
        dmPeer: json['dmPeer'] == null
            ? null
            : RoomMember.fromJson(json['dmPeer'] as Map<String, dynamic>),
      );
}

/// 방 상세 — 방 만들기·참여 응답과 GET /api/rooms/{id}. 멤버는 참여한 순서(만든 사람이 맨 앞).
class RoomDetail {
  const RoomDetail({
    required this.id,
    required this.type,
    this.name,
    this.inviteCode,
    required this.members,
  });

  final int id;
  final RoomType type;
  final String? name;
  final String? inviteCode;
  final List<RoomMember> members;

  factory RoomDetail.fromJson(Map<String, dynamic> json) => RoomDetail(
        id: json['id'] as int,
        type: RoomType.fromWire(json['type'] as String?),
        name: json['name'] as String?,
        inviteCode: json['inviteCode'] as String?,
        members: (json['members'] as List)
            .map((e) => RoomMember.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
