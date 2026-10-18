import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../models/chat_message.dart';
import '../models/room.dart';

/// 방이 없거나, 있어도 내가 멤버가 아닐 때 (서버가 두 경우 모두 404로 답한다).
/// 화면이 "코드를 찾을 수 없어요" 같은 안내를 고르기 쉽도록 DioException과 구분한다.
class RoomNotFoundException implements Exception {
  const RoomNotFoundException();

  @override
  String toString() => 'RoomNotFoundException';
}

/// 서버 채팅 API의 앱 쪽 클라이언트 (docs/api-spec.md 10절).
/// Plan D Task 3에서 방·프로필 메서드를 만들고, Task 4~7이 메시지·DM·사진·읽음 메서드를 덧붙인다.
///
/// 404는 [RoomNotFoundException]으로 바꾸고, 그 밖의 실패는 dio의 [DioException]을 그대로 던진다.
class ChatApi {
  ChatApi(this._dio);

  final Dio _dio;

  Future<RoomDetail> createRoom(String name) => _detail(
        () => _dio.post<Map<String, dynamic>>('/api/rooms', data: {'name': name}),
      );

  /// 이미 멤버인 방의 코드를 넣어도 오류가 아니라 그 방을 돌려준다(서버 규칙).
  Future<RoomDetail> joinRoom(String inviteCode) => _detail(
        () => _dio.post<Map<String, dynamic>>('/api/rooms/join', data: {'inviteCode': inviteCode}),
      );

  Future<RoomDetail> roomDetail(int roomId) =>
      _detail(() => _dio.get<Map<String, dynamic>>('/api/rooms/$roomId'));

  /// 내가 속한 방 목록, 최근 활동순.
  Future<List<RoomSummary>> myRooms() async {
    final response = await _dio.get<List<dynamic>>('/api/rooms');
    return response.data!
        .map((e) => RoomSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 메시지 목록, 최신순(id 내림차순). [before]가 없으면 가장 최근부터, 있으면 그보다 오래된 것부터.
  /// 서버가 [size]를 1~50으로 맞춘다.
  Future<List<ChatMessage>> messages(int roomId, {int? before, int size = 30}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/api/rooms/$roomId/messages',
        queryParameters: {'size': size, 'before': ?before},
      );
      return response.data!
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw const RoomNotFoundException();
      rethrow;
    }
  }

  /// 텍스트 메시지를 보낸다. 같은 메시지가 실시간 구독으로도 한 번 더 온다 — 화면에서 id로 걸러낸다.
  Future<ChatMessage> sendText(int roomId, String text) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/rooms/$roomId/messages',
        data: {'text': text},
      );
      return ChatMessage.fromJson(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw const RoomNotFoundException();
      rethrow;
    }
  }

  /// 채팅 화면에 표시할 내 이름·사진을 올린다(처음이면 만들고 있으면 덮어쓴다).
  Future<void> putProfile({required String? displayName, required String? photoUrl}) async {
    await _dio.put<void>(
      '/api/me/profile',
      data: {'displayName': displayName, 'photoUrl': photoUrl},
    );
  }

  Future<RoomDetail> _detail(Future<Response<Map<String, dynamic>>> Function() request) async {
    try {
      final response = await request();
      return RoomDetail.fromJson(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw const RoomNotFoundException();
      rethrow;
    }
  }
}

final chatApiProvider = Provider<ChatApi>((ref) => ChatApi(ref.watch(apiClientProvider)));
