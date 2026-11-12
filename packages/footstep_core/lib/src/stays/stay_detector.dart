import '../events/policy_event.dart';
import '../geo.dart';
import '../model/fix.dart';
import '../params.dart';
import '../steps/step_run.dart';

/// 머문 곳 묶기 설정(설계 5-6). 기본값은 Li 외(2008)의 반경 100m, 10분이다.
class StayParams {
  const StayParams({this.radiusM = 100, this.minDurationMs = 600000, this.useStillIntervals = true});

  /// 첫 점(기준점)에서 이 거리(m) 안에 이어진 점들을 한 곳으로 본다.
  final double radiusM;

  /// 이보다 오래 머물러야 머문 곳이다.
  final int minDurationMs;

  /// 걸음 감지기의 정지 구간으로 도착·출발 시각을 잡는다(제안). false면 점만으로 묶는다(Li 외 2008, 절제 실험).
  final bool useStillIntervals;

  /// summary.json의 stay_params. 이름은 CLI `--stay-param`과 같다.
  Map<String, Object> get params =>
      {'radius_m': radiusM, 'min_stay_s': minDurationMs / 1000, 'use_still': useStillIntervals};

  /// 반경·시간이 양수가 아니면 ArgumentError다 — 0이면 모든 점이 따로 놀거나 모든 점이 머문 곳이 된다.
  void check() {
    if (!radiusM.isFinite || radiusM <= 0) throw ArgumentError('radiusM은 양수여야 합니다: $radiusM');
    if (minDurationMs <= 0) throw ArgumentError('minDurationMs는 양수여야 합니다: $minDurationMs');
  }
}

/// CLI의 `--stay-param k=v`로 설정을 만든다. 모르는 키나 잘못된 값은 ArgumentError다.
StayParams createStayParams([Map<String, String> params = const {}]) {
  final reader = ParamReader('머문 곳 묶기', params)..allowOnly(const {'radius_m', 'min_stay_s', 'use_still'});
  // 아주 작은 min_stay_s(예: 0.0004)는 양수지만 밀리초로 반올림하면 0이다 — CLI가 인자 오류로 알리게 여기서 검사한다.
  return StayParams(
    radiusM: reader.positive('radius_m', 100),
    minDurationMs: (reader.positive('min_stay_s', 600) * 1000).round(),
    useStillIntervals: reader.flag('use_still', true),
  )..check();
}

/// 시각 구간 [startMs, endMs](양 끝 포함).
class TimeSpan {
  const TimeSpan(this.startMs, this.endMs);

  final int startMs;
  final int endMs;

  bool contains(int tMs) => tMs >= startMs && tMs <= endMs;

  @override
  bool operator ==(Object other) => other is TimeSpan && other.startMs == startMs && other.endMs == endMs;

  @override
  int get hashCode => Object.hash(startMs, endMs);

  @override
  String toString() => 'TimeSpan($startMs, $endMs)';
}

/// 머문 곳 하나(stays.csv의 행).
class Stay {
  const Stay({
    required this.arriveMs,
    required this.leaveMs,
    required this.lat,
    required this.lng,
    required this.nPoints,
  });

  final int arriveMs;
  final int leaveMs;

  /// 묶인 점들의 평균 위치.
  final double lat;
  final double lng;

  /// 묶인 점 수.
  final int nPoints;

  int get durationMs => leaveMs - arriveMs;
}

/// 걸음 감지기 상태 변화에서 정지 구간을 뽑는다. 마지막 상태는 [endMs]까지 이어진 것으로 본다.
/// [states]는 상태가 바뀐 순간만 담은 시각순 목록이다(StepRun.states와 같은 규칙).
List<TimeSpan> stillSpans(List<StateChange> states, int endMs) => [
      for (var k = 0; k < states.length; k++)
        if (states[k].state == StepState.still)
          TimeSpan(states[k].tMs, k + 1 < states.length ? states[k + 1].tMs : endMs),
    ];

