import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../map/world_geojson_parser.dart';
import 'checkin.dart';
import 'country_resolver.dart';

/// 세계지도 GeoJSON 폴리곤으로 좌표를 국가에 즉시 매칭한다(point-in-polygon).
/// 네트워크·외부 API가 필요 없어 실시간 위치 스트림처럼 짧은 주기로 반복 호출해도
/// 안전하다. GeocodingCountryResolver와 달리 오프라인에서도 동작한다.
///
/// world_geojson_parser가 폴리곤의 구멍(holes)을 버리고 외곽선만 쓰는 것과 같은
/// 근사를 그대로 물려받는다 — 경계 정밀도가 필요한 용도가 아니라 실시간 자동
/// 체크인의 "어느 나라인지" 판정용이라 이 정도 근사로 충분하다.
class PolygonCountryResolver implements CountryResolver {
  const PolygonCountryResolver(this._countries);

  final List<CountryPolygon> _countries;

  @override
  Future<String> resolveIso2(double lat, double lng) async {
    final point = LatLng(lat, lng);
    for (final country in _countries) {
      for (final ring in country.rings) {
        if (_pointInRing(point, ring)) return country.isoAlpha2;
      }
    }
    return Checkin.unknownCountry;
  }

  /// 표준 ray-casting: point에서 그은 반직선이 폴리곤 변과 만나는 횟수가
  /// 홀수면 내부, 짝수면 외부.
  bool _pointInRing(LatLng point, List<LatLng> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final lat1 = ring[i].latitude, lng1 = ring[i].longitude;
      final lat2 = ring[j].latitude, lng2 = ring[j].longitude;

      final crossesLatitude = (lat1 > point.latitude) != (lat2 > point.latitude);
      if (!crossesLatitude) continue;

      final lngAtPointLatitude =
          (lng2 - lng1) * (point.latitude - lat1) / (lat2 - lat1) + lng1;
      if (point.longitude < lngAtPointLatitude) inside = !inside;
    }
    return inside;
  }
}
