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

    test('기본판은 걸음 감지기 상태를 보지 않는다(멈춰 있어도 예정대로 잰다)', () {
      final policy = TimeSpeedPolicy();
      policy.onStart(const PolicyContext(nowMs: 0));

      expect(policy.onEvent(step(1000, StepState.still), const PolicyContext(nowMs: 1000)), isEmpty);
      expect(afterFix(policy, fix(2000, accuracy: 8, speed: 1.2)), [const WakeAt(tMs: 32000, tag: 'next')]);
      expect(policy.onEvent(const Wakeup(tMs: 32000, tag: 'next'), const PolicyContext(nowMs: 32000)),
          [const RequestFix()]);
    });
  });

  group('TimeSpeedPolicy(stillGate) — EnTracked처럼 멈춰 있으면 GPS를 쉰다', () {
    test('id와 파라미터가 기본판과 구분된다', () {
      final policy = TimeSpeedPolicy(errorBudgetM: 25, stillGate: true);

      expect(policy.id, 'time_speed_still');
      expect(policy.params, {'e_m': 25.0});
    });

    test('멈춘 상태에서 측위가 오면 다음 측위를 예약하지 않고 움직일 때까지 기다린다', () {
      final policy = TimeSpeedPolicy(stillGate: true);
      expect(policy.onStart(const PolicyContext(nowMs: 0)), [const RequestFix()]);

      expect(policy.onEvent(step(1000, StepState.still), const PolicyContext(nowMs: 1000)), isEmpty);
      expect(afterFix(policy, fix(2000, accuracy: 8, speed: 0)), isEmpty);
      // 멈춰 있는 동안은 상태가 다시 와도 아무것도 하지 않는다.
      expect(policy.onEvent(step(60000, StepState.still), const PolicyContext(nowMs: 60000)), isEmpty);
      // 움직이기 시작하면 바로 잰다(EnTracked: 움직임을 감지하면 GPS로 속도를 잰다).
      expect(policy.onEvent(step(90000, StepState.walking), const PolicyContext(nowMs: 90000)),
          [const RequestFix()]);
      // 그 뒤로는 기본판과 같다.
      expect(afterFix(policy, fix(92000, accuracy: 8, speed: 1.2)), [const WakeAt(tMs: 122000, tag: 'next')]);
    });

    test('예약한 시각에 멈춰 있으면 건너뛰고, 다시 움직일 때 잰다', () {
      final policy = TimeSpeedPolicy(stillGate: true);
      policy.onStart(const PolicyContext(nowMs: 0));
      policy.onEvent(step(500, StepState.walking), const PolicyContext(nowMs: 500));
      expect(afterFix(policy, fix(1000, accuracy: 8, speed: 1.2)), [const WakeAt(tMs: 31000, tag: 'next')]);

      expect(policy.onEvent(step(20000, StepState.still), const PolicyContext(nowMs: 20000)), isEmpty);
      expect(policy.onEvent(const Wakeup(tMs: 31000, tag: 'next'), const PolicyContext(nowMs: 31000)), isEmpty);
      expect(policy.onEvent(step(50000, StepState.otherMotion), const PolicyContext(nowMs: 50000)),
          [const RequestFix()]);
    });

    test('예약 시각 전에 멈췄다가 다시 움직여도 바로 재고, 이전 예약은 버린다', () {
      final policy = TimeSpeedPolicy(stillGate: true);
      policy.onStart(const PolicyContext(nowMs: 0));
      policy.onEvent(step(500, StepState.walking), const PolicyContext(nowMs: 500));
      expect(afterFix(policy, fix(1000, accuracy: 8, speed: 1.2)), [const WakeAt(tMs: 31000, tag: 'next')]);

      expect(policy.onEvent(step(5000, StepState.still), const PolicyContext(nowMs: 5000)), isEmpty);
      // 31초 예약이 남아 있어도 움직임을 감지하면 바로 잰다(EnTracked: 움직이면 GPS로 속도를 잰다).
      expect(policy.onEvent(step(10000, StepState.otherMotion), const PolicyContext(nowMs: 10000)),
          [const RequestFix()]);
      // 측위를 기다리는 동안의 상태 변화로는 다시 요청하지 않는다.
      expect(policy.onEvent(step(11000, StepState.still), const PolicyContext(nowMs: 11000)), isEmpty);
      expect(policy.onEvent(step(11500, StepState.walking), const PolicyContext(nowMs: 11500)), isEmpty);
      // 새 속도로 다음 예약: (50 - 8) / 8 = 5.25초.
      expect(afterFix(policy, fix(12000, accuracy: 8, speed: 8)), [const WakeAt(tMs: 17250, tag: 'next')]);
      expect(policy.onEvent(const Wakeup(tMs: 17250, tag: 'next'), const PolicyContext(nowMs: 17250)),
          [const RequestFix()]);
      // 버린 31초 예약이 와도(측위 응답을 기다리는 중) 다시 요청하지 않는다.
      expect(policy.onEvent(const Wakeup(tMs: 31000, tag: 'next'), const PolicyContext(nowMs: 31000)), isEmpty);
      // 응답 뒤 새 예약(22550)보다 이른 버린 예약도 무시한다.
      afterFix(policy, fix(17300, accuracy: 8, speed: 8));
      expect(policy.onEvent(const Wakeup(tMs: 20000, tag: 'next'), const PolicyContext(nowMs: 20000)), isEmpty);
    });

    test('움직이는 동안의 상태 변화(걷기 ↔ 기타 움직임)로는 따로 재지 않는다', () {
      final policy = TimeSpeedPolicy(stillGate: true);
      policy.onStart(const PolicyContext(nowMs: 0));
      policy.onEvent(step(500, StepState.walking), const PolicyContext(nowMs: 500));
      afterFix(policy, fix(1000, accuracy: 8, speed: 1.2));

      expect(policy.onEvent(step(5000, StepState.otherMotion), const PolicyContext(nowMs: 5000)), isEmpty);
      expect(policy.onEvent(step(9000, StepState.walking), const PolicyContext(nowMs: 9000)), isEmpty);
    });

    test('걸음 정보가 아직 없으면 움직이는 것으로 보고 예약한다', () {
      final policy = TimeSpeedPolicy(stillGate: true);
      policy.onStart(const PolicyContext(nowMs: 0));

      expect(afterFix(policy, fix(1000, accuracy: 8, speed: 1.2)), [const WakeAt(tMs: 31000, tag: 'next')]);
    });

    test('멈춘 상태에서 측위에 실패해도 다시 시도한다(머문 곳 위치는 남겨야 한다)', () {
      final policy = TimeSpeedPolicy(stillGate: true);
      policy.onStart(const PolicyContext(nowMs: 0));
      policy.onEvent(step(500, StepState.still), const PolicyContext(nowMs: 500));

      expect(policy.onEvent(const FixResult(tMs: 15000), const PolicyContext(nowMs: 15000)),
          [const WakeAt(tMs: 45000, tag: 'next')]);
      expect(policy.onEvent(const Wakeup(tMs: 45000, tag: 'next'), const PolicyContext(nowMs: 45000)),
          [const RequestFix()]);
    });

    test('다시 시작하면 이전 실행의 상태를 잊는다', () {
      final policy = TimeSpeedPolicy(stillGate: true);
      policy.onStart(const PolicyContext(nowMs: 0));
      policy.onEvent(step(500, StepState.still), const PolicyContext(nowMs: 500));
      afterFix(policy, fix(1000, speed: 0));

      policy.onStart(const PolicyContext(nowMs: 100000));
      expect(afterFix(policy, fix(101000, accuracy: 8, speed: 1.2)), [const WakeAt(tMs: 131000, tag: 'next')]);
    });
  });
}

StepUpdate step(int tMs, StepState state) =>
    StepUpdate(tMs: tMs, state: state, totalSteps: 0, stepsSinceLastFix: 0);
