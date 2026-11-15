import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

OsStepReading count(int tMs, int value) =>
    OsStepReading(tMs: tMs, kind: OsStepReading.count, value: '$value');

OsStepReading status(int tMs, String value) =>
    OsStepReading(tMs: tMs, kind: OsStepReading.status, value: value);

void main() {
  test('첫 누적값은 기준이고, 늘어나면 보행과 걸음 수를 알린다', () {
    final detector = OsStepDetector();

    // 첫 읽기는 정지 상태를 처음 알리는 사건이다(걸음 수는 기준이라 0).
    final first = detector.onOsStep(count(1000, 1520))!;
    expect(first.state, StepState.still);
    expect(first.totalSteps, 0);
    final update = detector.onOsStep(count(2000, 1525))!;

    expect(update.tMs, 2000);
    expect(update.state, StepState.walking);
    expect(update.totalSteps, 5);
    expect(update.stepsSinceLastFix, 5);
    expect(detector.id, 'os');
  });

  test('마지막 걸음 뒤 4초가 지나면 가속도 묶음 시각으로 정지를 알린다', () {
    final detector = OsStepDetector()
      ..onOsStep(count(1000, 100))
      ..onOsStep(count(2000, 103));

    expect(detector.onAccel(5000, const []), isNull); // 3초 뒤: 아직 보행
    final update = detector.onAccel(6500, const [])!;
    expect(update.state, StepState.still);
    expect(detector.onAccel(7500, const []), isNull); // 이미 정지
  });

  test('OS 상태가 walking이면 걸음 누적이 늦게 와도 보행으로 본다', () {
    final detector = OsStepDetector();

    expect(detector.onOsStep(status(1000, 'walking'))!.state, StepState.walking);
    expect(detector.onAccel(20000, const []), isNull);
    expect(detector.onOsStep(status(21000, 'stopped'))!.state, StepState.still);
  });

  test('onFix는 마지막 측위 이후 걸음 수를 0으로 되돌린다', () {
    final detector = OsStepDetector()
      ..onOsStep(count(1000, 0))
      ..onOsStep(count(2000, 10));
    expect(detector.stepsSinceLastFix, 10);

    detector.onFix();
    expect(detector.stepsSinceLastFix, 0);
    final update = detector.onOsStep(count(3000, 14))!;
    expect(update.stepsSinceLastFix, 4);
    expect(update.totalSteps, 14);
  });

  test('누적값이 줄면(재부팅 등) 기준을 다시 잡아 걸음을 이어 센다', () {
    final detector = OsStepDetector()
      ..onOsStep(count(1000, 500))
      ..onOsStep(count(2000, 510));

    detector.onOsStep(count(3000, 3));
    final update = detector.onOsStep(count(4000, 8))!;
    expect(update.totalSteps, 15);
  });

  group('첫 분류', () {
    test('정지로 시작하면 첫 OS 걸음 읽기에서 정지를 정확히 한 번 알린다', () {
      final detector = OsStepDetector();

      final first = detector.onOsStep(count(1000, 700))!;
      expect(first.tMs, 1000);
      expect(first.state, StepState.still);
      expect(first.totalSteps, 0);

      // 이후 같은 정지 상태는 다시 알리지 않는다.
      expect(detector.onOsStep(count(2000, 700)), isNull);
      expect(detector.onOsStep(status(3000, 'stopped')), isNull);
      expect(detector.onAccel(4000, const []), isNull);
    });

    test('OS 상태 읽기가 첫 입력이어도 첫 분류를 알린다', () {
      final detector = OsStepDetector();

      expect(detector.onOsStep(status(1000, 'stopped'))!.state, StepState.still);
      expect(detector.onOsStep(status(2000, 'stopped')), isNull);
    });

    test('OS 걸음 읽기가 오기 전에는 가속도 묶음만으로 분류하지 않는다', () {
      final detector = OsStepDetector();

      expect(detector.onAccel(1000, const []), isNull);
      expect(detector.onAccel(9000, const []), isNull);
      expect(detector.onOsStep(count(10000, 5))!.state, StepState.still);
    });

    test('받아들이지 못한 읽기(숫자가 아닌 누적값)는 첫 분류가 되지 않는다', () {
      final detector = OsStepDetector();

      expect(detector.onOsStep(OsStepReading(tMs: 1000, kind: OsStepReading.count, value: 'x')), isNull);
      expect(detector.onOsStep(count(2000, 5))!.state, StepState.still);
    });

    test('첫 분류 뒤에는 이전처럼 바뀔 때만 알린다', () {
      final detector = OsStepDetector();

      expect(detector.onOsStep(count(1000, 100))!.state, StepState.still);
      expect(detector.onOsStep(count(2000, 104))!.state, StepState.walking);
      expect(detector.onAccel(5000, const []), isNull);
      expect(detector.onAccel(6500, const [])!.state, StepState.still);
    });

    test('보행으로 시작하면 첫 분류가 보행이고 중복해서 알리지 않는다', () {
      final detector = OsStepDetector();

      expect(detector.onOsStep(status(1000, 'walking'))!.state, StepState.walking);
      expect(detector.onOsStep(status(2000, 'walking')), isNull);
    });
  });

  test('늘어난 걸음은 읽은 시각으로 걸음 시각에 남고, 가져가면 비운다', () {
    final detector = OsStepDetector()
      ..onOsStep(count(1000, 100))
      ..onOsStep(count(2000, 103))
      ..onOsStep(count(3000, 105));

    expect(detector.takeStepTimes(), [2000, 2000, 2000, 3000, 3000]);
    expect(detector.takeStepTimes(), isEmpty);
    expect(detector.params, {'walking_window_s': 4.0});
  });
}
