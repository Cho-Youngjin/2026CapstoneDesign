import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

import 'synthetic.dart';

void main() {
  test('2Hz 보행 30초(60걸음)를 거의 그대로 센다', () {
    final detector = BrajdicDetector();
    final updates = feed(detector, walk(30));

    expect(detector.totalSteps, inInclusiveRange(58, 61));
    expect(updates.last.state, StepState.walking);
    expect(updates.last.cadenceHz, isNull);
    final times = detector.takeStepTimes();
    expect(times, hasLength(detector.totalSteps));
    expect(times, orderedEquals([...times]..sort()));
    expect(detector.takeStepTimes(), isEmpty); // 가져가면 비운다
  });

  test('걸음 빠르기가 달라도 센다(1.5Hz·2.4Hz)', () {
    final slow = BrajdicDetector();
    feed(slow, walk(30, hz: 1.5, seed: 3));
    expect(slow.totalSteps, inInclusiveRange(43, 46));
    final fast = BrajdicDetector();
    feed(fast, walk(30, hz: 2.4, seed: 4));
    expect(fast.totalSteps, inInclusiveRange(69, 73));
  });

  test('표본 간격이 달라도(50Hz 기기) 같은 결과다', () {
    final detector = BrajdicDetector();
    feed(detector, walk(30, sampleMs: 20));
    expect(detector.totalSteps, inInclusiveRange(58, 61));
  });

  test('기록 공백(7초) 건너편을 한 창에 섞지 않는다', () {
    final detector = BrajdicDetector();
    feed(detector, gapWalk());
    // 공백 뒤 창이 다시 찰 때까지(약 0.8초) 첫 걸음 한두 개는 놓친다.
    expect(detector.totalSteps, inInclusiveRange(55, 61));
  });

  test('공백 앞뒤 표본을 한 창에 섞지 않아, 공백 앞 걷기만 돌린 결과와 같다', () {
    final walkOnly = BrajdicDetector();
    feed(walkOnly, walk(5));
    final detector = BrajdicDetector();
    // 5초 걷기 → 7초 공백 → 정지. 창을 비우지 않으면 공백 앞 걸음 흔들림이 공백 뒤 정지 구간의 보행 판정과
    // 봉우리에 섞여 가짜 걸음이 생긴다.
    feed(detector, [...walk(5), ...still(5, t0: 12000)]);
    expect(detector.takeStepTimes(), walkOnly.takeStepTimes());
  });

  test('정지면 0걸음이고, 0.8초 창이 찬 첫 묶음에서 정지를 한 번 알린다', () {
    final detector = BrajdicDetector();
    final updates = feed(detector, still(20));
    expect(updates, hasLength(1));
    expect(updates.single.tMs, 990);
    expect(updates.single.state, StepState.still);
    expect(detector.totalSteps, 0);
  });

  test('연속 확인이 없어 짧은 움직임도 센다(논문 방식 그대로)', () {
    final detector = BrajdicDetector();
    feed(detector, shortBurst());
    expect(detector.totalSteps, inInclusiveRange(3, 6));
  });

  test('기타 움직임을 구분하지 않아 버스 진동을 걸음으로 센다(제안판과 비교하려는 약점)', () {
    final detector = BrajdicDetector();
    final updates = feed(detector, bus(60));
    expect(detector.totalSteps, greaterThan(10));
    expect(updates.map((u) => u.state), isNot(contains(StepState.otherMotion)));
  });

  test('onFix는 마지막 측위 이후 걸음 수를 0으로 되돌리고, OS 걸음 읽기는 무시한다', () {
    final detector = BrajdicDetector();
    feed(detector, walk(10));
    final before = detector.totalSteps;
    detector.onFix();
    expect(detector.stepsSinceLastFix, 0);
    expect(detector.onOsStep(const OsStepReading(tMs: 1, kind: OsStepReading.count, value: '5')),
        isNull);
    expect(detector.totalSteps, before);
  });

  test('id와 파라미터', () {
    final detector = BrajdicDetector();
    expect(detector.id, 'brajdic');
    expect(detector.params, {'std_th': 0.6, 'smooth_s': 0.31, 'peak_win_s': 0.59});
  });

  test('걸음 시각은 중심 이동 평균 기준이라 사인 봉우리 근처에 놓인다', () {
    final detector = BrajdicDetector();
    feed(detector, walk(10));
    // 2Hz 사인의 봉우리는 125 + 500k ms다. 격자(20ms)와 잡음 때문에 앞뒤 40ms 안이면 된다.
    for (final t in detector.takeStepTimes()) {
      final offset = (t - 125) % 500;
      expect(offset <= 40 || offset >= 460, isTrue, reason: '걸음 시각 $t');
    }
  });
}
