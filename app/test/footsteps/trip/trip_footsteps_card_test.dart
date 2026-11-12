import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/footsteps/trip/trip_footsteps_card.dart';
import 'package:app/features/footsteps/trip/trip_recording_providers.dart';
import 'package:app/features/footsteps/trip/trip_recording_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'trip_fakes.dart';

void main() {
  final trip = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));

  test('기록 단계: 출발 전·여행 중·일시정지·귀국 다음 날 이후', () {
    expect(tripRecordingPhaseOf(trip, DateTime(2026, 11, 19, 23), paused: false), TripRecordingPhase.upcoming);
    expect(tripRecordingPhaseOf(trip, DateTime(2026, 11, 20), paused: false), TripRecordingPhase.recording);
    expect(tripRecordingPhaseOf(trip, DateTime(2026, 11, 21), paused: true), TripRecordingPhase.paused);
    expect(tripRecordingPhaseOf(trip, DateTime(2026, 11, 23), paused: true), TripRecordingPhase.ended);
  });

  Future<FakeTripRecordingCoordinator> pumpCard(
    WidgetTester tester, {
    required DateTime now,
    Map<String, Object> stored = const {},
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    final coordinator = FakeTripRecordingCoordinator();
    final router = GoRouter(
      initialLocation: '/visa/trip/7',
      routes: [
        GoRoute(
          path: '/visa/trip/:id',
          builder: (_, _) => Scaffold(body: TripFootstepsCard(trip: trip)),
        ),
        GoRoute(
          path: '/visa/trip/:id/footsteps',
          builder: (_, state) => Scaffold(body: Text('발걸음 ${state.pathParameters['id']}')),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        tripRecordingCoordinatorProvider.overrideWithValue(coordinator),
        tripClockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return coordinator;
  }

  testWidgets('여행 중이면 기록 중이라고 알리고, 일시정지·재개를 코디네이터로 보낸다', (tester) async {
    final coordinator = await pumpCard(tester, now: DateTime(2026, 11, 21, 9));
    expect(find.text('여행 중이라 발걸음을 기록하고 있어요.'), findsOneWidget);

    await tester.tap(find.text('기록 일시정지'));
    await tester.pumpAndSettle();
    expect(coordinator.pauses, [(7, true)]);
    expect(find.text('기록을 일시정지했어요.'), findsOneWidget);

    await tester.tap(find.text('기록 재개'));
    await tester.pumpAndSettle();
    expect(coordinator.pauses, [(7, true), (7, false)]);
    expect(find.text('여행 중이라 발걸음을 기록하고 있어요.'), findsOneWidget);
  });

  testWidgets('일시정지 상태는 여행별로 기기에 남은 값을 보여 준다', (tester) async {
    await pumpCard(tester, now: DateTime(2026, 11, 21, 9), stored: {TripRecordingStore.pausedKey: '[7]'});

    expect(find.text('기록을 일시정지했어요.'), findsOneWidget);
    expect(find.text('기록 재개'), findsOneWidget);
  });

  testWidgets('출발 전에는 출발일 0시부터 기록한다고 알리고, 재부팅 한계를 적어 둔다', (tester) async {
    await pumpCard(tester, now: DateTime(2026, 11, 12, 9));

    expect(find.text('출발일(11/20) 0시부터 발걸음을 기록해요.'), findsOneWidget);
    expect(find.textContaining('휴대폰을 다시 켠 뒤에는 앱을 한 번 열어 주세요'), findsOneWidget);
  });

  testWidgets('귀국 다음 날부터는 일시정지 버튼 없이 날짜별 발걸음만 연다', (tester) async {
    await pumpCard(tester, now: DateTime(2026, 11, 23));

    expect(find.text('귀국 다음 날 기록을 마쳤어요.'), findsOneWidget);
    expect(find.byKey(const Key('tripRecordingToggle')), findsNothing);

    await tester.tap(find.byKey(const Key('openTripFootsteps')));
    await tester.pumpAndSettle();
    expect(find.text('발걸음 7'), findsOneWidget);
  });
}
