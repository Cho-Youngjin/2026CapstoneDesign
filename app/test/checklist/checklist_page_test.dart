import 'package:app/core/network/country_detail_api.dart';
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/checklist/checklist_page.dart';
import 'package:app/features/visa/data/trip_api.dart';
import 'package:app/features/visa/data/trip_list_providers.dart';
import 'package:app/features/visa/models/trip_checklist_item.dart';
import 'package:app/features/visa/models/trip_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../visa/fake_trip_api.dart';

const _defaultItems = [
  TripChecklistItem(id: 10, category: 'POWER', title: '멀티어댑터', priority: 10, checked: false),
  TripChecklistItem(id: 20, category: 'MONEY', title: '환전', priority: 80, checked: false),
];

final _today = DateUtils.dateOnly(DateTime.now());
final _upcomingVn = sampleSummary(
    id: 1, depart: _today.add(const Duration(days: 30)), ret: _today.add(const Duration(days: 35)));
final _pastJp = sampleSummary(
    id: 2,
    iso2: 'JP',
    nameKo: '일본',
    depart: _today.subtract(const Duration(days: 60)),
    ret: _today.subtract(const Duration(days: 55)));

Future<({FakeTripApi api, SharedPreferences prefs})> _pumpChecklist(
  WidgetTester tester, {
  List<TripSummary>? trips,
  bool offline = false,
  Map<String, Object> stored = const {},
  List<TripChecklistItem> items = _defaultItems,
  int? getChecklistStatusCode,
  int? checkItemStatusCode,
  int? powerBankWhLimit = 100,
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final api = FakeTripApi(
    checklist: items,
    getChecklistStatusCode: getChecklistStatusCode,
    checkItemStatusCode: checkItemStatusCode,
  );
  final router = GoRouter(
    initialLocation: '/checklist',
    routes: [
      GoRoute(path: '/checklist', builder: (_, _) => const Scaffold(body: ChecklistPage())),
      GoRoute(
        path: '/checklist/wallet',
        builder: (_, state) => Scaffold(body: Text('wallet ${state.uri.queryParameters['trip']} ${state.uri.queryParameters['iso']}')),
      ),
      GoRoute(
        path: '/checklist/rate-alert',
        builder: (_, state) => Scaffold(body: Text('rate-alert ${state.uri.queryParameters['iso']}')),
      ),
      GoRoute(path: '/visa/new', builder: (_, _) => const Scaffold(body: Text('새 여행 폼'))),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      tripApiProvider.overrideWithValue(api),
      tripListProvider.overrideWith(
          (ref) async => TripListState(trips: trips ?? [_upcomingVn, _pastJp], offline: offline)),
      countryDetailProvider.overrideWith((ref, iso) async => CountryDetail(
            isoAlpha2: iso,
            nameKo: iso == 'JP' ? '일본' : '베트남',
            plugTypes: 'A, C, G',
            voltageV: 220,
            currencyCode: iso == 'JP' ? 'JPY' : 'VND',
            cardAcceptance: 'LOW',
            powerBankWhLimit: powerBankWhLimit,
          )),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return (api: api, prefs: prefs);
}

void main() {
  testWidgets('여행이 없으면 안내와 만들기 버튼을 보여주고, 누르면 새 여행 폼으로 간다', (tester) async {
    await _pumpChecklist(tester, trips: const []);

    expect(find.text('여행계획을 먼저 만들어 주세요.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('createTripButton')));
    await tester.pumpAndSettle();

    expect(find.text('새 여행 폼'), findsOneWidget);
  });

  testWidgets('선택한 여행이 없으면 가장 가까운 다가오는 여행의 체크리스트를 보여준다', (tester) async {
    final r = await _pumpChecklist(tester);

    expect(find.text('준비물 · 베트남'), findsOneWidget);
    expect(find.text(_upcomingVn.dateRangeLabel), findsOneWidget);
    expect(find.text('멀티어댑터'), findsOneWidget);
    expect(r.api.getChecklistCalls, [1]);
  });

  testWidgets('저장된 선택 여행이 있으면 그 여행을 보여준다', (tester) async {
    final r = await _pumpChecklist(tester, stored: {'selected_trip_id': 2});

    expect(find.text('준비물 · 일본'), findsOneWidget);
    expect(r.api.getChecklistCalls, [2]);
  });

  testWidgets('여행 바꾸기 시트에서 고르면 그 여행으로 바뀌고 선택이 저장된다', (tester) async {
    final r = await _pumpChecklist(tester);

    await tester.tap(find.byKey(const Key('changeTripButton')));
    await tester.pumpAndSettle();
    expect(find.text('다가오는 여행'), findsOneWidget);
    expect(find.text('지난 여행'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tripOption_2')));
    await tester.pumpAndSettle();

    expect(find.text('준비물 · 일본'), findsOneWidget);
    expect(r.prefs.getInt('selected_trip_id'), 2);
    expect(r.api.getChecklistCalls, [1, 2]);
  });

  testWidgets('서버 체크리스트의 체크 상태를 보여주고, 누르면 서버에 저장한다', (tester) async {
    final r = await _pumpChecklist(tester, items: const [
      TripChecklistItem(id: 10, category: 'POWER', title: '멀티어댑터', priority: 10, checked: true),
      TripChecklistItem(id: 20, category: 'MONEY', title: '환전', priority: 80, checked: false),
    ]);

    expect(find.text('1 / 3'), findsOneWidget);

    await tester.tap(find.text('환전').last);
    await tester.pumpAndSettle();

    expect(find.text('2 / 3'), findsOneWidget);
    expect(r.api.checkItemCalls, [(tripId: 1, itemId: 20, checked: true)]);
  });

  testWidgets('체크 저장이 실패하면 되돌리고 안내한다', (tester) async {
    await _pumpChecklist(tester, checkItemStatusCode: 500);

    await tester.tap(find.text('멀티어댑터'));
    await tester.pumpAndSettle();

    expect(find.text('0 / 3'), findsOneWidget);
    expect(find.text('저장하지 못했습니다. 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('보조배터리 행은 서버가 아니라 기기에 여행별로 체크를 저장한다', (tester) async {
    final r = await _pumpChecklist(tester);

    expect(find.text('보조배터리 기내 반입 (100Wh 이하)'), findsOneWidget);
    expect(find.text('0 / 3'), findsOneWidget);

    await tester.tap(find.text('보조배터리 기내 반입 (100Wh 이하)'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 3'), findsOneWidget);
    expect(r.prefs.getBool('checklist_powerbank_1'), isTrue);
    expect(r.api.checkItemCalls, isEmpty);
  });

  testWidgets('지갑 카드는 선택된 여행 나라의 지갑으로 간다', (tester) async {
    await _pumpChecklist(tester);

    expect(find.text('VND ›'), findsOneWidget);
    await tester.tap(find.byKey(const Key('walletCard')));
    await tester.pumpAndSettle();

    expect(find.text('wallet 1 VN'), findsOneWidget);
  });

  testWidgets('환전 섹션 끝의 환율 알림 행은 선택된 여행 나라의 환율 알림으로 간다', (tester) async {
    await _pumpChecklist(tester);

    expect(find.text('0 / 3'), findsOneWidget); // 체크 항목 수에는 들어가지 않는다
    await tester.ensureVisible(find.byKey(const Key('rateAlertLink')));
    await tester.tap(find.byKey(const Key('rateAlertLink')));
    await tester.pumpAndSettle();

    expect(find.text('rate-alert VN'), findsOneWidget);
  });

  testWidgets('준비물이 하나도 없어도 환율 알림 행이 있다', (tester) async {
    await _pumpChecklist(tester, items: const [], powerBankWhLimit: null);

    expect(find.text('이 나라에 등록된 준비물이 아직 없습니다.'), findsOneWidget);
    expect(find.byKey(const Key('rateAlertLink')), findsOneWidget);
  });

  testWidgets('환전 섹션이 없는 나라는 끝에 환전 섹션을 만들어 링크를 둔다', (tester) async {
    await _pumpChecklist(tester, items: const [
      TripChecklistItem(id: 10, category: 'POWER', title: '멀티어댑터', priority: 10, checked: false),
    ]);

    expect(find.text('환전'), findsOneWidget); // 섹션 라벨
    expect(find.byKey(const Key('rateAlertLink')), findsOneWidget);
  });

  testWidgets('체크리스트를 불러오지 못하면 다시 시도할 수 있다', (tester) async {
    await _pumpChecklist(tester, getChecklistStatusCode: 503);

    expect(find.text('준비물 목록을 불러오지 못했습니다.'), findsOneWidget);
    expect(find.byKey(const Key('checklistRetry')), findsOneWidget);
  });

  testWidgets('캐시된 목록을 보여주는 중이면 오프라인 안내를 띄운다', (tester) async {
    await _pumpChecklist(tester, offline: true);

    expect(find.byKey(const Key('offlineBanner')), findsOneWidget);
  });
}
