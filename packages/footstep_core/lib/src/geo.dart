import 'dart:math' as math;

/// 두 좌표 사이 거리(m). 지구를 반지름 6,371,008.8m인 구로 보는 haversine 식이다 — 걷는 거리 수준에서는
/// 타원체 식과 차이가 오차 예산(25m~)보다 훨씬 작다.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusM = 6371008.8;
  double rad(double degrees) => degrees * math.pi / 180;
  final sinLat = math.sin(rad(lat2 - lat1) / 2);
  final sinLng = math.sin(rad(lng2 - lng1) / 2);
  final a = sinLat * sinLat + math.cos(rad(lat1)) * math.cos(rad(lat2)) * sinLng * sinLng;
  return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(a)));
}
