import 'dart:collection';
import 'dart:math' as math;

import '../model/readings.dart';

/// 걸음 감지기가 쓰는 격자 간격(ms, 50Hz). 걸음 신호(약 1~3Hz)를 다루기에 충분하고, 100Hz 기기와 50Hz
/// 기기에서 같은 파라미터가 같은 뜻을 갖게 한다.
const gridStepMs = 20;

/// 격자 표본 하나. [afterGap]이면 바로 앞에 메우지 않은 큰 공백이 있었다.
class GridSample {
  const GridSample({required this.tMs, required this.magnitude, this.afterGap = false});

  final int tMs;
  final double magnitude;
  final bool afterGap;
}

/// 가속도 크기(√(x²+y²+z²), 폰 방향과 무관)를 [stepMs] 격자로 다시 표본화한다.
/// - 기기마다 표본 간격이 다르고 들쭉날쭉해서(Galaxy S23은 약 10ms), 창 길이를 시간으로 정한 파라미터가
///   기기와 무관하게 같은 뜻이 되게 한다.
/// - 칸 안의 표본은 평균한다. 칸보다 빠른 진동(엔진 등)이 낮은 주파수로 접혀 들어오는 것을 줄인다.
/// - [maxGapMs] 이하의 빈 칸은 직전 값으로 메우고, 그보다 긴 공백(서비스 재시작 등)은 메우지 않고 표시만 한다.
class MagnitudeGrid {
  MagnitudeGrid({this.stepMs = gridStepMs, this.maxGapMs = 200});

  final int stepMs;
  final int maxGapMs;

  int? _bin;
  double _sum = 0;
  int _count = 0;
  bool _gapBefore = false;

  /// [reading]을 넣고, 이번에 확정된 격자 표본을 돌려준다. 칸은 다음 칸의 표본이 들어와야 확정된다.
  List<GridSample> add(AccelReading reading) {
    final magnitude =
        math.sqrt(reading.x * reading.x + reading.y * reading.y + reading.z * reading.z);
    final bin = reading.tMs - reading.tMs % stepMs;
    final out = <GridSample>[];
    final current = _bin;
    if (current == null) {
      _bin = bin;
    } else if (bin > current) {
      final value = _sum / _count;
      out.add(GridSample(tMs: current, magnitude: value, afterGap: _gapBefore));
      _gapBefore = bin - current > maxGapMs;
      if (!_gapBefore) {
        for (var t = current + stepMs; t < bin; t += stepMs) {
          out.add(GridSample(tMs: t, magnitude: value));
        }
      }
      _bin = bin;
      _sum = 0;
      _count = 0;
    }
    // 시각이 거꾸로 온 표본(bin < current)은 지금 칸에 더한다. 세션 읽기가 정렬하므로 드물다.
    _sum += magnitude;
    _count++;
    return out;
  }
}

/// 2차 버터워스 필터(쌍선형 변환). 걸음 대역만 남기는 데 쓴다.
class Biquad {
  Biquad._(this._b0, this._b1, this._b2, this._a1, this._a2);

  factory Biquad.lowPass(double cutoffHz, double sampleHz) {
    final k = math.tan(math.pi * cutoffHz / sampleHz);
    final norm = 1 / (1 + k * math.sqrt2 + k * k);
    final b0 = k * k * norm;
    return Biquad._(b0, 2 * b0, b0, 2 * (k * k - 1) * norm, (1 - k * math.sqrt2 + k * k) * norm);
  }

  factory Biquad.highPass(double cutoffHz, double sampleHz) {
    final k = math.tan(math.pi * cutoffHz / sampleHz);
    final norm = 1 / (1 + k * math.sqrt2 + k * k);
    return Biquad._(
        norm, -2 * norm, norm, 2 * (k * k - 1) * norm, (1 - k * math.sqrt2 + k * k) * norm);
  }

  final double _b0;
  final double _b1;
  final double _b2;
  final double _a1;
  final double _a2;

  double _x1 = 0;
  double _x2 = 0;
  double _y1 = 0;
  double _y2 = 0;
  bool _started = false;

  /// 첫 입력에서는 필터가 이미 그 값에 오래 머물러 있던 것처럼 시작한다([steadyOutput]은 그때의 출력:
  /// 저역 통과는 입력 그대로, 고역 통과는 0). 0에서 시작하면 중력(약 9.8)이 계단처럼 들어와 첫 몇 초에
  /// 가짜 봉우리가 생긴다.
  double filter(double x, {required double steadyOutput}) {
    if (!_started) {
      _x1 = x;
      _x2 = x;
      _y1 = steadyOutput;
      _y2 = steadyOutput;
      _started = true;
    }
    final y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }
}

/// 최근 [capacity]개 값을 담는 창.
class RecentValues {
  RecentValues(this.capacity);

  final int capacity;
  final _values = ListQueue<double>();

  int get length => _values.length;

  bool get isFull => _values.length >= capacity;

  void add(double value) {
    _values.addLast(value);
    if (_values.length > capacity) _values.removeFirst();
  }

  void clear() => _values.clear();

  List<double> toList() => _values.toList(growable: false);
}

double mean(Iterable<double> values) {
  var sum = 0.0;
  var n = 0;
  for (final v in values) {
    sum += v;
    n++;
  }
  return n == 0 ? 0 : sum / n;
}

/// 모표준편차. 비어 있으면 0이다.
double stdDev(Iterable<double> values) {
  final list = values.toList(growable: false);
  if (list.isEmpty) return 0;
  final m = mean(list);
  var sum = 0.0;
  for (final v in list) {
    sum += (v - m) * (v - m);
  }
  return math.sqrt(sum / list.length);
}

/// 정규화 자기상관이 지연 [minLag]~[maxLag](표본 수)에서 봉우리(양옆보다 높은 점)를 이루는 곳 중 가장 높은 것.
/// 봉우리만 보는 이유: 느린 흔들림(버스의 좌우 흔들림)은 지연이 짧을수록 상관이 높아서, 범위 안 최댓값만 보면
/// '박자'로 오인된다. 걸음은 걸음 주기 지연에서 봉우리가 생긴다. 봉우리가 없거나 창이 짧으면 null이다.
({double r, int lag})? autocorrelationPeak(List<double> window, int minLag, int maxLag) {
  if (minLag < 2 || window.length <= maxLag + 2) return null;

  double corr(int lag) {
    final n = window.length - lag;
    var meanA = 0.0;
    var meanB = 0.0;
    for (var i = 0; i < n; i++) {
      meanA += window[i];
      meanB += window[i + lag];
    }
    meanA /= n;
    meanB /= n;
    var cross = 0.0;
    var varA = 0.0;
    var varB = 0.0;
    for (var i = 0; i < n; i++) {
      final a = window[i] - meanA;
      final b = window[i + lag] - meanB;
      cross += a * b;
      varA += a * a;
      varB += b * b;
    }
    final den = math.sqrt(varA * varB);
    return den > 0 ? cross / den : 0;
  }

  final r = {for (var lag = minLag - 1; lag <= maxLag + 1; lag++) lag: corr(lag)};
  ({double r, int lag})? best;
  for (var lag = minLag; lag <= maxLag; lag++) {
    final value = r[lag]!;
    if (value >= r[lag - 1]! && value > r[lag + 1]! && (best == null || value > best.r)) {
      best = (r: value, lag: lag);
    }
  }
  return best;
}
