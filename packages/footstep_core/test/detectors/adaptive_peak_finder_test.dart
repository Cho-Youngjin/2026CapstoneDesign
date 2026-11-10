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
