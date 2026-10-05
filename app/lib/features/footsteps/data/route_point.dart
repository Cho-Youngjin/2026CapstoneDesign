/// 실시간 이동 중 저장되는 좌표 하나. Checkin과 달리 국경 이동 확정 여부와
/// 무관하게 촘촘히 쌓여 "지나온 길"을 영구적으로 재구성하는 데 쓰인다.
class RoutePoint {
  const RoutePoint({
    required this.lat,
    required this.lng,
    required this.countryIso,
    required this.recordedAt,
  });

  final double lat;
  final double lng;
  final String countryIso;
  final DateTime recordedAt;
}
