import 'dart:math' as math;

import 'package:footstep_core/footstep_core.dart';
import 'package:footstep_core/src/detectors/signal.dart';
import 'package:test/test.dart';

AccelReading reading(int tMs, double magnitude) => AccelReading(tMs: tMs, x: 0, y: magnitude, z: 0);

void main() {
  group('MagnitudeGrid', () {
    test('20ms 칸 안의 표본은 크기의 평균이 되고, 칸은 다음 칸 표본이 와야 확정된다', () {
      final grid = MagnitudeGrid();
      expect(grid.add(const AccelReading(tMs: 0, x: 3, y: 4, z: 0)), isEmpty); // 크기 5
      expect(grid.add(reading(10, 7)), isEmpty);
      final out = grid.add(reading(20, 1));
      expect(out.map((s) => (s.tMs, s.magnitude, s.afterGap)), [(0, 6.0, false)]);
    });

    test('짧은 빈 칸은 직전 값으로 메운다', () {
      final grid = MagnitudeGrid()
        ..add(reading(0, 2))
        ..add(reading(10, 4));
      final out = grid.add(reading(70, 9));
      expect(out.map((s) => (s.tMs, s.magnitude)), [(0, 3.0), (20, 3.0), (40, 3.0)]);
    });

    test('200ms보다 긴 공백은 메우지 않고, 공백 뒤 첫 칸에 afterGap을 단다', () {
      final grid = MagnitudeGrid()..add(reading(0, 2));
      expect(grid.add(reading(500, 4)).map((s) => s.tMs), [0]);
      final out = grid.add(reading(520, 6));
      expect(out.map((s) => (s.tMs, s.magnitude, s.afterGap)), [(500, 4.0, true)]);
    });
  });

  group('Biquad', () {
    double amplitudeAfterSettling(Biquad filter, double hz) {
      var peak = 0.0;
      for (var i = 0; i < 500; i++) {
        final y = filter.filter(math.sin(2 * math.pi * hz * i / 50), steadyOutput: 0);
        if (i >= 250) peak = math.max(peak, y.abs());
      }
      return peak;
    }

    test('저역 통과(3Hz)는 일정한 입력을 그대로 내고, 걸음 박자는 남기고 빠른 진동은 줄인다', () {
      final steady = Biquad.lowPass(3, 50);
      for (var i = 0; i < 20; i++) {
        expect(steady.filter(9.81, steadyOutput: 9.81), closeTo(9.81, 1e-9));
      }
      expect(amplitudeAfterSettling(Biquad.lowPass(3, 50), 1), greaterThan(0.95));
      expect(amplitudeAfterSettling(Biquad.lowPass(3, 50), 10), lessThan(0.15));
    });

    test('고역 통과(0.7Hz)는 일정한 입력을 0으로 만들고, 느린 흔들림은 줄이고 걸음 박자는 남긴다', () {
      final steady = Biquad.highPass(0.7, 50);
      for (var i = 0; i < 20; i++) {
        expect(steady.filter(9.81, steadyOutput: 0), closeTo(0, 1e-9));
      }
      expect(amplitudeAfterSettling(Biquad.highPass(0.7, 50), 0.2), lessThan(0.15));
      expect(amplitudeAfterSettling(Biquad.highPass(0.7, 50), 2), greaterThan(0.95));
    });
  });

  test('stdDev는 모표준편차이고 비면 0이다', () {
    expect(stdDev([1, 2, 3, 4]), closeTo(1.1180, 1e-4));
    expect(stdDev(const []), 0);
    expect(mean([1, 2, 3, 4]), 2.5);
  });

  test('RecentValues는 최근 값만 남긴다', () {
    final values = RecentValues(3);
    for (final v in [1.0, 2.0, 3.0, 4.0]) {
      values.add(v);
    }
    expect(values.toList(), [2.0, 3.0, 4.0]);
    expect(values.isFull, isTrue);
    values.clear();
    expect(values.length, 0);
    expect(values.isFull, isFalse);
  });

  group('autocorrelationPeak', () {
    test('2Hz 사인은 0.5초(25표본) 지연에서 봉우리가 1에 가깝다', () {
      final w = [for (var i = 0; i < 150; i++) math.sin(2 * math.pi * 2 * i / 50)];
      final peak = autocorrelationPeak(w, 12, 65)!;
      expect(peak.lag, 25);
      expect(peak.r, greaterThan(0.95));
    });

    test('느린 흔들림(0.2Hz)은 지연이 커질수록 상관이 줄기만 해서 봉우리가 없다', () {
      final w = [for (var i = 0; i < 150; i++) math.sin(2 * math.pi * 0.2 * i / 50)];
      expect(autocorrelationPeak(w, 12, 65), isNull);
    });

    test('창이 지연 범위보다 짧으면 null이다', () {
      expect(autocorrelationPeak(List.filled(60, 1.0), 12, 65), isNull);
    });
  });
}
