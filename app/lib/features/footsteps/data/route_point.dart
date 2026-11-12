/// 실시간 이동 중 저장되는 좌표 하나. Checkin과 달리 국경 이동 확정 여부와
/// 무관하게 촘촘히 쌓여 "지나온 길"을 영구적으로 재구성하는 데 쓰인다.
///
/// 여행 기록(설계 2026-11-07 9-3)이 남긴 점은 [tripId]·[accuracyM]·[stepsSincePrev]·[state]를 함께 가진다.
/// 그 전의 실시간 경로·해외 매핑이 남긴 점은 넷 다 null이다.
class RoutePoint {
  const RoutePoint({
    required this.lat,
    required this.lng,
    required this.countryIso,
    required this.recordedAt,
    this.tripId,
    this.accuracyM,
    this.stepsSincePrev,
    this.state,
  });

  final double lat;
  final double lng;
  final String countryIso;
  final DateTime recordedAt;

  /// 이 점을 남긴 여행(서버 trip id).
  final int? tripId;

  /// 측위 정확도(m).
  final double? accuracyM;

  /// 직전 점 이후 걸음 수.
  final int? stepsSincePrev;

  /// 측위 때 수집 정책의 상태(`unknown`·`walking`·`still`·`otherMotion`·`vehicle`). 복원 API의 state와 같은 이름이다.
  final String? state;
}
