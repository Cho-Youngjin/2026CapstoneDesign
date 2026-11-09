import '../events/policy_event.dart';
import '../model/readings.dart';
import 'step_detector.dart';

/// OS 걸음 센서판 감지기(설계 5-2). 누적 걸음 수가 최근 [walkingWindowMs] 안에 늘었거나 OS 보행 상태가
/// walking이면 보행, 아니면 정지로 본다. 흔들림을 보지 않으므로 기타 움직임(탈것)은 구분하지 못한다.
///
/// OS 걸음 센서는 걸음을 몇 초씩 묶어 늦게 알리기도 한다. 그래서 정지 판단은 걸음 이벤트가 아니라 가속도
/// 묶음 시각([onAccel])을 시계로 삼아 내린다.
class OsStepDetector implements StepDetector {
  OsStepDetector({this.walkingWindowMs = 4000});

  final int walkingWindowMs;

  int? _base;
  int _total = 0;
  int _totalAtLastFix = 0;
  int? _lastIncreaseMs;
  String _lastStatus = 'unknown';
  StepState _state = StepState.still;

  @override
  String get id => 'os';

  @override
  StepState get state => _state;

  @override
  int get totalSteps => _total;

  @override
  int get stepsSinceLastFix => _total - _totalAtLastFix;

  @override
  StepUpdate? onOsStep(OsStepReading reading) {
    var increased = false;
    if (reading.kind == OsStepReading.count) {
      final value = int.tryParse(reading.value);
      if (value == null) return null;
      final base = _base ??= value;
      final total = value - base;
      if (total < _total) {
        // 누적값이 줄었다(재부팅 등). 지금까지 센 걸음을 이어 가도록 기준을 다시 잡는다.
        _base = value - _total;
      } else if (total > _total) {
        _total = total;
        _lastIncreaseMs = reading.tMs;
        increased = true;
      }
    } else if (reading.kind == OsStepReading.status) {
      _lastStatus = reading.value;
    }
    return _update(reading.tMs, stepsChanged: increased);
  }

  @override
  StepUpdate? onAccel(int tMs, List<AccelReading> batch) => _update(tMs, stepsChanged: false);

  @override
  void onFix() => _totalAtLastFix = _total;

  StepUpdate? _update(int tMs, {required bool stepsChanged}) {
    final last = _lastIncreaseMs;
    final recentlyStepped = last != null && tMs - last <= walkingWindowMs;
    final next =
        recentlyStepped || _lastStatus == 'walking' ? StepState.walking : StepState.still;
    if (next == _state && !stepsChanged) return null;
    _state = next;
    return StepUpdate(
      tMs: tMs,
      state: _state,
      totalSteps: _total,
      stepsSinceLastFix: stepsSinceLastFix,
    );
  }
}
