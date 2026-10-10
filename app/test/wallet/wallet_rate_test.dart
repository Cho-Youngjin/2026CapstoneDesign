import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/data/exchange_rate_api.dart';
import 'package:app/features/wallet/data/rate_cache.dart';
import 'package:app/features/wallet/data/wallet_rate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi implements ExchangeRateApi {
  _FakeApi({this.rate, this.fail = false});

  final ExchangeRate? rate;
  final bool fail;

  @override
  Future<ExchangeRate> getRate(String currencyCode) async {
    if (fail) throw Exception('네트워크 오류');
    return rate!;
  }
}

ExchangeRate _rate(double krwRate) => ExchangeRate(
      currencyCode: 'JPY',
      krwRate: krwRate,
      baseDate: DateTime(2026, 10, 8),
      source: 'EXIM',
    );

void main() {
  final now = DateTime(2026, 10, 9, 15);

  Future<RateCache> emptyCache() async {
    SharedPreferences.setMockInitialValues({});
    return RateCache(await SharedPreferences.getInstance());
  }

  test('캐시가 없고 서버가 응답하면 새 값을 내보내고 캐시에 저장한다', () async {
    final cache = await emptyCache();

    final values = await loadWalletRate(
      cache: cache, api: _FakeApi(rate: _rate(8.4746)), now: () => now, currencyCode: 'JPY',
    ).toList();

    expect(values, hasLength(1));
    expect(values.single!.rate.krwRate, 8.4746);
    expect(values.single!.fetchedAt, now);
    expect(cache.read('JPY')!.rate.krwRate, 8.4746);
  });

  test('캐시가 있으면 캐시를 먼저 내보내고 서버 값을 이어서 내보낸다', () async {
    final cache = await emptyCache();
    await cache.write('JPY', RateSnapshot(rate: _rate(8.40), fetchedAt: DateTime(2026, 10, 8)));

    final values = await loadWalletRate(
      cache: cache, api: _FakeApi(rate: _rate(8.4746)), now: () => now, currencyCode: 'JPY',
    ).toList();

    expect(values.map((v) => v!.rate.krwRate).toList(), [8.40, 8.4746]);
  });

  test('서버가 실패하면 캐시만 남는다', () async {
    final cache = await emptyCache();
    await cache.write('JPY', RateSnapshot(rate: _rate(8.40), fetchedAt: DateTime(2026, 10, 8)));

    final values = await loadWalletRate(
      cache: cache, api: _FakeApi(fail: true), now: () => now, currencyCode: 'JPY',
    ).toList();

    expect(values.map((v) => v!.rate.krwRate).toList(), [8.40]);
  });

  test('캐시도 없고 서버도 실패하면 null 하나를 내보낸다', () async {
    final cache = await emptyCache();

    final values = await loadWalletRate(
      cache: cache, api: _FakeApi(fail: true), now: () => now, currencyCode: 'JPY',
    ).toList();

    expect(values, [null]);
  });
}
