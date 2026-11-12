import '../../visa/models/trip.dart';
import '../../visa/models/trip_summary.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// `yyyy-MM-dd`. intl 대신 직접 만든다 — 기록 서비스·WorkManager isolate에서도 읽고 쓴다.
String _wireDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 여행 기록이 알아야 하는 여행 정보(설계 2026-11-07 9-2). 여행 목록의 한 줄에서 뽑아, 화면·기록 서비스·WorkManager가
/// 함께 보는 저장소(TripRecordingStore)에 둔다. 날짜는 시각 없는 달력 날짜다.
class TripPeriod {
  const TripPeriod({
    required this.tripId,
    required this.countryIso2,
    required this.countryNameKo,
    required this.departDate,
    required this.returnDate,
  });

  factory TripPeriod.fromSummary(TripSummary trip) => TripPeriod(
        tripId: trip.id,
        countryIso2: trip.countryIso2,
        countryNameKo: trip.countryNameKo,
        departDate: _dateOnly(trip.departDate),
        returnDate: _dateOnly(trip.returnDate),
      );

  factory TripPeriod.fromTrip(Trip trip) => TripPeriod(
        tripId: trip.id,
        countryIso2: trip.countryIso2,
        countryNameKo: trip.countryNameKo,
        departDate: _dateOnly(trip.departDate),
        returnDate: _dateOnly(trip.returnDate),
      );

  final int tripId;
  final String countryIso2;

  /// 출발일 알림 문구("오늘부터 ○○ 여행 발걸음을 기록합니다.")와 기록 알림에 쓴다.
  final String countryNameKo;
  final DateTime departDate;
  final DateTime returnDate;

  /// 기록을 시작하는 순간: 출발일 0시(기기 현지 시각).
  DateTime get startsAt => DateTime(departDate.year, departDate.month, departDate.day);

  /// 기록을 끝내는 순간: 귀국일 다음 날 0시(기기 현지 시각). DateTime이 달·해 넘김을 알아서 맞춘다.
  DateTime get endsAt => DateTime(returnDate.year, returnDate.month, returnDate.day + 1);

  /// [now]가 기록 기간 [출발일 0시, 귀국일 다음 날 0시) 안인가.
  bool covers(DateTime now) => !now.isBefore(startsAt) && now.isBefore(endsAt);

  Map<String, Object?> toJson() => {
        'tripId': tripId,
        'countryIso2': countryIso2,
        'countryNameKo': countryNameKo,
        'departDate': _wireDate(departDate),
        'returnDate': _wireDate(returnDate),
      };

  factory TripPeriod.fromJson(Map<String, Object?> json) => TripPeriod(
        tripId: json['tripId'] as int,
        countryIso2: json['countryIso2'] as String,
        countryNameKo: json['countryNameKo'] as String,
        departDate: DateTime.parse(json['departDate'] as String),
        returnDate: DateTime.parse(json['returnDate'] as String),
      );

  @override
  bool operator ==(Object other) =>
      other is TripPeriod &&
      other.tripId == tripId &&
      other.countryIso2 == countryIso2 &&
      other.countryNameKo == countryNameKo &&
      other.departDate == departDate &&
      other.returnDate == returnDate;

  @override
  int get hashCode => Object.hash(tripId, countryIso2, countryNameKo, departDate, returnDate);

  @override
  String toString() => 'TripPeriod($tripId $countryIso2 ${_wireDate(departDate)}~${_wireDate(returnDate)})';
}

/// 지금 기록할 여행(설계 9-2의 판단 로직). 없으면 null이다.
///
/// 기간 [출발일 0시, 귀국일 다음 날 0시) 안이고 일시정지하지 않은 여행 중 가장 늦게 출발한 것을 고른다 — 여행이
/// 겹치면 새로 시작한 여행이 지금의 여행이다. 출발일까지 같으면 id가 큰(나중에 만든) 여행이다. 점 하나는 한 여행에만
/// 속하므로(RoutePoints.trip_id) 하나만 고른다.
TripPeriod? shouldRecord(List<TripPeriod> trips, DateTime now, Set<int> pausedTripIds) {
  TripPeriod? best;
  for (final trip in trips) {
    if (pausedTripIds.contains(trip.tripId) || !trip.covers(now)) continue;
    final current = best;
    if (current == null ||
        trip.departDate.isAfter(current.departDate) ||
        (trip.departDate == current.departDate && trip.tripId > current.tripId)) {
      best = trip;
    }
  }
  return best;
}