/// 머문 곳 묶기(모듈 C-1, 설계 5-6).
///
/// 점 묶기는 Li 외(2008)의 정의를 따른다. 기준점 p_i에서 [StayParams.radiusM] 안에 이어진 점 p_i..p_j를 한 무리로
/// 보고, 도착 p_i·출발 p_j 시각 사이가 [StayParams.minDurationMs] 이상이면 머문 곳이다. 중심은 무리의 평균,
/// 다음 기준점은 p_(j+1)이다. 못 미치면 기준점을 하나 옮긴다. 기록 끝까지 머문 무리도 머문 곳으로 친다.
///
/// 제안([StayParams.useStillIntervals]): 무리에 걸음 감지기 정지 구간 안의 점이 있으면, 그 첫 점이 든 정지 구간의
/// 시작을 도착, 마지막 점이 든 정지 구간의 끝을 출발로 쓴다. 점이 드물어도(예: 5분마다 측위) 머문 시간을 알 수
/// 있고, 걸어오거나 떠나며 반경 안에 찍힌 점은 머문 시간에 넣지 않는다. 머문 곳의 점은 도착~출발 사이의 점이다.
/// 정지 구간이 이웃 점보다 먼저 시작하거나 늦게 끝나면 걸음 없이 옮겨 온 것(OS 센서판의 버스 등)이라 정지 구간이
/// 도착·출발을 알려 주지 않으므로 그쪽은 점 시각을 쓴다. 정지 구간 안의 점이 하나도 없으면 Li 외(2008) 그대로다.
///
/// [points]와 [stillSpans]는 시각순이어야 하고, 정지 구간은 서로 겹치지 않아야 한다.
List<Stay> detectStays(
  List<Fix> points, {
  List<TimeSpan> stillSpans = const [],
  StayParams params = const StayParams(),
}) {
  params.check();
  for (var k = 1; k < points.length; k++) {
    if (points[k].tMs < points[k - 1].tMs) throw ArgumentError('점이 시각순이 아닙니다: ${points[k].tMs}');
  }
  // 정지 구간이 겹치거나 뒤집히면 이분 탐색이 감싼 구간을 놓쳐 머문 곳을 조용히 잃는다 — 그 전에 멈춘다.
  for (var k = 0; k < stillSpans.length; k++) {
    final span = stillSpans[k];
    if (span.endMs < span.startMs) throw ArgumentError('정지 구간의 끝이 시작보다 앞섭니다: $span');
    if (k > 0 && span.startMs < stillSpans[k - 1].endMs) {
      throw ArgumentError('정지 구간이 시각순이 아니거나 겹칩니다: ${stillSpans[k - 1]}, $span');
    }
  }
  final spans = params.useStillIntervals ? stillSpans : const <TimeSpan>[];

  final stays = <Stay>[];
  var i = 0;
  while (i < points.length) {
    final anchor = points[i];
    var j = i;
    while (j + 1 < points.length &&
        haversineMeters(anchor.lat, anchor.lng, points[j + 1].lat, points[j + 1].lng) <= params.radiusM) {
      j++;
    }

    // 무리에서 정지 구간 안에 든 첫 점(first)과 마지막 점(last).
    var first = -1;
    var last = -1;
    for (var k = i; k <= j && spans.isNotEmpty; k++) {
      if (_spanContaining(spans, points[k].tMs) != null) {
        if (first < 0) first = k;
        last = k;
      }
    }

    var from = i;
    var to = j;
    var arriveMs = points[i].tMs;
    var leaveMs = points[j].tMs;
    if (first >= 0) {
      from = first;
      to = last;
      final arriveSpan = _spanContaining(spans, points[first].tMs)!;
      arriveMs = first == 0 || arriveSpan.startMs > points[first - 1].tMs
          ? arriveSpan.startMs
          : points[first].tMs;
      final leaveSpan = _spanContaining(spans, points[last].tMs)!;
      leaveMs = last + 1 == points.length || leaveSpan.endMs < points[last + 1].tMs
          ? leaveSpan.endMs
          : points[last].tMs;
    }

    if (leaveMs - arriveMs >= params.minDurationMs) {
      var lat = 0.0;
      var lng = 0.0;
      for (var k = from; k <= to; k++) {
        lat += points[k].lat;
        lng += points[k].lng;
      }
      final n = to - from + 1;
      stays.add(Stay(arriveMs: arriveMs, leaveMs: leaveMs, lat: lat / n, lng: lng / n, nPoints: n));
      i = j + 1;
    } else {
      i++;
    }
  }
  return stays;
}

/// [tMs]를 품은 정지 구간. 구간은 시각순이고 겹치지 않으므로 시작 시각으로 이진 탐색한다.
TimeSpan? _spanContaining(List<TimeSpan> spans, int tMs) {
  var low = 0;
  var high = spans.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (spans[mid].startMs <= tMs) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  // low는 시작이 tMs보다 늦은 첫 구간이다. 그 앞 구간이 tMs를 품는지 본다.
  if (low == 0) return null;
  final span = spans[low - 1];
  return span.contains(tMs) ? span : null;
}
