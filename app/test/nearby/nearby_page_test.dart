import 'package:app/core/network/country_api.dart';
import 'package:app/features/nearby/api/embassy_api.dart';
import 'package:app/features/nearby/api/places_api.dart';
import 'package:app/features/nearby/api/travel_alert_api.dart';
import 'package:app/features/nearby/models/embassy.dart';
import 'package:app/features/nearby/models/place.dart';
import 'package:app/features/nearby/models/travel_alert.dart';
import 'package:app/features/nearby/nearby_page.dart';
import 'package:app/features/nearby/providers/nearby_selection_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformViewCreatedCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

/// router_test.dart와 같은 이유 — GoogleMap이 실제 플랫폼 뷰를 요구해 위젯 테스트가
/// 멈추므로 플랫폼 뷰 생성을 건너뛰는 가짜 구현으로 교체한다.
class _FakeGoogleMapsFlutterPlatform extends GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) {
    return const SizedBox.shrink();
  }

  @override
  Future<void> init(int mapId) async {}
}

void main() {
  setUpAll(() {
    GoogleMapsFlutterPlatform.instance = _FakeGoogleMapsFlutterPlatform();
  });

  final fakePosition = Position(
    latitude: 21.02,
    longitude: 105.83,
    timestamp: DateTime(2026, 9, 7),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  const country =
      Country(isoAlpha2: 'VN', nameKo: '베트남', nameEn: 'Vietnam', continent: '아시아', tier: 'A');

  testWidgets('경보 배지와 공관 카드, 필터 탭이 함께 보인다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentPositionProvider.overrideWith((ref) async => fakePosition),
          countryListProvider.overrideWith((ref) async => [country]),
          nearbyPlacesProvider.overrideWith((ref) async => const [
                Place(
                  id: 'p1',
                  name: '호안끼엠 호수',
                  category: PlaceCategory.tourist,
                  address: '하노이',
                  lat: 21.03,
                  lng: 105.85,
                ),
              ]),
          travelAlertsProvider.overrideWith((ref, iso2) async => [
                TravelAlert(
                  id: 'a1',
                  level: 2,
                  region: '전역',
                  title: '황색경보',
                  issuedAt: DateTime(2026, 8, 1),
                ),
              ]),
          embassiesProvider.overrideWith((ref, iso2) async => const [
                Embassy(
                  id: 'e1',
                  type: '대사관',
                  name: '주베트남대한민국대사관',
                  lat: 21.02,
                  lng: 105.83,
                  phone: '+84-24-xxx-xxxx',
                  emergencyPhone: '+84-90-xxx-xxxx',
                  address: '하노이',
                ),
              ]),
        ],
        child: const MaterialApp(home: NearbyPage()),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump();

    // 필터 칩 라벨과 리스트 항목의 카테고리 라벨 둘 다 "관광지"라 2곳에서 보인다.
    expect(find.text('관광지'), findsWidgets);
    expect(find.text('호안끼엠 호수'), findsOneWidget);
    expect(find.text('황색경보 (여행자제)'), findsOneWidget);
    expect(find.textContaining('주베트남대한민국대사관'), findsOneWidget);
  });
}
