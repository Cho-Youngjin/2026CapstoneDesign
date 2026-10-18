import 'package:app/features/group/data/chat_api.dart';
import 'package:app/features/group/models/room.dart';
import 'package:dio/dio.dart';

/// 테스트용 그룹 방 목록 한 줄.
RoomSummary sampleRoom({
  int id = 1,
  String name = '도쿄 여행',
  int memberCount = 1,
  String? preview,
  DateTime? lastMessageAt,
  int unreadCount = 0,
}) {
  return RoomSummary(
    id: id,
    type: RoomType.group,
    name: name,
    inviteCode: 'ABC234',
    memberCount: memberCount,
    lastMessagePreview: preview,
    lastMessageAt: lastMessageAt,
    unreadCount: unreadCount,
  );
}

RoomDetail sampleDetail({int id = 1, String name = '도쿄 여행', String inviteCode = 'ABC234'}) {
  return RoomDetail(
    id: id,
    type: RoomType.group,
    name: name,
    inviteCode: inviteCode,
    members: const [RoomMember(uid: 'uid-a', displayName: '성주')],
  );
}

/// 서버 없이 ChatApi를 쓰는 화면·provider를 테스트하기 위한 가짜 구현.
/// 호출을 기록하고, 응답과 실패를 필드로 정한다.
class FakeChatApi implements ChatApi {
  FakeChatApi({List<RoomSummary>? rooms}) : rooms = rooms ?? [];

  /// myRooms가 돌려줄 목록. 테스트 중간에 바꿔서 "새로고침 후 목록"을 흉내 낼 수 있다.
  List<RoomSummary> rooms;

  /// 다음 myRooms 호출을 이 오류로 실패시킨다(한 번만).
  Object? nextMyRoomsError;

  /// createRoom·joinRoom이 돌려줄 방. 기본은 sampleDetail().
  RoomDetail detailToReturn = sampleDetail();

  /// joinRoom이 RoomNotFoundException을 던지게 한다.
  bool joinNotFound = false;

  /// putProfile을 실패시킨다.
  bool profileFails = false;

  int myRoomsCalls = 0;
  final List<String> createdNames = [];
  final List<String> joinedCodes = [];
  final List<({String? displayName, String? photoUrl})> profileUploads = [];

  @override
  Future<List<RoomSummary>> myRooms() async {
    myRoomsCalls++;
    final error = nextMyRoomsError;
    if (error != null) {
      nextMyRoomsError = null;
      throw error;
    }
    return rooms;
  }

  @override
  Future<RoomDetail> createRoom(String name) async {
    createdNames.add(name);
    return detailToReturn;
  }

  @override
  Future<RoomDetail> joinRoom(String inviteCode) async {
    joinedCodes.add(inviteCode);
    if (joinNotFound) throw const RoomNotFoundException();
    return detailToReturn;
  }

  @override
  Future<RoomDetail> roomDetail(int roomId) async => detailToReturn;

  @override
  Future<void> putProfile({required String? displayName, required String? photoUrl}) async {
    if (profileFails) {
      throw DioException.connectionError(
        requestOptions: RequestOptions(path: '/api/me/profile'),
        reason: 'offline',
      );
    }
    profileUploads.add((displayName: displayName, photoUrl: photoUrl));
  }
}
