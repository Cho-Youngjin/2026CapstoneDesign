import 'package:app/features/footsteps/map/world_geojson_parser.dart';
import 'package:app/features/footsteps/providers/footsteps_providers.dart';
import 'package:app/features/nearby/models/place.dart';
import 'package:app/features/nearby/providers/nearby_selection_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('카테고리 기본값은 관광지다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(nearbyCategoryProvider), PlaceCategory.tourist);
  });

  test('카테고리를 바꾸면 provider 값이 갱신된다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(nearbyCategoryProvider.notifier).state = PlaceCategory.atm;

    expect(container.read(nearbyCategoryProvider), PlaceCategory.atm);
  });

  test('국가 선택 기본값은 null이다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(selectedCountryProvider), isNull);
  });

  Position fakePosition(double lat, double lng) => Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

  final square = CountryPolygon(isoAlpha2: 'AA', rings: [
    [
      const LatLng(0, 0),
      const LatLng(0, 10),
      const LatLng(10, 10),
      const LatLng(10, 0),
    ],
  ]);

  test('현재 위치가 국가 폴리곤 안이면 그 국가를 반환한다', () async {
    final container = ProviderContainer(overrides: [
      currentPositionProvider.overrideWith((ref) async => fakePosition(5, 5)),
      worldCountryPolygonsProvider.overrideWith((ref) async => [square]),
    ]);
    addTearDown(container.dispose);

    expect(await container.read(currentLocationCountryProvider.future), 'AA');
  });

  test('현재 위치가 어느 국가에도 속하지 않으면 null을 반환한다', () async {
    final container = ProviderContainer(overrides: [
      currentPositionProvider.overrideWith((ref) async => fakePosition(50, 50)),
      worldCountryPolygonsProvider.overrideWith((ref) async => [square]),
    ]);
    addTearDown(container.dispose);

    expect(await container.read(currentLocationCountryProvider.future), isNull);
  });
}
