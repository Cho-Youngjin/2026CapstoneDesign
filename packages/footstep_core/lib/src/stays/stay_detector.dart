import 'dart:math' as math;

import '../events/policy_event.dart';
import '../geo.dart';
import '../model/fix.dart';
import '../params.dart';
import '../steps/step_run.dart';

/// 머문 곳 묶기 설정(설계 5-6). 기본값은 Li 외(2008)의 반경 100m, 10분이다.
class StayParams {
  const StayParams({
    this.radiusM = 100,
    this.minDurationMs = 600000,
    this.useStillIntervals = true,
    this.maxStillGapMs = 60000,
  });

  /// 첫 점(기준점)에서 이 거리(m) 안에 이어진 점들을 한 곳으로 본다.
  final double radiusM;

  /// 이보다 오래 머물러야 머문 곳이다.
  final int minDurationMs;

  /// 걸음 감지기의 정지 구간으로 도착·출발 시각을 잡는다(제안). false면 점만으로 묶는다(Li 외 2008, 절제 실험).
  final bool useStillIntervals;

  /// 정지 구간이 이 시간(ms) 안의 간격으로 이어지면 한 번의 정지로 이어 붙인다(제안). 실내에서 조금씩 움직이면 감지기가
  /// 정지를 짧게 끊기 때문이다. 0이면 맞닿은 구간만 잇는다.
  final int maxStillGapMs;

  /// summary.json의 stay_params. 이름은 CLI `--stay-param`과 같다.
  Map<String, Object> get params =>
      {
        'radius_m': radiusM,
        'min_stay_s': minDurationMs / 1000,
        'use_still': useStillIntervals,
        'still_gap_s': maxStillGapMs / 1000,
      };

  /// 반경·시간이 양수가 아니면 ArgumentError다 — 0이면 모든 점이 따로 놀거나 모든 점이 머문 곳이 된다.
  void check() {
    if (!radiusM.isFinite || radiusM <= 0) throw ArgumentError('radiusM은 양수여야 합니다: $radiusM');
    if (minDurationMs <= 0) throw ArgumentError('minDurationMs는 양수여야 합니다: $minDurationMs');
    if (maxStillGapMs < 0) throw ArgumentError('maxStillGapMs는 0 이상이어야 합니다: $maxStillGapMs');
  }
}

/// CLI의 `--stay-param k=v`로 설정을 만든다. 모르는 키나 잘못된 값은 ArgumentError다.
StayParams createStayParams([Map<String, String> params = const {}]) {
  final reader = ParamReader('머문 곳 묶기', params)..allowOnly(const {'radius_m', 'min_stay_s', 'use_still', 'still_gap_s'});
  // 아주 작은 min_stay_s(예: 0.0004)는 양수지만 밀리초로 반올림하면 0이다 — CLI가 인자 오류로 알리게 여기서 검사한다.
  return StayParams(
    radiusM: reader.positive('radius_m', 100),
    minDurationMs: (reader.positive('min_stay_s', 600) * 1000).round(),
    useStillIntervals: reader.flag('use_still', true),
    maxStillGapMs: (reader.nonNegative('still_gap_s', 60) * 1000).round(),
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
/// 이어 붙이기: 실내에서 조금씩 움직이면 감지기가 정지를 짧게 끊고 GPS도 실패해 마지막 점이 일찍 끝난다. 그래서 출발은
/// 마지막 점이 든 정지 구간의 끝에서 [StayParams.maxStillGapMs] 안 간격으로 이어진 다음 정지 구간들의 끝까지 늦추고,
/// 도착도 같은 방식으로 앞쪽으로 당긴다. 무리 밖의 이웃 점(출발은 무리 뒤 첫 점, 도착은 무리 앞의 점)의 시각을 넘거나
/// 가로지르는 구간은 잇지 않고, 도착은 앞 머문 곳의 출발도 넘지 못한다. 무리 안이지만 정지 구간 밖인 점은 이 이어
/// 붙이기를 끊지 않는다(중심·점 수에서는 앞서처럼 뺀다).
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
  var prevLeaveMs = _noLimitLow; // 앞 머문 곳의 출발. 도착을 거슬러 이어 붙일 때 이 앞으로는 못 간다.
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
      if (_spanIndexContaining(spans, points[k].tMs) >= 0) {
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
      final arriveIdx = _spanIndexContaining(spans, points[first].tMs);
      if (first == 0 || spans[arriveIdx].startMs > points[first - 1].tMs) {
        // 구간 시작이 도착이다. 앞쪽으로 이어진 정지 구간이 있으면 거슬러 간다. 한계는 무리 바로 앞의 점(무리에 안 든
        // 점)과 앞 머문 곳의 출발 시각이다.
        final lowerMs = math.max(i > 0 ? points[i - 1].tMs : _noLimitLow, prevLeaveMs);
        arriveMs = spans[_chainBackward(spans, arriveIdx, lowerMs, params.maxStillGapMs)].startMs;
      } else {
        arriveMs = points[first].tMs;
      }
      final leaveIdx = _spanIndexContaining(spans, points[last].tMs);
      if (last + 1 == points.length || spans[leaveIdx].endMs < points[last + 1].tMs) {
        // 구간 끝이 출발이다. 뒤쪽으로 이어진 정지 구간이 있으면 나아간다. 한계는 무리 바로 뒤의 점(무리에 안 든 첫
        // 점)의 시각이다. 무리 안이지만 정지 구간 밖인 점(last 뒤, j까지)은 한계가 아니다.
        final upperMs = j + 1 < points.length ? points[j + 1].tMs : _noLimitHigh;
        leaveMs = spans[_chainForward(spans, leaveIdx, upperMs, params.maxStillGapMs)].endMs;
      } else {
        leaveMs = points[last].tMs;
      }
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
      prevLeaveMs = leaveMs;
      i = j + 1;
    } else {
      i++;
    }
  }
  return stays;
}

const _noLimitLow = -1 << 62;
const _noLimitHigh = 1 << 62;

/// [spans]의 [from]번 구간에서 뒤로 이어 붙인 마지막 구간의 번호. 다음 구간이 앞 구간의 끝에서 [maxGapMs] 안에 시작하고
/// [upperMs] 전에 끝날 때만 잇는다. [upperMs] 이후에 시작하거나 그 시각을 가로지르는 구간은 쓰지 않는다 — 가로지르면
/// 걸음 없이 옮겨 온 것일 수 있어 위 출발 규칙처럼 믿지 않는다.
int _chainForward(List<TimeSpan> spans, int from, int upperMs, int maxGapMs) {
  var idx = from;
  while (idx + 1 < spans.length &&
      spans[idx + 1].startMs - spans[idx].endMs <= maxGapMs &&
      spans[idx + 1].endMs < upperMs) {
    idx++;
  }
  return idx;
}

/// [_chainForward]의 반대. 앞 구간이 [maxGapMs] 안에 끝나고 [lowerMs] 뒤에 시작할 때만 거슬러 간다.
int _chainBackward(List<TimeSpan> spans, int from, int lowerMs, int maxGapMs) {
  var idx = from;
  while (idx > 0 &&
      spans[idx].startMs - spans[idx - 1].endMs <= maxGapMs &&
      spans[idx - 1].startMs > lowerMs) {
    idx--;
  }
  return idx;
}

/// [tMs]를 품은 정지 구간의 번호(없으면 -1). 구간은 시각순이고 겹치지 않으므로 시작 시각으로 이진 탐색한다.
int _spanIndexContaining(List<TimeSpan> spans, int tMs) {
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
  if (low == 0) return -1;
  return spans[low - 1].contains(tMs) ? low - 1 : -1;
}
