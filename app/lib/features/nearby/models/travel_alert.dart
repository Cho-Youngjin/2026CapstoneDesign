class TravelAlert {
  const TravelAlert({
    required this.id,
    required this.level,
    required this.region,
    required this.title,
    required this.issuedAt,
  });

  final String id;
  final int level;
  final String region;
  final String title;
  final DateTime issuedAt;

  // 서버의 id는 숫자(Long) PK다 — 문자열로 캐스팅하면 런타임에 깨지므로
  // toString()으로 안전하게 변환한다.
  factory TravelAlert.fromJson(Map<String, dynamic> json) => TravelAlert(
        id: json['id'].toString(),
        level: json['level'] as int,
        region: json['region'] as String,
        title: json['title'] as String,
        issuedAt: DateTime.parse(json['issuedAt'] as String),
      );
}
