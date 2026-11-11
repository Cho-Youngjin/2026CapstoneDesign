import 'dart:math' as math;

import 'package:footstep_core/footstep_core.dart';
import 'package:footstep_core/src/replay/accel_batches.dart';

/// 결정적 난수(선형 합동). 설계 검증에 쓴 Python 시제품과 같은 수열이어야 기대값이 맞는다.
/// 그래서 dart:math의 Random을 쓰지 않는다.
Iterator<double> lcg(int seed) {
  Iterable<double> values() sync* {
    var state = seed;
    while (true) {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      yield state / 0x7fffffff;
    }
  }

  return values().iterator;
}

double _next(Iterator<double> it) {
  it.moveNext();
  return it.current;
}

AccelReading _magnitude(int tMs, double m) => AccelReading(tMs: tMs, x: 0, y: m, z: 0);

/// 보행 흉내: 중력 + [hz]로 출렁이는 사인 + 작은 잡음. 걸음 수 = 사인 주기 수다.
List<AccelReading> walk(int seconds,
    {double hz = 2, double amp = 3, int t0 = 0, int seed = 1, int sampleMs = 10}) {
  final noise = lcg(seed);
  final perSecond = 1000 ~/ sampleMs;
  return [
    for (var i = 0; i < seconds * perSecond; i++)
      _magnitude(t0 + i * sampleMs,
          9.81 + amp * math.sin(2 * math.pi * hz * i / perSecond) + 0.2 * (_next(noise) - 0.5)),
  ];
}

/// 책상 위 정지 흉내(100Hz): 중력 + 아주 작은 잡음.
List<AccelReading> still(int seconds, {int t0 = 0, int seed = 2}) {
  final noise = lcg(seed);
  return [
    for (var i = 0; i < seconds * 100; i++)
      _magnitude(t0 + i * 10, 9.81 + 0.05 * (_next(noise) - 0.5)),
  ];
}

/// 버스 흉내(100Hz): 엔진 진동(12·17.3Hz) + 0.3Hz 좌우 흔들림 + 잡음. 흔들림은 크지만 걸음 박자는 없다.
List<AccelReading> bus(int seconds, {int t0 = 0, int seed = 7}) {
  final noise = lcg(seed);
  return [
    for (var i = 0; i < seconds * 100; i++)
      _magnitude(
          t0 + i * 10,
          9.81 +
              1.5 *
                  (math.sin(2 * math.pi * 12 * i / 100) +
                      0.6 * math.sin(2 * math.pi * 17.3 * i / 100 + 1.0)) +
              0.5 * math.sin(2 * math.pi * 0.3 * i / 100) +
              0.3 * (_next(noise) - 0.5)),
  ];
}

/// 4초 보행(8걸음)을 3초 정지 사이사이에 세 번 — 끊어 걷기(이권희 외 2018의 실험 B와 같은 성격). 정답 24걸음.
List<AccelReading> stopAndGo() {
  final readings = <AccelReading>[];
  var t0 = 0;
  for (var k = 0; k < 3; k++) {
    readings.addAll(still(3, t0: t0, seed: 10 + k));
    t0 += 3000;
    readings.addAll(walk(4, t0: t0, seed: 20 + k));
    t0 += 4000;
  }
  readings.addAll(still(3, t0: t0, seed: 99));
  return readings;
}

/// 정지 3초 → 2초 보행(4걸음) → 정지 5초. 연속 N(5)걸음에 못 미치는 짧은 움직임이다.
List<AccelReading> shortBurst() => [
      ...still(3),
      ...walk(2, t0: 3000, seed: 5),
      ...still(5, t0: 5000, seed: 6),
    ];

/// 15초 보행 → 7초 기록 공백(서비스 재시작) → 15초 보행. 정답 60걸음.
List<AccelReading> gapWalk() => [...walk(15), ...walk(15, t0: 22000, seed: 2)];

/// 재생기와 같은 1초 묶음으로 감지기에 넣고, 나온 StepUpdate를 모은다.
List<StepUpdate> feed(StepDetector detector, List<AccelReading> readings) => [
      for (final batch in accelBatches(readings, 1000))
        ?detector.onAccel(batch.last.tMs, batch),
    ];

/// 한 걸음(1.4Hz)에 봉우리가 둘인 보행 흉내: 기본 박자 + 걸음 대역 안의 강한 2배 박자(2.8Hz).
/// 정답 걸음 수 = 1.4 × 초. 걸음 주기보다 한참 가까운 봉우리를 버리지 않으면 거의 2배로 센다.
List<AccelReading> twoBumpWalk(int seconds, {int seed = 71}) {
  final noise = lcg(seed);
  return [
    for (var i = 0; i < seconds * 100; i++)
      _magnitude(
          i * 10,
          9.81 +
              1.5 * math.sin(2 * math.pi * 1.4 * (i / 100)) +
              3.5 * math.sin(2 * math.pi * 2.8 * (i / 100)) +
              0.2 * (_next(noise) - 0.5)),
  ];
}

/// 10.2초까지 걷다(2Hz) 멈추고, 11.1초에 폰이 한 번 흔들린다(0.5초짜리 봉우리 하나). 16초 길이.
/// 멈춘 뒤의 흔들림은 걸음이 아니다.
List<AccelReading> stopThenBump({int seed = 1}) {
  final noise = lcg(seed);
  return [
    for (var i = 0; i < 1600; i++)
      _magnitude(
          i * 10,
          9.81 +
              (i * 10 < 10200
                  ? 3 * math.sin(2 * math.pi * 2 * i / 100)
                  : (i * 10 >= 11100 && i * 10 < 11600)
                      ? 3 * math.sin(2 * math.pi * 2 * (i * 10 - 11100) / 1000)
                      : 0.0) +
              0.2 * (_next(noise) - 0.5)),
  ];
}
