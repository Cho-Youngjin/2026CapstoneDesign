import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/features/group/data/chat_api.dart';
import 'package:app/features/group/models/chat_message.dart';
import 'package:app/features/group/models/room.dart';
import 'package:dio/dio.dart';

/// 1x1 투명 PNG — Image.memory가 실제로 디코딩할 수 있는 가장 작은 그림.
final onePixelPng = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));

/// 테스트용 사진 메시지.
ChatMessage sampleImageMessage({required int id, int roomId = 1, String senderUid = 'uid-b'}) {
  return ChatMessage(
    id: id,
    roomId: roomId,
    senderUid: senderUid,
    type: MessageType.image,
    imageUrl: '/api/rooms/$roomId/images/$id',
    createdAt: DateTime(2026, 10, 17, 9).add(Duration(minutes: id)),
  );
}

/// 테스트용 메시지. createdAt은 id에 따라 1분씩 늘어난다.
ChatMessage sampleMessage({
  required int id,
  int roomId = 1,
  String senderUid = 'uid-b',
  String text = '안녕',
  DateTime? createdAt,
}) {
  return ChatMessage(
    id: id,
    roomId: roomId,
    senderUid: senderUid,
    type: MessageType.text,
    text: text,
    createdAt: createdAt ?? DateTime(2026, 10, 17, 9).add(Duration(minutes: id)),
  );
}

/// 메시지를 STOMP로 받은 것처럼 JSON으로 바꾼다.
Map<String, dynamic> messageJson(ChatMessage m) => {
      'id': m.id,
      'roomId': m.roomId,
      'senderUid': m.senderUid,
      'type': m.type.wireValue,
      'text': m.text,
      'imageUrl': m.imageUrl,
      'createdAt': m.createdAt.toIso8601String(),
    };

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

  /// roomDetail이 RoomNotFoundException을 던지게 한다(멤버가 아닌 방).
  bool roomDetailNotFound = false;

  /// openDm이 돌려줄 DM 방. null이면 RoomNotFoundException(같은 그룹이 아님)을 던진다.
  RoomDetail? dmToReturn;

  final List<String> openedDmPeers = [];

  @override
  Future<RoomDetail> openDm(String peerUid) async {
    openedDmPeers.add(peerUid);
    final dm = dmToReturn;
    if (dm == null) throw const RoomNotFoundException();
    return dm;
  }

  @override
  Future<RoomDetail> roomDetail(int roomId) async {
    if (roomDetailNotFound) throw const RoomNotFoundException();
    return detailToReturn;
  }

  // ───────────── 메시지 (Plan D Task 4) ─────────────

  /// 서버에 저장된 메시지(방 하나 기준). messages()는 이걸 서버처럼 최신순·커서로 잘라 준다.
  final List<ChatMessage> storedMessages = [];

  /// 다음 messages 호출을 실패시킨다(한 번만).
  Object? nextMessagesError;

  /// sendText를 실패시킨다.
  bool sendFails = false;

  /// `before`가 이 키인 messages 응답을, 테스트가 completer를 완료할 때까지 붙잡아 둔다
  /// (느린 네트워크에서 응답 순서가 뒤바뀌는 상황을 흉내 낸다).
  final Map<int, Completer<void>> holdBefore = {};

  final List<({int? before, int size})> messageQueries = [];
  final List<String> sentTexts = [];
  int _nextId = 1000;

  @override
  Future<List<ChatMessage>> messages(int roomId, {int? before, int size = 30}) async {
    messageQueries.add((before: before, size: size));
    final hold = before == null ? null : holdBefore[before];
    if (hold != null) await hold.future;
    final error = nextMessagesError;
    if (error != null) {
      nextMessagesError = null;
      throw error;
    }
    final sorted = [...storedMessages]..sort((a, b) => b.id.compareTo(a.id));
    return sorted.where((m) => before == null || m.id < before).take(size).toList();
  }

  @override
  Future<ChatMessage> sendText(int roomId, String text) async {
    sentTexts.add(text);
    if (sendFails) {
      throw DioException.connectionError(
        requestOptions: RequestOptions(path: '/api/rooms/$roomId/messages'),
        reason: 'offline',
      );
    }
    final message = sampleMessage(id: _nextId++, roomId: roomId, text: text, senderUid: 'uid-a');
    storedMessages.add(message);
    return message;
  }

  // ───────────── 읽음 (Plan D Task 7) ─────────────

  /// markRead를 실패시킨다(호출은 기록한다).
  bool readFails = false;
  final List<int> readMarks = [];

  @override
  Future<void> markRead(int roomId, int lastReadMessageId) async {
    readMarks.add(lastReadMessageId);
    if (readFails) {
      throw DioException.connectionError(
        requestOptions: RequestOptions(path: '/api/rooms/$roomId/read'),
        reason: 'offline',
      );
    }
  }

  // ───────────── 사진 (Plan D Task 6) ─────────────

  /// 다음 sendImage를 이 오류로 실패시킨다(한 번만).
  Object? nextImageError;

  /// 정해 두면 sendImage 응답을 이 Completer가 끝날 때까지 미룬다(올리는 중인 상태를 보려고).
  Completer<void>? holdImage;

  final List<Uint8List> sentImages = [];
  final List<String> sentImageClientIds = [];

  /// imageBytes가 돌려줄 바이트(주소별). 없으면 1x1 PNG.
  final Map<String, Uint8List> imagesByUrl = {};
  final List<String> imageDownloads = [];

  @override
  Future<ChatMessage> sendImage(int roomId, Uint8List bytes, {required String clientId}) async {
    sentImages.add(bytes);
    sentImageClientIds.add(clientId);
    final hold = holdImage;
    if (hold != null) await hold.future;
    final error = nextImageError;
    if (error != null) {
      nextImageError = null;
      throw error;
    }
    final id = _nextId++;
    final message = ChatMessage(
      id: id,
      roomId: roomId,
      senderUid: 'uid-a',
      type: MessageType.image,
      imageUrl: '/api/rooms/$roomId/images/$id',
      createdAt: DateTime(2026, 10, 19, 9),
    );
    storedMessages.add(message);
    return message;
  }

  @override
  Future<Uint8List> imageBytes(String imageUrl) async {
    imageDownloads.add(imageUrl);
    return imagesByUrl[imageUrl] ?? onePixelPng;
  }

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
