import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/data/exchange_rate_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_http_client_adapter.dart';

void main() {
  test('수출입은행 환율 응답을 모두 읽는다', () {
    final rate = ExchangeRate.fromJson({
      'currencyCode': 'JPY',
      'krwRate': 8.4746,
      'baseDate': '2026-10-08',
      'previousKrwRate': 8.491,
      'previousBaseDate': '2026-10-07',
      'changePercent': -0.19,
      'source': 'EXIM',
    });

    expect(rate.currencyCode, 'JPY');
    expect(rate.krwRate, 8.4746);
    expect(rate.baseDate, DateTime(2026, 10, 8));
    expect(rate.previousKrwRate, 8.491);
    expect(rate.previousBaseDate, DateTime(2026, 10, 7));
    expect(rate.changePercent, -0.19);
    expect(rate.isReference, isFalse);
  });

  test('참고환율은 이전값이 없을 수 있다', () {
    final rate = ExchangeRate.fromJson({
      'currencyCode': 'VND',
      'krwRate': 0.051934,
      'baseDate': '2026-10-09',
      'previousKrwRate': null,
      'previousBaseDate': null,
      'changePercent': null,
      'source': 'ER_API',
    });

    expect(rate.previousKrwRate, isNull);
    expect(rate.changePercent, isNull);
    expect(rate.isReference, isTrue);
  });

  test('toJson으로 저장한 값을 fromJson으로 그대로 되읽는다', () {
    final original = ExchangeRate(
      currencyCode: 'USD',
      krwRate: 1339.2,
      baseDate: DateTime(2026, 10, 8),
      previousKrwRate: 1343.4,
      previousBaseDate: DateTime(2026, 10, 7),
      changePercent: -0.31,
      source: 'EXIM',
    );

    final restored = ExchangeRate.fromJson(original.toJson());

    expect(restored.krwRate, 1339.2);
    expect(restored.baseDate, DateTime(2026, 10, 8));
    expect(restored.previousBaseDate, DateTime(2026, 10, 7));
    expect(restored.changePercent, -0.31);
    expect(restored.source, 'EXIM');
  });

  test('getRate는 대문자 통화 코드 경로로 조회한다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/exchange-rates/JPY',
      statusCode: 200,
      body: '{"currencyCode":"JPY","krwRate":8.4746,"baseDate":"2026-10-08",'
          '"previousKrwRate":null,"previousBaseDate":null,"changePercent":null,"source":"EXIM"}',
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter;

    final rate = await ExchangeRateApi(dio).getRate('jpy');

    expect(adapter.lastRequest!.path, '/api/exchange-rates/JPY');
    expect(rate.krwRate, 8.4746);
  });
}
