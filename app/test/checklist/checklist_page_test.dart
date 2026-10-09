import 'package:app/core/network/checklist_api.dart';
import 'package:app/core/network/country_detail_api.dart';
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/checklist/checklist_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpChecklist(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: '/checklist',
    routes: [
      GoRoute(path: '/checklist', builder: (_, _) => const Scaffold(body: ChecklistPage())),
      GoRoute(
        path: '/checklist/wallet',
        builder: (_, state) => Scaffold(body: Text('wallet ${state.uri.queryParameters['iso']}')),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      countryDetailProvider.overrideWith((ref, iso) async => const CountryDetail(
            isoAlpha2: 'VN',
            nameKo: '베트남',
            plugTypes: 'A, C, G',
            voltageV: 220,
            currencyCode: 'VND',
            cardAcceptance: 'LOW',
            powerBankWhLimit: 100,
          )),
      checklistProvider.overrideWith((ref, iso) async => const [
            ChecklistItem(id: 10, category: 'POWER', title: '멀티어댑터', priority: 10),
            ChecklistItem(id: 20, category: 'MONEY', title: '환전', priority: 80),
          ]),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('상단 세 번째 카드는 지갑이고, 누르면 그 나라 지갑으로 간다', (tester) async {
    await _pumpChecklist(tester);

    expect(find.text('지갑'), findsOneWidget);
    expect(find.text('VND ›'), findsOneWidget);
    expect(find.text('보조배터리'), findsNothing);

    await tester.tap(find.byKey(const Key('walletCard')));
    await tester.pumpAndSettle();

    expect(find.text('wallet VN'), findsOneWidget);
  });

  testWidgets('보조배터리는 전자기기 섹션의 체크리스트 행이 되고, 체크하면 진행률에 반영된다', (tester) async {
    await _pumpChecklist(tester);

    expect(find.text('보조배터리 기내 반입 (100Wh 이하)'), findsOneWidget);
    expect(find.text('0 / 3'), findsOneWidget);

    await tester.tap(find.text('보조배터리 기내 반입 (100Wh 이하)'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 3'), findsOneWidget);
  });
}
