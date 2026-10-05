import 'package:app/features/footsteps/data/checkin.dart';
import 'package:app/features/footsteps/data/polygon_country_resolver.dart';
import 'package:app/features/footsteps/map/world_geojson_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// lat/lng 0~10 사각형 국가. ray-casting 검증에는 실제 국경 모양이 필요 없다.
final _square = CountryPolygon(isoAlpha2: 'AA', rings: [
  [
    const LatLng(0, 0),
    const LatLng(0, 10),
    const LatLng(10, 10),
    const LatLng(10, 0),
  ],
]);

void main() {
  test('폴리곤 내부 좌표는 해당 국가 코드를 반환한다', () async {
    final resolver = PolygonCountryResolver([_square]);

    expect(await resolver.resolveIso2(5, 5), 'AA');
  });

  test('폴리곤 밖 좌표는 미확인(XX)을 반환한다', () async {
    final resolver = PolygonCountryResolver([_square]);

    expect(await resolver.resolveIso2(50, 50), Checkin.unknownCountry);
  });

  test('여러 국가 중 좌표를 포함하는 국가를 찾는다', () async {
    final other = CountryPolygon(isoAlpha2: 'BB', rings: [
      [
        const LatLng(20, 20),
        const LatLng(20, 30),
        const LatLng(30, 30),
        const LatLng(30, 20),
      ],
    ]);
    final resolver = PolygonCountryResolver([_square, other]);

    expect(await resolver.resolveIso2(25, 25), 'BB');
  });

  test('국가 목록이 비어 있으면 미확인을 반환한다', () async {
    final resolver = PolygonCountryResolver(const []);

    expect(await resolver.resolveIso2(5, 5), Checkin.unknownCountry);
  });
}
