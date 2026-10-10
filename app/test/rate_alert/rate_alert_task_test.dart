import 'package:app/features/rate_alert/background/rate_alert_task.dart';
import 'package:app/features/rate_alert/data/rate_alert_store.dart';
import 'package:app/features/rate_alert/domain/rate_alert_evaluator.dart';
import 'package:app/features/rate_alert/domain/rate_alert_settings.dart';
import 'package:app/features/rate_alert/notify/rate_notifier.dart';
import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/data/exchange_rate_api.dart';
import 'package:app/features/wallet/data/rate_cache.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi implements ExchangeRateApi {
  _FakeApi(this.rates, {this.fail = false});

  final Map<String, ExchangeRate> rates;
  final bool fail;
  final requested = <String>[];

  @override
  Future<ExchangeRate> getRate(String currencyCode) async {
    requested.add(currencyCode);
    if (fail) throw DioException(requestOptions: RequestOptions(path: '/api/exchange-rates/$currencyCode'));
    return rates[currencyCode]!;
  }
}

class _FakeNotifier implements RateNotifier {
  final shown = <RateAlertMessage>[];

  @override
  Future<void> show(RateAlertMessage message) async => shown.add(message);
}

final _jpyRate = ExchangeRate(
  currencyCode: 'JPY',
  krwRate: 8.4746,
  baseDate: DateTime(2026, 10, 8),
  previousKrwRate: 8.4389,
  previousBaseDate: DateTime(2026, 10, 7),
  changePercent: 0.42,
  source: 'EXIM',
);

void main() {
  late SharedPreferences prefs;
  late RateAlertStore store;
  late RateCache cache;
  late _FakeNotifier notifier;
  final now = DateTime(2026, 10, 8, 14);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = RateAlertStore(prefs);
    cache = RateCache(prefs);
    notifier = _FakeNotifier();
  });

  final target = RateTarget(
    id: 5,
    unit: 100,
    targetKrw: 850,
    direction: TargetDirection.below,
    active: true,
    createdAt: DateTime(2026, 10, 1),
  );

  test('켜진 통화의 환율을 받아 캐시를 갱신하고, 알림을 보내고, 바뀐 설정을 저장한다', () async {
    await store.save('JPY', RateAlertSettings(daily: true, targets: [target]));
    final api = _FakeApi({'JPY': _jpyRate});

    final result = await handleRateAlertTask(
        store: store, api: api, cache: cache, notifier: notifier, now: () => now);

    expect(result, isTrue);
    expect(notifier.shown.map((m) => m.title), ['환율 등락 알림', '목표 환율 도달']);
    expect(cache.read('JPY')!.rate.krwRate, 8.4746);
    expect(cache.read('JPY')!.fetchedAt, now);
    final saved = await store.read('JPY');
    expect(saved.lastDailyBaseDate, DateTime(2026, 10, 8));
    expect(saved.targets.single.active, isFalse);
    expect(saved.targets.single.firedAt, now);
  });

  test('다시 돌려도 같은 알림을 또 보내지 않는다', () async {
    await store.save('JPY', RateAlertSettings(daily: true, targets: [target]));
    final api = _FakeApi({'JPY': _jpyRate});

    await handleRateAlertTask(store: store, api: api, cache: cache, notifier: notifier, now: () => now);
    await handleRateAlertTask(store: store, api: api, cache: cache, notifier: notifier, now: () => now);

    expect(notifier.shown, hasLength(2));
  });

  test('꺼진 통화는 조회하지 않는다', () async {
    await store.save('USD', RateAlertSettings(targets: [target.copyWith(active: false)]));
    await store.save('JPY', const RateAlertSettings(daily: true));
    final api = _FakeApi({'JPY': _jpyRate});

    await handleRateAlertTask(store: store, api: api, cache: cache, notifier: notifier, now: () => now);

    expect(api.requested, ['JPY']);
  });

  test('서버 조회가 실패하면 알림도 없고 설정도 그대로다', () async {
    await store.save('JPY', RateAlertSettings(daily: true, targets: [target]));
    final api = _FakeApi({}, fail: true);

    final result = await handleRateAlertTask(
        store: store, api: api, cache: cache, notifier: notifier, now: () => now);

    expect(result, isTrue); // 실패로 돌려 WorkManager가 곧바로 재시도하게 하지 않는다 — 3시간 뒤 다시 본다.
    expect(notifier.shown, isEmpty);
    expect(cache.read('JPY'), isNull);
    final saved = await store.read('JPY');
    expect(saved.lastDailyBaseDate, isNull);
    expect(saved.targets.single.active, isTrue);
  });
}
