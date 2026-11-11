import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

/// 위도 1도 = 111,195m(geo.dart의 지구 반지름 기준).
const _degPerMeter = 1 / 111195.08;

/// [minute]분에 기준 위치에서 북쪽으로 [northM]m인 점.
Fix at(double minute, double northM) => Fix(
      tMs: (minute * 60000).round(),
      lat: 37.5 + northM * _degPerMeter,
      lng: 127.0,
      accuracyM: 5,
    );

TimeSpan minutes(double from, double to) => TimeSpan((from * 60000).round(), (to * 60000).round());

void main() {
  group('점만으로 묶기 (Li 외 2008)', () {
    const pointsOnly = StayParams(useStillIntervals: false);

    test('10분 넘게 머문 두 곳을 도착·출발 시각과 함께 찾는다', () {
      // A에서 0~12분(±10m 흔들림), 13~15분 이동, B(북쪽 1200m)에서 16~28분, 29분에 떠난다.
      final points = [
        for (var m = 0; m <= 12; m++) at(m.toDouble(), m.isEven ? 10 : -10),
        at(13, 300),
        at(14, 600),
        at(15, 900),
        for (var m = 16; m <= 28; m++) at(m.toDouble(), 1200 + (m.isEven ? 5 : -5)),
        at(29, 1500),
      ];

      final stays = detectStays(points, params: pointsOnly);

      expect(stays.map((s) => (s.arriveMs, s.leaveMs, s.nPoints)), [
        (0, 12 * 60000, 13),
        (16 * 60000, 28 * 60000, 13),
      ]);
      expect(haversineMeters(stays[0].lat, stays[0].lng, 37.5, 127.0), lessThan(2));
      expect(haversineMeters(stays[1].lat, stays[1].lng, 37.5 + 1200 * _degPerMeter, 127.0), lessThan(2));
    });

    test('머문 시간이 10분에 못 미치면 머문 곳이 아니다', () {
      final points = [for (var m = 0; m <= 9; m++) at(m.toDouble(), 0), at(10, 500)];

      expect(detectStays(points, params: pointsOnly), isEmpty);
    });

    test('기준점(첫 점)에서 반경 밖의 점이 나오면 무리가 끝난다', () {
      // 0~10분은 기준점에서 99m 안, 11분은 101m — 무리는 0~10분(10분)이다.
      final points = [for (var m = 0; m <= 10; m++) at(m.toDouble(), m * 9.9), at(11, 101)];

      final stay = detectStays(points, params: pointsOnly).single;
      expect((stay.arriveMs, stay.leaveMs, stay.nPoints), (0, 10 * 60000, 11));
    });

    test('기록 끝까지 머문 무리도 머문 곳이다', () {
      final points = [for (var m = 0; m <= 11; m++) at(m.toDouble(), 0)];

      final stay = detectStays(points, params: pointsOnly).single;
      expect((stay.arriveMs, stay.leaveMs), (0, 11 * 60000));
    });

    test('정지 구간을 줘도 쓰지 않는다', () {
      final points = [at(0, -300), at(5, 0), at(10, 0), at(15, 300)];

      expect(detectStays(points, stillSpans: [minutes(1.5, 13)], params: pointsOnly), isEmpty);
    });
  });

  group('걸음 감지기 정지 구간으로 시각 잡기 (제안)', () {
    test('5분마다 잰 점 두 개뿐이어도 정지 구간으로 도착·출발 시각을 잡는다', () {
      // 1.5분에 도착해 13분에 떠났다. 점은 5분·10분 두 개라 점 사이는 5분뿐이다.
      final points = [at(0, -300), at(5, 0), at(10, 3), at(15, 300)];

      final stay = detectStays(points, stillSpans: [minutes(1.5, 13)]).single;

      expect((stay.arriveMs, stay.leaveMs, stay.nPoints), (90000, 13 * 60000, 2));
      expect(haversineMeters(stay.lat, stay.lng, 37.5 + 1.5 * _degPerMeter, 127.0), lessThan(0.1));
    });

    test('점 하나라도 정지 구간이 길면 머문 곳이다(1시간 주기 측위)', () {
      final points = [at(0, -3000), at(60, 0), at(120, 3000)];

      final stay = detectStays(points, stillSpans: [minutes(40, 80)]).single;
      expect((stay.arriveMs, stay.leaveMs, stay.nPoints), (40 * 60000, 80 * 60000, 1));
    });

    test('정지 구간이 이웃 점보다 앞서 시작하면 걸음 없이 옮겨 온 것이라 도착은 점 시각이다', () {
      // OS 센서판은 버스 안에서도 정지다. 0분 점(2km 남쪽)부터 이미 정지였으니 언제 도착했는지 모른다.
      final points = [at(0, -2000), at(5, 0), at(10, 0), at(15, 0), at(20, 300)];

      final stay = detectStays(points, stillSpans: [minutes(-1, 17)]).single;
      expect((stay.arriveMs, stay.leaveMs, stay.nPoints), (5 * 60000, 17 * 60000, 3));
    });

    test('정지 구간이 다음 점 뒤까지 이어지면 출발은 점 시각이다', () {
      final points = [at(0, -300), at(5, 0), at(16, 0), at(20, 3000)];

      final stay = detectStays(points, stillSpans: [minutes(1, 25)]).single;
      expect((stay.arriveMs, stay.leaveMs), (60000, 16 * 60000));
    });

    test('반경 안에 걸어 들어오며 찍힌 점은 머문 곳에 넣지 않고 정지 구간 시작을 도착으로 쓴다', () {
      // 0분 점은 60m 남쪽에서 걸어오던 중(정지 구간 밖)이다. 1분에 멈춰 11분에 떠났다.
      final points = [at(0, -60), at(5, 0), at(9, 0), at(15, 300)];

      final stay = detectStays(points, stillSpans: [minutes(1, 11)]).single;
      expect((stay.arriveMs, stay.leaveMs, stay.nPoints), (60000, 11 * 60000, 2));
      expect(haversineMeters(stay.lat, stay.lng, 37.5, 127.0), lessThan(0.1));
    });

    test('걷다 찍힌 점이 정지 점들과 반경 안에 묶여도 머문 시간은 정지 구간으로 잰다', () {
      // 5분 점은 걷는 중(90m 북쪽), 9.5분에 멈춰 기록 끝(15.8분)까지 있었다. 점만으로는 5~15분이 10분이라
      // 머문 곳이 되지만, 실제로 머문 시간은 6.3분이다(실제 세션 fixed_5m 재생에서 본 경우).
      final points = [at(0, -400), at(5, 90), at(10, 0), at(15, 5)];
      final spans = [minutes(9.5, 15.8)];

      expect(detectStays(points, stillSpans: spans), isEmpty);
      expect(detectStays(points, stillSpans: spans, params: const StayParams(useStillIntervals: false))
          .map((s) => (s.arriveMs, s.leaveMs, s.nPoints)), [(5 * 60000, 15 * 60000, 3)]);
    });
  });

  test('걸음 감지기 상태 변화에서 정지 구간을 뽑는다(마지막 상태는 끝 시각까지)', () {
    final states = [
      const StateChange(tMs: 0, state: StepState.still),
      const StateChange(tMs: 1000, state: StepState.walking),
      const StateChange(tMs: 5000, state: StepState.still),
      const StateChange(tMs: 9000, state: StepState.otherMotion),
      const StateChange(tMs: 12000, state: StepState.still),
    ];

    expect(stillSpans(states, 20000),
        [const TimeSpan(0, 1000), const TimeSpan(5000, 9000), const TimeSpan(12000, 20000)]);
    expect(stillSpans(const [], 20000), isEmpty);
  });

  group('설정과 입력 검증', () {
    test('CLI 파라미터로 설정을 만든다', () {
      expect(createStayParams().params, {'radius_m': 100.0, 'min_stay_s': 600.0, 'use_still': true});
      expect(createStayParams({'radius_m': '50', 'min_stay_s': '300', 'use_still': 'false'}).params,
          {'radius_m': 50.0, 'min_stay_s': 300.0, 'use_still': false});
      expect(() => createStayParams({'radius': '50'}), throwsArgumentError);
      expect(() => createStayParams({'min_stay_s': '0'}), throwsArgumentError);
    });

    test('시각순이 아닌 점이나 0 이하의 반경·시간은 ArgumentError다', () {
      expect(() => detectStays([at(1, 0), at(0, 0)]), throwsArgumentError);
      expect(() => detectStays([at(0, 0)], params: const StayParams(radiusM: 0)), throwsArgumentError);
      expect(() => detectStays([at(0, 0)], params: const StayParams(minDurationMs: 0)), throwsArgumentError);
    });

    test('점이 없으면 머문 곳도 없다', () {
      expect(detectStays(const []), isEmpty);
    });
  });
}
