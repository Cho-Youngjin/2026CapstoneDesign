import 'dart:convert';

import 'package:app/core/network/country_detail_api.dart';
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/rate_alert/background/rate_alert_scheduler.dart';
import 'package:app/features/rate_alert/data/rate_alert_store.dart';
import 'package:app/features/rate_alert/domain/rate_alert_settings.dart';
import 'package:app/features/rate_alert/notify/notification_permission.dart';
import 'package:app/features/rate_alert/rate_alert_page.dart';
import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/data/wallet_rate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../wallet/wallet_fixtures.dart';

class _FakePermission implements NotificationPermission {
  _FakePermission(this.granted);

  final bool granted;
  int requests = 0;

  @override
  Future<bool> request() async {
    requests++;
    return granted;
  }
}

class _FakeScheduler implements RateAlertScheduler {
  final calls = <bool>[];

  @override
  Future<void> sync({required bool enabled}) async => calls.add(enabled);
}

class _Harness {
  _Harness(this.store, this.permission, this.scheduler);

  final RateAlertStore store;
  final _FakePermission permission;
  final _FakeScheduler scheduler;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  bool granted = true,
  RateSnapshot? rate,
  bool withRate = true,
  Map<String, Object> initialPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  final permission = _FakePermission(granted);
  final scheduler = _FakeScheduler();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      countryDetailProvider.overrideWith((ref, iso) async => const CountryDetail(
            isoAlpha2: 'JP',
            nameKo: '일본',
            currencyCode: 'JPY',
            cardAcceptance: 'MEDIUM',
          )),
      walletRateProvider.overrideWith(
          (ref, code) => Stream<RateSnapshot?>.value(withRate ? (rate ?? snapshot()) : null)),
      notificationPermissionProvider.overrideWithValue(permission),
      rateAlertSchedulerProvider.overrideWithValue(scheduler),
    ],
    child: const MaterialApp(home: Scaffold(body: RateAlertPage(isoAlpha2: 'JP'))),
  ));
  await tester.pumpAndSettle();
  return _Harness(RateAlertStore(prefs), permission, scheduler);
}

Future<void> _addTarget(WidgetTester tester, String amount, {TargetDirection? direction}) async {
  if (direction != null) {
    await tester.ensureVisible(find.byKey(Key('direction_${direction.code}')));
    await tester.tap(find.byKey(Key('direction_${direction.code}')));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.byKey(const Key('targetAmountField')));
  await tester.enterText(find.byKey(const Key('targetAmountField')), amount);
  await tester.ensureVisible(find.byKey(const Key('addTargetButton')));
  await tester.tap(find.byKey(const Key('addTargetButton')));
  await tester.pumpAndSettle();
}

bool _switchValue(WidgetTester tester, String key) =>
    tester.widget<Switch>(find.byKey(Key(key))).value;

