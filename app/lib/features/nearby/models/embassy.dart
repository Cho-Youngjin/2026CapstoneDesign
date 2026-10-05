class Embassy {
  const Embassy({
    required this.id,
    required this.type,
    required this.name,
    required this.lat,
    required this.lng,
    required this.phone,
    required this.emergencyPhone,
    required this.address,
  });

  final String id;
  final String type;
  final String name;
  final double lat;
  final double lng;
  final String phone;
  final String emergencyPhone;
  final String address;

  // 서버의 id는 숫자(Long) PK다 — 문자열로 캐스팅하면 런타임에 깨지므로
  // toString()으로 안전하게 변환한다.
  factory Embassy.fromJson(Map<String, dynamic> json) => Embassy(
        id: json['id'].toString(),
        type: json['type'] as String,
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        phone: json['phone'] as String,
        emergencyPhone: json['emergencyPhone'] as String,
        address: json['address'] as String,
      );
}
