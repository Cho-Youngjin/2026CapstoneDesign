import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

StepUpdate step(int tMs, StepState state) =>
    StepUpdate(tMs: tMs, state: state, totalSteps: 0, stepsSinceLastFix: 0);

void main() {
  group('FixedIntervalPolicy (현재 앱 1시간 방식, 고정 주기)', () {
    test('시작하면 바로 측위하고 다음 주기를 예약한다', () {
      final policy = FixedIntervalPolicy(id: 'fixed_1m', intervalMs: 60000);

      expect(policy.onStart(const PolicyContext(nowMs: 1000)),
          [const RequestFix(), const WakeAt(tMs: 61000, tag: 'tick')]);
      expect(policy.id, 'fixed_1m');
      expect(policy.params, {'interval_s': 60});
    });

    test('주기가 되면 측위하고 그 시각 기준으로 다음 주기를 예약한다', () {
      final policy = FixedIntervalPolicy(id: 'hourly', intervalMs: 3600000);

      expect(policy.onEvent(const Wakeup(tMs: 3601000, tag: 'tick'), const PolicyContext(nowMs: 3601000)),
          [const RequestFix(), const WakeAt(tMs: 7201000, tag: 'tick')]);
    });

    test('다른 사건에는 아무것도 하지 않는다', () {
      final policy = FixedIntervalPolicy(id: 'fixed_30s', intervalMs: 30000);
      const ctx = PolicyContext(nowMs: 5000);

      expect(policy.onEvent(const Wakeup(tMs: 5000, tag: 'other'), ctx), isEmpty);
      expect(policy.onEvent(step(5000, StepState.walking), ctx), isEmpty);
      expect(policy.onEvent(const FixResult(tMs: 5000), ctx), isEmpty);
    });
  });

  group('ContinuousPolicy (현재 앱 10m 연속 방식)', () {
    test('시작하면 1초·10m 연속 측위를 켜고 그 뒤에는 아무것도 하지 않는다', () {
      final policy = ContinuousPolicy();

      expect(policy.onStart(const PolicyContext(nowMs: 0)),
          [const StartContinuous(intervalMs: 1000, distanceFilterM: 10)]);
      expect(policy.onEvent(const Wakeup(tMs: 10, tag: 'tick'), const PolicyContext(nowMs: 10)),
          isEmpty);
      expect(policy.id, 'continuous_10m');
      expect(policy.params, {'interval_ms': 1000, 'distance_filter_m': 10.0});
    });
  });

  group('StillSuppressPolicy (Zhuang 외 2010: 정지 중 측위 억제)', () {
    test('보행 중에는 주기마다 측위한다', () {
      final policy = StillSuppressPolicy();
      expect(policy.onStart(const PolicyContext(nowMs: 0)),
          [const RequestFix(), const WakeAt(tMs: 60000, tag: 'tick')]);

      policy.onEvent(step(1000, StepState.walking), const PolicyContext(nowMs: 1000));
      expect(policy.onEvent(const Wakeup(tMs: 60000, tag: 'tick'), const PolicyContext(nowMs: 60000)),
          [const RequestFix(), const WakeAt(tMs: 120000, tag: 'tick')]);
    });

    test('정지 중에는 측위를 건너뛰고 다음 주기만 예약한다', () {
      final policy = StillSuppressPolicy()..onStart(const PolicyContext(nowMs: 0));

      policy.onEvent(step(1000, StepState.still), const PolicyContext(nowMs: 1000));
      expect(policy.onEvent(const Wakeup(tMs: 60000, tag: 'tick'), const PolicyContext(nowMs: 60000)),
          [const WakeAt(tMs: 120000, tag: 'tick')]);
    });

    test('걸음 정보가 아직 없으면 측위한다', () {
      final policy = StillSuppressPolicy(intervalMs: 120000)..onStart(const PolicyContext(nowMs: 0));

      expect(policy.onEvent(const Wakeup(tMs: 120000, tag: 'tick'), const PolicyContext(nowMs: 120000)),
          [const RequestFix(), const WakeAt(tMs: 240000, tag: 'tick')]);
      expect(policy.id, 'still_suppress');
      expect(policy.params, {'interval_s': 120});
    });
  });
}
