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
