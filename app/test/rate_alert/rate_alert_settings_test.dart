import 'package:app/features/rate_alert/domain/rate_alert_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final target = RateTarget(
    id: 123,
    unit: 100,
    targetKrw: 845,
    direction: TargetDirection.below,
    active: false,
    createdAt: DateTime(2026, 10, 11, 9, 30),
    firedAt: DateTime(2026, 10, 12, 11, 10),
  );

  test('표시 단위로 받은 목표를 1단위 기준으로 바꾼다', () {
    expect(target.krwPerUnit, closeTo(8.45, 1e-9));
  });

  test('JSON 왕복 후에도 같은 값이다', () {
    final settings = RateAlertSettings(
      daily: true,
      lastDailyBaseDate: DateTime(2026, 10, 8),
      targets: [target],
    );

    final restored = RateAlertSettings.fromJson(settings.toJson());

    expect(restored.daily, isTrue);
    expect(restored.lastDailyBaseDate, DateTime(2026, 10, 8));
    final t = restored.targets.single;
    expect(t.id, 123);
    expect(t.unit, 100);
    expect(t.targetKrw, 845);
    expect(t.direction, TargetDirection.below);
    expect(t.active, isFalse);
    expect(t.createdAt, DateTime(2026, 10, 11, 9, 30));
    expect(t.firedAt, DateTime(2026, 10, 12, 11, 10));
  });

  test('매일 알림이나 켜진 목표가 하나라도 있으면 켜진 설정이다', () {
    expect(RateAlertSettings.empty.isEnabled, isFalse);
    expect(const RateAlertSettings(daily: true).isEnabled, isTrue);
    expect(RateAlertSettings(targets: [target]).isEnabled, isFalse); // 도달해서 꺼진 목표만 있음
    expect(RateAlertSettings(targets: [target.copyWith(active: true)]).isEnabled, isTrue);
  });

  test('다시 켜면 도달 시각을 지울 수 있다', () {
    final again = target.copyWith(active: true, clearFiredAt: true);
    expect(again.active, isTrue);
    expect(again.firedAt, isNull);
  });

  test('목표 금액 표기는 불필요한 소수를 붙이지 않는다', () {
    expect(formatTargetKrw(850), '850원');
    expect(formatTargetKrw(1339.5), '1,339.5원');
    expect(formatTargetKrw(52.25), '52.25원');
  });

  test('새 목표 id는 안드로이드 알림 id(32비트) 범위다', () {
    final id = newTargetId(DateTime(2026, 10, 11, 9, 30, 15, 123));
    expect(id, greaterThanOrEqualTo(0));
    expect(id, lessThan(1000000000));
  });
}