void main() {
  testWidgets('제목·환율 배너·빈 목표 안내·꺼진 매일 알림을 보여준다', (tester) async {
    await _pump(tester);

    expect(find.text('일본 환율 알림'), findsOneWidget);
    expect(find.text('100엔 = 847.46원'), findsOneWidget);
    expect(find.text('아직 목표가 없습니다.'), findsOneWidget);
    expect(find.text('100엔당 목표 환율'), findsOneWidget);
    expect(_switchValue(tester, 'dailySwitch'), isFalse);
  });

  testWidgets('목표를 추가하면 목록에 보이고, 1단위 기준으로 저장되고, 작업이 등록된다', (tester) async {
    final h = await _pump(tester);

    await _addTarget(tester, '845');

    expect(find.text('100엔당 845원 이하'), findsOneWidget);
    expect(find.text('대기 중'), findsOneWidget);
    expect(find.text('현재 환율이 이미 목표에 도달했어요'), findsNothing);
    final saved = (await h.store.read('JPY')).targets.single;
    expect(saved.krwPerUnit, closeTo(8.45, 1e-9));
    expect(saved.active, isTrue);
    expect(h.scheduler.calls.last, isTrue);
  });

  testWidgets('이미 도달한 목표를 저장하면 바로 알려준다', (tester) async {
    await _pump(tester);

    await _addTarget(tester, '840', direction: TargetDirection.above);

    expect(find.text('100엔당 840원 이상'), findsOneWidget);
    expect(find.text('현재 환율이 이미 목표에 도달했어요'), findsOneWidget);
  });

  testWidgets('금액이 잘못되면 저장하지 않고 안내한다', (tester) async {
    final h = await _pump(tester);

    await _addTarget(tester, '0');

    expect(find.text('금액을 확인해 주세요'), findsOneWidget);
    expect((await h.store.read('JPY')).targets, isEmpty);
    expect(h.permission.requests, 0);
  });

  testWidgets('무한대·NaN은 금액으로 받지 않는다', (tester) async {
    final h = await _pump(tester);

    await _addTarget(tester, 'Infinity');
    expect(find.text('금액을 확인해 주세요'), findsOneWidget);
    expect((await h.store.read('JPY')).targets, isEmpty);

    await _addTarget(tester, 'NaN');
    expect(find.text('금액을 확인해 주세요'), findsOneWidget);
    expect((await h.store.read('JPY')).targets, isEmpty);
    expect(h.permission.requests, 0);
  });

  testWidgets('알림 권한을 거부하면 매일 알림 스위치가 꺼진 채로 남고 안내한다', (tester) async {
    final h = await _pump(tester, granted: false);

    await tester.tap(find.byKey(const Key('dailySwitch')));
    await tester.pumpAndSettle();

    expect(_switchValue(tester, 'dailySwitch'), isFalse);
    expect(find.text('알림 권한이 꺼져 있어 환율 알림을 켤 수 없어요. 설정에서 알림을 허용해 주세요.'),
        findsOneWidget);
    expect((await h.store.read('JPY')).daily, isFalse);
    expect(h.scheduler.calls, isEmpty);
  });

  testWidgets('매일 알림을 켜면 작업을 등록하고, 끄면 취소한다', (tester) async {
    final h = await _pump(tester);

    await tester.tap(find.byKey(const Key('dailySwitch')));
    await tester.pumpAndSettle();
    expect(_switchValue(tester, 'dailySwitch'), isTrue);
    expect(h.scheduler.calls, [true]);

    await tester.tap(find.byKey(const Key('dailySwitch')));
    await tester.pumpAndSettle();
    expect(_switchValue(tester, 'dailySwitch'), isFalse);
    expect(h.scheduler.calls, [true, false]);
    expect(h.permission.requests, 1); // 끌 때는 권한을 묻지 않는다
  });

  testWidgets('도달한 목표는 회색 상태로 보이고, 다시 켜거나 삭제할 수 있다', (tester) async {
    final fired = RateTarget(
      id: 9,
      unit: 100,
      targetKrw: 850,
      direction: TargetDirection.below,
      active: false,
      createdAt: DateTime(2026, 10, 1),
      firedAt: DateTime(2026, 10, 8, 14),
    );
    final h = await _pump(tester, initialPrefs: {
      RateAlertStore.key: jsonEncode({'JPY': RateAlertSettings(targets: [fired]).toJson()}),
    });

    expect(find.text('도달 · 10월 8일'), findsOneWidget);
    expect(_switchValue(tester, 'targetSwitch_9'), isFalse);

    await tester.tap(find.byKey(const Key('targetSwitch_9')));
    await tester.pumpAndSettle();
    final again = (await h.store.read('JPY')).targets.single;
    expect(again.active, isTrue);
    expect(again.firedAt, isNull);
    expect(find.text('대기 중'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deleteTarget_9')));
    await tester.pumpAndSettle();
    expect((await h.store.read('JPY')).targets, isEmpty);
    expect(find.text('아직 목표가 없습니다.'), findsOneWidget);
    expect(h.scheduler.calls.last, isFalse);
  });

  testWidgets('환율을 모르면 목표 추가 폼 대신 안내를 보여준다', (tester) async {
    await _pump(tester, withRate: false);

    expect(find.byKey(const Key('targetAmountField')), findsNothing);
    expect(find.text('환율 정보를 받은 뒤에 목표를 추가할 수 있어요.'), findsOneWidget);
  });
}
