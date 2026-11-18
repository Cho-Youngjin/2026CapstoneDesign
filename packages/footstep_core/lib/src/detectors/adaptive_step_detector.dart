import '../events/policy_event.dart';
import '../model/readings.dart';
import 'adaptive_peak_finder.dart';
import 'signal.dart';
import 'step_detector.dart';
import 'step_timeline.dart';

/// 제안 걸음 감지기(설계 5-2, 연구 자료 4-1).
/// 1. 가속도 크기를 20ms 격자로 다시 표본화하고, 걸음 대역(0.7~3Hz)만 남긴다.
/// 2. 흔들림(0.8초 창 크기 표준편차)이 작으면 정지다.
/// 3. 흔들리는데 박자(3초 창 정규화 자기상관의 봉우리)가 있으면 보행, 없으면 기타 움직임(탈것·폰 만지기)이다. 박자 창이 차기 전에는 판정하지 않는다.
/// 4. 적응형 임계값(이권희 외 2018)으로 걸음 후보를 찾고, 걸음 주기의 0.6배보다 가까운 후보는 버린다.
/// 5. 연속 N걸음이 모이고 보행이면 그 걸음들을 소급해 센다. 기타 움직임으로 판정된 동안 모인 후보는 버린다. 확인된 뒤에는 보행 상태인 동안 걸음을 바로 센다.
/// 버스 진동처럼 흔들림만 있고 박자가 없는 움직임에서는 확인이 일어나지 않아 걸음을 세지 않는다.
/// 6. (선택, [swingCorrection]) 흔드는 손 보정: 폰을 손에 들고 팔을 흔들며 걸으면 크기 신호가 두 걸음(한 보)에
///    한 번 출렁여 후보가 한 보에 하나만 잡힌다(실측: 손 구간에서 −35~−52%). 보행이고 폰 방향의 흔들림
///    ([tiltSwingDeg])이 [swingTiltThresholdDeg] 이상이면, 걸음 주기의 약 2배 간격으로 이어진 두 후보 사이에
///    걸음 하나를 채운다. 이미 한 걸음마다 후보가 잡히면 간격이 2배가 아니라 아무것도 하지 않는다.
class AdaptiveStepDetector implements StepDetector, StepTimeline {
  AdaptiveStepDetector({
    this.shakeThreshold = 0.6,
    this.bandShakeThreshold = 0.3,
    this.rhythmThreshold = 0.4,
    this.confirmSteps = 5,
    this.maxStepGapMs = 1500,
    this.swingCorrection = false,
    this.swingTiltThresholdDeg = 4.5,
  }) {
    _restart();
  }

  /// 정지와 움직임을 가르는 0.8초 창 표준편차(m/s²). Brajdic & Harle의 STD_TH 값이다.
  final double shakeThreshold;

  /// 걸음 대역 신호의 0.8초 표준편차 하한(m/s²). 엔진 진동처럼 걸음 대역 밖에서만 흔들리면 박자를 보지 않는다.
  final double bandShakeThreshold;

  /// 박자로 인정하는 자기상관 봉우리 높이(Brajdic & Harle 0.4).
  final double rhythmThreshold;

  /// 소급 카운트 전에 모아야 하는 연속 걸음 수 N(연구 자료 4-1의 5~6 중 5).
  final int confirmSteps;

  /// 이보다 벌어지면 걸음이 끊긴 것으로 본다.
  final int maxStepGapMs;

  /// 흔드는 손 보정을 켤지(절제 실험 스위치). 기준값을 예비 세션으로 정하기 전까지는 기본으로 끈다 — 켜지 않으면
  /// 결과가 보정 전과 같다.
  final bool swingCorrection;

  /// 흔드는 손으로 보는 폰 방향 흔들림 하한(도, 3초 창). 잠정값 4.5는 평가용 세션 관찰(주머니·가방 1.8~2.6°,
  /// 손 6.4~9.4°)에서 잡은 것이라, 예비 세션으로 다시 정해야 한다.
  final double swingTiltThresholdDeg;

  static const _lowCutHz = 0.7;
  static const _highCutHz = 3.0;
  static const _shakeWindowMs = 800;
  static const _rhythmWindowMs = 3000;

