import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// GPS 경로로 이동 거리를 계산해 걸음 수를 대략 추정한다. Health Connect
/// 걸음 수와는 별개의 독립적인 추정치라 — 권한 거부·기기 미지원 등으로
/// Health 데이터가 비어 있을 때도 "이 정도는 걸었다"를 보여줄 보조 지표,
/// 혹은 Health 수치가 실제와 맞는지 대조해볼 참고값으로 쓴다. 보폭은
/// 성인 평균값(약 0.75m)을 고정으로 써서 개인차에 따른 오차가 있을 수 있다.
const averageStrideMeters = 0.75;
const _earthRadiusMeters = 6371000.0;

double totalDistanceMeters(List<LatLng> points) {
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += _haversineMeters(points[i - 1], points[i]);
  }
  return total;
}

/// 두 기록 사이가 이보다 오래 비면 이어서 걸은 것으로 보지 않는다(다른 날, 다른 해외 매핑 세션).
const maxWalkingGap = Duration(minutes: 10);

/// 연속한 두 기록이 이보다 멀면 걸어서 이동한 것으로 보지 않는다(다른 출발점에서 새로 시작한 해외 매핑 등).
/// 경로는 10m마다 기록되므로 정상적인 걷기에서는 나올 수 없는 거리다.
const maxWalkingJumpMeters = 1000.0;

/// 기록 시각 순서대로 이동 거리를 합하되, 오래 비었거나 한 번에 멀리 뛴 구간은 빼고 더한다.
///
/// 한 나라의 기록을 전부 한 줄로 이으면, 다른 날·다른 세션 사이의 직선거리(수백 km일 수도 있다)가
/// 걸은 거리로 잡혀 추정 걸음 수가 크게 부풀기 때문이다.
double walkingDistanceMeters(List<(LatLng, DateTime)> points) {
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    final (prev, prevAt) = points[i - 1];
    final (cur, curAt) = points[i];
    if (curAt.difference(prevAt).abs() > maxWalkingGap) continue;
    final meters = _haversineMeters(prev, cur);
    if (meters > maxWalkingJumpMeters) continue;
    total += meters;
  }
  return total;
}

int estimateStepsFromDistance(double meters) => (meters / averageStrideMeters).round();

double _haversineMeters(LatLng a, LatLng b) {
  final lat1 = _degToRad(a.latitude);
  final lat2 = _degToRad(b.latitude);
  final dLat = _degToRad(b.latitude - a.latitude);
  final dLng = _degToRad(b.longitude - a.longitude);

  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return _earthRadiusMeters * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

double _degToRad(double deg) => deg * math.pi / 180;
