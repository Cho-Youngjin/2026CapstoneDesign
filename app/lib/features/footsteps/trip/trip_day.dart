import 'package:footstep_core/footstep_core.dart' show Fix, Stay, TimeSpan, detectStays;

import '../data/route_point.dart';
import '../health/step_attribution.dart' show dayKeyOf;
import 'trip_period.dart';

/// 여행 기간의 날짜(출발일~귀국일, 양 끝 포함). 날짜별 보기의 날짜 칩이 된다(설계 9-4).
List<DateTime> tripDates(TripPeriod trip) => [
      for (var d = trip.startsAt; d.isBefore(trip.endsAt); d = DateTime(d.year, d.month, d.day + 1)) d,
    ];

/// 날짜별 보기에서 처음 고를 날: 여행 중이면 오늘, 아니면 기록이 있는 마지막 날, 그것도 없으면 출발일.
DateTime initialTripDate(TripPeriod trip, List<RoutePoint> points, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (trip.covers(now)) return today;
  final dates = tripDates(trip);
  for (final point in points.reversed) {
    final day = dayKeyOf(point.recordedAt);
    if (dates.contains(day)) return day;
  }
  return trip.startsAt;
}

/// 날짜별 보기가 쓰는 측위 정확도의 상한(m). 이보다 나쁜(큰) 점은 경로·거리·머문 곳에서 뺀다(걸음은 센다).
/// 앱의 오차 예산 E(50m)와 같고, 서버 `RouteReconstructionService.MAX_ACCURACY_M`과 같은 값이다.
/// SIM·인터넷이 없을 때 네트워크 위치가 정확도 49~68m로 보고되고도 1.2~1.5km 어긋난 적이 있어서다.
const maxFixAccuracyM = 50.0;

/// 하루 점(시각순)에서 정확도가 [maxFixAccuracyM]보다 나쁜 점을 빼고, 뺀 점의 '직전 이후 걸음 수'는 다음에 남는 점에
/// 더한다(서버 요청의 걸음 수가 맞게). 정확도를 모르는(null) 점은 남긴다. 뒤에 남은 점이 없으면 그 걸음은 점에서 사라지므로
/// 하루 걸음 합은 이 함수가 아니라 원래 점들로 센다([TripDay.steps]).
List<RoutePoint> dropInaccuratePoints(List<RoutePoint> points) {
  final kept = <RoutePoint>[];
  var carried = 0;
  for (final p in points) {
    if ((p.accuracyM ?? 0) > maxFixAccuracyM) {
      carried += p.stepsSincePrev ?? 0;
      continue;
    }
    kept.add(carried == 0
        ? p
        : RoutePoint(
            lat: p.lat,
            lng: p.lng,
            countryIso: p.countryIso,
            recordedAt: p.recordedAt,
            tripId: p.tripId,
            accuracyM: p.accuracyM,
            stepsSincePrev: (p.stepsSincePrev ?? 0) + carried,
            state: p.state,
          ));
    carried = 0;
  }
  return kept;
}

/// 고른 날 하루의 여행 기록(설계 9-4). 점은 기기 현지 날짜로 묶는다(국가 지도·걸음 귀속과 같은 [dayKeyOf]).
class TripDay {
  const TripDay({
    required this.date,
    required this.points,
    required this.stays,
    required this.steps,
    this.inaccuratePoints = 0,
  });

  final DateTime date;

  /// 그날의 점(시각순). 정확도가 [maxFixAccuracyM]보다 나쁜 점은 빠져 있고, 그 걸음 수는 다음 점에 더해져 있다.
  final List<RoutePoint> points;

  /// 그날의 머문 곳. 밤을 넘긴 머문 곳은 도착이 전날·출발이 다음 날일 수 있다.
  final List<Stay> stays;

  /// 그날의 걸음 수 = 그날 모든 점(정확도가 나빠 [points]에서 뺀 점 포함)의 '직전 점 이후 걸음 수' 합. 하루의 마지막 측위 뒤
  /// 걸음은 다음 측위(다음 날일 수 있다)에 든다.
  final int steps;

  /// 정확도가 [maxFixAccuracyM]보다 나빠 [points]에서 뺀 점 수. [points]가 비었는데 이 값이 있으면 기록은 있지만 그릴
  /// 위치가 없는 날이다(화면은 '기록 없음' 대신 걸음 수와 함께 알린다).
  final int inaccuratePoints;

  /// 복원 결과 캐시 키의 일부(설계 9-4: 여행, 날짜, 마지막 점 시각). 점이 없으면 0이다.
  int get lastPointMs => points.isEmpty ? 0 : points.last.recordedAt.millisecondsSinceEpoch;
}

/// [tripPoints](한 여행의 모든 점, 시각순)와 [stillSpans](정지 구간, 시작 시각순)에서 [date] 하루를 뽑는다.
///
/// 머문 곳은 footstep_core의 [detectStays](설계 5-6, 재생기와 같은 코드)로 묶는다. 그날과 겹치는 정지 구간을 잘라내지 않고
/// 넘겨, 밤새 머문 숙소처럼 날을 넘긴 머문 곳도 실제 도착·출발 시각으로 보인다.
TripDay buildTripDay(DateTime date, List<RoutePoint> tripPoints, List<TimeSpan> stillSpans) {
  final day = DateTime(date.year, date.month, date.day);
  final next = DateTime(day.year, day.month, day.day + 1);
  final dayPoints = [for (final p in tripPoints) if (dayKeyOf(p.recordedAt) == day) p];
  // 걸음은 정확도가 나쁜 점의 것까지 모두 센다. 믿을 수 없는 건 위치뿐이다.
  final steps = dayPoints.fold(0, (sum, p) => sum + (p.stepsSincePrev ?? 0));
  // 머문 곳 판정·서버 요청·직선 대체·거리는 모두 정확도가 나쁜 점을 뺀 이 점들로 한다.
  final points = dropInaccuratePoints(dayPoints);
  final fixes = [
    for (final p in points)
      Fix(tMs: p.recordedAt.millisecondsSinceEpoch, lat: p.lat, lng: p.lng, accuracyM: p.accuracyM ?? 0),
  ];
  final dayStart = day.millisecondsSinceEpoch;
  final dayEnd = next.millisecondsSinceEpoch;
  final spans = [
    for (final s in stillSpans)
      if (s.endMs >= dayStart && s.startMs < dayEnd) s,
  ];
  return TripDay(
    date: day,
    points: points,
    stays: _staysOf(fixes, spans),
    steps: steps,
    inaccuratePoints: dayPoints.length - points.length,
  );
}

/// 정지 구간이 겹치거나 뒤집힌 잘못된 기록이 DB에 있으면 detectStays가 ArgumentError를 던진다. 이 함수는 화면의 build에서
/// 불리므로 빨간 오류 화면 대신, 정지 구간 없이 점만으로 머문 곳을 잡는다.
List<Stay> _staysOf(List<Fix> fixes, List<TimeSpan> spans) {
  try {
    return detectStays(fixes, stillSpans: spans);
  } on ArgumentError {
    return detectStays(fixes);
  }
}
