import 'dart:collection';
import 'dart:math' as math;

import '../events/policy_event.dart';
import '../model/readings.dart';
import 'signal.dart';
import 'step_detector.dart';
import 'step_timeline.dart';

/// 논문 기준판 걸음 감지기(Brajdic & Harle, UbiComp 2013의 추천 조합, 설계 5-2). 기본값은 논문의 최적값이다.
/// - 보행 판정 STD_TH(표 3): 가속도 크기의 0.8초 창 표준편차가 [stdThreshold](0.6)보다 크면 보행이다.
/// - 걸음 세기 WPD(표 4): 크기를 [smoothMs](0.31초) 중심 이동 평균으로 다듬고, [peakWindowMs](0.59초) 창의
///   한가운데가 창에서 가장 크면 걸음 하나로 센다(창 하나에 봉우리 하나). 그 순간 보행 판정이 참일 때만 센다.
/// 논문은 기타 움직임(탈것)을 다루지 않아서 이 감지기도 정지·보행만 낸다. 그래서 버스 진동을 걸음으로 셀 수
/// 있고, 그 점이 제안판과 비교하려는 지점이다.
class BrajdicDetector implements StepDetector, StepTimeline {
  BrajdicDetector({this.stdThreshold = 0.6, this.smoothMs = 310, this.peakWindowMs = 590});

  final double stdThreshold;
  final int smoothMs;
  final int peakWindowMs;

  static const _stdWindowMs = 800;

  final _grid = MagnitudeGrid();
  final _raw = RecentValues(_stdWindowMs ~/ gridStepMs);
  late final int _smoothSamples = math.max(1, (smoothMs / gridStepMs).round());
  late final _smoothing = RecentValues(_smoothSamples);

  /// 봉우리 창의 한쪽 폭(표본 수). 창 전체는 2 × [_half] + 1 표본이다.
  late final int _half = math.max(1, (peakWindowMs / gridStepMs / 2).round());

  /// 논문은 중심 이동 평균을 쓴다. 실시간으로는 뒤쪽 이동 평균만 셀 수 있는데, 그것은 중심 이동 평균을
  /// (표본 수 − 1) ÷ 2 표본만큼 늦춘 것과 같다. 걸음 시각에서 이만큼 빼면 중심 이동 평균의 봉우리 시각이 된다.
  late final int _delayMs = (_smoothSamples - 1) * gridStepMs ~/ 2;
  final _smoothed = ListQueue<({int tMs, double value})>();
  final _stepTimes = <int>[];

  int _total = 0;
  int _totalAtLastFix = 0;
  StepState _state = StepState.still;
  bool _announced = false;

  @override
  String get id => 'brajdic';

  @override
  Map<String, Object> get params =>
      {'std_th': stdThreshold, 'smooth_s': smoothMs / 1000, 'peak_win_s': peakWindowMs / 1000};

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
    if (!_raw.isFull) return null;
    final next = stdDev(_raw.toList()) > stdThreshold ? StepState.walking : StepState.still;
    if (_announced && next == _state && _total == before) return null;
    _announced = true;
    _state = next;
    return StepUpdate(
      tMs: tMs,
      state: _state,
      totalSteps: _total,
      stepsSinceLastFix: stepsSinceLastFix,
    );
  }

  /// 가속도만 쓰는 방식이라 OS 걸음 센서 값은 쓰지 않는다.
  @override
  StepUpdate? onOsStep(OsStepReading reading) => null;

  @override
  void onFix() => _totalAtLastFix = _total;

  @override
  List<int> takeStepTimes() {
    final times = List<int>.of(_stepTimes);
    _stepTimes.clear();
    return times;
  }

  void _addSample(GridSample sample) {
    if (sample.afterGap) {
      // 공백(서비스 재시작 등) 건너편 표본을 한 창에 섞으면 가짜 흔들림과 봉우리가 생긴다.
      _raw.clear();
      _smoothing.clear();
      _smoothed.clear();
    }
    _raw.add(sample.magnitude);
    _smoothing.add(sample.magnitude);
    _smoothed.addLast((tMs: sample.tMs, value: mean(_smoothing.toList())));
    if (_smoothed.length > 2 * _half + 1) _smoothed.removeFirst();
    if (_smoothed.length < 2 * _half + 1) return;

    final window = _smoothed.toList(growable: false);
    final center = window[_half];
    for (var i = 0; i < window.length; i++) {
      // 평평한 꼭대기를 한 번만 세려고 왼쪽은 '더 작아야', 오른쪽은 '크지 않아야' 봉우리로 본다.
      if (i < _half && window[i].value >= center.value) return;
      if (i > _half && window[i].value > center.value) return;
    }
    // 봉우리가 확정된 순간의 0.8초 창으로 보행 여부를 본다(STD_TH).
    if (_raw.isFull && stdDev(_raw.toList()) > stdThreshold) {
      _total++;
      _stepTimes.add(center.tMs - _delayMs);
    }
  }
}
