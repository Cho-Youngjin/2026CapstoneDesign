import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

Fix fix(int tMs, {double accuracy = 8, double? speed}) =>
    Fix(tMs: tMs, lat: 37.5, lng: 127.0, accuracyM: accuracy, speedMps: speed);

List<PolicyAction> afterFix(CollectionPolicy policy, Fix f) =>
    policy.onEvent(FixResult(tMs: f.tMs, fix: f), PolicyContext(nowMs: f.tMs, lastFix: f));

void main() {
  group('SpeedAdaptivePolicy (Galeana-Zapién 외 2014: 속도에 따라 간격 조절)', () {
    test('시작하면 측위하고, 깨어나면 다시 측위한다', () {
      final policy = SpeedAdaptivePolicy();

      expect(policy.onStart(const PolicyContext(nowMs: 0)), [const RequestFix()]);
      expect(policy.onEvent(const Wakeup(tMs: 30000, tag: 'next'), const PolicyContext(nowMs: 30000)),
          [const RequestFix()]);
      expect(policy.id, 'speed_adaptive');
    });

    test('마지막 속도 구간에 따라 다음 측위 간격을 정한다', () {
      final policy = SpeedAdaptivePolicy();

      expect(afterFix(policy, fix(10000, speed: 0.2)), [const WakeAt(tMs: 130000, tag: 'next')]);
      expect(afterFix(policy, fix(10000, speed: 1.3)), [const WakeAt(tMs: 40000, tag: 'next')]);
      expect(afterFix(policy, fix(10000, speed: 8)), [const WakeAt(tMs: 20000, tag: 'next')]);
      expect(afterFix(policy, fix(10000)), [const WakeAt(tMs: 40000, tag: 'next')]); // 속도 모름 → 보행 간격
    });

    test('측위에 실패하면 30초 뒤 다시 시도한다', () {
      final policy = SpeedAdaptivePolicy();

      expect(policy.onEvent(const FixResult(tMs: 15000), const PolicyContext(nowMs: 15000)),
          [const WakeAt(tMs: 45000, tag: 'next')]);
    });
  });

  group('TimeSpeedPolicy (EnTracked·RAPS: 마지막 오차 + 속도 × 시간 > E이면 측위)', () {
    test('오차 예산이 다 찰 시각에 깨어나 측위한다', () {
      final policy = TimeSpeedPolicy();

      expect(policy.onStart(const PolicyContext(nowMs: 0)), [const RequestFix()]);
      // (50 - 8) / max(1.2, 1.4) = 30초
      expect(afterFix(policy, fix(0, accuracy: 8, speed: 1.2)), [const WakeAt(tMs: 30000, tag: 'next')]);
      expect(policy.onEvent(const Wakeup(tMs: 30000, tag: 'next'), const PolicyContext(nowMs: 30000)),
          [const RequestFix()]);
    });

    test('빠르면 최소 5초, 오차가 이미 예산보다 크면 최소 간격으로 다시 잰다', () {
      final policy = TimeSpeedPolicy();

      expect(afterFix(policy, fix(0, accuracy: 8, speed: 10)), [const WakeAt(tMs: 5000, tag: 'next')]);
      expect(afterFix(policy, fix(0, accuracy: 60, speed: 1.0)), [const WakeAt(tMs: 5000, tag: 'next')]);
    });

    test('정지해 있어도 걷기 속도(1.4m/s)를 하한으로 써서 10분을 넘기지 않는다', () {
      final policy = TimeSpeedPolicy(errorBudgetM: 25);

      // (25 - 5) / 1.4 = 14.2857초 → 14286ms
      expect(afterFix(policy, fix(0, accuracy: 5, speed: 0)), [const WakeAt(tMs: 14286, tag: 'next')]);
      expect(policy.params, {'e_m': 25.0});
      expect(policy.id, 'time_speed');
    });

    test('측위에 실패하면 30초 뒤 다시 시도한다', () {
      final policy = TimeSpeedPolicy();

      expect(policy.onEvent(const FixResult(tMs: 15000), const PolicyContext(nowMs: 15000)),
          [const WakeAt(tMs: 45000, tag: 'next')]);
    });
  });
}
