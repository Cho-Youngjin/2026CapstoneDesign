import '../detectors/step_detector.dart';
import '../detectors/step_timeline.dart';
import '../events/policy_event.dart';
import '../replay/accel_batches.dart';
import '../session/session_reader.dart';

/// 감지기 상태가 바뀐 순간(첫 분류 포함).
class StateChange {
  const StateChange({required this.tMs, required this.state, this.cadenceHz});

  final int tMs;
  final StepState state;
  final double? cadenceHz;
}

/// 걸음 감지기 하나를 정책 없이 세션에 돌린 결과. 걸음 감지 평가(설계 7-2)의 입력이다.
class StepRun {
  const StepRun({
    required this.sessionId,
    required this.detectorId,
    required this.detectorParams,
    required this.startMs,
    required this.endMs,
    required this.stepTimes,
    required this.states,
  });

  final String sessionId;
  final String detectorId;
  final Map<String, Object> detectorParams;
  final int startMs;
  final int endMs;

  /// 센 걸음마다 그 걸음의 시각(오름차순).
  final List<int> stepTimes;

  /// 상태가 바뀐 순간들(시각순).
  final List<StateChange> states;

  int get totalSteps => stepTimes.length;
}

/// [data]의 가속도 묶음과 OS 걸음을 시각순으로 [detector]에 넣는다. 묶는 규칙과 같은 시각의 순서(가속도 묶음
/// 먼저)는 재생기와 같다 — 재생 결과와 걸음 평가가 같은 감지기 동작을 보게 한다.
StepRun runDetector(SessionData data, StepDetector detector, {int accelBatchMs = 1000}) {
  final start = data.startMs;
  final end = data.endMs;
  if (start == null || end == null) {
    throw ArgumentError('기록이 없는 세션입니다: ${data.sessionId}');
  }
  if (accelBatchMs <= 0) throw ArgumentError('accelBatchMs는 양수여야 합니다: $accelBatchMs');

  final batches = accelBatches(data.accel, accelBatchMs).toList();
  final osSteps = data.osSteps;
  final stepTimes = <int>[];
  final states = <StateChange>[];
  var lastTotal = 0;

  void handle(StepUpdate? update) {
    if (detector case final StepTimeline timeline) {
      stepTimes.addAll(timeline.takeStepTimes());
    } else if (update != null && update.totalSteps > lastTotal) {
      // 걸음 시각을 모르는 감지기는 늘어난 걸음을 알린 시각에 둔다.
      stepTimes.addAll(List.filled(update.totalSteps - lastTotal, update.tMs));
    }
    if (update == null) return;
    lastTotal = update.totalSteps;
    if (states.isEmpty || states.last.state != update.state) {
      states.add(StateChange(tMs: update.tMs, state: update.state, cadenceHz: update.cadenceHz));
    }
  }

  var i = 0;
  var j = 0;
  while (i < batches.length || j < osSteps.length) {
    final takeBatch =
        j >= osSteps.length || (i < batches.length && batches[i].last.tMs <= osSteps[j].tMs);
    if (takeBatch) {
      final batch = batches[i++];
      handle(detector.onAccel(batch.last.tMs, batch));
    } else {
      handle(detector.onOsStep(osSteps[j++]));
    }
  }
  stepTimes.sort();

  return StepRun(
    sessionId: data.sessionId,
    detectorId: detector.id,
    detectorParams: detector.params,
    startMs: start,
    endMs: end,
    stepTimes: stepTimes,
    states: states,
  );
}
