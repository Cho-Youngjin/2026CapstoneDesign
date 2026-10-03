import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../models/trip.dart';

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
}

final tripApiProvider = Provider<TripApi>(
  (ref) => TripApi(ref.watch(apiClientProvider)),
);