  /// 자기상관을 보는 지연 범위. 위쪽은 두 걸음(한 보)까지다. 주머니에 넣으면 왼발·오른발 모양이 달라 한 보
  /// 지연의 상관이 더 높게 나온다.
  static const _minLag = 240 ~/ gridStepMs;
  static const _maxLag = 1300 ~/ gridStepMs;

  /// 이보다 긴 봉우리 지연은 한 보(두 걸음)로 보고 걸음 주기를 절반으로 잡는다.
  /// 한계: 초당 1.25걸음보다 느린 걸음은 걸음 지연 자체가 0.8초를 넘어, 걸음 빠르기(cadenceHz)가 2배로
  /// 보고된다(걸음 수는 맞다). 걸음 세기 기록이 있는 예비 세션으로 조정할 항목이다.
  static const _stepLagLimitMs = 800;
  static const _minIntervalFraction = 0.6;
  static const _defaultPeriodMs = 500.0;

  /// 폰 방향을 볼 때 축별 가속도에 거는 저역 통과(Hz). 팔 흔들림(약 1Hz)은 남기고 걸음 충격(약 2Hz 이상)은 줄인다.
  static const _tiltCutHz = 1.5;

  /// 두 후보 사이를 '걸음 하나를 놓친 간격'으로 보는 범위(걸음 주기의 배수).
  static const _swingGapMin = 1.5;
  static const _swingGapMax = 2.5;

  /// 보정한 걸음 빠르기가 사람 걸음 범위(초당 1.3~2.5걸음) 밖이면 채우지 않는다.
  static const _swingMinPeriodMs = 400.0;
  static const _swingMaxPeriodMs = 770.0;

  final _grid = MagnitudeGrid();
  final _shake = RecentValues(_shakeWindowMs ~/ gridStepMs);
  final _band = RecentValues(_rhythmWindowMs ~/ gridStepMs);
  final _tiltX = RecentValues(_rhythmWindowMs ~/ gridStepMs);
  final _tiltY = RecentValues(_rhythmWindowMs ~/ gridStepMs);
  final _tiltZ = RecentValues(_rhythmWindowMs ~/ gridStepMs);
  final _peaks = AdaptivePeakFinder();
  late Biquad _lowPass;
  late Biquad _highPass;
  late Biquad _tiltLowX;
  late Biquad _tiltLowY;
  late Biquad _tiltLowZ;

  /// 직전 묶음에서 흔드는 손으로 판정했는지. 걸음 후보는 묶음 안 표본마다 나오므로 직전 판정을 쓴다.
  bool _swing = false;

  /// 확인을 기다리는 걸음 후보 시각. 최근 2N개까지만 둔다 — 박자 판정(3초 창)이 늦게 서는 동안의 걸음은
  /// 살리되, 오래 이어진 박자 없는 흔들림이 한꺼번에 걸음으로 바뀌지 않게 한다.
  final _pending = <int>[];
  final _stepTimes = <int>[];
  bool _confirmed = false;
  int? _lastStepMs;
  double _periodMs = _defaultPeriodMs;

  int _total = 0;
  int _totalAtLastFix = 0;
  int? _lastSampleMs;
  int? _fixMarkMs;
  StepState _state = StepState.still;
  bool _announced = false;

  @override
  String get id => 'adaptive';

  @override
  Map<String, Object> get params => {
        'std_th': shakeThreshold,
        'band_std_th': bandShakeThreshold,
        'ac_th': rhythmThreshold,
        'n_confirm': confirmSteps,
        'max_gap_s': maxStepGapMs / 1000,
        'swing': swingCorrection,
        'swing_tilt_th': swingTiltThresholdDeg,
      };

  @override
  StepState get state => _state;

  @override
  int get totalSteps => _total;

  @override
  int get stepsSinceLastFix => _total - _totalAtLastFix;

