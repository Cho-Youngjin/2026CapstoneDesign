import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/data/route_point.dart';
import 'package:app/features/footsteps/map/base_google_map.dart';
import 'package:app/features/footsteps/trip/route_reconstruct_api.dart';
import 'package:app/features/footsteps/trip/trip_footsteps_page.dart';
import 'package:app/features/footsteps/trip/trip_footsteps_providers.dart';
import 'package:app/features/footsteps/trip/trip_recording_permissions.dart';
import 'package:app/features/footsteps/trip/trip_recording_providers.dart';
import 'package:app/features/visa/data/trip_list_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformViewCreatedCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footstep_core/footstep_core.dart' show Stay;
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import '../../visa/fake_trip_api.dart' show sampleSummary;
import 'trip_fakes.dart';

/// GoogleMap이 실제 플랫폼 뷰를 요구해 위젯 테스트가 멈추므로 플랫폼 뷰 생성을 건너뛴다(국가 지도 테스트와 같은 대역).
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

/// 복원 API 대역. 받은 점 수를 기록하고, 정해 둔 구간을 돌려주거나 실패한다.
class _FakeReconstructApi implements RouteReconstructApi {
  List<RouteSegmentView> Function(List<RoutePoint> points)? respond;
  bool fails = false;
  final calls = <int>[];

  @override
  Future<List<RouteSegmentView>> reconstruct(List<RoutePoint> points, List<Stay> stays) async {
    calls.add(points.length);
    if (fails) throw StateError('서버 꺼짐');
    return respond?.call(points) ??
        [RouteSegmentView(kind: 'walk', coords: [for (final p in points) LatLng(p.lat + 0.001, p.lng)], fallback: false)];
  }
}

