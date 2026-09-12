import 'package:app/app.dart';
import 'package:app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpApp(WidgetTester tester, {required bool isLoggedIn}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: TravelFootstepsApp(router: createRouter(isLoggedIn: isLoggedIn)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
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

      await tester.tap(find.text('발걸음').last);
      await tester.pumpAndSettle();

      // 발걸음 화면은 헤더도 '발걸음'이라 탭바 라벨과 합쳐 2곳에서 보인다.
      expect(find.text('발걸음'), findsWidgets);
      expect(find.text('준비물'), findsOneWidget); // 탭 라벨만 남는다
    });
  });
}
