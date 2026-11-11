import '../events/policy_event.dart';
import '../model/readings.dart';
import 'step_detector.dart';
import 'step_timeline.dart';

/// OS 걸음 센서판 감지기(설계 5-2). 누적 걸음 수가 최근 [walkingWindowMs] 안에 늘었거나 OS 보행 상태가
/// walking이면 보행, 아니면 정지로 본다. 흔들림을 보지 않으므로 기타 움직임(탈것)은 구분하지 못한다.
///
/// OS 걸음 센서는 걸음을 몇 초씩 묶어 늦게 알리기도 한다. 그래서 정지 판단은 걸음 이벤트가 아니라 가속도
/// 묶음 시각([onAccel])을 시계로 삼아 내린다.
class OsStepDetector implements StepDetector, StepTimeline {
  OsStepDetector({this.walkingWindowMs = 4000});

  final int walkingWindowMs;

  int? _base;
  int _total = 0;
  int _totalAtLastFix = 0;
  int? _lastIncreaseMs;
  String _lastStatus = 'unknown';
  StepState _state = StepState.still;

  /// OS 걸음 읽기(누적값 또는 상태)를 한 번이라도 받아들였는가. 그 전의 '정지'는 기본값일 뿐 관측이
  /// 아니므로 정책에는 '걸음 정보 없음'으로 남겨야 한다.
  bool _hasOsInput = false;

  /// 첫 분류를 정책에 알렸는가. 정지로 시작한 세션도 첫 읽기에서 한 번은 알려야 정지 억제 정책이
  /// 처음부터 정지를 안다.
  bool _announced = false;

  final _stepTimes = <int>[];

  @override
  Map<String, Object> get params => {'walking_window_s': walkingWindowMs / 1000};

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
      _hasOsInput = true;
      final base = _base ??= value;
      final total = value - base;
      if (total < _total) {
        // 누적값이 줄었다(재부팅 등). 지금까지 센 걸음을 이어 가도록 기준을 다시 잡는다.
        _base = value - _total;
      } else if (total > _total) {
        // OS는 걸음을 몇 개씩 묶어 늦게 알린다. 묶인 걸음은 모두 읽은 시각에 둔다.
        _stepTimes.addAll(List.filled(total - _total, reading.tMs));
        _total = total;
        _lastIncreaseMs = reading.tMs;
        increased = true;
      }
    } else if (reading.kind == OsStepReading.status) {
      _lastStatus = reading.value;
      _hasOsInput = true;
    }
    return _update(reading.tMs, stepsChanged: increased);
  }

  @override
  StepUpdate? onAccel(int tMs, List<AccelReading> batch) => _update(tMs, stepsChanged: false);

  @override
  void onFix() => _totalAtLastFix = _total;

  @override
  List<int> takeStepTimes() {
    final times = List<int>.of(_stepTimes);
    _stepTimes.clear();
    return times;
  }

  StepUpdate? _update(int tMs, {required bool stepsChanged}) {
    // OS 걸음 읽기를 받기 전에는 가속도 묶음만으로 분류하지 않는다.
    if (!_hasOsInput) return null;
    final last = _lastIncreaseMs;
    final recentlyStepped = last != null && tMs - last <= walkingWindowMs;
    final next =
        recentlyStepped || _lastStatus == 'walking' ? StepState.walking : StepState.still;
    if (next == _state && !stepsChanged && _announced) return null;
    _announced = true;
    _state = next;
    return StepUpdate(
      tMs: tMs,
      state: _state,
      totalSteps: _total,
      stepsSinceLastFix: stepsSinceLastFix,
    );
  }
}
