import 'dart:math' as math;

import 'package:footstep_core/src/detectors/adaptive_peak_finder.dart';
import 'package:test/test.dart';

void main() {
  /// 50Hz(20ms)로 2Hz 사인을 5초 넣고 확정된 봉우리 시각을 모은다.
  List<int> feedSine(AdaptivePeakFinder finder, {required double amplitude, double offset = 0}) => [
        for (var i = 0; i < 250; i++)
          ?finder.add(i * 20, offset + amplitude * math.sin(2 * math.pi * 2 * i * 20 / 1000)),
      ];

  test('Tmax를 넘고 Tmin 아래로 내려갔다가 0으로 돌아오면 봉우리 시각 하나를 확정한다', () {
    // 마지막 주기(4620ms 봉우리)는 5초 안에 0으로 돌아오지 않아 아직 확정되지 않는다.
    expect(feedSine(AdaptivePeakFinder(), amplitude: 2),
        [120, 620, 1120, 1620, 2120, 2620, 3120, 3620, 4120]);
  });

  test('Tmax는 직전 두 봉우리 평균의 1/3로 바뀐다(이권희 외 2018 식 (4))', () {
    final finder = AdaptivePeakFinder();
    feedSine(finder, amplitude: 2);
    expect(finder.maxThreshold, closeTo(0.665, 0.001));
  });

  test('Tmax는 봉우리 하나로는 안 바뀌고, 크기가 다른 두 봉우리의 평균으로 바뀌어 약한 봉우리를 거른다', () {
    final finder = AdaptivePeakFinder();

    // 첫 봉우리(3.0): 넘고 → 골짜기 → 0으로 돌아오면 확정. 직전 봉우리가 없어 Tmax는 그대로다.
    expect(finder.add(0, 3.0), isNull);
    expect(finder.add(20, -1.0), isNull);
    expect(finder.add(40, 0.0), 0);
    expect(finder.maxThreshold, 1.0);

    // 둘째 봉우리(6.0): Tmax = (3 + 6) / 6 = 1.5. 한쪽 봉우리만 쓰는 식이면 1.0이나 2.0이 된다.
    expect(finder.add(60, 6.0), isNull);
    expect(finder.add(80, -1.0), isNull);
    expect(finder.add(100, 0.0), 60);
    expect(finder.maxThreshold, closeTo(1.5, 1e-9));

    // 처음 Tmax(1.0)는 넘지만 바뀐 Tmax(1.5)에 못 미치는 봉우리는 후보가 아니다.
    expect(finder.add(120, 1.2), isNull);
    expect(finder.add(140, -1.0), isNull);
    expect(finder.add(160, 0.0), isNull);
    expect(finder.maxThreshold, closeTo(1.5, 1e-9));

    // 다음 봉우리(2.0)는 확정되고 Tmax = (6 + 2) / 6이 된다.
    expect(finder.add(180, 2.0), isNull);
    expect(finder.add(200, -1.0), isNull);
    expect(finder.add(220, 0.0), 180);
    expect(finder.maxThreshold, closeTo(8 / 6, 1e-9));
  });

  test('Tmax(처음 1.0)를 넘지 못하는 작은 흔들림은 후보가 아니다', () {
    expect(feedSine(AdaptivePeakFinder(), amplitude: 0.5), isEmpty);
  });

  test('Tmin 아래로 내려가지 않으면(골짜기 없음) 확정하지 않는다', () {
    expect(feedSine(AdaptivePeakFinder(), amplitude: 1, offset: 1.5), isEmpty);
  });

  test('reset은 Tmax를 처음 값으로 되돌린다', () {
    final finder = AdaptivePeakFinder();
    feedSine(finder, amplitude: 2);
    finder.reset();
    expect(finder.maxThreshold, 1.0);
  });
}
