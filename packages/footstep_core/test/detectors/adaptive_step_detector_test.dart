import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

import 'synthetic.dart';

void main() {
  test('2Hz 보행 30초(60걸음)를 세고, 보행 상태와 걸음 빠르기(2Hz)를 알린다', () {
    final detector = AdaptiveStepDetector();
    final updates = feed(detector, walk(30));

    expect(detector.totalSteps, inInclusiveRange(58, 61));
    expect(updates.last.state, StepState.walking);
    expect(updates.last.cadenceHz, closeTo(2.0, 0.1));
    final times = detector.takeStepTimes();
    expect(times, hasLength(detector.totalSteps));
    expect(times, orderedEquals([...times]..sort()));
  });

  test('연속 N(5)걸음을 확인한 뒤 기다리던 걸음을 소급해 센다', () {
    final detector = AdaptiveStepDetector();
    final updates = feed(detector, walk(30));
    final first = updates.firstWhere((u) => u.totalSteps > 0);

    expect(first.state, StepState.walking);
    expect(first.totalSteps, greaterThanOrEqualTo(5));
    // 소급분이라 첫 걸음 시각은 그 사건보다 이르다.
    expect(detector.takeStepTimes().first, lessThan(first.tMs - 2000));
  });

  test('걸음 빠르기가 달라도 센다(1.5Hz·2.4Hz)', () {
    final slow = AdaptiveStepDetector();
    feed(slow, walk(30, hz: 1.5, seed: 3));
    expect(slow.totalSteps, inInclusiveRange(43, 46));
    final fast = AdaptiveStepDetector();
    feed(fast, walk(30, hz: 2.4, seed: 4));
    expect(fast.totalSteps, inInclusiveRange(70, 73));
  });

  test('끊어 걷기(8걸음 × 3)를 센다', () {
    final detector = AdaptiveStepDetector();
    feed(detector, stopAndGo());
    expect(detector.totalSteps, inInclusiveRange(22, 25));
  });

  test('연속 N걸음에 못 미치는 짧은 움직임(4걸음)은 세지 않는다', () {
    final detector = AdaptiveStepDetector();
    feed(detector, shortBurst());
    expect(detector.totalSteps, 0);
  });

  test('버스 진동은 흔들림만 있고 박자가 없어 기타 움직임이고 0걸음이다', () {
    final detector = AdaptiveStepDetector();
    final updates = feed(detector, bus(60));
    expect(detector.totalSteps, 0);
    expect(updates.map((u) => u.state).toSet(), {StepState.otherMotion});
  });

  test('정지면 0걸음이고, 0.8초 창이 찬 첫 묶음에서 정지를 한 번 알린다', () {
    final detector = AdaptiveStepDetector();
    final updates = feed(detector, still(20));
    expect(updates, hasLength(1));
    expect(updates.single.tMs, 990);
    expect(updates.single.state, StepState.still);
    expect(updates.single.cadenceHz, isNull);
  });

  test('표본 간격이 달라도(50Hz 기기) 같은 결과다', () {
    final detector = AdaptiveStepDetector();
    feed(detector, walk(30, sampleMs: 20));
    expect(detector.totalSteps, inInclusiveRange(58, 61));
  });

  test('기록 공백(7초) 뒤에는 처음부터 다시 확인한다', () {
    final detector = AdaptiveStepDetector();
    feed(detector, gapWalk());
    expect(detector.totalSteps, inInclusiveRange(56, 61));
  });

  test('onFix는 마지막 측위 이후 걸음 수를 0으로 되돌리고, OS 걸음 읽기는 무시한다', () {
    final detector = AdaptiveStepDetector();
    feed(detector, walk(10));
    detector.onFix();
    expect(detector.stepsSinceLastFix, 0);
    expect(detector.onOsStep(const OsStepReading(tMs: 1, kind: OsStepReading.count, value: '5')),
        isNull);
  });

  test('id와 파라미터', () {
    final detector = AdaptiveStepDetector();
    expect(detector.id, 'adaptive');
    expect(detector.params,
        {'std_th': 0.6, 'band_std_th': 0.3, 'ac_th': 0.4, 'n_confirm': 5, 'max_gap_s': 1.5});
  });
}
