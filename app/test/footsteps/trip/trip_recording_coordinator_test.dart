import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/trip/trip_departure_notices.dart';
import 'package:app/features/footsteps/trip/trip_recording_coordinator.dart';
import 'package:app/features/footsteps/trip/trip_recording_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../visa/fake_alarm_backend.dart';
import '../../visa/fake_trip_api.dart' show sampleSummary;
import 'trip_fakes.dart';

void main() {
  late TripRecordingStore store;
  late FakeTripRecordingService service;
  late FakeTripRecordingPermissions permissions;
  late FakeAlarmBackend alarms;
  late AppDatabase db;
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
    alarms = FakeAlarmBackend();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    now = DateTime(2026, 11, 20, 9);
    coordinator = TripRecordingCoordinator(
      store: store,
      service: service,
      permissions: permissions,
      notices: TripDepartureNotices(alarms, store, now: () => seoulTime(2026, 11, 12, 15)),
      db: db,
      clock: () => now,
    );
  });

  Future<void> addPoint(int tripId) => db.insertTripPoint(
      tripId: tripId, lat: 37.5, lng: 127.0, countryIso: 'KR', recordedAt: DateTime.utc(2026, 11, 20, 1));

  group('켜기·끄기', () {
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
  });

  group('출발일 알림', () {
    test('목록을 받으면 출발일 아침 알림을 맞추고, 일시정지하면 지운다', () async {
      await coordinator.updateTrips([domestic, later]);
      expect(alarms.scheduled.keys, unorderedEquals([departureNoticeIdFor(7), departureNoticeIdFor(9)]));

      await coordinator.setPaused(9, true);
      expect(alarms.scheduled.keys, [departureNoticeIdFor(7)]);
    });

    test('알림이 실패해도 기록은 켠다', () async {
      final failing = TripRecordingCoordinator(
        store: store,
        service: service,
        permissions: permissions,
        notices: TripDepartureNotices(FakeAlarmBackend(failing: true), store,
            now: () => seoulTime(2026, 11, 12, 15)),
        db: db,
        clock: () => now,
      );

      await failing.updateTrips([domestic]);

      expect(service.started, [7]);
    });
  });

  group('기록 정리(설계 9-3)', () {
    test('목록에 없는 여행의 좌표·정지 구간은 지운다(다른 기기에서 지웠거나 다른 계정의 여행)', () async {
      await addPoint(7);
      await addPoint(8);
      await db.insertTripStillSpan(
          tripId: 8, startAt: DateTime.utc(2026, 11, 20, 1), endAt: DateTime.utc(2026, 11, 20, 2));

      await coordinator.updateTrips([domestic]);

      expect(await db.routePointsForTrip(7), hasLength(1));
      expect(await db.routePointsForTrip(8), isEmpty);
      expect(await db.stillSpansForTrip(8), isEmpty);
    });

    test('여행을 지우면 기록 중이던 서비스를 끄고 좌표·일시정지·출발일 알림을 지운다', () async {
      await coordinator.updateTrips([domestic, later]);
      await coordinator.setPaused(9, true);
      await addPoint(7);

      await coordinator.forgetTrip(7);

      expect(service.runningTripId, isNull);
      expect(await db.routePointsForTrip(7), isEmpty);
      expect(store.readTrips().map((t) => t.tripId), [9]);
      expect(alarms.scheduled, isEmpty); // 7은 지웠고 9는 일시정지
    });

    test('기록 중이 아닌 여행을 지우면 서비스는 그대로 둔다', () async {
      await coordinator.updateTrips([domestic, later]);

      await coordinator.forgetTrip(9);

      expect(service.runningTripId, 7);
    });

    test('같은 계정이면 아무것도 하지 않고, 처음 로그인하면 주인만 적는다', () async {
      await addPoint(7);

      await coordinator.claimFor('uid-a');
      expect(store.readOwner(), 'uid-a');

      await coordinator.updateTrips([domestic]);
      await coordinator.claimFor('uid-a');
      expect(service.runningTripId, 7);
      expect(await db.routePointsForTrip(7), hasLength(1));
    });

    test('로그아웃하면 기록을 끄고 일정·알림을 비우되 좌표는 남긴다', () async {
      await coordinator.claimFor('uid-a');
      await coordinator.updateTrips([domestic]);
      await addPoint(7);

      await coordinator.claimFor(null);

      expect(service.runningTripId, isNull);
      expect(store.readTrips(), isEmpty);
      expect(alarms.scheduled, isEmpty);
      expect(await db.routePointsForTrip(7), hasLength(1));
      expect(store.readOwner(), 'uid-a');
    });

    test('다른 계정이 로그인하면 이전 계정의 여행 좌표를 모두 지운다', () async {
      await coordinator.claimFor('uid-a');
      await coordinator.updateTrips([domestic]);
      await addPoint(7);
      await coordinator.claimFor(null);

      await coordinator.claimFor('uid-b');

      expect(await db.routePointsForTrip(7), isEmpty);
      expect(store.readOwner(), 'uid-b');
    });
  });
}
