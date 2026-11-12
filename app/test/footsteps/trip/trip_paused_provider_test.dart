import 'package:app/core/db/app_database.dart';
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/footsteps/trip/trip_departure_notices.dart';
import 'package:app/features/footsteps/trip/trip_recording_providers.dart';
import 'package:app/features/footsteps/trip/trip_recording_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../visa/fake_alarm_backend.dart';
import '../../visa/fake_trip_api.dart' show sampleSummary;
import 'trip_fakes.dart';

/// 진짜 코디네이터·저장소로, 일시정지 목록(pausedTripIdsProvider)이 저장소와 어긋나지 않는지 본다.
void main() {
  late ProviderContainer container;
  late TripRecordingStore store;
  late FakeTripRecordingService service;

  final today = DateTime.now();
  final first = DateTime(today.year, today.month, today.day);
  final trip7 = sampleSummary(id: 7, iso2: 'KR', nameKo: '대한민국', depart: first, ret: first.add(const Duration(days: 2)));
  final trip9 = sampleSummary(id: 9, iso2: 'KR', nameKo: '대한민국', depart: first, ret: first.add(const Duration(days: 3)));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = TripRecordingStore(prefs);
    service = FakeTripRecordingService();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      tripRecordingServiceProvider.overrideWithValue(service),
      tripRecordingPermissionsProvider.overrideWithValue(FakeTripRecordingPermissions()),
      tripDepartureNoticesProvider.overrideWithValue(TripDepartureNotices(FakeAlarmBackend(), store)),
    ]);
    addTearDown(container.dispose);
    container.listen(pausedTripIdsProvider, (_, _) {});
  });

  test('다른 계정으로 바뀌어 일시정지가 지워지면 목록도 함께 비어, 카드가 일시정지라고 잘못 말하지 않는다', () async {
    final coordinator = container.read(tripRecordingCoordinatorProvider);
    await coordinator.claimFor('uid-a');
    await coordinator.updateTrips([trip7]);
    await container.read(pausedTripIdsProvider.notifier).setPaused(7, true);
    expect(container.read(pausedTripIdsProvider), {7});

    await coordinator.claimFor(null);
    await coordinator.claimFor('uid-b');

    expect(store.readPaused(), isEmpty);
    expect(container.read(pausedTripIdsProvider), isEmpty);
  });

  test('새 목록에 없는 여행의 일시정지가 정리되면 목록도 따라간다', () async {
    final coordinator = container.read(tripRecordingCoordinatorProvider);
    await coordinator.updateTrips([trip7, trip9]);
    await container.read(pausedTripIdsProvider.notifier).setPaused(7, true);

    await coordinator.updateTrips([trip9]);

    expect(container.read(pausedTripIdsProvider), isEmpty);
  });

  test('여행을 지우면 그 여행의 일시정지도 목록에서 빠진다', () async {
    final coordinator = container.read(tripRecordingCoordinatorProvider);
    await coordinator.updateTrips([trip7, trip9]);
    await container.read(pausedTripIdsProvider.notifier).setPaused(7, true);
    await container.read(pausedTripIdsProvider.notifier).setPaused(9, true);

    await coordinator.forgetTrip(7);

    expect(container.read(pausedTripIdsProvider), {9});
  });

  test('기록을 맞추다 실패해도 저장된 값대로 목록을 맞추고, 오류는 호출한 쪽에 알린다', () async {
    await container.read(tripRecordingCoordinatorProvider).updateTrips([trip7]);
    final notifier = container.read(pausedTripIdsProvider.notifier);
    await notifier.setPaused(7, true);
    service.startThrows = true;

    await expectLater(notifier.setPaused(7, false), throwsStateError);

    expect(store.readPaused(), isEmpty); // 재개는 이미 저장됐다
    expect(container.read(pausedTripIdsProvider), isEmpty);
  });
}
