import 'dart:async';
import 'dart:convert';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/rate_alert/notify/notification_permission.dart';
import 'package:app/features/visa/data/trip_api.dart';
import 'package:app/features/visa/data/trip_deletion.dart';
import 'package:app/features/visa/data/trip_list_providers.dart';
import 'package:app/features/visa/models/trip.dart';
import 'package:app/features/visa/notifications/alarm_scheduler.dart';
import 'package:app/features/visa/visa_result_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_alarm_backend.dart';
import 'fake_trip_api.dart';

class FakePermission implements NotificationPermission {
  FakePermission({this.fails = false, this.hold});

  final bool fails;

  /// 정해 두면 이 Completer가 끝날 때까지 답하지 않는다 — 권한 대화상자가 떠 있는 동안.
  final Completer<void>? hold;
  int calls = 0;

  @override
  Future<bool> request() async {
    calls++;
    if (hold != null) await hold!.future;
    if (fails) throw Exception('permission plugin failed');
    return true;
  }
}

class _FakeTripDeleter implements TripDeleter {
  _FakeTripDeleter({this.fails = false});

  final bool fails;
  final List<int> calls = [];

  @override
  Ref get ref => throw UnimplementedError();

  @override
  Future<void> delete(int tripId) async {
    calls.add(tripId);
    if (fails) throw Exception('delete failed');
  }
}

