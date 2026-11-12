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

/// 고른 날 하루의 여행 기록(설계 9-4). 점은 기기 현지 날짜로 묶는다(국가 지도·걸음 귀속과 같은 [dayKeyOf]).
class TripDay {
  const TripDay({required this.date, required this.points, required this.stays});

  final DateTime date;

  /// 그날의 점(시각순).
  final List<RoutePoint> points;

  /// 그날의 머문 곳. 밤을 넘긴 머문 곳은 도착이 전날·출발이 다음 날일 수 있다.
  final List<Stay> stays;

  /// 그날의 걸음 수 = 그날 점들의 '직전 점 이후 걸음 수' 합. 하루의 마지막 측위 뒤 걸음은 다음 측위(다음 날일 수 있다)에 든다.
  int get steps => points.fold(0, (sum, p) => sum + (p.stepsSincePrev ?? 0));

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
  final points = [for (final p in tripPoints) if (dayKeyOf(p.recordedAt) == day) p];
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
  return TripDay(date: day, points: points, stays: detectStays(fixes, stillSpans: spans));
}
