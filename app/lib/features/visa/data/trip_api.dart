import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../models/trip.dart';
import '../models/trip_checklist_item.dart';
import '../models/trip_summary.dart';

/// 서버는 LocalDate를 `yyyy-MM-dd` 문자열로 주고받는다.
final _wireDate = DateFormat('yyyy-MM-dd');

/// `server/.../trip/TripController.java`(`/api/trips`)의 앱 쪽 클라이언트.
///
/// 실패 시 dio의 [DioException]을 그대로 던진다 — 화면에서 메시지로 바꿔 보여준다.
class TripApi {
  TripApi(this._dio);

  final Dio _dio;

  /// 여행계획을 저장하고 비자 판정 + 역산 일정이 담긴 결과를 받는다.
  Future<Trip> createTrip({
    required String countryIso2,
    required DateTime departDate,
    required DateTime returnDate,
    required DateTime passportExpiry,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/trips',
      data: {
        'countryIso2': countryIso2,
        'departDate': _wireDate.format(departDate),
        'returnDate': _wireDate.format(returnDate),
        'passportExpiry': _wireDate.format(passportExpiry),
      },
    );
    return Trip.fromJson(response.data!);
  }

  Future<Trip> getTrip(int id) async {
    final response = await _dio.get<Map<String, dynamic>>('/api/trips/$id');
    return Trip.fromJson(response.data!);
  }

  /// 판정 기준 데이터가 바뀐 여행(`judgementStale == true`)을 최신 기준으로 다시 판정한다.
  Future<Trip> refreshTrip(int id) async {
    final response =
        await _dio.post<Map<String, dynamic>>('/api/trips/$id/refresh');
    return Trip.fromJson(response.data!);
  }

  Future<TripTask> markTaskDone(int tripId, int taskId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/trips/$tripId/tasks/$taskId/done',
    );
    return TripTask.fromJson(response.data!);
  }

  /// 잘못 눌러 완료한 일정을 되돌린다. 이미 완료가 아니어도 서버는 그대로 false를 돌려준다.
  Future<TripTask> markTaskUndone(int tripId, int taskId) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/api/trips/$tripId/tasks/$taskId/done',
    );
    return TripTask.fromJson(response.data!);
  }

  /// 내 여행 목록(출발일 최신순).
  Future<List<TripSummary>> listTrips() async {
    final response = await _dio.get<List<dynamic>>('/api/trips');
    return response.data!
        .map((e) => TripSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 여행을 지운다. 서버가 준비 일정·체크리스트도 함께 지운다.
  Future<void> deleteTrip(int id) async {
    await _dio.delete<void>('/api/trips/$id');
  }

  /// 여행 생성 시점에 복사해 둔 그 여행 전용 준비물 목록(우선순위순).
  Future<List<TripChecklistItem>> getChecklist(int tripId) async {
    final response = await _dio.get<List<dynamic>>('/api/trips/$tripId/checklist');
    return response.data!
        .map((e) => TripChecklistItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 준비물 하나를 체크(또는 해제)한다.
  Future<TripChecklistItem> checkItem(int tripId, int itemId, {required bool checked}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/trips/$tripId/checklist/$itemId/check',
      data: {'checked': checked},
    );
    return TripChecklistItem.fromJson(response.data!);
  }
}

final tripApiProvider = Provider<TripApi>(
  (ref) => TripApi(ref.watch(apiClientProvider)),
);