/// 여행 상세 화면을 `/visa/trip/:id`로 띄운다. 화면이 목록·준비물 탭·지갑으로 이동하므로
/// 그 자리 화면도 같이 둔다.
Future<
    ({
      FakeTripApi api,
      SharedPreferences prefs,
      _FakeTripDeleter deleter,
      FakeAlarmBackend alarms,
    })> pumpResultPage(
  WidgetTester tester, {
  Trip? trip,
  Trip? tripAfterRefresh,
  int? getTripStatusCode,
  Map<String, Object> stored = const {},
  bool deleteFails = false,
  bool watchTripList = false,
  FakeAlarmBackend? alarms,
  AlarmScheduler? scheduler,
  NotificationPermission? permission,
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final api = FakeTripApi(
    tripToReturn: trip,
    tripAfterRefresh: tripAfterRefresh,
    getTripStatusCode: getTripStatusCode,
    trips: [sampleSummary(id: 8)],
  );
  final deleter = _FakeTripDeleter(fails: deleteFails);
  final alarmBackend = alarms ?? FakeAlarmBackend();
  final id = (trip ?? sampleTrip()).id;

  final router = GoRouter(
    initialLocation: '/visa/trip/$id',
    routes: [
      GoRoute(path: '/visa', builder: (_, _) => const Scaffold(body: Text('여행 목록'))),
      GoRoute(
        path: '/visa/trip/:id',
        builder: (_, state) =>
            Scaffold(body: VisaResultPage(tripId: int.parse(state.pathParameters['id']!))),
      ),
      GoRoute(path: '/checklist', builder: (_, _) => const Scaffold(body: Text('준비물 탭'))),
      GoRoute(
        path: '/checklist/wallet',
        builder: (_, state) => Scaffold(
            body: Text('wallet ${state.uri.queryParameters['trip']} ${state.uri.queryParameters['iso']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUidProvider.overrideWithValue('uid-a'),
        tripApiProvider.overrideWithValue(api),
        tripDeleterProvider.overrideWithValue(deleter),
        alarmSchedulerProvider.overrideWithValue(
            scheduler ??
                AlarmScheduler(alarmBackend,
                    registry: MemoryAlarmRegistry('uid-a'), now: () => seoulTime(2026, 9, 7, 12))),
        notificationPermissionProvider.overrideWithValue(permission ?? FakePermission()),
      ],
      // 목록 provider를 누군가 보고 있어야 invalidate가 다시 조회로 이어진다(여행 목록 탭 역할).
      child: Consumer(builder: (context, ref, child) {
        if (watchTripList) ref.watch(tripListProvider);
        return child!;
      }, child: MaterialApp.router(routerConfig: router)),
    ),
  );
  await tester.pumpAndSettle();
  return (api: api, prefs: prefs, deleter: deleter, alarms: alarmBackend);
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
  testWidgets('없는 여행이면 안내하고 선택된 여행이었다면 선택을 지운다', (tester) async {
    final r = await pumpResultPage(tester, getTripStatusCode: 404, stored: {'selected_trip_id.uid-a': 7});

    expect(find.textContaining('여행을 찾을 수 없습니다'), findsOneWidget);
    expect(r.prefs.getInt('selected_trip_id.uid-a'), isNull);

    await tester.tap(find.text('목록으로'));
    await tester.pumpAndSettle();

    expect(find.text('여행 목록'), findsOneWidget);
  });

  testWidgets('[준비물 체크리스트]는 이 여행을 선택하고 준비물 탭으로 간다', (tester) async {
    final r = await pumpResultPage(tester);

    await tester.ensureVisible(find.byKey(const Key('openChecklistButton')));
    await tester.tap(find.byKey(const Key('openChecklistButton')));
    await tester.pumpAndSettle();

    expect(find.text('준비물 탭'), findsOneWidget);
    expect(r.prefs.getInt('selected_trip_id.uid-a'), 7);
  });

  testWidgets('404면 그 여행을 캐시된 목록에서도 뺀다', (tester) async {
    final cached = jsonEncode([
      sampleSummary(id: 7).toJson(),
      sampleSummary(id: 8).toJson(),
    ]);
    final r = await pumpResultPage(
      tester,
      getTripStatusCode: 404,
      stored: {'trips.cache.v1.uid-a': cached},
    );

    final remaining = (jsonDecode(r.prefs.getString('trips.cache.v1.uid-a')!) as List)
        .map((e) => (e as Map<String, dynamic>)['id']);
    expect(remaining, [8]);
  });

  testWidgets('404면 여행 목록을 다시 불러온다', (tester) async {
    final r = await pumpResultPage(tester, getTripStatusCode: 404, watchTripList: true);

    expect(r.api.listTripsCalls, 2);
  });

  testWidgets('[지갑]은 이 여행의 지갑으로 간다', (tester) async {
    await pumpResultPage(tester);

    await tester.ensureVisible(find.byKey(const Key('openWalletButton')));
    await tester.tap(find.byKey(const Key('openWalletButton')));
    await tester.pumpAndSettle();

    expect(find.text('wallet 7 VN'), findsOneWidget);
  });

  testWidgets('메뉴의 여행 삭제는 확인 후 지우고 목록으로 간다', (tester) async {
    final r = await pumpResultPage(tester);

    await tester.tap(find.byKey(const Key('tripMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteTripMenuItem')));
    await tester.pumpAndSettle();
    expect(find.text('여행을 삭제할까요?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirmDeleteTrip')));
    await tester.pumpAndSettle();

    expect(r.deleter.calls, [7]);
    expect(find.text('여행 목록'), findsOneWidget);
  });

  testWidgets('삭제가 실패하면 화면에 남아 안내한다', (tester) async {
    await pumpResultPage(tester, deleteFails: true);

    await tester.tap(find.byKey(const Key('tripMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteTripMenuItem')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDeleteTrip')));
    await tester.pumpAndSettle();

    expect(find.text('여행을 삭제하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    expect(find.text('여행 목록'), findsNothing);
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

    final api = (await pumpResultPage(tester, trip: trip)).api;

    await tester.tap(find.text('여행자보험 가입'));
    await tester.pumpAndSettle();

    expect(api.markTaskDoneCalls, [
      (tripId: trip.id, taskId: 3),
    ]);
    expect(find.text('완료'), findsOneWidget);
  });

  testWidgets('완료한 일정을 다시 누르면 완료를 취소하고 서버에 알린다', (tester) async {
    final trip = sampleTrip(tasks: [
      task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20), done: true),
    ]);

    final api = (await pumpResultPage(tester, trip: trip)).api;
    expect(find.text('완료'), findsOneWidget);

    await tester.tap(find.text('여행자보험 가입'));
    await tester.pumpAndSettle();

    expect(api.markTaskUndoneCalls, [(tripId: trip.id, taskId: 3)]);
    expect(api.markTaskDoneCalls, isEmpty);
    expect(find.text('완료'), findsNothing);
  });

  testWidgets('완료를 취소하지 못하면 완료로 남기고 안내한다', (tester) async {
    final trip = sampleTrip(tasks: [
      task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20), done: true),
    ]);
    final api = (await pumpResultPage(tester, trip: trip)).api;
    api.markTaskUndoneStatusCode = 500;

    await tester.tap(find.text('여행자보험 가입'));
    await tester.pumpAndSettle();

    expect(find.text('완료'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('응답을 기다리는 동안 같은 일정을 또 눌러도 요청은 한 번만 간다', (tester) async {
    final trip = sampleTrip(tasks: [
      task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20), done: true),
    ]);
    final api = (await pumpResultPage(tester, trip: trip)).api;
    api.holdMarkTaskUndone = Completer<void>();

    await tester.tap(find.text('여행자보험 가입'));
    await tester.pump();
    await tester.tap(find.text('여행자보험 가입'));
    await tester.pump();
    api.holdMarkTaskUndone!.complete();
    await tester.pumpAndSettle();

    expect(api.markTaskUndoneCalls, hasLength(1));
    expect(api.markTaskDoneCalls, isEmpty);
  });

  testWidgets('판정 기준이 바뀌었으면 다시 판정할 수 있게 한다', (tester) async {
    final trip = sampleTrip(judgementStale: true);

    final api = (await pumpResultPage(tester, trip: trip)).api;

    expect(find.textContaining('판정 기준'), findsOneWidget);

    await tester.tap(find.text('다시 판정'));
    await tester.pumpAndSettle();

    expect(api.refreshTripCalls, [trip.id]);
  });

  group('준비 일정 알람', () {
    // pumpResultPage의 알람 시계는 2026-09-07 12:00(서울)이다.
    testWidgets('여행을 열면 남은 일정마다 알람을 예약한다', (tester) async {
      final trip = sampleTrip(id: 7, tasks: [
        task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20)),
        task(id: 4, title: '여권 재발급', dueDate: DateTime(2026, 9, 1)),
      ]);

      final alarms = (await pumpResultPage(tester, trip: trip)).alarms;

      expect(alarms.scheduled.keys, [notificationIdFor(3)]);
    });

    testWidgets('울릴 일정이 있으면 알림 권한을 요청한다 (이미 있던 여행도)', (tester) async {
      final permission = FakePermission();
      await pumpResultPage(tester,
          trip: sampleTrip(tasks: [
            task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20)),
          ]),
          permission: permission);

      expect(permission.calls, 1);
    });

    testWidgets('울릴 일정이 없으면 알림 권한을 묻지 않는다', (tester) async {
      final permission = FakePermission();
      await pumpResultPage(tester,
          trip: sampleTrip(tasks: [
            task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 9, 1)),
          ]),
          permission: permission);

      expect(permission.calls, 0);
    });

    testWidgets('알림 권한 요청이 실패해도 알람은 예약해 둔다', (tester) async {
      final alarms = (await pumpResultPage(tester,
              trip: sampleTrip(id: 7, tasks: [
                task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20)),
              ]),
              permission: FakePermission(fails: true)))
          .alarms;

      expect(alarms.scheduled.keys, [notificationIdFor(3)]);
    });

    testWidgets('다른 기기에서 지운 여행(404)이면 이 기기의 알람도 지운다', (tester) async {
      final alarms = FakeAlarmBackend();
      final scheduler = AlarmScheduler(alarms, now: () => seoulTime(2026, 9, 7, 12));
      await scheduler.syncTrip(sampleTrip(id: 7, tasks: [
        task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20)),
      ]));

      await pumpResultPage(tester, getTripStatusCode: 404, alarms: alarms, scheduler: scheduler);

      expect(alarms.scheduled, isEmpty);
    });

    testWidgets('일정을 완료하면 그 알람을 취소한다', (tester) async {
      final trip = sampleTrip(id: 7, tasks: [
        task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20)),
        task(id: 5, title: '최종 서류 점검', dueDate: DateTime(2026, 12, 13)),
      ]);
      final alarms = (await pumpResultPage(tester, trip: trip)).alarms;

      await tester.tap(find.text('여행자보험 가입'));
      await tester.pumpAndSettle();

      expect(alarms.scheduled.keys, [notificationIdFor(5)]);
    });

    testWidgets('완료를 취소하면 그 일정의 알람을 다시 예약한다', (tester) async {
      final trip = sampleTrip(id: 7, tasks: [
        task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20), done: true),
        task(id: 5, title: '최종 서류 점검', dueDate: DateTime(2026, 12, 13)),
      ]);
      final alarms = (await pumpResultPage(tester, trip: trip)).alarms;
      expect(alarms.scheduled.keys, [notificationIdFor(5)]);

      await tester.tap(find.text('여행자보험 가입'));
      await tester.pumpAndSettle();

      expect(alarms.scheduled.keys,
          unorderedEquals([notificationIdFor(3), notificationIdFor(5)]));
    });

    testWidgets('완료를 취소해 울릴 일정이 생기면 그때 알림 권한을 요청한다', (tester) async {
      final permission = FakePermission();
      await pumpResultPage(tester,
          trip: sampleTrip(tasks: [
            task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20), done: true),
          ]),
          permission: permission);
      expect(permission.calls, 0, reason: '처음에는 울릴 일정이 없다');

      await tester.tap(find.text('여행자보험 가입'));
      await tester.pumpAndSettle();

      expect(permission.calls, 1);
    });

    testWidgets('완료를 취소한 일정이 이미 마감일을 지났으면 알람을 잡지 않는다', (tester) async {
      final trip = sampleTrip(id: 7, tasks: [
        task(id: 3, title: '여권 재발급', dueDate: DateTime(2026, 9, 1), done: true),
      ]);
      final alarms = (await pumpResultPage(tester, trip: trip)).alarms;

      await tester.tap(find.text('여권 재발급'));
      await tester.pumpAndSettle();

      expect(alarms.scheduled, isEmpty);
    });

    testWidgets('취소 응답이 오기 전에 화면을 나가도 그 일정의 알람은 다시 예약한다', (tester) async {
      final trip = sampleTrip(id: 7, tasks: [
        task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20), done: true),
      ]);
      final r = await pumpResultPage(tester, trip: trip);
      r.api.holdMarkTaskUndone = Completer<void>();

      await tester.tap(find.text('여행자보험 가입'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('여행 목록'), findsOneWidget);

      r.api.holdMarkTaskUndone!.complete();
      await tester.pumpAndSettle();

      expect(r.alarms.scheduled.keys, [notificationIdFor(3)]);
    });

    testWidgets('두 일정을 취소하고 응답 전에 화면을 나가도 두 알람이 모두 남는다', (tester) async {
      final trip = sampleTrip(id: 7, tasks: [
        task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20), done: true),
        task(id: 5, title: '최종 서류 점검', dueDate: DateTime(2026, 12, 13), done: true),
      ]);
      final r = await pumpResultPage(tester, trip: trip);
      r.api.holdMarkTaskUndone = Completer<void>();

      await tester.tap(find.text('여행자보험 가입'));
      await tester.pump();
      await tester.tap(find.text('최종 서류 점검'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      r.api.holdMarkTaskUndone!.complete();
      await tester.pumpAndSettle();

      expect(r.alarms.scheduled.keys,
          unorderedEquals([notificationIdFor(3), notificationIdFor(5)]));
    });

    testWidgets('취소 응답을 기다리는 사이 로그아웃했으면 알람을 되살리지 않고 권한도 묻지 않는다', (tester) async {
      final alarms = FakeAlarmBackend();
      final permission = FakePermission();
      final scheduler = AlarmScheduler(alarms,
          registry: MemoryAlarmRegistry('uid-a'), now: () => seoulTime(2026, 9, 7, 12));
      final r = await pumpResultPage(tester,
          trip: sampleTrip(id: 7, tasks: [
            task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20), done: true),
          ]),
          alarms: alarms,
          scheduler: scheduler,
          permission: permission);
      r.api.holdMarkTaskUndone = Completer<void>();

      await tester.tap(find.text('여행자보험 가입'));
      await tester.pump();
      await scheduler.claimFor(null); // 계정 가드가 로그아웃을 보고 정리했다

      r.api.holdMarkTaskUndone!.complete();
      await tester.pumpAndSettle();

      expect(alarms.scheduled, isEmpty);
      expect(permission.calls, 0);
    });

    testWidgets('일정 응답을 기다리는 동안에는 다시 판정하지 않는다 (일정 id가 바뀌어 알람이 어긋난다)', (tester) async {
      final trip = sampleTrip(id: 7, judgementStale: true, tasks: [
        task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20), done: true),
      ]);
      final r = await pumpResultPage(tester, trip: trip);
      r.api.holdMarkTaskUndone = Completer<void>();

      await tester.tap(find.text('여행자보험 가입'));
      await tester.pump();
      await tester.tap(find.text('다시 판정'));
      await tester.pump();

      expect(r.api.refreshTripCalls, isEmpty);
      r.api.holdMarkTaskUndone!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('다시 판정하는 동안에는 일정을 눌러도 요청하지 않는다', (tester) async {
      final trip = sampleTrip(id: 7, judgementStale: true, tasks: [
        task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20), done: true),
      ]);
      final r = await pumpResultPage(tester, trip: trip);
      r.api.holdRefreshTrip = Completer<void>();

      await tester.tap(find.text('다시 판정'));
      await tester.pump();
      await tester.tap(find.text('여행자보험 가입'));
      await tester.pump();

      expect(r.api.markTaskUndoneCalls, isEmpty);
      r.api.holdRefreshTrip!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('다시 판정 응답을 기다리는 사이 다른 계정으로 바뀌었으면 예약하지 않는다', (tester) async {
      final alarms = FakeAlarmBackend();
      final scheduler = AlarmScheduler(alarms,
          registry: MemoryAlarmRegistry('uid-a'), now: () => seoulTime(2026, 9, 7, 12));
      final before = sampleTrip(id: 7, judgementStale: true);
      final after = sampleTrip(id: 7, tasks: [
        task(id: 13, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20)),
      ]);
      final r = await pumpResultPage(tester,
          trip: before, tripAfterRefresh: after, alarms: alarms, scheduler: scheduler);
      r.api.holdRefreshTrip = Completer<void>();

      await tester.tap(find.text('다시 판정'));
      await tester.pump();
      await scheduler.claimFor('uid-b');

      r.api.holdRefreshTrip!.complete();
      await tester.pumpAndSettle();

      expect(alarms.scheduled, isEmpty);
    });

    testWidgets('권한 대화상자가 떠 있는 동안 완료한 일정의 알람은 되살아나지 않는다', (tester) async {
      final dialog = Completer<void>();
      final r = await pumpResultPage(tester,
          trip: sampleTrip(id: 7, tasks: [
            task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20)),
          ]),
          permission: FakePermission(hold: dialog));

      await tester.tap(find.text('여행자보험 가입'));
      await tester.pumpAndSettle();
      dialog.complete();
      await tester.pumpAndSettle();

      expect(r.alarms.scheduled, isEmpty);
    });

    testWidgets('완료 응답이 오기 전에 화면을 나가도 그 일정의 알람은 취소한다', (tester) async {
      final trip = sampleTrip(id: 7, tasks: [
        task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20)),
      ]);
      final r = await pumpResultPage(tester, trip: trip);
      r.api.holdMarkTaskDone = Completer<void>();

      await tester.tap(find.text('여행자보험 가입'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back)); // 응답 전에 목록으로 나간다
      await tester.pumpAndSettle();
      expect(find.text('여행 목록'), findsOneWidget);

      r.api.holdMarkTaskDone!.complete();
      await tester.pumpAndSettle();

      expect(r.alarms.scheduled, isEmpty);
    });

    testWidgets('다시 판정하면 새 일정으로 알람을 다시 맞춘다', (tester) async {
      final before = sampleTrip(id: 7, judgementStale: true, tasks: [
        task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20)),
      ]);
      final after = sampleTrip(id: 7, tasks: [
        task(id: 13, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20)),
        task(id: 14, title: '비자 신청', dueDate: DateTime(2026, 11, 5)),
      ]);
      final alarms =
          (await pumpResultPage(tester, trip: before, tripAfterRefresh: after)).alarms;

      await tester.tap(find.text('다시 판정'));
      await tester.pumpAndSettle();

      expect(alarms.scheduled.keys,
          unorderedEquals([notificationIdFor(13), notificationIdFor(14)]));
    });

    testWidgets('알람 예약이 실패해도 화면은 그대로 쓸 수 있다', (tester) async {
      final trip = sampleTrip(tasks: [
        task(id: 3, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20)),
      ]);

      final api =
          (await pumpResultPage(tester, trip: trip, alarms: FakeAlarmBackend(failing: true))).api;
      await tester.tap(find.text('여행자보험 가입'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(api.markTaskDoneCalls, hasLength(1));
      expect(find.text('완료'), findsOneWidget);
    });
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
