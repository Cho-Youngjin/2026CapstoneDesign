/// GPS 위치 하나. [tMs]는 기록 시각(gps.csv의 t_ms)이다 — 재생기는 이 시각을 '그 위치를 알 수 있게 된
/// 때'로 쓴다. 속도·방향은 기기가 모르면 null이다.
class Fix {
  const Fix({
    required this.tMs,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    this.speedMps,
    this.bearingDeg,
  });

  final int tMs;
  final double lat;
  final double lng;
  final double accuracyM;
  final double? speedMps;
  final double? bearingDeg;
}
