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
    const ctx0 = PolicyContext(nowMs: 0);
    PolicyContext at(int t) => PolicyContext(nowMs: t);
    Wakeup tick(int t) => Wakeup(tMs: t, tag: 'tick');

    test('보행 중에는 주기마다 측위한다', () {
      final policy = StillSuppressPolicy();
      expect(policy.onStart(ctx0), [const RequestFix(), const WakeAt(tMs: 60000, tag: 'tick')]);

      policy.onEvent(step(1000, StepState.walking), at(1000));
      expect(policy.onEvent(tick(60000), at(60000)),
          [const RequestFix(), const WakeAt(tMs: 120000, tag: 'tick')]);
    });

    test('정지가 직전·이번 확인에서 연달아 보여야 측위를 건너뛴다', () {
      final policy = StillSuppressPolicy()..onStart(ctx0);
      policy.onEvent(step(1000, StepState.still), at(1000));

      // 첫 정지 확인: 잠깐 멈춘 것일 수 있어 아직 측위한다.
      expect(policy.onEvent(tick(60000), at(60000)),
          [const RequestFix(), const WakeAt(tMs: 120000, tag: 'tick')]);
      // 두 번째 연속 정지: 건너뛰고 다음 확인만 예약한다.
      expect(policy.onEvent(tick(120000), at(120000)), [const WakeAt(tMs: 180000, tag: 'tick')]);
    });

    test('억제하는 동안에도 마지막 측위 뒤 5분이 지나면 확인 측위를 한다', () {
      final policy = StillSuppressPolicy()..onStart(ctx0);
      policy.onEvent(step(1000, StepState.still), at(1000));
      policy.onEvent(tick(60000), at(60000)); // 측위(마지막 측위 60초)

      for (final t in [120000, 180000, 240000, 300000]) {
        expect(policy.onEvent(tick(t), at(t)), [WakeAt(tMs: t + 60000, tag: 'tick')], reason: '$t');
      }
      expect(policy.onEvent(tick(360000), at(360000)),
          [const RequestFix(), const WakeAt(tMs: 420000, tag: 'tick')]);
      expect(policy.onEvent(tick(420000), at(420000)), [const WakeAt(tMs: 480000, tag: 'tick')]);
    });

    test('억제 중에 걷기 시작하면 다음 확인에서 바로 측위한다', () {
      final policy = StillSuppressPolicy()..onStart(ctx0);
      policy.onEvent(step(1000, StepState.still), at(1000));
      policy.onEvent(tick(60000), at(60000));
      policy.onEvent(tick(120000), at(120000)); // 억제

      policy.onEvent(step(130000, StepState.walking), at(130000));
      expect(policy.onEvent(tick(180000), at(180000)),
          [const RequestFix(), const WakeAt(tMs: 240000, tag: 'tick')]);
    });

    test('걸음 정보가 아직 없으면 측위한다', () {
      final policy = StillSuppressPolicy(intervalMs: 120000)..onStart(ctx0);

      expect(policy.onEvent(tick(120000), at(120000)),
          [const RequestFix(), const WakeAt(tMs: 240000, tag: 'tick')]);
      expect(policy.id, 'still_suppress');
      expect(policy.params, {'interval_s': 120, 'verify_s': 300});
    });

    test('onStart는 이전 실행의 상태를 지운다', () {
      final policy = StillSuppressPolicy()..onStart(ctx0);
      policy.onEvent(step(1000, StepState.still), at(1000));
      policy.onEvent(tick(60000), at(60000));

      policy.onStart(ctx0); // 같은 인스턴스를 다시 쓴다
      expect(policy.onEvent(tick(60000), at(60000)),
          [const RequestFix(), const WakeAt(tMs: 120000, tag: 'tick')]);
    });
  });
}
