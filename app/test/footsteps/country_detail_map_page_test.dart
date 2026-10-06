import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/db/app_database.dart';
import 'package:app/core/network/api_client.dart';
import 'package:app/features/footsteps/data/country_resolver.dart';
import 'package:app/features/footsteps/map/base_google_map.dart';
import 'package:app/features/footsteps/map/country_detail_map_page.dart';
import 'package:app/features/footsteps/providers/footsteps_providers.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformViewCreatedCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

/// nearby_page_test.dart와 같은 이유 — GoogleMap이 실제 플랫폼 뷰를 요구해
/// 위젯 테스트가 멈추므로 플랫폼 뷰 생성을 건너뛰는 가짜 구현으로 교체한다.
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

/// 서버 스냅 프록시 대역 — 받은 좌표를 위도 +1.0 만큼 옮겨 돌려준다.
/// 응답이 원본과 구분되므로 "어느 날짜의 좌표를 스냅한 결과가 그려졌는지"를
/// 위도만 보고 판별할 수 있다.
class _ShiftingSnapAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final sent = (options.data as List<dynamic>).cast<Map<String, dynamic>>();
    final json = jsonEncode([
      for (final p in sent) {'lat': (p['lat'] as num) + 1.0, 'lng': p['lng']},
    ]);
    return ResponseBody.fromString(json, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// GeocodingCountryResolver는 geocoding 플러그인(플랫폼 채널)을 물어서 테스트에서
/// 생성조차 되지 않는다. 이 화면은 이미 저장된 기록만 읽으므로 판정은 쓰이지 않는다.
class _FixedCountryResolver implements CountryResolver {
  @override
  Future<String> resolveIso2(double lat, double lng) async => 'JP';
}

void main() {
  setUpAll(() {
    GoogleMapsFlutterPlatform.instance = _FakeGoogleMapsFlutterPlatform();
  });

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// DB 조회 → 재빌드 → 스냅 요청 → 재빌드가 차례로 일어나야 폴리라인이 확정된다.
  ///
  /// runAsync는 실제 I/O(sqlite 조회)를 돌리기 위한 것이고, pump에 기간을 주는 것은
  /// dio가 요청 일부를 Timer(이벤트 루프)로 올리기 때문이다 — 기간 없는 pump는
  /// 마이크로태스크만 비워서 요청이 어댑터까지 가지 않는다.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpPage(WidgetTester tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _ShiftingSnapAdapter();
    // dio 기본 transformer는 JSON 인코딩/디코딩을 compute(별도 isolate)로 돌린다.
    // 위젯 테스트의 가짜 시계 아래에서는 그 isolate가 끝나지 않아 요청이 멈추므로
    // 동기 transformer로 바꾼다.
    dio.transformer = SyncTransformer();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          countryResolverProvider.overrideWithValue(_FixedCountryResolver()),
          apiClientProvider.overrideWithValue(dio),
          // 실제 GPS 스트림(Geolocator)은 테스트에서 쓸 수 없다. 이 화면의 과거
          // 기록 렌더링만 보려는 것이므로 빈 스트림으로 둔다.
          liveRouteProvider.overrideWith((ref) => const Stream<List<LatLng>>.empty()),
        ],
        child: MaterialApp(
          home: CountryDetailMapPage(isoAlpha2: 'JP', onBack: () {}),
        ),
      ),
    );
    await settle(tester);
  }

  Polyline? walkingRoute(WidgetTester tester) {
    final map = tester.widget<BaseGoogleMap>(find.byType(BaseGoogleMap));
    return map.polylines
        .where((p) => p.polylineId == const PolylineId('day_walking_route'))
        .firstOrNull;
  }

  // 실시간 추적은 RoutePoint만 쌓고 체크인은 만들지 않는다(국경을 넘을 때만
  // 체크인이 생긴다). 체크인이 없으면 화면 전체를 "기록 없음"으로 덮어버려서
  // 같은 나라 안에서 걸은 경로가 지도에 전혀 나오지 않았다.
  testWidgets('체크인이 없고 경로 좌표만 있어도 그날 경로가 지도에 그려진다', (tester) async {
    final at = DateTime(2026, 10, 6, 12);
    await db.insertRoutePoint(lat: 35.60, lng: 139.70, countryIso: 'JP', recordedAt: at);
    await db.insertRoutePoint(
      lat: 35.61,
      lng: 139.71,
      countryIso: 'JP',
      recordedAt: at.add(const Duration(minutes: 1)),
    );

    await pumpPage(tester);

    expect(find.text('이 나라의 체크인 기록이 없습니다'), findsNothing);
    expect(find.text('10/6'), findsOneWidget);
    expect(walkingRoute(tester), isNotNull);
  });

  // 스냅 캐시 키가 "좌표 개수"뿐이라, 좌표 개수가 같은 다른 날짜로 바꾸면
  // 다시 스냅하지 않고 전날 선을 그대로 그렸다.
  testWidgets('좌표 개수가 같은 다른 날짜를 골라도 그 날짜의 경로로 다시 그려진다', (tester) async {
    final day1 = DateTime(2026, 10, 4, 12);
    final day2 = DateTime(2026, 10, 6, 12);
    for (final (day, lat) in [(day1, 10.0), (day2, 30.0)]) {
      await db.insertRoutePoint(lat: lat, lng: 100, countryIso: 'JP', recordedAt: day);
      await db.insertRoutePoint(
        lat: lat + 0.01,
        lng: 100.01,
        countryIso: 'JP',
        recordedAt: day.add(const Duration(minutes: 1)),
      );
    }

    await pumpPage(tester);

    // 처음에는 가장 최근 날짜(10/6)가 선택된다 — 스냅 결과라 위도 +1.0.
    expect(walkingRoute(tester)!.points.first.latitude, closeTo(31.0, 0.001));

    await tester.tap(find.text('10/4'));
    await settle(tester);

    expect(walkingRoute(tester)!.points.first.latitude, closeTo(11.0, 0.001));
  });

  // 같은 캐시 문제의 다른 얼굴 — 좌표가 1개뿐인 날짜는 스냅을 건너뛰면서
  // 이전 날짜의 스냅 결과를 지우지 않아 전날 선이 그대로 남았다.
  testWidgets('경로 좌표가 1개뿐인 날짜로 바꾸면 앞서 본 날짜의 선이 남지 않는다', (tester) async {
    await db.insertRoutePoint(
      lat: 10.0,
      lng: 100,
      countryIso: 'JP',
      recordedAt: DateTime(2026, 10, 4, 12),
    );
    await db.insertRoutePoint(
      lat: 10.01,
      lng: 100.01,
      countryIso: 'JP',
      recordedAt: DateTime(2026, 10, 4, 12, 1),
    );
    await db.insertRoutePoint(
      lat: 30.0,
      lng: 100,
      countryIso: 'JP',
      recordedAt: DateTime(2026, 10, 6, 12),
    );

    await pumpPage(tester);

    // 좌표가 2개인 10/4를 먼저 봐서 스냅 결과를 캐시에 올린다.
    await tester.tap(find.text('10/4'));
    await settle(tester);
    expect(walkingRoute(tester)!.points.first.latitude, closeTo(11.0, 0.001));

    // 10/6은 좌표가 1개뿐이라 선을 그릴 수 없다 — 10/4 선이 남아 있으면 안 된다.
    await tester.tap(find.text('10/6'));
    await settle(tester);

    expect(walkingRoute(tester), isNull);
  });
}
