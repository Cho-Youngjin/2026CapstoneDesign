/// 적응형 임계값 걸음 후보 찾기(이권희·김광현·오종택, JIIBC 2018, 식 (4)). 신호는 걸음 대역만 남긴 0 중심
/// 가속도 크기(m/s²)다.
/// 1. 최대 임계값(Tmax)을 넘으면 봉우리를 찾기 시작한다.
/// 2. 최소 임계값(Tmin) 아래로 내려갈 때까지 가장 높은 값(Pmax)과 그 시각을 기억한다.
/// 3. 신호가 다시 0 이상으로 올라오면 걸음 후보 하나로 확정하고, Tmax를 직전 두 Pmax 평균의 1/3로 바꾼다.
/// 휴대 위치나 걸음 세기마다 봉우리 크기가 달라도 임계값이 따라간다. 봉우리 사이에 골짜기(Tmin 아래)를 요구하므로
/// 한 걸음 안의 작은 굴곡을 두 번 세지 않는다.
class AdaptivePeakFinder {
  AdaptivePeakFinder({this.minThreshold = -0.588, this.initialMaxThreshold = 1.0})
      : _maxThreshold = initialMaxThreshold;

  /// Tmin. 논문은 중력 단위 0.94(정지 1.0 기준 −0.06g)로 고정한다. 0 중심 m/s²로 바꾸면 −0.06 × 9.80665다.
  final double minThreshold;

  /// 첫 두 봉우리 전의 Tmax. 논문은 '임의 값'으로 정했다. 실제 세션의 보행 봉우리(약 3~5 m/s²)의 1/3 근처다.
  final double initialMaxThreshold;

  double _maxThreshold;
  _Phase _phase = _Phase.waiting;
  double _peak = 0;
  int _peakMs = 0;
  double? _previousPeak;

  double get maxThreshold => _maxThreshold;

  /// 표본 하나를 넣는다. 걸음 후보가 확정되면 그 봉우리 시각을 돌려준다.
  int? add(int tMs, double value) {
    switch (_phase) {
      case _Phase.waiting:
        if (value > _maxThreshold) {
          _phase = _Phase.peak;
          _peak = value;
          _peakMs = tMs;
        }
      case _Phase.peak:
        if (value > _peak) {
          _peak = value;
          _peakMs = tMs;
        }
        if (value < minThreshold) _phase = _Phase.valley;
      case _Phase.valley:
        if (value >= 0) {
          _phase = _Phase.waiting;
          final previous = _previousPeak;
          // 식 (4): Tmax = 1/3 × (두 Pmax의 평균) = (Pmax(i) + Pmax(i−1)) / 6
          if (previous != null) _maxThreshold = (previous + _peak) / 6;
          _previousPeak = _peak;
          return _peakMs;
        }
    }
    return null;
  }

  /// 기록 공백 뒤에는 봉우리 크기 기억을 버리고 처음부터 찾는다.
  void reset() {
    _phase = _Phase.waiting;
    _previousPeak = null;
    _maxThreshold = initialMaxThreshold;
  }
}

enum _Phase { waiting, peak, valley }
