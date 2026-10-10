import 'package:app/features/rate_alert/background/rate_alert_scheduler.dart';
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
  _FakeApi(this.rates, {this.fail = false, this.onFetch});

  final Map<String, ExchangeRate> rates;
  final bool fail;

  /// 값을 돌려주기 직전에 불린다 — 조회를 기다리는 동안 사용자가 설정을 바꾸는 상황을 흉내 낸다.
  final Future<void> Function()? onFetch;
  final requested = <String>[];

  @override
  Future<ExchangeRate> getRate(String currencyCode) async {
    requested.add(currencyCode);
    if (fail) throw DioException(requestOptions: RequestOptions(path: '/api/exchange-rates/$currencyCode'));
    await onFetch?.call();
    return rates[currencyCode]!;
  }
}

class _FakeNotifier implements RateNotifier {
  final shown = <RateAlertMessage>[];

  @override
  Future<void> show(RateAlertMessage message) async => shown.add(message);
}

class _FakeScheduler implements RateAlertScheduler {
  final calls = <bool>[];

  @override
  Future<void> sync({required bool enabled}) async => calls.add(enabled);
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
  late _FakeScheduler scheduler;
  final now = DateTime(2026, 10, 8, 14);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = RateAlertStore(prefs);
    cache = RateCache(prefs);
    notifier = _FakeNotifier();
    scheduler = _FakeScheduler();
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
        store: store, api: api, cache: cache, notifier: notifier, scheduler: scheduler, now: () => now);

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

    await handleRateAlertTask(store: store, api: api, cache: cache, notifier: notifier, scheduler: scheduler, now: () => now);
    await handleRateAlertTask(store: store, api: api, cache: cache, notifier: notifier, scheduler: scheduler, now: () => now);

    expect(notifier.shown, hasLength(2));
  });

  test('꺼진 통화는 조회하지 않는다', () async {
    await store.save('USD', RateAlertSettings(targets: [target.copyWith(active: false)]));
    await store.save('JPY', const RateAlertSettings(daily: true));
    final api = _FakeApi({'JPY': _jpyRate});

    await handleRateAlertTask(store: store, api: api, cache: cache, notifier: notifier, scheduler: scheduler, now: () => now);

    expect(api.requested, ['JPY']);
  });

  test('서버 조회가 실패하면 알림도 없고 설정도 그대로다', () async {
    await store.save('JPY', RateAlertSettings(daily: true, targets: [target]));
    final api = _FakeApi({}, fail: true);

    final result = await handleRateAlertTask(
        store: store, api: api, cache: cache, notifier: notifier, scheduler: scheduler, now: () => now);

    expect(result, isTrue); // 실패로 돌려 WorkManager가 곧바로 재시도하게 하지 않는다 — 3시간 뒤 다시 본다.
    expect(notifier.shown, isEmpty);
    expect(cache.read('JPY'), isNull);
    final saved = await store.read('JPY');
    expect(saved.lastDailyBaseDate, isNull);
    expect(saved.targets.single.active, isTrue);
    expect(scheduler.calls, isEmpty); // 설정이 켜진 채 남으므로 작업은 그대로 둔다.
  });

  test('조회 중에 사용자가 바꾼 설정을 덮어쓰지 않는다', () async {
    await store.save('JPY', RateAlertSettings(daily: true, targets: [target]));
    // 사용자가 매일 알림을 끄고 기존 목표를 지운 뒤 새 목표를 추가한 상황.
    final newTarget = RateTarget(
      id: 77,
      unit: 100,
      targetKrw: 900,
      direction: TargetDirection.below,
      active: true,
      createdAt: DateTime(2026, 10, 8, 13),
    );
    final api = _FakeApi({'JPY': _jpyRate},
        onFetch: () => store.save('JPY', RateAlertSettings(targets: [newTarget])));

    await handleRateAlertTask(
        store: store, api: api, cache: cache, notifier: notifier, scheduler: scheduler, now: () => now);

    expect(notifier.shown.map((m) => m.notificationId), [77]);
    expect(notifier.shown.map((m) => m.title), isNot(contains('환율 등락 알림')));
    final saved = await store.read('JPY');
    expect(saved.daily, isFalse);
    expect(saved.targets.single.id, 77);
    expect(saved.targets.single.active, isFalse);
    expect(saved.targets.single.firedAt, now);
  });

  test('조회 중에 알림이 모두 꺼지면 보내지 않는다', () async {
    await store.save('JPY', RateAlertSettings(daily: true, targets: [target]));
    final api = _FakeApi({'JPY': _jpyRate}, onFetch: () => store.save('JPY', RateAlertSettings.empty));

    await handleRateAlertTask(
        store: store, api: api, cache: cache, notifier: notifier, scheduler: scheduler, now: () => now);

    expect(notifier.shown, isEmpty);
    final saved = await store.read('JPY');
    expect(saved.isEnabled, isFalse);
    expect(saved.targets, isEmpty);
  });

  test('마지막 목표가 도달하면 주기 작업을 취소한다', () async {
    await store.save('JPY', RateAlertSettings(targets: [target]));
    final api = _FakeApi({'JPY': _jpyRate});

    await handleRateAlertTask(
        store: store, api: api, cache: cache, notifier: notifier, scheduler: scheduler, now: () => now);

    expect(notifier.shown, hasLength(1));
    expect(scheduler.calls, [false]);
  });

  test('켜진 알림이 남아 있으면 작업을 그대로 둔다', () async {
    await store.save('JPY', RateAlertSettings(daily: true, targets: [target]));
    final api = _FakeApi({'JPY': _jpyRate});

    await handleRateAlertTask(
        store: store, api: api, cache: cache, notifier: notifier, scheduler: scheduler, now: () => now);

    expect(scheduler.calls, isEmpty);
  });
}
