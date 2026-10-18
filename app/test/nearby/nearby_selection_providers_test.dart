import 'package:app/features/footsteps/map/world_geojson_parser.dart';
import 'package:app/features/footsteps/providers/footsteps_providers.dart';
import 'package:app/features/nearby/models/place.dart';
import 'package:app/features/nearby/providers/nearby_selection_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  group('effectiveCountryIso2', () {
    const available = ['JP', 'VN', 'TH'];

    test('현재 위치 국가가 목록에 없으면 목록 첫 항목으로 떨어진다', () {
      // 한국에서 주변정보 탭을 열면 KR이 Tier A 목록에 없어, 그대로 쓰면
      // DropdownButton의 "value는 items 중 정확히 하나와 같아야 한다" assertion에 걸렸다.
      expect(
        effectiveCountryIso2(selected: null, currentLocation: 'KR', available: available),
        'JP',
      );
    });

    test('직접 고른 국가가 목록에 없으면 무시한다', () {
      expect(
        effectiveCountryIso2(selected: 'KR', currentLocation: 'JP', available: available),
        'JP',
      );
    });

    test('직접 고른 국가가 목록에 있으면 그것을 쓴다', () {
      expect(
        effectiveCountryIso2(selected: 'VN', currentLocation: 'JP', available: available),
        'VN',
      );
    });

    test('목록이 비어 있으면 null이다', () {
      expect(
        effectiveCountryIso2(selected: 'JP', currentLocation: 'JP', available: const []),
        isNull,
      );
    });
  });

  group('국가 자동 판정', () {
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('현재 위치가 한국이면 한국이 기본이다', () {
      expect(
        effectiveCountryIso2(selected: null, currentLocation: 'KR', available: const ['KR', 'JP', 'VN']),
        'KR',
      );
    });

    test('위치 국가가 바뀌면(해외 매핑 시작·종료) 직접 고른 국가를 풀고 자동 판정을 따른다', () async {
      final locationIso = StateProvider<String?>((ref) => 'KR');
      final container = ProviderContainer(overrides: [
        liveRouteProvider.overrideWith((ref) => const Stream.empty()),
        currentLocationCountryProvider.overrideWith((ref) async => ref.watch(locationIso)),
      ]);
      addTearDown(container.dispose);
      container.listen(nearbyAnchorUpdaterProvider, (_, _) {});
      container.listen(currentLocationCountryProvider, (_, _) {});
      await settle();

      container.read(selectedCountryProvider.notifier).state = 'VN';
      await settle();
      // 위치 국가가 그대로면 직접 고른 값을 유지한다.
      expect(container.read(selectedCountryProvider), 'VN');

      container.read(locationIso.notifier).state = 'JP'; // 해외 매핑 시작
      await settle();
      expect(container.read(selectedCountryProvider), isNull);

      container.read(selectedCountryProvider.notifier).state = 'TH';
      container.read(locationIso.notifier).state = 'KR'; // 해외 매핑 종료
      await settle();
      expect(container.read(selectedCountryProvider), isNull);
    });
  });

  group('주변 정보 기준 위치', () {
    const seoul = LatLng(37.5572, 126.9246);
    const tokyoStation = LatLng(35.6812, 139.7671);
    // 가짜 위치 스트림이 값을 내고 파생 provider들이 반영될 때까지 몇 번 양보한다.
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    ProviderContainer makeContainer({LatLng? lastGps}) {
      final container = ProviderContainer(overrides: [
        liveRouteProvider.overrideWith(
          (ref) => lastGps == null ? const Stream.empty() : Stream.value([lastGps]),
        ),
      ]);
      addTearDown(container.dispose);
      // 앱에서는 탭 화면이 구독을 유지한다 — 테스트에서도 같은 방식으로 살려 둔다.
      container.listen(nearbyAnchorUpdaterProvider, (_, _) {});
      container.listen(liveRouteProvider, (_, _) {});
      return container;
    }

    test('마지막 실제 GPS를 기준 위치로 쓴다', () async {
      final container = makeContainer(lastGps: seoul);
      await settle();

      expect(container.read(nearbyAnchorProvider), seoul);
    });

    test('해외 매핑 중이면 해외 현재 위치를 기준으로 삼는다', () async {
      final container = makeContainer(lastGps: seoul);
      await settle();

      container.read(overseasPositionProvider.notifier).state = tokyoStation;
      await settle();

      expect(container.read(nearbyAnchorProvider), tokyoStation);
    });

    test('기준 거리보다 적게 움직이면 갱신하지 않고, 넘으면 갱신한다', () async {
      final container = makeContainer();
      container.read(overseasPositionProvider.notifier).state = tokyoStation;
      await settle();

      // 위도 0.0003° ≈ 33m — 기준(300m) 미만이라 그대로다.
      container.read(overseasPositionProvider.notifier).state = const LatLng(35.6815, 139.7671);
      await settle();
      expect(container.read(nearbyAnchorProvider), tokyoStation);

      // 위도 0.005° ≈ 556m — 기준을 넘어 갱신된다.
      const farther = LatLng(35.6862, 139.7671);
      container.read(overseasPositionProvider.notifier).state = farther;
      await settle();
      expect(container.read(nearbyAnchorProvider), farther);
    });

    test('해외 매핑이 끝나면 마지막 실제 GPS로 돌아온다', () async {
      final container = makeContainer(lastGps: seoul);
      container.read(overseasPositionProvider.notifier).state = tokyoStation;
      await settle();
      expect(container.read(nearbyAnchorProvider), tokyoStation);

      container.read(overseasPositionProvider.notifier).state = null;
      await settle();

      expect(container.read(nearbyAnchorProvider), seoul);
    });
  });

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
