import 'package:flutter/material.dart';

enum PlaceCategory {
  tourist('TOURIST', '관광지'),
  restaurant('RESTAURANT', '음식점'),
  pharmacy('PHARMACY', '약국'),
  atm('ATM', 'ATM');

  const PlaceCategory(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// 목록 아이콘과 지도 핀에서 카테고리를 한눈에 구분하는 색.
  Color get color => switch (this) {
        PlaceCategory.tourist => const Color(0xFF2E7D32), // 초록
        PlaceCategory.restaurant => const Color(0xFFEF6C00), // 주황
        PlaceCategory.pharmacy => const Color(0xFFC2185B), // 분홍
        PlaceCategory.atm => const Color(0xFF1565C0), // 파랑
      };

  /// 지도 마커 색(구글 지도 hue 값). [color]와 같은 계열로 맞춘다.
  double get markerHue => switch (this) {
        PlaceCategory.tourist => 120, // 초록
        PlaceCategory.restaurant => 30, // 주황
        PlaceCategory.pharmacy => 330, // 장미/분홍
        PlaceCategory.atm => 210, // 파랑
      };
}

class Place {
  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.lat,
    required this.lng,
    this.distanceMeters,
  });

  final String id;
  final String name;
  final PlaceCategory category;
  final String address;
  final double lat;
  final double lng;

  /// 조회 기준 위치에서 이 장소까지의 대략적인 직선 거리(m). 앱이 계산해 채우며, 모르면 null이다.
  final double? distanceMeters;

  Place withDistance(double meters) => Place(
        id: id,
        name: name,
        category: category,
        address: address,
        lat: lat,
        lng: lng,
        distanceMeters: meters,
      );

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        id: json['id'] as String,
        name: json['name'] as String,
        category: PlaceCategory.values.firstWhere(
          (c) => c.apiValue == json['category'],
          orElse: () => PlaceCategory.tourist,
        ),
        address: json['address'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
      );
}
