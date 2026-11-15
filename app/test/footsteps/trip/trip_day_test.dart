import 'package:app/features/footsteps/data/route_point.dart';
import 'package:app/features/footsteps/trip/trip_day.dart';
import 'package:app/features/footsteps/trip/trip_footsteps_providers.dart' show DayRoute;
import 'package:flutter_test/flutter_test.dart';
import 'package:footstep_core/footstep_core.dart' show TimeSpan;

import 'trip_fakes.dart';

/// 위도 1도 = 111,195m(footstep_core geo.dart의 지구 반지름 기준).
const _degPerMeter = 1 / 111195.08;

RoutePoint point(DateTime at, {double northM = 0, int? steps, String state = 'walking', double? accuracy = 5}) => RoutePoint(
      lat: 37.5 + northM * _degPerMeter,
      lng: 127.0,
      countryIso: 'KR',
      recordedAt: at,
      tripId: 7,
      accuracyM: accuracy,
      stepsSincePrev: steps,
      state: state,
    );

TimeSpan span(DateTime from, DateTime to) => TimeSpan(from.millisecondsSinceEpoch, to.millisecondsSinceEpoch);

void main() {
  final trip = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));

  test('날짜 칩은 출발일부터 귀국일까지(양 끝 포함)다', () {
    expect(tripDates(trip), [DateTime(2026, 11, 20), DateTime(2026, 11, 21), DateTime(2026, 11, 22)]);
    expect(tripDates(period(1, DateTime(2026, 11, 30), DateTime(2026, 12, 1))),
        [DateTime(2026, 11, 30), DateTime(2026, 12, 1)]);
  });

  test('처음 고르는 날: 여행 중이면 오늘, 아니면 기록이 있는 마지막 날, 없으면 출발일', () {
    final points = [point(DateTime(2026, 11, 20, 9)), point(DateTime(2026, 11, 21, 9))];

    expect(initialTripDate(trip, points, DateTime(2026, 11, 22, 15)), DateTime(2026, 11, 22));
    expect(initialTripDate(trip, points, DateTime(2026, 12, 1)), DateTime(2026, 11, 21));
    expect(initialTripDate(trip, const [], DateTime(2026, 12, 1)), DateTime(2026, 11, 20));
  });

  test('점을 기기 현지 날짜로 묶고, 그날 걸음은 직전 점 이후 걸음의 합이다', () {
    final points = [
      point(DateTime(2026, 11, 20, 23, 50), steps: 100),
      point(DateTime(2026, 11, 21, 0, 10), steps: 40),
      point(DateTime(2026, 11, 21, 9), steps: null), // 시작 직후 점은 걸음을 모를 수 있다
      point(DateTime(2026, 11, 21, 9, 5), steps: 600),
    ];

    final day = buildTripDay(DateTime(2026, 11, 21, 15), points, const []);

    expect(day.date, DateTime(2026, 11, 21));
    expect(day.points.map((p) => p.recordedAt.hour), [0, 9, 9]);
    expect(day.steps, 640);
    expect(day.lastPointMs, DateTime(2026, 11, 21, 9, 5).millisecondsSinceEpoch);
    expect(buildTripDay(DateTime(2026, 11, 22), points, const []).points, isEmpty);
    expect(buildTripDay(DateTime(2026, 11, 22), points, const []).lastPointMs, 0);
  });

  test('머문 곳은 걸음 감지기 정지 구간으로 도착·출발을 잡는다(5분마다 잰 점이 드물어도)', () {
    // 10:00에 카페에 도착해 10:32에 떠났다. 정지 확인 점은 5분마다다.
    final points = [
      point(DateTime(2026, 11, 21, 9, 55), northM: -300),
      for (var m = 0; m <= 25; m += 5) point(DateTime(2026, 11, 21, 10, 0, 30).add(Duration(minutes: m)), state: 'still'),
      point(DateTime(2026, 11, 21, 10, 33), northM: 300),
    ];
    final spans = [span(DateTime(2026, 11, 21, 10), DateTime(2026, 11, 21, 10, 32))];

    final stay = buildTripDay(DateTime(2026, 11, 21), points, spans).stays.single;

    expect(DateTime.fromMillisecondsSinceEpoch(stay.arriveMs), DateTime(2026, 11, 21, 10));
    expect(Duration(milliseconds: stay.durationMs), const Duration(minutes: 32));
  });

  test('겹치거나 뒤집힌 정지 구간이 DB에 있어도 던지지 않고 점만으로 머문 곳을 잡는다', () {
    final points = [
      point(DateTime(2026, 11, 21, 9, 55), northM: -300),
      for (var m = 0; m <= 25; m += 5) point(DateTime(2026, 11, 21, 10, 0, 30).add(Duration(minutes: m)), state: 'still'),
      point(DateTime(2026, 11, 21, 10, 33), northM: 300),
    ];
    final overlapping = [
      span(DateTime(2026, 11, 21, 10), DateTime(2026, 11, 21, 10, 20)),
      span(DateTime(2026, 11, 21, 10, 10), DateTime(2026, 11, 21, 10, 32)),
    ];
    final inverted = [span(DateTime(2026, 11, 21, 10, 30), DateTime(2026, 11, 21, 10))];

    for (final spans in [overlapping, inverted]) {
      final day = buildTripDay(DateTime(2026, 11, 21), points, spans);

      expect(day.points, hasLength(8));
      expect(day.stays, hasLength(1)); // 정지 구간 없이 점 시각으로 잡은 머문 곳
    }
  });

  test('밤을 넘긴 숙소는 두 날 모두 실제 도착·출발 시각으로 보인다', () {
    final points = [
      point(DateTime(2026, 11, 20, 21, 55), northM: -500),
      for (var t = DateTime(2026, 11, 20, 22, 5); t.isBefore(DateTime(2026, 11, 21, 8)); t = t.add(const Duration(minutes: 5)))
        point(t, state: 'still'),
      point(DateTime(2026, 11, 21, 8, 5), northM: 500),
    ];
    final spans = [span(DateTime(2026, 11, 20, 22), DateTime(2026, 11, 21, 8))];

    for (final date in [DateTime(2026, 11, 20), DateTime(2026, 11, 21)]) {
      final stay = buildTripDay(date, points, spans).stays.single;
      expect(DateTime.fromMillisecondsSinceEpoch(stay.arriveMs), DateTime(2026, 11, 20, 22), reason: '$date');
      expect(DateTime.fromMillisecondsSinceEpoch(stay.leaveMs), DateTime(2026, 11, 21, 8), reason: '$date');
    }
  });

  group('정확도가 50m보다 나쁜 위치(네트워크 위치가 1km 넘게 튄 점)', () {
    // 실기기: 13:57:46 정확도 52, 13:57:52 정확도 66(1.5km 밖), 13:57:59 정확도 11로 돌아옴.
    final at = DateTime(2026, 11, 21, 13, 57, 46);
    List<RoutePoint> walk() => [
          point(at, northM: 0, steps: 10, accuracy: 20),
          point(at.add(const Duration(seconds: 6)), northM: 1476, steps: 7, accuracy: 66),
          point(at.add(const Duration(seconds: 13)), northM: 20, steps: 4, accuracy: 11),
          point(at.add(const Duration(seconds: 44)), northM: 3000, steps: 5, accuracy: 60), // 뒤에 남은 점이 없다
        ];

    test('경로 점에서 뺀다. 50m와 정확도를 모르는 점은 남긴다', () {
      final points = [
        point(at, steps: 1, accuracy: 50),
        point(at.add(const Duration(seconds: 6)), northM: 10, steps: 1, accuracy: 50.1),
        point(at.add(const Duration(seconds: 12)), northM: 20, steps: 1, accuracy: null),
      ];

      final day = buildTripDay(DateTime(2026, 11, 21), points, const []);

      expect(day.points.map((p) => p.accuracyM), [50, null]);
    });

    test('그날 걸음은 뺀 점의 걸음까지 모두 센다', () {
      final day = buildTripDay(DateTime(2026, 11, 21), walk(), const []);

      expect(day.points, hasLength(2));
      expect(day.steps, 26); // 10 + 7 + 4 + 5
    });

    test('뺀 점의 걸음은 다음에 남은 점의 걸음에 더한다(요청에 보낼 걸음 수)', () {
      final day = buildTripDay(DateTime(2026, 11, 21), walk(), const []);

      expect(day.points.map((p) => p.stepsSincePrev), [10, 11]);
    });

    test('걸음 수를 모르는 점끼리만 이어지면 null로 둔다', () {
      final points = [
        point(at, accuracy: 10),
        point(at.add(const Duration(seconds: 6)), northM: 900, accuracy: 70),
        point(at.add(const Duration(seconds: 12)), northM: 10, accuracy: 10),
      ];

      expect(buildTripDay(DateTime(2026, 11, 21), points, const []).points.last.stepsSincePrev, isNull);
    });

    test('이동 거리(직선 대체 경로)에 튄 점이 들어가지 않는다', () {
      final day = buildTripDay(DateTime(2026, 11, 21), walk(), const []);

      expect(DayRoute.straight(day.points, roadMatched: false).distanceMeters, closeTo(20, 1));
    });

    test('머문 곳은 튄 점 때문에 끊기지 않는다', () {
      // 10:00~10:25 카페에서 5분마다 재다가 10:12에 1.4km 튄 점(정확도 66)이 하나 끼었다.
      final points = [
        point(DateTime(2026, 11, 21, 9, 55), northM: -300),
        for (var m = 0; m <= 25; m += 5) point(DateTime(2026, 11, 21, 10, 0, 30).add(Duration(minutes: m)), state: 'still'),
        point(DateTime(2026, 11, 21, 10, 12), northM: 1400, state: 'still', accuracy: 66),
        point(DateTime(2026, 11, 21, 10, 33), northM: 300),
      ];
      final spans = [span(DateTime(2026, 11, 21, 10), DateTime(2026, 11, 21, 10, 32))];

      final stay = buildTripDay(DateTime(2026, 11, 21), points, spans).stays.single;

      expect(stay.nPoints, 6);
      expect(stay.lat, closeTo(37.5, 0.0001));
    });

    test('모두 정확도가 나빠도 그날 걸음은 센다', () {
      final points = [point(at, steps: 3, accuracy: 80), point(at.add(const Duration(seconds: 6)), steps: 4, accuracy: 90)];

      final day = buildTripDay(DateTime(2026, 11, 21), points, const []);

      expect(day.points, isEmpty);
      expect(day.steps, 7);
    });
  });
}
