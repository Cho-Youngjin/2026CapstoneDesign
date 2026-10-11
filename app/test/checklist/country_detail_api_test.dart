import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/network/country_detail_api.dart';
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// 서버 응답을 고정하거나(성공) 매번 실패시키는 가짜 국가 상세 API.
class _FakeDetailApi implements CountryDetailApi {
  _FakeDetailApi({this.detail});

  final CountryDetail? detail;
  int calls = 0;

  @override
  Future<CountryDetail> fetchDetail(String isoAlpha2) async {
    calls++;
    final d = detail;
    if (d == null) throw DioException(requestOptions: RequestOptions(path: '/api/countries/$isoAlpha2'));
    return d;
  }
}

Future<ProviderContainer> _container(_FakeDetailApi api, {Map<String, Object> stored = const {}}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    countryDetailApiProvider.overrideWithValue(api),
  ]);
  addTearDown(container.dispose);
  return container;
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

  group('countryDetailProvider', () {
    const vietnam = CountryDetail(
      isoAlpha2: 'VN',
      nameKo: '베트남',
      plugTypes: 'A, C',
      voltageV: 220,
      currencyCode: 'VND',
      cardAcceptance: 'LOW',
      powerBankWhLimit: 100,
    );

    test('서버에서 받은 국가 정보를 기기에 저장해 두었다가 서버 조회가 실패하면 그것을 쓴다', () async {
      final online = await _container(_FakeDetailApi(detail: vietnam));
      await online.read(countryDetailProvider('VN').future);
      final saved = online.read(sharedPreferencesProvider).getString('country_detail.v1.VN');
      expect(saved, isNotNull);

      final offline = await _container(_FakeDetailApi(), stored: {'country_detail.v1.VN': saved!});
      final detail = await offline.read(countryDetailProvider('VN').future);

      expect(detail.nameKo, '베트남');
      expect(detail.currencyCode, 'VND');
      expect(detail.plugTypes, 'A, C');
      expect(detail.voltageV, 220);
      expect(detail.powerBankWhLimit, 100);
      expect(detail.paymentTier, PaymentTier.cashRecommended);
    });

    test('저장된 정보도 없으면 재시도 없이 바로 오류를 낸다', () async {
      final api = _FakeDetailApi();
      final container = await _container(api);

      await expectLater(container.read(countryDetailProvider('VN').future), throwsA(isA<DioException>()));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(api.calls, 1);
    });
  });
}
