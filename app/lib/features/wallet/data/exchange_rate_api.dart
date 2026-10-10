import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'exchange_rate.dart';

/// 서버 환율 조회. 서버가 배치로 채운 캐시를 읽기만 하는 API라 로그인 토큰 없이도 동작한다
/// (3단계의 백그라운드 알림 작업이 그대로 쓴다).
class ExchangeRateApi {
  ExchangeRateApi(this._dio);

  final Dio _dio;

  Future<ExchangeRate> getRate(String currencyCode) async {
    final response = await _dio
        .get<Map<String, dynamic>>('/api/exchange-rates/${currencyCode.toUpperCase()}');
    return ExchangeRate.fromJson(response.data!);
  }
}

final exchangeRateApiProvider = Provider<ExchangeRateApi>((ref) {
  return ExchangeRateApi(ref.watch(apiClientProvider));
});
