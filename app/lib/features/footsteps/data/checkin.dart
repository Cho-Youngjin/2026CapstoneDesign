enum CheckinSource { auto, manual, import }

class Checkin {
  const Checkin({
    required this.id,
    required this.lat,
    required this.lng,
    required this.countryIso,
    required this.recordedAt,
    required this.source,
    required this.synced,
    this.serverId,
  });

  final int id;
  final double lat;
  final double lng;

  /// ISO-3166-1 alpha-2. 역지오코딩에 실패하면 'XX'(미확인)로 저장하고
  /// 동기화 시 재시도 대상이 된다.
  final String countryIso;
  final DateTime recordedAt;
  final CheckinSource source;
  final bool synced;
  final String? serverId;

  static const unknownCountry = 'XX';
}
