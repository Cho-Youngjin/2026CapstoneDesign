import 'dart:io';

import 'package:app/app.dart';
import 'package:app/features/footsteps/providers/footsteps_providers.dart';
import 'package:app/features/footsteps/recording/recording_providers.dart';
import 'package:app/features/footsteps/recording/session_library.dart';
import 'package:app/features/footsteps/trip/trip_recording_providers.dart';
import 'package:app/features/visa/data/trip_list_providers.dart';
import 'package:app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformViewCreatedCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'footsteps/lab/fake_recording_controller.dart';
import 'footsteps/trip/trip_fakes.dart';
import 'visa/fake_trip_api.dart' show sampleSummary;

/// GoogleMap은 실제 플랫폼 뷰를 만들려고 시도하는데, 위젯 테스트 환경에는 그걸 받아줄
/// 네이티브 플랫폼이 없어 `pumpAndSettle`이 영원히 끝나지 않는다(Plan C Task 8이
/// FootstepsPage에 실제 지도를 붙이면서 생긴 문제). 플랫폼 뷰 생성을 건너뛰는 가짜
/// 구현으로 교체해 테스트가 지도를 렌더링하지 않고도 통과하게 한다.
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

Future<FakeTripRecordingCoordinator> pumpApp(
  WidgetTester tester, {
  required bool isLoggedIn,
  TripListState trips = const TripListState(trips: []),
}) async {
  final coordinator = FakeTripRecordingCoordinator();
  await tester.pumpWidget(
    ProviderScope(
      // 첫 탭(여행 목록)이 서버를 부르지 않게 목록을 고정한다. 여행 기록은 서비스를 켜지 않게 대역으로 바꾼다.
      overrides: [
        tripListProvider.overrideWith((ref) async => trips),
        tripRecordingCoordinatorProvider.overrideWithValue(coordinator),
      ],
      child: TravelFootstepsApp(router: createRouter(isLoggedIn: isLoggedIn)),
    ),
  );
  await tester.pumpAndSettle();
  return coordinator;
}

