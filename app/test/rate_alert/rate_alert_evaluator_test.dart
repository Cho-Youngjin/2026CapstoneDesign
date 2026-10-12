import 'package:app/features/rate_alert/domain/rate_alert_evaluator.dart';
import 'package:app/features/rate_alert/domain/rate_alert_settings.dart';
import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/domain/currency_info.dart';
import 'package:flutter_test/flutter_test.dart';

ExchangeRate _jpy({double rate = 8.4746, double? previous = 8.4389, DateTime? baseDate}) => ExchangeRate(
      currencyCode: 'JPY',
      krwRate: rate,
      baseDate: baseDate ?? DateTime(2026, 10, 8),
      previousKrwRate: previous,
      previousBaseDate: previous == null ? null : DateTime(2026, 10, 7),
      changePercent: previous == null ? null : 0.42,
      source: 'EXIM',
    );

RateTarget _target({
  int id = 1,
  double krw = 850,
  TargetDirection direction = TargetDirection.below,
  bool active = true,
}) =>
    RateTarget(
      id: id,
      unit: 100,
      targetKrw: krw,
      direction: direction,
      active: active,
      createdAt: DateTime(2026, 10, 1),
    );

void main() {
  final jpy = currencyInfoOf('JPY');
  final now = DateTime(2026, 10, 8, 14, 0);

  RateAlertOutcome run(RateAlertSettings settings, {ExchangeRate? rate}) =>
      evaluateRateAlerts(settings: settings, rate: rate ?? _jpy(), currency: jpy, now: now);

  group('전일 대비 알림', () {
    test('새 고시일이고 이전값이 있으면 보내고 고시일을 기록한다', () {
      final outcome = run(const RateAlertSettings(daily: true));

      final message = outcome.messages.single;
      expect(message.title, '환율 등락 알림');
      expect(message.body, '엔화 100엔 847.46원 · 전 영업일보다 ▲3.57원(0.42%)');
      expect(message.notificationId, dailyNotificationId('JPY'));
      expect(outcome.settings.lastDailyBaseDate, DateTime(2026, 10, 8));
    });

    test('하락이면 ▼로 보낸다', () {
      final outcome = run(const RateAlertSettings(daily: true),
          rate: ExchangeRate(
            currencyCode: 'JPY',
            krwRate: 8.4389,
            baseDate: DateTime(2026, 10, 8),
            previousKrwRate: 8.4746,
            changePercent: -0.42,
            source: 'EXIM',
          ));

      expect(outcome.messages.single.body, '엔화 100엔 843.89원 · 전 영업일보다 ▼3.57원(0.42%)');
    });

    test('같은 고시일로는 두 번 보내지 않는다', () {
      final outcome = run(RateAlertSettings(daily: true, lastDailyBaseDate: DateTime(2026, 10, 8)));

      expect(outcome.messages, isEmpty);
    });

    test('이전값이 없으면 보내지 않고 고시일도 기록하지 않는다', () {
      final outcome = run(const RateAlertSettings(daily: true), rate: _jpy(previous: null));

      expect(outcome.messages, isEmpty);
      expect(outcome.settings.lastDailyBaseDate, isNull);
    });

    test('꺼져 있으면 보내지 않는다', () {
      expect(run(RateAlertSettings.empty).messages, isEmpty);
    });
  });

  group('목표 도달 알림', () {
    test('이하 목표는 환율이 목표와 같으면 보낸다(경계값)', () {
      final outcome = run(RateAlertSettings(targets: [_target(krw: 847.46)]));

      final message = outcome.messages.single;
      expect(message.title, '목표 환율 도달');
      expect(message.body, '엔화 100엔 847.46원 (목표 847.46원 이하)');
      expect(message.notificationId, 1);
      final fired = outcome.settings.targets.single;
      expect(fired.active, isFalse);
      expect(fired.firedAt, now);
    });

    test('이상 목표는 환율이 목표와 같으면 보낸다(경계값)', () {
      final outcome = run(RateAlertSettings(
          targets: [_target(krw: 847.46, direction: TargetDirection.above)]));

      expect(outcome.messages.single.body, '엔화 100엔 847.46원 (목표 847.46원 이상)');
    });

    test('도달하지 않으면 보내지 않고 목표도 그대로다', () {
      final outcome = run(RateAlertSettings(targets: [
        _target(krw: 845),
        _target(id: 2, krw: 850, direction: TargetDirection.above),
      ]));

      expect(outcome.messages, isEmpty);
      expect(outcome.settings.targets.every((t) => t.active), isTrue);
    });

    test('꺼진 목표는 조건을 만족해도 무시한다', () {
      final outcome = run(RateAlertSettings(targets: [_target(krw: 850, active: false)]));

      expect(outcome.messages, isEmpty);
      expect(outcome.settings.targets.single.firedAt, isNull);
    });

    test('여러 목표가 동시에 충족되면 모두 보낸다', () {
      final outcome = run(RateAlertSettings(daily: true, targets: [
        _target(id: 1, krw: 850),
        _target(id: 2, krw: 900),
      ]));

      expect(outcome.messages.map((m) => m.notificationId),
          [dailyNotificationId('JPY'), 1, 2]);
      expect(outcome.settings.targets.every((t) => !t.active), isTrue);
    });
  });

  test('isTargetReached는 표시 단위 금액을 전 단위로 비교한다', () {
    final below = _target(krw: 847.46);
    expect(isTargetReached(below, 8.4746), isTrue);
    expect(isTargetReached(below, 8.4747), isFalse);
  });
}