  @override
  StepUpdate? onAccel(int tMs, List<AccelReading> batch) {
    final before = _total;
    for (final reading in batch) {
      for (final sample in _grid.add(reading)) {
        _addSample(sample);
      }
    }
    // 0.8초 창이 차기 전의 '정지'는 관측이 아니라 기본값이라 알리지 않는다.
    if (!_shake.isFull) return null;

    final shake = stdDev(_shake.toList());
    var rhythm = -1.0;
    if (shake > shakeThreshold && _band.isFull) {
      final band = _band.toList();
      if (stdDev(band.sublist(band.length - _shake.capacity)) >= bandShakeThreshold) {
        final peak = autocorrelationPeak(band, _minLag, _maxLag);
        if (peak != null) {
          rhythm = peak.r;
          final lagMs = peak.lag * gridStepMs;
          _periodMs = lagMs <= _stepLagLimitMs ? lagMs.toDouble() : lagMs / 2;
        }
      }
    }
    // 흔드는 손: 박자 있는 보행이고, 폰 방향이 진자처럼 흔들리고, 걸음 주기가 사람 걸음 범위 안일 때만.
    // 느린 걸음(초당 1걸음)도 후보가 '주기의 2배' 간격으로 오지만(주기를 절반으로 잡으므로), 몸에 붙은 폰은
    // 방향이 거의 안 흔들려 여기서 걸러진다.
    _swing = swingCorrection &&
        rhythm >= rhythmThreshold &&
        _tiltX.isFull &&
        _periodMs >= _swingMinPeriodMs &&
        _periodMs <= _swingMaxPeriodMs &&
        tiltSwingDeg(_tiltX.toList(), _tiltY.toList(), _tiltZ.toList()) >= swingTiltThresholdDeg;
    // 흔들리는데 박자 창(3초)이 아직 안 찼으면 보행인지 기타 움직임인지 모른다. 모르는 동안은 상태를 바꾸지 않는다 —
    // '기타 움직임(탈것 의심)'으로 알리면 정책이 세션 시작이나 공백 뒤마다 탈것 확인 측위를 하게 된다.
    final StepState? next;
    if (shake <= shakeThreshold) {
      next = StepState.still;
    } else if (!_band.isFull) {
      next = null;
    } else {
      next = rhythm >= rhythmThreshold ? StepState.walking : StepState.otherMotion;
    }

    if (!_confirmed &&
        _pending.length >= confirmSteps &&
        next == StepState.walking &&
        tMs - _pending.last <= maxStepGapMs) {
      // 박자 있는 보행 안에서 연속 N걸음이 모였다 — 기다리던 걸음을 소급해 센다.
      _count(_pending);
      _lastStepMs = _pending.last;
      _pending.clear();
      _confirmed = true;
    }
    if (next == StepState.otherMotion) {
      // 박자 없는 흔들림(탈것 진동·폰 만지기)으로 판정된 동안 모인 후보는 걸음이 아니다. 남겨 두면 곧이어
      // 걷기 시작할 때 소급 카운트에 섞여, 탈것 구간 안에 가짜 걸음이 최대 2N개 생긴다.
      _pending.clear();
    }

    if (next == null) {
      // 상태는 그대로 두되, 이 묶음에서 걸음 수가 늘었으면(공백 직전에 센 걸음) 그것은 알린다.
      if (!_announced || _total == before) return null;
      return StepUpdate(
        tMs: tMs,
        state: _state,
        totalSteps: _total,
        stepsSinceLastFix: stepsSinceLastFix,
      );
    }
    if (_announced && next == _state && _total == before) return null;
    _announced = true;
    _state = next;
    return StepUpdate(
      tMs: tMs,
      state: _state,
      totalSteps: _total,
      stepsSinceLastFix: stepsSinceLastFix,
      cadenceHz: _state == StepState.walking ? 1000 / _periodMs : null,
    );
  }

  /// 가속도만 쓰는 방식이라 OS 걸음 센서 값은 쓰지 않는다(배터리 실험에서 OS 센서판과 비교한다).
  @override
  StepUpdate? onOsStep(OsStepReading reading) => null;

  @override
  void onFix() {
    _totalAtLastFix = _total;
    // 아직 확인을 기다리는 후보는 모두 이 측위보다 먼저 걸은 걸음이다. 나중에 소급해 셀 때 측위 이후 걸음에
    // 넣지 않도록, 지금까지 본 마지막 표본 시각을 경계로 남긴다.
    _fixMarkMs = _lastSampleMs;
  }

