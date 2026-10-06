import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/visa/data/trip_api.dart';
import 'package:app/features/visa/models/trip.dart';
import 'package:app/features/visa/visa_result_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_trip_api.dart';

/// 결과 화면만 띄운다. 화면이 `context.pop()`과 체크리스트 push를 쓰므로
/// GoRouter 안에 넣어야 한다.
Future<FakeTripApi> pumpResultPage(
  WidgetTester tester, {
  Trip? trip,
  bool withActiveTrip = true,
}) async {
  SharedPreferences.setMockInitialValues(
    withActiveTrip ? {'active_trip_id': trip?.id ?? sampleTrip().id} : {},
  );
  final prefs = await SharedPreferences.getInstance();
  final api = FakeTripApi(tripToReturn: trip);

  final router = GoRouter(
    initialLocation: '/visa/result',
    routes: [
      GoRoute(
        path: '/visa/result',
        builder: (_, _) => const Scaffold(body: VisaResultPage()),
      ),
      GoRoute(path: '/checklist', builder: (_, _) => const Scaffold()),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        tripApiProvider.overrideWithValue(api),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

TripTask task({
  required int id,
  required String title,
  required DateTime dueDate,
  bool done = false,
}) {
  return TripTask(id: id, title: title, dueDate: dueDate, done: done);
}

void main() {
  testWidgets('저장한 여행이 없으면 안내를 보여준다', (tester) async {
    await pumpResultPage(tester, withActiveTrip: false);

    expect(find.textContaining('여행 계획이 없습니다'), findsOneWidget);
  });

  testWidgets('국가 이름과 판정 결과를 서버 데이터로 보여준다', (tester) async {
    await pumpResultPage(tester, trip: sampleTrip(nameKo: '일본', iso2: 'JP'));

    expect(find.text('일본 판정 결과'), findsOneWidget);
    expect(find.text('무비자 45일'), findsOneWidget);
    expect(find.text('체류 20일 → 가능'), findsOneWidget);
    expect(find.text('여권 요건 충족'), findsOneWidget);
    expect(find.text('잔여 유효기간 6개월 요건 충족'), findsOneWidget);
  });

  // 하드코딩 시절에는 어느 나라를 골라도 "무비자 45일"이 떴다.
  testWidgets('판정이 불가한 국가는 영사관 확인 필요로 보여준다', (tester) async {
    final trip = sampleTrip(
      nameKo: '수리남',
      visaResult: const VisaResult(
        verdict: VisaVerdict.unverified,
        stayDays: 30,
        visaFreeDays: null,
        passportOk: true,
      ),
    );

    await pumpResultPage(tester, trip: trip);

    expect(find.text('수리남 판정 결과'), findsOneWidget);
    expect(find.text('영사관 확인 필요'), findsOneWidget);
    expect(find.text('무비자 45일'), findsNothing);
  });

  testWidgets('역산 일정 항목을 마감일 순서대로 보여준다', (tester) async {
    final trip = sampleTrip(tasks: [
      task(id: 1, title: '여권 재발급 신청', dueDate: DateTime(2026, 9, 21)),
      task(id: 2, title: '최종 서류 점검', dueDate: DateTime(2026, 12, 13)),
    ]);

    await pumpResultPage(tester, trip: trip);

    expect(find.text('여권 재발급 신청'), findsOneWidget);
    expect(find.text('D-90 · 09/21'), findsOneWidget);
    expect(find.text('최종 서류 점검'), findsOneWidget);
    expect(find.text('D-7 · 12/13'), findsOneWidget);
  });

  testWidgets('일정 항목을 누르면 완료로 표시하고 서버에 알린다', (tester) async {
    final trip = sampleTrip(tasks: [
      task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20)),
    ]);

    final api = await pumpResultPage(tester, trip: trip);

    await tester.tap(find.text('여행자보험 가입'));
    await tester.pumpAndSettle();

    expect(api.markTaskDoneCalls, [
      (tripId: trip.id, taskId: 3),
    ]);
    expect(find.text('완료'), findsOneWidget);
  });

  testWidgets('판정 기준이 바뀌었으면 다시 판정할 수 있게 한다', (tester) async {
    final trip = sampleTrip(judgementStale: true);

    final api = await pumpResultPage(tester, trip: trip);

    expect(find.textContaining('판정 기준'), findsOneWidget);

    await tester.tap(find.text('다시 판정'));
    await tester.pumpAndSettle();

    expect(api.refreshTripCalls, [trip.id]);
  });
  // 테스트 기본 화면(800x600)은 실기기보다 넓어서 2단 배지가 넘치는 걸 못 잡는다.
  // 가장 문구가 긴 조합(여권 재발급 + 초과)을 폰 폭에서 그려본다 — 위젯 테스트는
  // RenderFlex 오버플로가 나면 실패하므로 이 테스트 자체가 검사가 된다.
  testWidgets('폰 폭(360)에서 가장 긴 문구 조합도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final trip = sampleTrip(
      nameKo: '투르크메니스탄',
      visaResult: const VisaResult(
        verdict: VisaVerdict.visaFreeExceeded,
        stayDays: 60,
        visaFreeDays: 45,
        passportOk: false,
        passportValidityMonths: 6,
        passportShortfallDays: 85,
      ),
      tasks: [
        task(id: 1, title: '여권 재발급 신청 (영사민원실 방문)', dueDate: DateTime(2026, 9, 21)),
      ],
      judgementStale: true,
    );

    await pumpResultPage(tester, trip: trip);

    expect(find.text('무비자 45일 초과'), findsOneWidget);
    expect(find.text('6개월 요건까지 85일 부족'), findsOneWidget);
    expect(find.text('지금 바로'), findsOneWidget);
  });
}
