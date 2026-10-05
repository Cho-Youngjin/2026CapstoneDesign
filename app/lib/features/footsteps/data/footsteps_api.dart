import 'package:dio/dio.dart';

import 'checkin.dart';
import 'daily_step.dart';

abstract class FootstepsApi {
  Future<Map<int, String>> pushCheckins(List<Checkin> items);
  Future<Map<int, String>> pushDailySteps(List<DailyStep> items);
}

class DioFootstepsApi implements FootstepsApi {
  DioFootstepsApi(this._dio);

  final Dio _dio;

  @override
  Future<Map<int, String>> pushCheckins(List<Checkin> items) async {
    if (items.isEmpty) return {};

    final response = await _dio.post<List<dynamic>>('/api/checkins', data: [
      for (final c in items)
        {
          'localId': c.id,
          'lat': c.lat,
          'lng': c.lng,
          'countryIso': c.countryIso,
          'recordedAt': c.recordedAt.toIso8601String(),
          'source': c.source.name.toUpperCase(),
        },
    ]);

    return {
      for (final row in response.data!)
        (row as Map<String, dynamic>)['localId'] as int: row['serverId'] as String,
    };
  }

  @override
  Future<Map<int, String>> pushDailySteps(List<DailyStep> items) async {
    if (items.isEmpty) return {};

    final response = await _dio.post<List<dynamic>>('/api/daily-steps', data: [
      for (final d in items)
        {
          'localId': d.id,
          // 서버는 순수 yyyy-MM-dd(LocalDate)로 받고 타임존 변환을 전혀 하지 않는다
          // (DailyStepSyncRequest 주석 참고). toIso8601String()을 쓰면 전체
          // datetime 문자열이 되어 서버 파싱이 깨지므로 날짜만 직접 포맷한다.
          'date': _formatDate(d.date),
          'countryIso': d.countryIso,
          'stepCount': d.stepCount,
        },
    ]);

    return {
      for (final row in response.data!)
        (row as Map<String, dynamic>)['localId'] as int: row['serverId'] as String,
    };
  }

  String _formatDate(DateTime date) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
  }
}
