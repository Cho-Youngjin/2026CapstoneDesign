class Embassy {
  const Embassy({
    required this.id,
    required this.type,
    required this.name,
    required this.lat,
    required this.lng,
    this.phone,
    this.emergencyPhone,
    this.address,
  });

  final String id;
  final String type;
  final String name;
  final double lat;
  final double lng;
  /// 서버 스키마가 nullable로 선언한 세 필드(V3__travel_alert_embassy.sql) —
  /// 공공데이터에 전화번호나 주소가 비어 있는 분관이 섞여 있다. non-null로 캐스팅하면
  /// 한 건만 비어도 공관 목록 전체가 에러로 사라지므로 nullable로 받는다.
  final String? phone;
  final String? emergencyPhone;
  final String? address;

  // 서버의 id는 숫자(Long) PK다 — 문자열로 캐스팅하면 런타임에 깨지므로
  // toString()으로 안전하게 변환한다.
  factory Embassy.fromJson(Map<String, dynamic> json) => Embassy(
        id: json['id'].toString(),
        type: json['type'] as String,
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        phone: json['phone'] as String?,
        emergencyPhone: json['emergencyPhone'] as String?,
        address: json['address'] as String?,
      );
}
