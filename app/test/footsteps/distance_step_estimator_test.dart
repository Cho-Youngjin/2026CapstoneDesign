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
}
