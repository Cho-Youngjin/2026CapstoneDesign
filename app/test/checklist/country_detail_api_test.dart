import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/network/country_detail_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.statusCode, this.body);

  final int statusCode;
  final Map<String, dynamic> body;
  RequestOptions? capturedRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    capturedRequest = options;
    final payload = utf8.encode(jsonEncode(body));
    return ResponseBody.fromBytes(
      payload,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  group('PaymentTier.fromCardAcceptance', () {
    test('HIGH -> 카드 결제 용이', () {
      expect(PaymentTier.fromCardAcceptance('HIGH').labelKo, '카드 결제 용이');
    });

    test('MEDIUM -> 현금 구비', () {
      expect(PaymentTier.fromCardAcceptance('MEDIUM').labelKo, '현금 구비');
    });

    test('LOW -> 현금 권장', () {
      expect(PaymentTier.fromCardAcceptance('LOW').labelKo, '현금 권장');
    });

    test('알 수 없는 값이면 예외를 던진다', () {
      expect(
        () => PaymentTier.fromCardAcceptance('UNKNOWN'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('CountryDetail.fromJson', () {
    test('서버 응답 필드를 그대로 파싱한다', () {
      final detail = CountryDetail.fromJson({
        'isoAlpha2': 'JP',
        'nameKo': '일본',
        'cardAcceptance': 'MEDIUM',
        'plugTypes': 'A, B',
        'voltageV': 100,
        'powerBankWhLimit': 160,
      });

      expect(detail.isoAlpha2, 'JP');
      expect(detail.paymentTier!.labelKo, '현금 구비');
    });

    test('cardAcceptance가 아직 채워지지 않았으면(null) paymentTier도 null이다', () {
      final detail = CountryDetail.fromJson({
        'isoAlpha2': 'JP',
        'nameKo': '일본',
        'cardAcceptance': null,
      });

      expect(detail.paymentTier, isNull);
    });
  });

  group('CountryDetailApi.fetchDetail', () {
    test('GET /api/countries/{iso2}로 요청하고 결과를 파싱한다', () async {
      final adapter = _StubAdapter(200, {
        'isoAlpha2': 'VN',
        'nameKo': '베트남',
        'cardAcceptance': 'LOW',
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;
      final api = CountryDetailApi(dio);

      final detail = await api.fetchDetail('VN');

      expect(adapter.capturedRequest!.path, '/api/countries/VN');
      expect(detail.paymentTier!.labelKo, '현금 권장');
    });
  });
}
