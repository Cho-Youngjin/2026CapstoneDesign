import 'package:app/features/footsteps/trip/trip_recording_coordinator.dart';
import 'package:app/features/footsteps/trip/trip_recording_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../visa/fake_trip_api.dart' show sampleSummary;
import 'trip_fakes.dart';

void main() {
  late TripRecordingStore store;
  late FakeTripRecordingService service;
  late FakeTripRecordingPermissions permissions;
  late DateTime now;
  late TripRecordingCoordinator coordinator;

  final domestic = sampleSummary(
      id: 7, iso2: 'KR', nameKo: '대한민국', depart: DateTime(2026, 11, 20), ret: DateTime(2026, 11, 22));
  final later = sampleSummary(id: 9, depart: DateTime(2026, 11, 21), ret: DateTime(2026, 11, 25));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = TripRecordingStore(await SharedPreferences.getInstance());
    service = FakeTripRecordingService();
    permissions = FakeTripRecordingPermissions();
    now = DateTime(2026, 11, 20, 9);
    coordinator = TripRecordingCoordinator(
      store: store,
      service: service,
      permissions: permissions,
      clock: () => now,
    );
  });

  test('목록을 받으면 일정을 바꾸고, 오늘이 여행 기간이면 그 여행으로 기록 서비스를 켠다', () async {
    await coordinator.updateTrips([domestic]);

    expect(store.readTrips().single.tripId, 7);
    expect(service.started, [7]);

    // 이미 그 여행으로 돌고 있으면 다시 켜지 않는다(앱을 다시 열 때마다 부른다).
    await coordinator.sync();
    expect(service.started, [7]);
  });

  test('여행 기간이 아니면 켜지 않고, 돌던 여행 기록은 끈다', () async {
    now = DateTime(2026, 11, 19, 23, 59);
    await coordinator.updateTrips([domestic]);
    expect(service.started, isEmpty);

    now = DateTime(2026, 11, 20);
    await coordinator.sync();
    expect(service.started, [7]);

    now = DateTime(2026, 11, 23);
    await coordinator.sync();
    expect(service.stops, 1);
    expect(service.runningTripId, isNull);
  });

  test('일시정지하면 끄고, 재개하면 다시 켠다', () async {
    await coordinator.updateTrips([domestic]);

    await coordinator.setPaused(7, true);
    expect(store.readPaused(), {7});
    expect(service.runningTripId, isNull);

    await coordinator.setPaused(7, false);
    expect(service.started, [7, 7]);
  });

  test('겹치는 여행이 새로 시작하면 그 여행으로 바꿔 켠다', () async {
    await coordinator.updateTrips([domestic, later]);
    expect(service.started, [7]);

    now = DateTime(2026, 11, 21, 8);
    await coordinator.sync();
    expect(service.stops, 1);
    expect(service.started, [7, 9]);
  });

  test('실험 화면의 세션이 돌고 있으면 건드리지 않는다(배터리 측정이 오염된다)', () async {
    service.labRunning = true;

    await coordinator.updateTrips([domestic]);

    expect(service.started, isEmpty);
    expect(service.stops, 0);
  });

  test('위치 권한이 없으면 켜지 않는다', () async {
    permissions.location = false;

    await coordinator.updateTrips([domestic]);

    expect(service.started, isEmpty);
  });

  test('앱을 열 때와 목록 도착이 겹쳐도 한 번만 켠다', () async {
    await store.replaceTrips([period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22))]);

    await Future.wait([coordinator.sync(), coordinator.updateTrips([domestic]), coordinator.sync()]);

    expect(service.started, [7]);
  });
}
