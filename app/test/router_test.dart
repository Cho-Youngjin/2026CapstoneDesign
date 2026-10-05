import 'package:app/app.dart';
import 'package:app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformViewCreatedCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

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

Future<void> pumpApp(WidgetTester tester, {required bool isLoggedIn}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: TravelFootstepsApp(router: createRouter(isLoggedIn: isLoggedIn)),
    ),
  );
  await tester.pumpAndSettle();
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

  group('createRouter', () {
    testWidgets('로그인하지 않으면 로그인 화면이 보인다', (tester) async {
      await pumpApp(tester, isLoggedIn: false);

      expect(find.text('Google로 계속하기'), findsOneWidget);
    });

    testWidgets('로그인했으면 첫 탭(비자)이 보인다', (tester) async {
      await pumpApp(tester, isLoggedIn: true);

      expect(find.text('Google로 계속하기'), findsNothing);
      expect(find.byKey(const Key('wireframeTabBar')), findsOneWidget);
      // 탭바 라벨에 '비자'가 있다 (화면 본문은 각 기능 브랜치에서 실 콘텐츠로 교체된다).
      expect(find.text('비자'), findsWidgets);
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
  });
}