void main() {
  setUpAll(() {
    GoogleMapsFlutterPlatform.instance = _FakeGoogleMapsFlutterPlatform();
  });

  group('AppRoutes', () {
    test('6개 탭 경로가 순서대로 정의되어 있다', () {
      expect(AppRoutes.tabs, [
        AppRoutes.visa,
        AppRoutes.checklist,
        AppRoutes.footsteps,
        AppRoutes.group,
        AppRoutes.translate,
        AppRoutes.nearby,
      ]);
    });

    test('탭 라벨과 아이콘 개수가 탭 개수와 같다', () {
      expect(AppRoutes.tabLabels, hasLength(AppRoutes.tabs.length));
      expect(AppRoutes.tabIcons, hasLength(AppRoutes.tabs.length));
    });
  });

  group('앱 생명주기', () {
    testWidgets('발걸음 탭이 아닌 탭에서 백그라운드로 가도 실시간 GPS를 끄고, 돌아오면 다시 켠다', (tester) async {
      await pumpApp(tester, isLoggedIn: true); // 첫 탭(여행 목록) — 발걸음 탭은 떠 있지 않다
      final container = ProviderScope.containerOf(tester.element(find.byType(TravelFootstepsApp)));
      expect(container.read(realtimeTrackingEnabledProvider), isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(container.read(realtimeTrackingEnabledProvider), isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(container.read(realtimeTrackingEnabledProvider), isTrue);
    });

    // 설계 9-2의 1번: 여행 기록은 앱이 포그라운드로 올 때만 켠다(Android 14 제한).
    testWidgets('앱을 열면 여행 기록을 맞추고, 포그라운드로 돌아올 때마다 다시 맞춘다', (tester) async {
      final coordinator = await pumpApp(tester, isLoggedIn: true);
      // 시작할 때는 위치 권한 요청(플랫폼 채널)이 끝난 뒤에 맞춘다 — 그 응답은 실제 이벤트 루프에서 온다.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(coordinator.syncs, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(coordinator.syncs, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(coordinator.syncs, 2);
    });

    testWidgets('서버에서 받은 여행 목록으로 여행 기록 일정을 바꾼다', (tester) async {
      final coordinator =
          await pumpApp(tester, isLoggedIn: true, trips: TripListState(trips: [sampleSummary(id: 3)]));

      expect(coordinator.updates, [
        [3],
      ]);
    });

    testWidgets('오프라인 캐시 목록으로는 여행 기록 일정을 바꾸지 않는다', (tester) async {
      final coordinator = await pumpApp(tester,
          isLoggedIn: true, trips: TripListState(trips: [sampleSummary(id: 3)], offline: true));

      expect(coordinator.updates, isEmpty);
    });
  });

  group('createRouter', () {
    testWidgets('로그인하지 않으면 로그인 화면이 보인다', (tester) async {
      await pumpApp(tester, isLoggedIn: false);

      expect(find.text('Google로 계속하기'), findsOneWidget);
    });

    testWidgets('로그인하지 않아도 회원가입 화면에는 들어갈 수 있다', (tester) async {
      await pumpApp(tester, isLoggedIn: false);

      await tester.ensureVisible(find.byKey(const Key('signUpLink')));
      await tester.tap(find.byKey(const Key('signUpLink')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('signUpButton')), findsOneWidget);
    });

    testWidgets('로그인했으면 첫 탭(여행)이 보인다', (tester) async {
      await pumpApp(tester, isLoggedIn: true);

      expect(find.text('Google로 계속하기'), findsNothing);
      expect(find.byKey(const Key('wireframeTabBar')), findsOneWidget);
      // 탭바 라벨에 '여행'이 있다 (화면 본문은 각 기능 브랜치에서 실 콘텐츠로 교체된다).
      expect(find.text('여행'), findsWidgets);
    });

    testWidgets('하단 탭바는 시스템 내비게이션 바 높이만큼 올라가 가려지지 않는다', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.reset);

      await pumpApp(tester, isLoggedIn: true);

      final bar = tester.getRect(find.byKey(const Key('wireframeTabBar')));
      expect(bar.height, 62 + 48);
      final label = tester.getRect(find.text('준비물'));
      expect(label.bottom, lessThanOrEqualTo(bar.bottom - 48));
    });

    testWidgets('탭을 누르면 해당 화면으로 이동한다', (tester) async {
      await pumpApp(tester, isLoggedIn: true);

      // FootstepsPage(발걸음)가 GeoJSON 에셋을 실제로 읽는다 — 이 real I/O는
      // testWidgets의 fake-async 존 안에서 절대 끝나지 않으므로 runAsync로 감싸
      // 진짜 이벤트 루프에서 돌게 한다. pumpAndSettle은 쓰지 않는다 — 지도 로딩
      // 스피너가 반복 애니메이션이라 "더 이상 프레임이 없음"에 절대 도달하지 않는다.
      await tester.tap(find.text('발걸음').last);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      await tester.pump();

      // 탭바 라벨은 남아있다(화면 본문은 이제 지도라 별도 '발걸음' 텍스트는 없다).
      expect(find.text('발걸음'), findsWidgets);
      expect(find.text('준비물'), findsOneWidget); // 탭 라벨만 남는다
    });

    testWidgets('실험 화면 경로(/footsteps/lab)로 가면 실험 화면이 보인다', (tester) async {
      final router = createRouter(isLoggedIn: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tripListProvider.overrideWith((ref) async => const TripListState(trips: [])),
            tripRecordingCoordinatorProvider.overrideWithValue(FakeTripRecordingCoordinator()),
            recordingControllerProvider.overrideWithValue(FakeRecordingController()),
            sessionLibraryProvider.overrideWithValue(_EmptyLibrary()),
          ],
          child: TravelFootstepsApp(router: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.footstepsLab);
      await tester.pumpAndSettle();

      expect(find.text('발걸음 실험'), findsOneWidget);
      expect(find.byKey(const Key('lab-start-stop')), findsOneWidget);
    });
  });
}

class _EmptyLibrary implements SessionLibrary {
  @override
  Future<List<SessionSummary>> list() async => const [];

  @override
  Future<File> zip(SessionSummary session, Directory outDir) => throw UnimplementedError();
}
