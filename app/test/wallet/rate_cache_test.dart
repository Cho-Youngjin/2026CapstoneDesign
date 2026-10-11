import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/data/rate_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  RateSnapshot snapshot() => RateSnapshot(
        rate: ExchangeRate(
          currencyCode: 'JPY',
          krwRate: 8.4746,
          baseDate: DateTime(2026, 10, 8),
          changePercent: 0.42,
          source: 'EXIM',
        ),
        fetchedAt: DateTime(2026, 10, 9, 12, 30),
      );

  test('저장한 환율을 통화별 키로 되읽는다', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = RateCache(prefs);

    await cache.write('jpy', snapshot());
    final read = cache.read('JPY');

    expect(RateCache.keyOf('jpy'), 'rateCache.JPY');
    expect(read!.rate.krwRate, 8.4746);
    expect(read.rate.changePercent, 0.42);
    expect(read.fetchedAt, DateTime(2026, 10, 9, 12, 30));
  });

  test('저장된 값이 없으면 null', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = RateCache(await SharedPreferences.getInstance());

    expect(cache.read('USD'), isNull);
  });

  test('깨진 값은 없는 것으로 본다', () async {
    SharedPreferences.setMockInitialValues({'rateCache.USD': '{not json'});
    final cache = RateCache(await SharedPreferences.getInstance());

    expect(cache.read('USD'), isNull);
  });
}
