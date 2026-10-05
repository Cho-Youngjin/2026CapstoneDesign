enum PlaceCategory {
  tourist('TOURIST', '관광지'),
  restaurant('RESTAURANT', '음식점'),
  pharmacy('PHARMACY', '약국'),
  atm('ATM', 'ATM');

  const PlaceCategory(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

class Place {
  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String name;
  final PlaceCategory category;
  final String address;
  final double lat;
  final double lng;

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
