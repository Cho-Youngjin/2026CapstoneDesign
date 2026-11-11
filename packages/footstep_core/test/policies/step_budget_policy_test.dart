import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

StepUpdate step(int tMs, StepState state, [int steps = 0]) =>
    StepUpdate(tMs: tMs, state: state, totalSteps: steps, stepsSinceLastFix: steps);

/// 기준 위치(북위 37.5°)에서 [dLat]도 북쪽. 0.003°는 약 334m다.
Fix fixAt(int tMs, {double dLat = 0, double accuracyM = 5}) =>
    Fix(tMs: tMs, lat: 37.5 + dLat, lng: 127.0, accuracyM: accuracyM);

PolicyContext at(int nowMs, [Fix? lastFix]) => PolicyContext(nowMs: nowMs, lastFix: lastFix);

FixResult ok(Fix fix) => FixResult(tMs: fix.tMs, fix: fix);

FixResult failed(int tMs) => FixResult(tMs: tMs);

Wakeup wake(int tMs, String tag) => Wakeup(tMs: tMs, tag: tag);

/// 시작 측위(1초)를 받은 정책과 그 위치.
(StepBudgetPolicy, Fix) started([StepBudgetPolicy? policy]) {
  final p = policy ?? StepBudgetPolicy();
  p.onStart(at(0));
  final f0 = fixAt(1000);
  p.onEvent(ok(f0), at(1000, f0));
  return (p, f0);
}

