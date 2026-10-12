import 'package:app/core/auth/app_user.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/visa/data/trip_list_providers.dart';
import 'package:app/features/visa/models/trip_summary.dart';
import 'package:app/features/visa/trip_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../auth/fake_auth_repository.dart';
import 'fake_trip_api.dart';

final _today = DateUtils.dateOnly(DateTime.now());

Future<void> _pumpList(
  WidgetTester tester, {
  List<TripSummary> trips = const [],
  bool offline = false,
  bool fails = false,
}) async {
  final router = GoRouter(
    initialLocation: '/visa',
    routes: [
      GoRoute(path: '/visa', builder: (_, _) => const Scaffold(body: TripListPage())),
      GoRoute(path: '/visa/new', builder: (_, _) => const Scaffold(body: Text('새 여행 폼'))),
      GoRoute(
        path: '/visa/trip/:id',
        builder: (_, state) => Scaffold(body: Text('상세 ${state.pathParameters['id']}')),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(
          FakeAuthRepository()..signIn(const AppUser(uid: 'uid-abcdef', displayName: '여행자'))),
      tripListProvider.overrideWith((ref) async {
        if (fails) throw Exception('offline');
        return TripListState(trips: trips, offline: offline);
      }),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('여행이 없으면 첫 여행을 만들라고 안내하고, 누르면 새 여행 폼으로 간다', (tester) async {
    await _pumpList(tester);

    expect(find.text('첫 여행계획을 만들어 보세요'), findsOneWidget);

    await tester.tap(find.byKey(const Key('emptyCreateTripButton')));
    await tester.pumpAndSettle();

    expect(find.text('새 여행 폼'), findsOneWidget);
  });

  testWidgets('다가오는 여행과 지난 여행을 나눠 보여주고, 카드를 누르면 상세로 간다', (tester) async {
    await _pumpList(tester, trips: [
      sampleSummary(
          id: 1,
          iso2: 'JP',
          nameKo: '일본',
          depart: _today.subtract(const Duration(days: 60)),
          ret: _today.subtract(const Duration(days: 55))),
      sampleSummary(
          id: 2,
          depart: _today.add(const Duration(days: 30)),
          ret: _today.add(const Duration(days: 35))),
    ]);

    expect(find.text('다가오는 여행'), findsOneWidget);
    expect(find.text('지난 여행'), findsOneWidget);
    expect(find.text('일본'), findsOneWidget);
    expect(find.text('베트남'), findsOneWidget);
    expect(find.text('무비자'), findsNWidgets(2));
    final upcomingY = tester.getTopLeft(find.text('베트남')).dy;
    final pastY = tester.getTopLeft(find.text('일본')).dy;
    expect(upcomingY, lessThan(pastY));

    await tester.tap(find.text('베트남'));
    await tester.pumpAndSettle();

    expect(find.text('상세 2'), findsOneWidget);
  });

  testWidgets('상단 버튼으로 새 여행 폼에 간다', (tester) async {
    await _pumpList(tester, trips: [sampleSummary()]);

    await tester.tap(find.byKey(const Key('createTripButton')));
    await tester.pumpAndSettle();

    expect(find.text('새 여행 폼'), findsOneWidget);
  });

  testWidgets('캐시된 목록이면 오프라인 안내를 보여준다', (tester) async {
    await _pumpList(tester, trips: [sampleSummary()], offline: true);

    expect(find.text('오프라인 · 마지막으로 불러온 목록'), findsOneWidget);
  });

  testWidgets('목록을 불러오지 못하면 다시 시도할 수 있다', (tester) async {
    await _pumpList(tester, fails: true);

    expect(find.text('여행 목록을 불러오지 못했습니다.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('헤더의 계정 아이콘을 누르면 계정 시트가 열린다', (tester) async {
    await _pumpList(tester, trips: [sampleSummary()]);

    await tester.tap(find.byKey(const Key('accountButton')));
    await tester.pumpAndSettle();

    expect(find.text('여행자'), findsOneWidget);
    expect(find.byKey(const Key('signOutButton')), findsOneWidget);
  });
}
