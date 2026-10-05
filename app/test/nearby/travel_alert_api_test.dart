import 'dart:convert';
import 'dart:typed_data';

import 'package:app/features/nearby/api/travel_alert_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GET /api/countries/{iso2}/alerts 를 호출해 파싱한다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _FakeAlertsAdapter();

    final alerts = await fetchTravelAlerts(dio, iso2: 'VN');

    expect(alerts, hasLength(1));
    expect(alerts.first.level, 2);
    expect(alerts.first.region, '전역');
  });
}

class _FakeAlertsAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.path, '/api/countries/VN/alerts');
    final json = jsonEncode([
      {
        'id': 1,
        'level': 2,
        'region': '전역',
        'title': '황색경보 발령',
        'issuedAt': '2026-08-01T00:00:00Z',
      },
    ]);
    return ResponseBody.fromString(json, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