void main() {
  test('시작하면 바로 한 번 측위하고, 걸음 정보 전에는 상태를 모른다', () {
    final policy = StepBudgetPolicy();
    expect(policy.onStart(at(0)), [const RequestFix()]);
    expect(policy.stateLabel, 'unknown');
    expect(policy.id, 'step_budget');
    expect(policy.params, {
      'e_m': 50.0,
      'stride_m': 0.75,
      'use_steps': true,
      'suppress_still': true,
      'vehicle_probe': true,
    });
  });

  group('보행', () {
    test('마지막 오차 + 걸음 수 × 보폭이 E를 넘을 때만 측위하고, 응답을 기다리는 동안은 다시 요청하지 않는다', () {
      final (p, f0) = started();
      expect(p.onEvent(step(2000, StepState.walking), at(2000, f0)), isEmpty);
      expect(p.stateLabel, 'walking');

      // 5 + 60 × 0.75 = 50: 아직 넘지 않았다.
      expect(p.onEvent(step(30000, StepState.walking, 60), at(30000, f0)), isEmpty);
      // 5 + 61 × 0.75 = 50.75 > 50.
      expect(p.onEvent(step(31000, StepState.walking, 61), at(31000, f0)), [const RequestFix()]);
      expect(p.onEvent(step(32000, StepState.walking, 62), at(32000, f0)), isEmpty);

      final f1 = fixAt(33000);
      expect(p.onEvent(ok(f1), at(33000, f1)), isEmpty);
      expect(p.onEvent(step(34000, StepState.walking, 1), at(34000, f1)), isEmpty);
    });

    test('배터리가 20% 미만이면 E를 2배로 보고, 다시 오르면 되돌린다', () {
      final (p, f0) = started();
      p.onEvent(step(2000, StepState.walking), at(2000, f0));
      p.onEvent(const BatteryLevel(tMs: 2500, pct: 19), at(2500, f0));

      // 5 + 126 × 0.75 = 99.5 ≤ 100
      expect(p.onEvent(step(3000, StepState.walking, 126), at(3000, f0)), isEmpty);
      // 5 + 127 × 0.75 = 100.25 > 100
      expect(p.onEvent(step(4000, StepState.walking, 127), at(4000, f0)), [const RequestFix()]);

      final f1 = fixAt(5000);
      p.onEvent(ok(f1), at(5000, f1));
      p.onEvent(const BatteryLevel(tMs: 5500, pct: 50), at(5500, f1));
      expect(p.onEvent(step(6000, StepState.walking, 61), at(6000, f1)), [const RequestFix()]);
    });

    test('걸음 수를 쓰지 않으면(절제) 걷기 속도 1.4m/s로 짐작해 오차가 E를 넘는 시각에 잰다', () {
      final (p, f0) = started(StepBudgetPolicy(useSteps: false));
      // (50 − 5) / 1.4 = 32.143초. 걸음 수는 보지 않는다.
      expect(p.onEvent(step(2000, StepState.walking, 999), at(2000, f0)),
          [const WakeAt(tMs: 33143, tag: 'budget#1')]);
      expect(p.onEvent(wake(33143, 'budget#1'), at(33143, f0)), [const RequestFix()]);

      final f1 = fixAt(34000);
      expect(p.onEvent(ok(f1), at(34000, f1)), [const WakeAt(tMs: 66143, tag: 'budget#2')]);
    });
  });

  group('정지', () {
    test('정지가 30초 이어지면 한 번 재어 머문 곳을 남기고, 그 뒤로는 5분마다 확인만 한다', () {
      final (p, f0) = started();
      expect(p.onEvent(step(2000, StepState.still), at(2000, f0)),
          [const WakeAt(tMs: 32000, tag: 'stay#1')]);
      expect(p.stateLabel, 'still');
      expect(p.onEvent(wake(32000, 'stay#1'), at(32000, f0)), [const RequestFix()]);

      final stay = fixAt(33000);
      expect(p.onEvent(ok(stay), at(33000, stay)), [const WakeAt(tMs: 333000, tag: 'check#2')]);
      expect(p.onEvent(wake(333000, 'check#2'), at(333000, stay)), [const RequestFix()]);

      final same = fixAt(334000, dLat: 0.0001); // 약 11m: 머문 곳 그대로
      expect(p.onEvent(ok(same), at(334000, same)), [const WakeAt(tMs: 634000, tag: 'check#3')]);
      expect(p.stateLabel, 'still');
    });

    test('정지가 30초 이어지지 않으면(잠깐 멈춤) 재지 않는다', () {
      final (p, f0) = started();
      p.onEvent(step(2000, StepState.still), at(2000, f0));
      expect(p.onEvent(step(10000, StepState.walking), at(10000, f0)), isEmpty);
      expect(p.onEvent(wake(32000, 'stay#1'), at(32000, f0)), isEmpty);
    });

    test('확인한 위치가 머문 곳에서 벗어났으면 걸음 없이 움직이는 탈것으로 보고 time_speed 규칙으로 잰다', () {
      final (p, f0) = started();
      p.onEvent(step(2000, StepState.still), at(2000, f0));
      p.onEvent(wake(32000, 'stay#1'), at(32000, f0));
      final stay = fixAt(33000);
      p.onEvent(ok(stay), at(33000, stay));
      p.onEvent(wake(333000, 'check#2'), at(333000, stay));

      final moved = fixAt(334000, dLat: 0.003); // 약 334m
      // 속도 하한 시속 12km(3.333m/s): (50 − 5) / 3.333 = 13.5초 뒤
      expect(p.onEvent(ok(moved), at(334000, moved)), [const WakeAt(tMs: 347500, tag: 'vehicle#3')]);
      expect(p.stateLabel, 'vehicle');
    });

    test('정지 억제를 끄면(절제) 정지해도 걷기 속도로 짐작해 계속 잰다', () {
      final (p, f0) = started(StepBudgetPolicy(suppressStill: false));
      expect(p.onEvent(step(2000, StepState.still), at(2000, f0)),
          [const WakeAt(tMs: 33143, tag: 'budget#1')]);
    });

    test('상태가 바뀌면 앞 상태에서 예약한 깨우기는 무시한다', () {
      final (p, f0) = started();
      p.onEvent(step(2000, StepState.still), at(2000, f0));
      p.onEvent(wake(32000, 'stay#1'), at(32000, f0));
      final stay = fixAt(33000);
      p.onEvent(ok(stay), at(33000, stay)); // check#2 예약

      p.onEvent(step(60000, StepState.walking), at(60000, stay));
      expect(p.onEvent(wake(333000, 'check#2'), at(333000, stay)), isEmpty);
    });
  });

  group('기타 움직임과 탈것', () {
    test('30초 이어지면 30초 간격 확인 측위 두 번의 속도를 보고, 시속 12km 이상이면 탈것이며 탈것 진동은 다시 확인하지 않는다', () {
      final (p, f0) = started();
      expect(p.onEvent(step(2000, StepState.otherMotion), at(2000, f0)),
          [const WakeAt(tMs: 32000, tag: 'probe1#1')]);
      expect(p.stateLabel, 'otherMotion');
      expect(p.onEvent(wake(32000, 'probe1#1'), at(32000, f0)), [const RequestFix()]);

      final probe1 = fixAt(33000);
      expect(p.onEvent(ok(probe1), at(33000, probe1)), [const WakeAt(tMs: 63000, tag: 'probe2#2')]);
      expect(p.onEvent(wake(63000, 'probe2#2'), at(63000, probe1)), [const RequestFix()]);

      final probe2 = fixAt(64000, dLat: 0.003); // 약 334m / 31초 ≈ 10.8m/s
      // (50 − 5) / 10.8 ≈ 4.2초 → 최소 5초
      expect(p.onEvent(ok(probe2), at(64000, probe2)), [const WakeAt(tMs: 69000, tag: 'vehicle#3')]);
      expect(p.stateLabel, 'vehicle');

      expect(p.onEvent(step(65000, StepState.otherMotion), at(65000, probe2)), isEmpty);
      expect(p.stateLabel, 'vehicle');

      expect(p.onEvent(wake(69000, 'vehicle#3'), at(69000, probe2)), [const RequestFix()]);
      final v1 = fixAt(70000, dLat: 0.003); // 신호 대기: 그대로 → 속도 하한으로 13.5초
      expect(p.onEvent(ok(v1), at(70000, v1)), [const WakeAt(tMs: 83500, tag: 'vehicle#4')]);

      // 내려서 걸으면 보행이고, 탈것 예약은 무시한다.
      expect(p.onEvent(step(71000, StepState.walking), at(71000, v1)), isEmpty);
      expect(p.stateLabel, 'walking');
      expect(p.onEvent(wake(83500, 'vehicle#4'), at(83500, v1)), isEmpty);
    });

    test('확인 측위 두 번이 느리면(폰 만지기 등) 정지처럼 5분마다 확인만 한다', () {
      final (p, f0) = started();
      p.onEvent(step(2000, StepState.otherMotion), at(2000, f0));
      p.onEvent(wake(32000, 'probe1#1'), at(32000, f0));
      final probe1 = fixAt(33000);
      p.onEvent(ok(probe1), at(33000, probe1));
      p.onEvent(wake(63000, 'probe2#2'), at(63000, probe1));

      final probe2 = fixAt(64000);
      expect(p.onEvent(ok(probe2), at(64000, probe2)), [const WakeAt(tMs: 364000, tag: 'check#3')]);
      expect(p.stateLabel, 'otherMotion');
    });

    test('탈것 확인을 끄면(절제) 기타 움직임을 정지처럼 다룬다', () {
      final (p, f0) = started(StepBudgetPolicy(vehicleProbe: false));
      expect(p.onEvent(step(2000, StepState.otherMotion), at(2000, f0)),
          [const WakeAt(tMs: 32000, tag: 'stay#1')]);
      expect(p.onEvent(wake(32000, 'stay#1'), at(32000, f0)), [const RequestFix()]);
      final stay = fixAt(33000);
      expect(p.onEvent(ok(stay), at(33000, stay)), [const WakeAt(tMs: 333000, tag: 'check#2')]);
      expect(p.stateLabel, 'otherMotion');
    });
  });

  test('측위가 거듭 실패하면 30초 → 1분 → 2분 → 5분(최대)으로 늘리고, 그 사이에는 걸음이 넘쳐도 요청하지 않는다', () {
    final p = StepBudgetPolicy();
    p.onStart(at(0));
    expect(p.onEvent(failed(15000), at(15000)), [const WakeAt(tMs: 45000, tag: 'retry#1')]);
    expect(p.onEvent(step(20000, StepState.walking, 100), at(20000)), isEmpty);

    var now = 45000;
    var seq = 1;
    for (final delay in [60000, 120000, 300000, 300000]) {
      expect(p.onEvent(wake(now, 'retry#$seq'), at(now)), [const RequestFix()]);
      final failAt = now + 15000;
      seq++;
      expect(p.onEvent(failed(failAt), at(failAt)), [WakeAt(tMs: failAt + delay, tag: 'retry#$seq')]);
      now = failAt + delay;
    }

    // 성공하면 다시 30초부터다.
    expect(p.onEvent(wake(now, 'retry#$seq'), at(now)), [const RequestFix()]);
    final fix = fixAt(now + 5000);
    expect(p.onEvent(ok(fix), at(now + 5000, fix)), isEmpty);
    expect(p.onEvent(step(now + 6000, StepState.walking, 100), at(now + 6000, fix)), [const RequestFix()]);
    seq++;
    expect(p.onEvent(failed(now + 21000), at(now + 21000)),
        [WakeAt(tMs: now + 51000, tag: 'retry#$seq')]);
  });

  test('onStart는 이전 실행의 상태를 지운다', () {
    final (p, f0) = started();
    p.onEvent(step(2000, StepState.still), at(2000, f0));
    p.onEvent(const BatteryLevel(tMs: 2500, pct: 10), at(2500, f0));

    expect(p.onStart(at(0)), [const RequestFix()]);
    expect(p.stateLabel, 'unknown');
    final f1 = fixAt(1000);
    p.onEvent(ok(f1), at(1000, f1));
    p.onEvent(step(2000, StepState.walking), at(2000, f1));
    expect(p.onEvent(step(3000, StepState.walking, 61), at(3000, f1)), [const RequestFix()]);
  });
}
