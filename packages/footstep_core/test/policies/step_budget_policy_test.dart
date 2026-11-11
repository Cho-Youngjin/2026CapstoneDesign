import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

StepUpdate step(int tMs, StepState state, [int steps = 0]) =>
    StepUpdate(tMs: tMs, state: state, totalSteps: steps, stepsSinceLastFix: steps);

/// 기준 위치(북위 37.5°)에서 [dLat]도 북쪽. 0.001°는 약 111m, 0.003°는 약 334m다.
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

/// 기타 움직임의 확인 측위로 탈것이 된 정책과 마지막 탈것 측위(64초). 다음 깨우기는 69초의 `vehicle#3`이다.
(StepBudgetPolicy, Fix) inVehicle() {
  final (p, f0) = started();
  p.onEvent(step(2000, StepState.otherMotion), at(2000, f0));
  p.onEvent(wake(32000, 'probe1#1'), at(32000, f0));
  final probe1 = fixAt(33000);
  p.onEvent(ok(probe1), at(33000, probe1));
  p.onEvent(wake(63000, 'probe2#2'), at(63000, probe1));
  final probe2 = fixAt(64000, dLat: 0.003);
  p.onEvent(ok(probe2), at(64000, probe2));
  return (p, probe2);
}

/// 탈것 상태에서 예약 [first]에 깨어 1초 뒤 [place](측위 시각 → 북쪽 위도 차) 위치를 받는 일을, 정책이 탈것 예약을
/// 그만 낼 때까지(최대 [maxFixes]번) 되풀이한다. 받은 측위 시각들과 마지막 응답에 낸 할 일을 돌려준다.
(List<int>, List<PolicyAction>) ride(
  StepBudgetPolicy p,
  Fix last,
  WakeAt first, {
  double Function(int tMs)? place,
  int maxFixes = 30,
}) {
  var w = first;
  final times = <int>[];
  var actions = <PolicyAction>[];
  for (var i = 0; i < maxFixes; i++) {
    expect(p.onEvent(wake(w.tMs, w.tag), at(w.tMs, last)), [const RequestFix()]);
    final t = w.tMs + 1000;
    final f = fixAt(t, dLat: place == null ? 0.003 : place(t));
    actions = p.onEvent(ok(f), at(t, f));
    times.add(t);
    last = f;
    final next = actions.length == 1 ? actions.single : null;
    if (next is! WakeAt || !next.tag.startsWith('vehicle#')) break;
    w = next;
  }
  return (times, actions);
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

    test('측위 오차만으로 E를 넘어도(빌딩 숲) 마지막 측위 뒤 5초 안에는 다시 재지 않는다', () {
      final p = StepBudgetPolicy();
      p.onStart(at(0));
      final f0 = fixAt(1000, accuracyM: 60);
      p.onEvent(ok(f0), at(1000, f0));

      expect(p.onEvent(step(2000, StepState.walking, 1), at(2000, f0)), isEmpty);
      expect(p.onEvent(step(5999, StepState.walking, 6), at(5999, f0)), isEmpty);
      expect(p.onEvent(step(6000, StepState.walking, 7), at(6000, f0)), [const RequestFix()]);
    });

    test('배터리가 20% 미만이면 E를 2배로 보고, 20% 이상이 되면 되돌린다', () {
      final (p, f0) = started();
      p.onEvent(step(2000, StepState.walking), at(2000, f0));
      p.onEvent(const BatteryLevel(tMs: 2500, pct: 19), at(2500, f0));

      // 5 + 126 × 0.75 = 99.5 ≤ 100
      expect(p.onEvent(step(7000, StepState.walking, 126), at(7000, f0)), isEmpty);
      // 5 + 127 × 0.75 = 100.25 > 100
      expect(p.onEvent(step(8000, StepState.walking, 127), at(8000, f0)), [const RequestFix()]);

      final f1 = fixAt(9000);
      p.onEvent(ok(f1), at(9000, f1));
      p.onEvent(const BatteryLevel(tMs: 9500, pct: 20), at(9500, f1));
      // 5 + 61 × 0.75 = 50.75 > 50
      expect(p.onEvent(step(15000, StepState.walking, 61), at(15000, f1)), [const RequestFix()]);
    });

    test('걸음 수를 쓰지 않으면(절제) 걷기 속도 1.4m/s로 짐작해 오차가 E를 넘는 시각에 잰다', () {
      final (p, f0) = started(StepBudgetPolicy(useSteps: false));
      // (50 − 5) / 1.4 = 32.143초. 걸음 수는 보지 않는다.
      expect(p.onEvent(step(2000, StepState.walking, 999), at(2000, f0)), [const WakeAt(tMs: 33143, tag: 'budget#1')]);
      expect(p.onEvent(wake(33143, 'budget#1'), at(33143, f0)), [const RequestFix()]);

      final f1 = fixAt(34000);
      expect(p.onEvent(ok(f1), at(34000, f1)), [const WakeAt(tMs: 66143, tag: 'budget#2')]);
    });
  });

  group('정지', () {
    test('정지가 30초 이어지면 한 번 재어 머문 곳을 남기고, 그 뒤로는 5분마다 확인만 한다', () {
      final (p, f0) = started();
      expect(p.onEvent(step(2000, StepState.still), at(2000, f0)), [const WakeAt(tMs: 32000, tag: 'stay#1')]);
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

    test('확인한 위치가 머문 곳과 두 오차의 합 안이면(실내 GPS 튐) E보다 멀어도 벗어난 것으로 보지 않는다', () {
      final (p, f0) = started();
      p.onEvent(step(2000, StepState.still), at(2000, f0));
      p.onEvent(wake(32000, 'stay#1'), at(32000, f0));
      final stay = fixAt(33000, accuracyM: 60);
      p.onEvent(ok(stay), at(33000, stay));
      p.onEvent(wake(333000, 'check#2'), at(333000, stay));

      final jumped = fixAt(334000, dLat: 0.0007, accuracyM: 60); // 약 78m: E(50m)보다 멀지만 두 오차의 합(120m) 안
      expect(p.onEvent(ok(jumped), at(334000, jumped)), [const WakeAt(tMs: 634000, tag: 'check#3')]);
      expect(p.stateLabel, 'still');
    });

    test('정지 억제를 끄면(절제) 정지해도 걷기 속도로 짐작해 계속 잰다', () {
      final (p, f0) = started(StepBudgetPolicy(suppressStill: false));
      expect(p.onEvent(step(2000, StepState.still), at(2000, f0)), [const WakeAt(tMs: 33143, tag: 'budget#1')]);
      expect(p.onEvent(wake(33143, 'budget#1'), at(33143, f0)), [const RequestFix()]);

      final f1 = fixAt(34000);
      expect(p.onEvent(ok(f1), at(34000, f1)), [const WakeAt(tMs: 66143, tag: 'budget#2')]);
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
      expect(p.onEvent(step(2000, StepState.otherMotion), at(2000, f0)), [const WakeAt(tMs: 32000, tag: 'probe1#1')]);
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

    test('확인 측위 두 위치가 서로의 오차 안이면 빨라 보여도 탈것으로 보지 않는다', () {
      final (p, f0) = started();
      p.onEvent(step(2000, StepState.otherMotion), at(2000, f0));
      p.onEvent(wake(32000, 'probe1#1'), at(32000, f0));
      final probe1 = fixAt(33000, accuracyM: 60);
      p.onEvent(ok(probe1), at(33000, probe1));
      p.onEvent(wake(63000, 'probe2#2'), at(63000, probe1));

      // 약 111m / 31초 ≈ 3.6m/s로 시속 12km를 넘지만, 두 오차의 합(120m) 안이다.
      final probe2 = fixAt(64000, dLat: 0.001, accuracyM: 60);
      expect(p.onEvent(ok(probe2), at(64000, probe2)), [const WakeAt(tMs: 364000, tag: 'check#3')]);
      expect(p.stateLabel, 'otherMotion');
    });

    test('탈것 기준은 속도라 E와 묶지 않는다(E가 커도 오차 밖으로 시속 12km 넘게 움직이면 탈것)', () {
      final (p, f0) = started(StepBudgetPolicy(errorBudgetM: 150));
      p.onEvent(step(2000, StepState.otherMotion), at(2000, f0));
      p.onEvent(wake(32000, 'probe1#1'), at(32000, f0));
      final probe1 = fixAt(33000);
      p.onEvent(ok(probe1), at(33000, probe1));
      p.onEvent(wake(63000, 'probe2#2'), at(63000, probe1));

      final probe2 = fixAt(64000, dLat: 0.0012); // 약 133m / 31초 ≈ 4.3m/s: E(150m) 안, 두 오차의 합(10m) 밖
      // (150 − 5) / 4.304 = 33.687초 뒤
      expect(p.onEvent(ok(probe2), at(64000, probe2)), [const WakeAt(tMs: 97687, tag: 'vehicle#3')]);
      expect(p.stateLabel, 'vehicle');
    });

    test('탈것 확인을 끄면(절제) 기타 움직임을 정지처럼 다룬다', () {
      final (p, f0) = started(StepBudgetPolicy(vehicleProbe: false));
      expect(p.onEvent(step(2000, StepState.otherMotion), at(2000, f0)), [const WakeAt(tMs: 32000, tag: 'stay#1')]);
      expect(p.onEvent(wake(32000, 'stay#1'), at(32000, f0)), [const RequestFix()]);
      final stay = fixAt(33000);
      expect(p.onEvent(ok(stay), at(33000, stay)), [const WakeAt(tMs: 333000, tag: 'check#2')]);
      expect(p.stateLabel, 'otherMotion');
    });

    test('정지 억제를 끄면(절제) 정지처럼 다루는 기타 움직임도 걷기 속도로 짐작해 계속 잰다', () {
      final (p, f0) = started(StepBudgetPolicy(suppressStill: false, vehicleProbe: false));
      expect(p.onEvent(step(2000, StepState.otherMotion), at(2000, f0)), [const WakeAt(tMs: 33143, tag: 'budget#1')]);
      expect(p.onEvent(wake(33143, 'budget#1'), at(33143, f0)), [const RequestFix()]);
      final f1 = fixAt(34000);
      expect(p.onEvent(ok(f1), at(34000, f1)), [const WakeAt(tMs: 66143, tag: 'budget#2')]);
    });

    test('정지 억제를 끄면(절제) 느린 확인 측위 뒤에도 5분 확인 대신 계속 잰다', () {
      final (p, f0) = started(StepBudgetPolicy(suppressStill: false));
      p.onEvent(step(2000, StepState.otherMotion), at(2000, f0));
      p.onEvent(wake(32000, 'probe1#1'), at(32000, f0));
      final probe1 = fixAt(33000);
      p.onEvent(ok(probe1), at(33000, probe1));
      p.onEvent(wake(63000, 'probe2#2'), at(63000, probe1));

      final probe2 = fixAt(64000);
      // (50 − 5) / 1.4 = 32.143초 뒤
      expect(p.onEvent(ok(probe2), at(64000, probe2)), [const WakeAt(tMs: 96143, tag: 'budget#3')]);
      expect(p.onEvent(wake(96143, 'budget#3'), at(96143, probe2)), [const RequestFix()]);
      final f2 = fixAt(97000);
      expect(p.onEvent(ok(f2), at(97000, f2)), [const WakeAt(tMs: 129143, tag: 'budget#4')]);
    });

    test('정지 억제를 꺼도, 기타 움직임 전에 낸 요청의 응답이 확인 측위 예약을 덮어쓰지 않는다', () {
      final (p, f0) = started(StepBudgetPolicy(suppressStill: false));
      p.onEvent(step(2000, StepState.walking), at(2000, f0));
      expect(p.onEvent(step(40000, StepState.walking, 61), at(40000, f0)), [const RequestFix()]);
      expect(p.onEvent(step(41000, StepState.otherMotion), at(41000, f0)), [const WakeAt(tMs: 71000, tag: 'probe1#1')]);

      final f1 = fixAt(42000);
      expect(p.onEvent(ok(f1), at(42000, f1)), isEmpty);
      expect(p.onEvent(wake(71000, 'probe1#1'), at(71000, f1)), [const RequestFix()]);
    });

    test('탈것에서 잠깐 정지(신호 대기)는 탈것 그대로다', () {
      final (p, v) = inVehicle();
      expect(p.onEvent(step(66000, StepState.still), at(66000, v)), isEmpty);
      expect(p.stateLabel, 'vehicle');

      expect(p.onEvent(wake(69000, 'vehicle#3'), at(69000, v)), [const RequestFix()]);
      final v1 = fixAt(70000, dLat: 0.003); // 그 자리지만 정지 4초째
      expect(p.onEvent(ok(v1), at(70000, v1)), [const WakeAt(tMs: 83500, tag: 'vehicle#4')]);
      expect(p.stateLabel, 'vehicle');
    });

    test('탈것에서 감지기 정지와 측위상 한 자리가 둘 다 2분 넘게 이어지면 정지로 바꿔 5분마다 확인한다', () {
      final (p, v) = inVehicle(); // 64초 측위까지 움직였다
      p.onEvent(step(66000, StepState.still), at(66000, v));
      p.onEvent(step(68000, StepState.still), at(68000, v)); // 같은 정지를 다시 알려도 시계는 66초부터다

      final (times, last) = ride(p, v, const WakeAt(tMs: 69000, tag: 'vehicle#3'));
      // 그 자리에서 속도 하한으로 13.5초마다 재다가, 정지 66초부터 2분이 된 186초 측위에서 정지로 바꾼다.
      expect(times, [70000, 84500, 99000, 113500, 128000, 142500, 157000, 171500, 186000]);
      expect(last, [const WakeAt(tMs: 486000, tag: 'check#12')]);
      expect(p.stateLabel, 'still');
    });

    test('감지기가 늘 정지인 채로(OS 센서판의 버스) 탈것을 찾았으면, 정류장 정차는 마지막으로 움직인 때부터 잰다', () {
      final (p, f0) = started();
      p.onEvent(step(2000, StepState.still), at(2000, f0)); // 이 뒤로 감지기는 계속 정지다
      p.onEvent(wake(32000, 'stay#1'), at(32000, f0));
      final stay = fixAt(33000);
      p.onEvent(ok(stay), at(33000, stay));
      p.onEvent(wake(333000, 'check#2'), at(333000, stay));
      final moved = fixAt(334000, dLat: 0.003); // 탈것을 찾았고, 버스는 여기 정류장에 섰다
      p.onEvent(ok(moved), at(334000, moved));

      final (times, last) = ride(p, moved, const WakeAt(tMs: 347500, tag: 'vehicle#3'));
      // 감지기 정지는 2초부터지만, 측위로 마지막 움직임을 본 334초부터 2분이 지난 464.5초에야 정지로 바꾼다.
      expect(times, [348500, 363000, 377500, 392000, 406500, 421000, 435500, 450000, 464500]);
      expect(last, [const WakeAt(tMs: 764500, tag: 'check#12')]);
    });

    test('탈것에서 감지기가 다시 흔들림(기타 움직임)을 알리면 그 자리여도 탈것 그대로다', () {
      final (p, v) = inVehicle();
      p.onEvent(step(66000, StepState.still), at(66000, v));
      p.onEvent(step(67000, StepState.otherMotion), at(67000, v));

      final (times, last) = ride(p, v, const WakeAt(tMs: 69000, tag: 'vehicle#3'), maxFixes: 15);
      expect(times, hasLength(15)); // 약 3분 반
      expect(last.single, isA<WakeAt>().having((w) => w.tag, 'tag', 'vehicle#18'));
      expect(p.stateLabel, 'vehicle');
    });

    test('탈것에서 감지기가 2분 넘게 정지여도 측위가 계속 움직이면(기어가는 버스) 탈것 그대로다', () {
      final (p, v) = inVehicle();
      p.onEvent(step(66000, StepState.still), at(66000, v));

      // 초당 0.00002°(약 2.2m/s, 시속 8km): 한 번(14.5초)에 약 32m로 두 오차의 합(10m)보다 멀지만 E(50m) 안이다.
      final (times, last) = ride(
        p,
        v,
        const WakeAt(tMs: 69000, tag: 'vehicle#3'),
        place: (t) => 0.003 + 0.00002 * (t - 64000) / 1000,
        maxFixes: 15,
      );
      expect(times, hasLength(15));
      expect(last.single, isA<WakeAt>().having((w) => w.tag, 'tag', 'vehicle#18'));
      expect(p.stateLabel, 'vehicle');
    });
    test('탈것이 달리다 다른 곳에 서면, 선 뒤 첫 측위부터 2분이 지나야 정지로 바꾼다', () {
      final (p, v) = inVehicle();
      p.onEvent(step(66000, StepState.still), at(66000, v)); // 감지기는 달리는 동안에도 정지다

      // 초당 0.00007°(약 7.8m/s)로 달리다 100초에 섰다.
      final (times, last) = ride(
        p,
        v,
        const WakeAt(tMs: 69000, tag: 'vehicle#3'),
        place: (t) => 0.003 + 0.00007 * ((t < 100000 ? t : 100000) - 64000) / 1000,
      );
      // 달리는 동안은 속도에 맞춰 약 6.8초마다, 선 뒤로는 속도 하한으로 14.5초마다 잰다. 선 뒤 첫 측위(103.9초)부터
      // 2분이 지난 234.4초 측위에서 정지로 바꾼다.
      expect(times, [
        70000, 76781, 83562, 90343, 97124, 103905, //
        118405, 132905, 147405, 161905, 176405, 190905, 205405, 219905, 234405,
      ]);
      expect(last, [const WakeAt(tMs: 534405, tag: 'check#18')]);
      expect(p.stateLabel, 'still');
    });

    test('탈것이 아주 느리게라도 오차 밖으로 계속 움직이면(정체 속 서행) 2분이 지나도 탈것 그대로다', () {
      final (p, v) = inVehicle();
      p.onEvent(step(66000, StepState.still), at(66000, v));

      // 초당 0.0000027°(약 0.3m/s): 2분에 약 36m로 E(50m) 안이지만, 약 45초마다 두 오차의 합(10m)을 벗어난다.
      final (times, last) = ride(
        p,
        v,
        const WakeAt(tMs: 69000, tag: 'vehicle#3'),
        place: (t) => 0.003 + 0.0000027 * (t - 64000) / 1000,
        maxFixes: 15,
      );
      expect(times, hasLength(15));
      expect(last.single, isA<WakeAt>().having((w) => w.tag, 'tag', 'vehicle#18'));
      expect(p.stateLabel, 'vehicle');
    });
  });

  group('멈춤·폭주 방지', () {
    test('탈것 측위를 기다리는 중에 걷기 시작하면 그 응답으로 탈것 예약을 다시 걸지 않는다', () {
      final (p, v) = inVehicle();
      expect(p.onEvent(wake(69000, 'vehicle#3'), at(69000, v)), [const RequestFix()]);
      p.onEvent(step(69500, StepState.walking), at(69500, v));

      final f = fixAt(70000, dLat: 0.003);
      expect(p.onEvent(ok(f), at(70000, f)), isEmpty);
      expect(p.stateLabel, 'walking');
    });

    test('확인 측위가 실패하면 다시 시도한 응답도 확인 측위로 다룬다', () {
      final (p, f0) = started();
      p.onEvent(step(2000, StepState.still), at(2000, f0));
      p.onEvent(wake(32000, 'stay#1'), at(32000, f0));
      final stay = fixAt(33000);
      p.onEvent(ok(stay), at(33000, stay));

      expect(p.onEvent(wake(333000, 'check#2'), at(333000, stay)), [const RequestFix()]);
      expect(p.onEvent(failed(348000), at(348000, stay)), [const WakeAt(tMs: 378000, tag: 'retry#3')]);
      expect(p.onEvent(wake(378000, 'retry#3'), at(378000, stay)), [const RequestFix()]);
      final same = fixAt(379000);
      expect(p.onEvent(ok(same), at(379000, same)), [const WakeAt(tMs: 679000, tag: 'check#4')]);
    });

    test('실패 뒤 기다리는 동안 머문 곳 측위 시각이 와도 잃지 않고, 다시 시도할 때 잰다', () {
      final p = StepBudgetPolicy();
      p.onStart(at(0));
      expect(p.onEvent(step(5000, StepState.still), at(5000)), [const WakeAt(tMs: 35000, tag: 'stay#1')]);
      expect(p.onEvent(failed(15000), at(15000)), [const WakeAt(tMs: 45000, tag: 'retry#2')]);
      expect(p.onEvent(wake(35000, 'stay#1'), at(35000)), isEmpty);

      expect(p.onEvent(wake(45000, 'retry#2'), at(45000)), [const RequestFix()]);
      final stay = fixAt(46000);
      expect(p.onEvent(ok(stay), at(46000, stay)), [const WakeAt(tMs: 346000, tag: 'check#3')]);
    });

    test('정지 억제를 끄면, 새 측위가 앞 위치로 잡은 걷기 속도 예약을 이 위치 기준으로 다시 잡는다', () {
      final (p, f0) = started(StepBudgetPolicy(suppressStill: false));
      p.onEvent(step(2000, StepState.walking), at(2000, f0));
      expect(p.onEvent(step(20000, StepState.walking, 61), at(20000, f0)), [const RequestFix()]);
      // 응답을 기다리는 동안 멈췄다: 마지막 위치(1초) 기준으로 예약한다.
      expect(p.onEvent(step(21000, StepState.still), at(21000, f0)), [const WakeAt(tMs: 33143, tag: 'budget#1')]);

      final f1 = fixAt(22000);
      expect(p.onEvent(ok(f1), at(22000, f1)), [const WakeAt(tMs: 54143, tag: 'budget#2')]);
      expect(p.onEvent(wake(33143, 'budget#1'), at(33143, f1)), isEmpty);
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
      expect(p.onEvent(step(now + 11000, StepState.walking, 100), at(now + 11000, fix)), [const RequestFix()]);
      seq++;
      expect(p.onEvent(failed(now + 26000), at(now + 26000)), [WakeAt(tMs: now + 56000, tag: 'retry#$seq')]);
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
      expect(p.onEvent(step(7000, StepState.walking, 61), at(7000, f1)), [const RequestFix()]);
    });
  });
}