  @override
  List<int> takeStepTimes() {
    final times = List<int>.of(_stepTimes);
    _stepTimes.clear();
    return times;
  }

  void _addSample(GridSample sample) {
    if (sample.afterGap) _restart();
    _lastSampleMs = sample.tMs;
    _shake.add(sample.magnitude);
    final low = _lowPass.filter(sample.magnitude, steadyOutput: sample.magnitude);
    final band = _highPass.filter(low, steadyOutput: 0);
    _band.add(band);
    if (swingCorrection) {
      _tiltX.add(_tiltLowX.filter(sample.x, steadyOutput: sample.x));
      _tiltY.add(_tiltLowY.filter(sample.y, steadyOutput: sample.y));
      _tiltZ.add(_tiltLowZ.filter(sample.z, steadyOutput: sample.z));
    }
    final peakMs = _peaks.add(sample.tMs, band);
    if (peakMs != null) _onCandidate(peakMs);
  }

  void _onCandidate(int tMs) {
    if (_swing) {
      final previous = _pending.isNotEmpty ? _pending.last : _lastStepMs;
      if (previous != null) {
        final gap = tMs - previous;
        // 흔드는 손에서는 한 보에 후보가 하나다. 두 후보가 걸음 주기의 약 2배 간격이면 그 사이 걸음(반대쪽 발)을
        // 놓친 것이므로, 가운데 시각에 걸음 하나를 채운다. 끊긴 걸음(maxStepGapMs 초과)은 채우지 않는다.
        if (gap >= _swingGapMin * _periodMs &&
            gap <= _swingGapMax * _periodMs &&
            gap <= maxStepGapMs) {
          _acceptCandidate(previous + gap ~/ 2);
        }
      }
    }
    _acceptCandidate(tMs);
  }

  void _acceptCandidate(int tMs) {
    final previous = _pending.isNotEmpty ? _pending.last : _lastStepMs;
    // 걸음 주기보다 한참 가까운 후보는 한 걸음 안의 굴곡이다.
    if (previous != null && tMs - previous < _minIntervalFraction * _periodMs) return;
    final last = _lastStepMs;
    // 확인된 뒤에도 보행 상태일 때만 바로 센다. 걷다가 멈추거나 탈것에 타면 상태가 보행을 벗어나고, 그 뒤의
    // 흔들림은 다시 연속 N걸음과 박자를 확인받아야 걸음이 된다.
    if (_confirmed && _state == StepState.walking && last != null && tMs - last <= maxStepGapMs) {
      _count([tMs]);
      _lastStepMs = tMs;
      return;
    }
    _confirmed = false;
    if (_pending.isNotEmpty && tMs - _pending.last > maxStepGapMs) _pending.clear();
    _pending.add(tMs);
    if (_pending.length > 2 * confirmSteps) _pending.removeAt(0);
  }

  void _count(List<int> times) {
    _stepTimes.addAll(times);
    _total += times.length;
    final mark = _fixMarkMs;
    // 측위 경계 이전에 걸은 걸음(소급분)은 측위 이전 구간 몫이다 — 측위 이후 걸음 수에 넣지 않는다.
    if (mark != null) _totalAtLastFix += times.where((t) => t <= mark).length;
  }

  /// 처음이나 기록 공백 뒤: 창·필터·후보를 비운다. 걸음 수와 마지막 걸음 시각은 이어 간다.
  void _restart() {
    _lowPass = Biquad.lowPass(_highCutHz, 1000 / gridStepMs);
    _highPass = Biquad.highPass(_lowCutHz, 1000 / gridStepMs);
    _tiltLowX = Biquad.lowPass(_tiltCutHz, 1000 / gridStepMs);
    _tiltLowY = Biquad.lowPass(_tiltCutHz, 1000 / gridStepMs);
    _tiltLowZ = Biquad.lowPass(_tiltCutHz, 1000 / gridStepMs);
    _tiltX.clear();
    _tiltY.clear();
    _tiltZ.clear();
    _swing = false;
    _shake.clear();
    _band.clear();
    _peaks.reset();
    _pending.clear();
    _confirmed = false;
  }
}
