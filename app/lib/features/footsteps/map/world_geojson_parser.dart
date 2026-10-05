import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';

class CountryPolygon {
  const CountryPolygon({required this.isoAlpha2, required this.rings});

  final String isoAlpha2;
  final List<List<LatLng>> rings;
}

/// 세계지도 GeoJSON(FeatureCollection)을 파싱해 국가별 폴리곤 목록을 반환한다.
/// ISO-3166-1 alpha-2 코드가 없는 feature는 건너뛴다(자체 영유권 분쟁지역, 부속영토 등).
/// 깨진 JSON이거나 예상 형식이 아니면 예외를 던지지 않고 빈 리스트를 반환한다.
List<CountryPolygon> parseWorldGeoJson(String geoJsonContent) {
  try {
    final root = jsonDecode(geoJsonContent) as Map<String, dynamic>;
    final features = root['features'] as List<dynamic>? ?? const [];

    final polygons = <CountryPolygon>[];
    for (final feature in features) {
      final props = feature['properties'] as Map<String, dynamic>?;
      final iso = props?['ISO3166-1-Alpha-2'] as String?;
      if (iso == null || iso.isEmpty) continue;

      final geometry = feature['geometry'] as Map<String, dynamic>?;
      if (geometry == null) continue;

      final rings = _ringsFromGeometry(geometry);
      if (rings.isEmpty) continue;

      polygons.add(CountryPolygon(isoAlpha2: iso.toUpperCase(), rings: rings));
    }
    return polygons;
  } catch (_) {
    return const [];
  }
}

List<List<LatLng>> _ringsFromGeometry(Map<String, dynamic> geometry) {
  final type = geometry['type'] as String?;
  final coordinates = geometry['coordinates'];

  switch (type) {
    case 'Polygon':
      // coordinates: [ring][point][lng,lat] — 첫 ring(외곽선)만 쓰고 구멍(holes)은 무시한다.
      return _polygonRings(coordinates as List<dynamic>);
    case 'MultiPolygon':
      // coordinates: [polygon][ring][point][lng,lat]
      final rings = <List<LatLng>>[];
      for (final polygon in coordinates as List<dynamic>) {
        rings.addAll(_polygonRings(polygon as List<dynamic>));
      }
      return rings;
    default:
      return const [];
  }
}

List<List<LatLng>> _polygonRings(List<dynamic> polygonCoords) {
  if (polygonCoords.isEmpty) return const [];
  final outerRing = polygonCoords.first as List<dynamic>;
  final points = outerRing
      .map((p) => p as List<dynamic>)
      .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
      .toList();
  return [points];
}