void main() {
  setUpAll(() => GoogleMapsFlutterPlatform.instance = _FakeGoogleMapsFlutterPlatform());

  late AppDatabase db;
  late _FakeReconstructApi api;
  late FakeTripRecordingPermissions permissions;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeReconstructApi();
    permissions = FakeTripRecordingPermissions();
  });

  tearDown(() => db.close());

  Future<void> addPoint(DateTime at, {double lat = 37.5, int? steps, String state = 'walking'}) =>
      db.insertTripPoint(
          tripId: 7, lat: lat, lng: 127.0, countryIso: 'KR', recordedAt: at, stepsSincePrev: steps, state: state);

  /// DB 조회(실제 I/O) → 재빌드 → 복원 → 재빌드가 차례로 일어나야 지도가 확정된다(국가 지도 테스트와 같은 방법).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpPage(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/visa/trip/7/footsteps',
      routes: [
        GoRoute(
          path: '/visa/trip/:id/footsteps',
          builder: (_, state) =>
              Scaffold(body: TripFootstepsPage(tripId: int.parse(state.pathParameters['id']!))),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tripListProvider.overrideWith((ref) async => TripListState(trips: [
              sampleSummary(
                  id: 7, iso2: 'KR', nameKo: '대한민국', depart: DateTime(2026, 11, 20), ret: DateTime(2026, 11, 22)),
            ])),
        appDatabaseProvider.overrideWithValue(db),
        routeReconstructApiProvider.overrideWithValue(api),
        tripRecordingPermissionsProvider.overrideWithValue(permissions),
        tripClockProvider.overrideWithValue(() => DateTime(2026, 11, 21, 15)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle(tester);
  }

  Set<Polyline> polylines(WidgetTester tester) => tester.widget<BaseGoogleMap>(find.byType(BaseGoogleMap)).polylines;

  Future<void> seedTwoDays() async {
    await addPoint(DateTime(2026, 11, 20, 9), steps: 10);
    await addPoint(DateTime(2026, 11, 20, 9, 5), lat: 37.501, steps: 20);
    await addPoint(DateTime(2026, 11, 21, 9), state: 'unknown');
    await addPoint(DateTime(2026, 11, 21, 9, 5), lat: 37.502, steps: 1200);
    await addPoint(DateTime(2026, 11, 21, 9, 10), lat: 37.504, steps: 2345);
  }

  testWidgets('출발일~귀국일 날짜 칩을 두고, 오늘(여행 중)의 복원 경로·걸음·이동 거리를 보여 준다', (tester) async {
    await seedTwoDays();
    api.respond = (points) => [
          RouteSegmentView(kind: 'walk', coords: [const LatLng(37.5, 127.0), const LatLng(37.502, 127.0)], fallback: false),
          RouteSegmentView(kind: 'estimated', coords: [const LatLng(37.502, 127.0), const LatLng(37.504, 127.0)], fallback: false),
        ];

    await pumpPage(tester);

    expect(find.text('대한민국 발걸음'), findsOneWidget);
    for (final label in ['11/20', '11/21', '11/22']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(api.calls, [3]);
    final lines = polylines(tester).toList()..sort((a, b) => a.polylineId.value.compareTo(b.polylineId.value));
    expect(lines.map((l) => l.patterns.isEmpty), [true, false]); // estimated는 점선
    expect(find.text('3,545'), findsOneWidget); // 걸음
    expect(find.text('445m'), findsOneWidget); // 복원 경로 길이(0.004도 ≈ 445m)
    expect(find.byKey(const Key('roadMatchFailed')), findsNothing);
  });

  testWidgets('다른 날을 고르면 그날 점으로 복원하고, 한 번 본 날은 다시 부르지 않는다(메모리 캐시)', (tester) async {
    await seedTwoDays();
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('tripDate_2026-11-20')));
    await settle(tester);
    expect(api.calls, [3, 2]);
    expect(find.text('30'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tripDate_2026-11-21')));
    await settle(tester);
    expect(api.calls, [3, 2]);
  });

  testWidgets('복원에 실패하면 점을 직선으로 잇고 "도로 맞춤을 못 했어요"라고 안내한다', (tester) async {
    await seedTwoDays();
    api.fails = true;

    await pumpPage(tester);

    final line = polylines(tester).single;
    expect(line.points, [const LatLng(37.5, 127.0), const LatLng(37.502, 127.0), const LatLng(37.504, 127.0)]);
    expect(find.byKey(const Key('roadMatchFailed')), findsOneWidget);

    // 다시 시도하면 그 날만 다시 부른다.
    api.fails = false;
    await tester.tap(find.text('다시 시도'));
    await settle(tester);
    expect(api.calls, [3, 3]);
    expect(find.byKey(const Key('roadMatchFailed')), findsNothing);
  });

  testWidgets('서버가 직선으로 대신 채운 구간(fallback)이 있어도 안내한다', (tester) async {
    await seedTwoDays();
    api.respond = (points) => [
          RouteSegmentView(kind: 'walk', coords: [for (final p in points) LatLng(p.lat, p.lng)], fallback: true),
        ];

    await pumpPage(tester);

    expect(find.byKey(const Key('roadMatchFailed')), findsOneWidget);
  });

  testWidgets('머문 곳은 도착 시각과 머문 시간으로 지도 마커와 목록에 보인다', (tester) async {
    await addPoint(DateTime(2026, 11, 21, 9, 55), lat: 37.497);
    for (var m = 0; m <= 25; m += 5) {
      await addPoint(DateTime(2026, 11, 21, 10, 0, 30).add(Duration(minutes: m)), state: 'still');
    }
    await addPoint(DateTime(2026, 11, 21, 10, 33), lat: 37.503);
    await db.insertTripStillSpan(
        tripId: 7, startAt: DateTime(2026, 11, 21, 10), endAt: DateTime(2026, 11, 21, 10, 32));

    await pumpPage(tester);

    final marker = tester.widget<BaseGoogleMap>(find.byType(BaseGoogleMap)).markers.single;
    expect(marker.infoWindow.title, '10:00 도착');
    expect(marker.infoWindow.snippet, '32분 머묾');
    expect(find.text('10:00 도착 · 32분 머묾'), findsOneWidget);
    expect(find.text('1곳'), findsOneWidget);
  });

  testWidgets('기록이 없는 날은 지도 대신 안내를 보여 준다', (tester) async {
    await seedTwoDays();
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('tripDate_2026-11-22')));
    await settle(tester);

    expect(find.text('이 날의 발걸음 기록이 없어요'), findsOneWidget);
    expect(find.byType(BaseGoogleMap), findsNothing);
  });

  testWidgets('권한이 없으면 "기록이 꺼져 있어요" 배너와 설정 이동 버튼을 띄운다', (tester) async {
    permissions.absent = {TripRecordingPermission.notification, TripRecordingPermission.backgroundLocation};
    await pumpPage(tester);

    expect(find.text('기록이 꺼져 있어요'), findsOneWidget);
    expect(find.text('권한이 없어요: 백그라운드 위치, 알림'), findsOneWidget);
    await tester.tap(find.byKey(const Key('openRecordingSettings')));
    expect(permissions.settingsOpened, 1);
  });

  testWidgets('권한이 모두 있으면 배너가 없다', (tester) async {
    await pumpPage(tester);

    expect(find.byKey(const Key('tripRecordingOffBanner')), findsNothing);
  });

  test('머문 시간·이동 거리 문구', () {
    expect(stayDurationLabel(const Duration(minutes: 32)), '32분');
    expect(stayDurationLabel(const Duration(hours: 1, minutes: 5)), '1시간 5분');
    expect(stayDurationLabel(const Duration(hours: 9)), '9시간');
    expect(distanceLabel(850.4), '850m');
    expect(distanceLabel(8249), '8.2km');
  });
}
