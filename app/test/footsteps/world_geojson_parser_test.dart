import 'package:app/features/footsteps/map/world_geojson_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Polygon geometry를 파싱해 하나의 ring을 만든다', () {
    const json = '''
    {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "properties": {"name": "Singapore", "ISO3166-1-Alpha-2": "SG"},
          "geometry": {
            "type": "Polygon",
            "coordinates": [[[103.6, 1.2], [104.0, 1.2], [104.0, 1.5], [103.6, 1.5], [103.6, 1.2]]]
          }
        }
      ]
    }
    ''';

    final polygons = parseWorldGeoJson(json);

    expect(polygons, hasLength(1));
    expect(polygons.first.isoAlpha2, 'SG');
    expect(polygons.first.rings, hasLength(1));
    expect(polygons.first.rings.first, hasLength(5));
    expect(polygons.first.rings.first.first.latitude, 1.2);
    expect(polygons.first.rings.first.first.longitude, 103.6);
  });

  test('MultiPolygon geometry를 파싱해 여러 ring을 만든다', () {
    const json = '''
    {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "properties": {"name": "United States", "ISO3166-1-Alpha-2": "US"},
          "geometry": {
            "type": "MultiPolygon",
            "coordinates": [
              [[[-100.0, 40.0], [-99.0, 40.0], [-99.0, 41.0], [-100.0, 41.0], [-100.0, 40.0]]],
              [[[-150.0, 60.0], [-149.0, 60.0], [-149.0, 61.0], [-150.0, 61.0], [-150.0, 60.0]]]
            ]
          }
        }
      ]
    }
    ''';

    final polygons = parseWorldGeoJson(json);

    expect(polygons, hasLength(1));
    expect(polygons.first.isoAlpha2, 'US');
    expect(polygons.first.rings, hasLength(2));
  });

  test('ISO 코드가 없는 feature는 건너뛴다', () {
    const json = '''
    {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "properties": {"name": "Unknown"},
          "geometry": {
            "type": "Polygon",
            "coordinates": [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 0.0]]]
          }
        }
      ]
    }
    ''';

    expect(parseWorldGeoJson(json), isEmpty);
  });

  test('깨진 JSON을 주면 예외 없이 빈 리스트를 반환한다', () {
    expect(parseWorldGeoJson('not json'), isEmpty);
  });
}
