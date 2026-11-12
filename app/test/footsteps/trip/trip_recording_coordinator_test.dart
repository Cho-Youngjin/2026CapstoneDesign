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

    test('돌고 있는 나중 여행을 일시정지하면 겹치는 이른 여행으로 바꾸고, 재개하면 다시 나중 여행으로 돌아온다', () async {
      now = DateTime(2026, 11, 21, 8);
      await coordinator.updateTrips([domestic, later]);
      expect(service.runningTripId, 9);

      await coordinator.setPaused(9, true);
      expect(service.runningTripId, 7);

      await coordinator.setPaused(9, false);
      expect(service.runningTripId, 9);
      expect(service.started, [9, 7, 9]);
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

    test('저장된 일정에 곧 울릴 알림이 있는지 알려 준다', () async {
      expect(coordinator.hasUpcomingNotice(), isFalse);

      await coordinator.updateTrips([domestic]);
      expect(coordinator.hasUpcomingNotice(), isTrue);

      await coordinator.setPaused(7, true);
      expect(coordinator.hasUpcomingNotice(), isFalse);
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

    test('목록이 비어 오면(서버 초기화·오류) 일정은 비우되 좌표는 지우지 않는다 — 폰에만 있는 연구 데이터다', () async {
      await coordinator.updateTrips([domestic]);
      await addPoint(7);

      await coordinator.updateTrips(const []);

      expect(store.readTrips(), isEmpty);
      expect(service.runningTripId, isNull);
      expect(await db.routePointsForTrip(7), hasLength(1));
    });

    test('빈 목록이 연달아 와도 좌표는 지우지 않는다(첫 빈 목록이 일정을 비워도 두 번째가 안전장치를 우회하지 못한다)', () async {
      await coordinator.updateTrips([domestic]);
      await addPoint(7);
      await db.insertTripStillSpan(
          tripId: 7, startAt: DateTime.utc(2026, 11, 20, 1), endAt: DateTime.utc(2026, 11, 20, 2));

      await coordinator.updateTrips(const []);
      await coordinator.updateTrips(const []);

      expect(store.readTrips(), isEmpty);
      expect(await db.routePointsForTrip(7), hasLength(1));
      expect(await db.stillSpansForTrip(7), hasLength(1));
    });

    test('로그아웃 뒤 다시 로그인해 빈 목록을 받아도 좌표는 지우지 않고, 다음 비어 있지 않은 목록이 고아 좌표를 정리한다', () async {
      await coordinator.claimFor('uid-a');
      await coordinator.updateTrips([domestic]);
      await addPoint(7);

      await coordinator.claimFor(null); // 일정이 비워진다
      await coordinator.claimFor('uid-a');
      await coordinator.updateTrips(const []);

      expect(await db.routePointsForTrip(7), hasLength(1));

      await coordinator.updateTrips([later]);

      expect(await db.routePointsForTrip(7), isEmpty);
    });

    test('여행을 일부러 지운 뒤 서비스가 늦게 쓴 점은 다음 목록이 비어 있어도 지운다', () async {
      await coordinator.updateTrips([domestic]);
      await addPoint(7);

      await coordinator.forgetTrip(7);
      await addPoint(7); // 끄기가 먼저 돌아온 서비스가 지운 뒤에 마저 쓴 점
      await db.insertTripStillSpan(
          tripId: 7, startAt: DateTime.utc(2026, 11, 20, 1), endAt: DateTime.utc(2026, 11, 20, 2));
      expect(await db.routePointsForTrip(7), hasLength(1));

      await coordinator.updateTrips(const []);

      expect(await db.routePointsForTrip(7), isEmpty);
      expect(await db.stillSpansForTrip(7), isEmpty);
    });

    test('계정을 바꾼 뒤 서비스가 늦게 쓴 이전 계정의 점은 다음 목록이 비어 있어도 지운다', () async {
      await coordinator.claimFor('uid-a');
      await coordinator.updateTrips([domestic]);
      await addPoint(7);

      await coordinator.claimFor('uid-b');
      await addPoint(7); // 이전 계정의 여행을 기록하던 서비스가 늦게 쓴 점
      expect(await db.routePointsForTrip(7), hasLength(1));

      await coordinator.updateTrips(const []);

      expect(await db.routePointsForTrip(7), isEmpty);
    });

    test('계정이 A→B→A로 바뀌어 A의 여행이 목록에 다시 오면 지운 여행 표시를 풀고 새로 쓴 점을 지우지 않는다', () async {
      await coordinator.claimFor('uid-a');
      await coordinator.updateTrips([domestic]);
      await coordinator.claimFor('uid-b'); // A의 여행 7을 지운 여행으로 적는다
      await coordinator.claimFor('uid-a');

      await coordinator.updateTrips([domestic]); // 서버가 A의 여행 7을 다시 준다
      await addPoint(7); // 다시 켜진 기록이 쓴 점
      await coordinator.updateTrips([domestic]);

      expect(await db.routePointsForTrip(7), hasLength(1));
      expect(store.readPurged(), isNot(contains(7)));
    });

    test('A→B→A 사이에 예전 세션이 늦게 쓴 점은 지운 표시를 풀기 전에 지운다', () async {
      await coordinator.claimFor('uid-a');
      await coordinator.updateTrips([domestic]);
      await coordinator.claimFor('uid-b');
      await coordinator.claimFor('uid-a');
      await addPoint(7); // B로 바꿀 때 끈 서비스가 늦게 쓴 점(계정 전환이 지웠어야 할 기록)

      await coordinator.updateTrips([domestic]);

      expect(await db.routePointsForTrip(7), isEmpty);
      expect(store.readPurged(), isNot(contains(7)));
    });

    test('일부러 지우지 않은 여행의 점은 빈 목록이 몇 번 와도 남는다(안전장치)', () async {
      await coordinator.updateTrips([domestic, later]);
      await addPoint(7);
      await addPoint(9);

      await coordinator.forgetTrip(9);
      await coordinator.updateTrips(const []);
      await coordinator.updateTrips(const []);

      expect(await db.routePointsForTrip(7), hasLength(1));
      expect(await db.routePointsForTrip(9), isEmpty);
    });

    test('비어 있지 않은 목록에서 빠진 여행의 좌표는 지운다', () async {
      await coordinator.updateTrips([domestic, later]);
      await addPoint(7);
      await addPoint(9);

      await coordinator.updateTrips([later]);

      expect(await db.routePointsForTrip(7), isEmpty);
      expect(await db.routePointsForTrip(9), hasLength(1));
    });

    test('목록에서 빠진 여행의 기록 서비스를 먼저 끈 뒤에 좌표를 지운다(서비스가 마지막으로 쓰는 점이 지운 뒤에 남지 않게)', () async {
      await coordinator.updateTrips([domestic]);
      await addPoint(7);
      var pointsWhenStopping = -1;
      service.onStop = () async => pointsWhenStopping = (await db.routePointsForTrip(7)).length;

      await coordinator.updateTrips([later]);

      expect(pointsWhenStopping, 1);
      expect(await db.routePointsForTrip(7), isEmpty);
    });

    test('기록 서비스를 끄다 실패해도 여행 삭제 정리는 이어간다', () async {
      await coordinator.updateTrips([domestic, later]);
      await addPoint(7);
      service.stopThrows = true;

      await coordinator.forgetTrip(7);

      expect(await db.routePointsForTrip(7), isEmpty);
      expect(store.readTrips().map((t) => t.tripId), [9]);
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

    test('로그아웃해도 일시정지는 남아, 같은 계정이 다시 로그인해도 멈춘 여행을 몰래 다시 기록하지 않는다', () async {
      await coordinator.claimFor('uid-a');
      await coordinator.updateTrips([domestic]);
      await coordinator.setPaused(7, true);
      service.started.clear();

      await coordinator.claimFor(null);
      expect(store.readPaused(), {7});
      await coordinator.claimFor('uid-a');
      await coordinator.updateTrips([domestic]);

      expect(store.readPaused(), {7});
      expect(service.started, isEmpty);
    });

    test('다른 계정이 로그인하면 일시정지도 비운다', () async {
      await coordinator.claimFor('uid-a');
      await coordinator.updateTrips([domestic]);
      await coordinator.setPaused(7, true);
      await coordinator.claimFor(null);

      await coordinator.claimFor('uid-b');

      expect(store.readPaused(), isEmpty);
    });

    test('계정을 바꿀 때 기록 서비스를 끄다 실패해도 이전 계정의 좌표 정리는 이어간다', () async {
      await coordinator.claimFor('uid-a');
      await coordinator.updateTrips([domestic]);
      await addPoint(7);
      service.stopThrows = true;

      await coordinator.claimFor('uid-b');

      expect(await db.routePointsForTrip(7), isEmpty);
      expect(store.readOwner(), 'uid-b');
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
