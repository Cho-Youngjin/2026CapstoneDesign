import 'package:app/core/db/app_database.dart';
import 'package:app/core/network/country_api.dart';
import 'package:app/features/footsteps/data/checkin.dart';
import 'package:app/features/footsteps/data/country_resolver.dart';
import 'package:app/features/footsteps/footsteps_page.dart';
import 'package:app/features/footsteps/import/timeline_import_page.dart';
import 'package:app/features/footsteps/map/world_map_page.dart';
import 'package:app/features/footsteps/providers/footsteps_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformViewCreatedCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

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

class _FixedCountryResolver implements CountryResolver {
  @override
  Future<String> resolveIso2(double lat, double lng) async => 'JP';
}

void main() {
  setUpAll(() {
    GoogleMapsFlutterPlatform.instance = _FakeGoogleMapsFlutterPlatform();
  });

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      countryResolverProvider.overrideWithValue(_FixedCountryResolver()),
      // GeoJSON 에셋과 서버 국가 목록은 이 테스트의 관심사가 아니다.
      worldCountryPolygonsProvider.overrideWith((ref) async => const []),
      countryListProvider.overrideWith((ref) async => const <Country>[]),
      liveRouteProvider.overrideWith((ref) => const Stream<List<LatLng>>.empty()),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  // Timeline 임포트는 체크인 행을 DB에 새로 넣는다. 그런데 visitedCountriesProvider는
  // FutureProvider라 한 번 계산되면 캐시되므로, 임포트 화면에서 돌아올 때 invalidate하지
  // 않으면 새로 들어온 국가가 세계지도에 바로 나타나지 않는다.
  testWidgets('Timeline 임포트 화면에서 돌아오면 방문국 목록을 다시 읽는다', (tester) async {
    expect(await container.read(visitedCountriesProvider.future), isEmpty);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FootstepsPage()),
      ),
    );
    await settle(tester);

    await tester.tap(find.byTooltip('Timeline 가져오기'));
    await settle(tester);
    expect(find.byType(TimelineImportPage), findsOneWidget);

    // 임포트가 체크인을 저장한 상황을 만든다 — 파일 선택(file_picker)은 테스트에서
    // 띄울 수 없으므로 그 결과만 DB에 직접 반영한다.
    await db.insertCheckin(
      lat: 35.6,
      lng: 139.7,
      countryIso: 'JP',
      recordedAt: DateTime(2026, 10, 6, 12),
      source: CheckinSource.import,
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pop();
    await settle(tester);

    expect(await container.read(visitedCountriesProvider.future), {'JP'});
  });
}
