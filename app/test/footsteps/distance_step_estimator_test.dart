import 'package:app/features/footsteps/health/distance_step_estimator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('좌표가 1개 이하면 이동 거리는 0이다', () {
    expect(totalDistanceMeters(const []), 0);
    expect(totalDistanceMeters(const [LatLng(37.5, 127.0)]), 0);
  });

  test('적도 위 경도 1도 차이는 대략 111km다', () {
    final meters = totalDistanceMeters(const [
      LatLng(0, 0),
      LatLng(0, 1),
    ]);

    expect(meters, closeTo(111320, 200)); // 오차 200m 허용
  });

  test('여러 구간의 거리를 순서대로 합산한다', () {
    final oneDegree = totalDistanceMeters(const [LatLng(0, 0), LatLng(0, 1)]);

    final total = totalDistanceMeters(const [
      LatLng(0, 0),
      LatLng(0, 1),
      LatLng(0, 2),
    ]);

    expect(total, closeTo(oneDegree * 2, 1));
  });

  test('거리를 보폭으로 나눠 걸음 수를 추정한다', () {
    expect(estimateStepsFromDistance(750), 1000);
    expect(estimateStepsFromDistance(0), 0);
  });

  group('walkingDistanceMeters', () {
    final t0 = DateTime.utc(2026, 10, 18, 9);
    // 위도 0.001° ≈ 111m
    const a = LatLng(35.6800, 139.7600);
    const b = LatLng(35.6810, 139.7600);
    const c = LatLng(35.6820, 139.7600);

    test('이어서 걸은 기록은 그대로 합한다', () {
      final meters = walkingDistanceMeters([(a, t0), (b, t0.add(const Duration(minutes: 1))), (c, t0.add(const Duration(minutes: 2)))]);

      expect(meters, closeTo(totalDistanceMeters(const [a, b, c]), 0.01));
    });

    test('기록 사이가 오래 비면(다른 날·다른 세션) 그 사이는 걸은 것으로 치지 않는다', () {
      final meters = walkingDistanceMeters([
        (a, t0),
        (b, t0.add(const Duration(minutes: 1))),
        (c, t0.add(const Duration(days: 1))), // 다음 날 이어서 시작
      ]);

      expect(meters, closeTo(totalDistanceMeters(const [a, b]), 0.01));
    });

    test('한 번에 너무 멀리 뛴 구간(다른 출발점에서 새로 시작)은 빼고 더한다', () {
      const osaka = LatLng(34.6937, 135.5023); // 도쿄에서 약 400km
      final meters = walkingDistanceMeters([
        (a, t0),
        (b, t0.add(const Duration(seconds: 30))),
        (osaka, t0.add(const Duration(minutes: 1))),
      ]);

      expect(meters, closeTo(totalDistanceMeters(const [a, b]), 0.01));
    });
  });
}
