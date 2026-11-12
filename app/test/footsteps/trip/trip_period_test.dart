import 'package:app/features/footsteps/trip/trip_period.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../visa/fake_trip_api.dart' show sampleSummary;
import 'trip_fakes.dart';

void main() {
  // 11/20 출발, 11/22 귀국 여행. 기록 기간은 11/20 0시 ~ 11/23 0시(기기 현지 시각)다.
  final trip = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));

  group('기록 기간의 날짜 경계', () {
    test('출발일 0시부터 기록한다(전날 23:59는 아니다)', () {
      // 경계는 기기 현지 시각이다. DateTime ==는 UTC 여부도 보므로 UTC로 만든 구현은 어느 시간대의 CI에서도 실패한다.
      expect(trip.startsAt, DateTime(2026, 11, 20));
      expect(trip.endsAt, DateTime(2026, 11, 23));
      expect(trip.covers(DateTime(2026, 11, 20)), isTrue);
      expect(trip.covers(DateTime(2026, 11, 19, 23, 59, 59)), isFalse);
    });

    test('귀국일 23:59까지 기록하고 다음 날 0시에 끝난다', () {
      expect(trip.covers(DateTime(2026, 11, 22, 23, 59, 59)), isTrue);
      expect(trip.covers(DateTime(2026, 11, 23)), isFalse);
    });

    test('귀국일이 달의 마지막 날이어도 다음 달 1일 0시에 끝난다', () {
      final monthEnd = period(1, DateTime(2026, 11, 29), DateTime(2026, 11, 30));
      expect(monthEnd.endsAt, DateTime(2026, 12, 1));
      expect(monthEnd.covers(DateTime(2026, 11, 30, 23, 59)), isTrue);
      expect(monthEnd.covers(DateTime(2026, 12, 1)), isFalse);
    });

    test('UTC로 준 시각도 같은 순간으로 비교한다', () {
      expect(trip.covers(DateTime(2026, 11, 20, 0, 0, 1).toUtc()), isTrue);
    });
  });

  group('shouldRecord', () {
    test('기간 안의 여행을 고르고, 기간 밖이면 null이다', () {
      expect(shouldRecord([trip], DateTime(2026, 11, 21, 15), const {}), trip);
      expect(shouldRecord([trip], DateTime(2026, 11, 23), const {}), isNull);
      expect(shouldRecord(const [], DateTime(2026, 11, 21), const {}), isNull);
    });

    test('일시정지한 여행은 기간 안이어도 기록하지 않는다', () {
      expect(shouldRecord([trip], DateTime(2026, 11, 21), {7}), isNull);
    });

    test('여행이 겹치면 나중에 출발한 여행을 기록한다', () {
      final long = period(3, DateTime(2026, 11, 18), DateTime(2026, 11, 25));

      expect(shouldRecord([trip, long], DateTime(2026, 11, 19), const {})?.tripId, 3);
      expect(shouldRecord([long, trip], DateTime(2026, 11, 21), const {})?.tripId, 7);
      // 나중 여행을 일시정지하면 겹친 다른 여행을 기록한다.
      expect(shouldRecord([long, trip], DateTime(2026, 11, 21), {7})?.tripId, 3);
    });

    test('출발일까지 같으면 나중에 만든(id가 큰) 여행이다', () {
      final twin = period(9, DateTime(2026, 11, 20), DateTime(2026, 11, 21));
      expect(shouldRecord([twin, trip], DateTime(2026, 11, 20, 8), const {})?.tripId, 9);
      // 목록 순서와 상관없다(먼저 온 쪽이나 나중 온 쪽을 고르는 구현이 아니다).
      expect(shouldRecord([trip, twin], DateTime(2026, 11, 20, 8), const {})?.tripId, 9);
    });
  });

  test('여행 목록 한 줄에서 날짜만 뽑고 JSON으로 그대로 되읽힌다', () {
    final fromSummary = TripPeriod.fromSummary(sampleSummary(
      id: 5,
      iso2: 'JP',
      nameKo: '일본',
      depart: DateTime(2026, 12, 20, 13, 5),
      ret: DateTime(2027, 1, 9),
    ));

    expect(fromSummary.departDate, DateTime(2026, 12, 20));
    expect(fromSummary.toJson(), {
      'tripId': 5,
      'countryIso2': 'JP',
      'countryNameKo': '일본',
      'departDate': '2026-12-20',
      'returnDate': '2027-01-09',
    });
    expect(TripPeriod.fromJson(fromSummary.toJson()), fromSummary);
  });
}
