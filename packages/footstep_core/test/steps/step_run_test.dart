import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

OsStepReading count(int tMs, int value) =>
    OsStepReading(tMs: tMs, kind: OsStepReading.count, value: '$value');

/// 걸음 시각을 모르는 감지기 흉내: 가속도 묶음마다 2걸음씩 늘었다고 알리고, 부른 순서를 남긴다.
class _CountOnly implements StepDetector {
  final calls = <String>[];
  int _total = 0;

  @override
  String get id => 'count_only';

  @override
  Map<String, Object> get params => const {};

  @override
  StepState get state => StepState.walking;

  @override
  int get totalSteps => _total;

  @override
  int get stepsSinceLastFix => _total;

  @override
  StepUpdate? onAccel(int tMs, List<AccelReading> batch) {
    calls.add('accel@$tMs');
    _total += 2;
    return StepUpdate(
        tMs: tMs, state: StepState.walking, totalSteps: _total, stepsSinceLastFix: _total);
  }

  @override
  StepUpdate? onOsStep(OsStepReading reading) {
    calls.add('os@${reading.tMs}');
    return null;
  }

  @override
  void onFix() {}
}

void main() {
  final stillAccel = [for (var t = 0; t <= 4990; t += 10) AccelReading(tMs: t, x: 0, y: 9.81, z: 0)];

  test('가속도 묶음과 OS 걸음을 시각순으로 넣고, 걸음 시각과 상태 변화를 모은다', () {
    final data = SessionData(
      sessionId: 's1',
      accel: stillAccel,
      osSteps: [count(1000, 100), count(2000, 103), count(3000, 105)],
    );

    final run = runDetector(data, OsStepDetector());

    expect(run.sessionId, 's1');
    expect(run.detectorId, 'os');
    expect(run.startMs, 0);
    expect(run.endMs, 4990);
    expect(run.stepTimes, [2000, 2000, 2000, 3000, 3000]);
    expect(run.totalSteps, 5);
    expect(run.states.map((s) => (s.tMs, s.state)),
        [(1000, StepState.still), (2000, StepState.walking)]);
  });

  test('걸음 시각을 모르는 감지기는 늘어난 걸음을 알린 시각에 두고, 같은 시각은 가속도 묶음이 먼저다', () {
    final detector = _CountOnly();
    final data = SessionData(
      sessionId: 's2',
      accel: [for (var t = 0; t <= 2000; t += 10) AccelReading(tMs: t, x: 0, y: 9.81, z: 0)],
      osSteps: [count(990, 1)],
    );

    final run = runDetector(data, detector);

    expect(detector.calls, ['accel@990', 'os@990', 'accel@1990', 'accel@2000']);
    expect(run.stepTimes, [990, 990, 1990, 1990, 2000, 2000]);
    expect(run.states.map((s) => s.tMs), [990]); // 상태가 바뀔 때만 남는다
  });

  test('기록이 없는 세션이나 0 이하 묶음 길이는 ArgumentError다', () {
    expect(() => runDetector(const SessionData(sessionId: 'empty'), OsStepDetector()),
        throwsArgumentError);
    expect(
        () => runDetector(SessionData(sessionId: 's', accel: stillAccel), OsStepDetector(),
            accelBatchMs: 0),
        throwsArgumentError);
  });
}
