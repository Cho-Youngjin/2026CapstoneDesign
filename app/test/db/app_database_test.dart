import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/data/checkin.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footstep_core/footstep_core.dart' show TimeSpan;

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('체크인을 저장하고 전체 조회하면 그대로 나온다', () async {
    await db.insertCheckin(lat: 35.6, lng: 139.7, countryIso: 'JP',
        recordedAt: DateTime.utc(2026, 12, 20, 9), source: CheckinSource.manual);

    final all = await db.allCheckins();

    expect(all, hasLength(1));
    expect(all.first.countryIso, 'JP');
    expect(all.first.source, CheckinSource.manual);
    expect(all.first.synced, isFalse);
  });

  test('국가별로 필터링해 조회할 수 있다', () async {
    await db.insertCheckin(lat: 35.6, lng: 139.7, countryIso: 'JP',
        recordedAt: DateTime.utc(2026, 12, 20, 9), source: CheckinSource.auto);
    await db.insertCheckin(lat: 21.0, lng: 105.8, countryIso: 'VN',
        recordedAt: DateTime.utc(2026, 12, 21, 9), source: CheckinSource.auto);

    final jp = await db.checkinsForCountry('JP');

    expect(jp, hasLength(1));
    expect(jp.first.countryIso, 'JP');
  });

  test('동기화되지 않은 체크인만 조회하고, 동기화 표시 후에는 빠진다', () async {
    final id = await db.insertCheckin(lat: 35.6, lng: 139.7, countryIso: 'JP',
        recordedAt: DateTime.utc(2026, 12, 20, 9), source: CheckinSource.auto);

    expect(await db.unsyncedCheckins(), hasLength(1));

    await db.markCheckinSynced(id, 'server-id-1');

    expect(await db.unsyncedCheckins(), isEmpty);
  });

  test('같은 날짜·국가의 걸음 수는 upsert된다', () async {
    final date = DateTime.utc(2026, 12, 20);

    await db.upsertDailySteps(date, 'JP', 5000);
    await db.upsertDailySteps(date, 'JP', 7000);

    final rows = await db.allDailySteps();
    expect(rows, hasLength(1));
    expect(rows.first.stepCount, 7000);
    expect(rows.first.synced, isFalse); // 값이 바뀌었으니 재동기화 대상
  });

  test('국가별 누적 걸음 수를 집계한다', () async {
    await db.upsertDailySteps(DateTime.utc(2026, 12, 20), 'JP', 5000);
    await db.upsertDailySteps(DateTime.utc(2026, 12, 21), 'JP', 6000);
    await db.upsertDailySteps(DateTime.utc(2026, 12, 22), 'VN', 3000);

    final totals = await db.cumulativeStepsByCountry();

    expect(totals['JP'], 11000);
    expect(totals['VN'], 3000);
  });

  test('경로 좌표를 저장하고 국가별로 시간순 조회할 수 있다', () async {
    await db.insertRoutePoint(
      lat: 35.61, lng: 139.71, countryIso: 'JP', recordedAt: DateTime.utc(2026, 12, 20, 9, 1));
    await db.insertRoutePoint(
      lat: 35.60, lng: 139.70, countryIso: 'JP', recordedAt: DateTime.utc(2026, 12, 20, 9, 0));
    await db.insertRoutePoint(
      lat: 21.0, lng: 105.8, countryIso: 'VN', recordedAt: DateTime.utc(2026, 12, 21, 9, 0));

    final jp = await db.routePointsForCountry('JP');

    expect(jp, hasLength(2));
    expect(jp.first.lat, 35.60); // 시간순이므로 9:00이 먼저
    expect(jp.last.lat, 35.61);
  });

  group('여행 기록(스키마 3)', () {
    test('여행 점을 정확도·걸음·상태와 함께 저장하고 여행별로 시각순 조회한다', () async {
      await db.insertTripPoint(tripId: 7, lat: 37.51, lng: 127.01, countryIso: 'KR',
          recordedAt: DateTime.utc(2026, 11, 20, 9, 5), accuracyM: 8, stepsSincePrev: 64, state: 'walking');
      await db.insertTripPoint(tripId: 7, lat: 37.50, lng: 127.00, countryIso: 'KR',
          recordedAt: DateTime.utc(2026, 11, 20, 9), state: 'unknown');
      await db.insertTripPoint(tripId: 8, lat: 35.6, lng: 139.7, countryIso: 'JP',
          recordedAt: DateTime.utc(2026, 11, 20, 9, 1));
      await db.insertRoutePoint(lat: 37.6, lng: 127.1, countryIso: 'KR', recordedAt: DateTime.utc(2026, 11, 20, 9, 2));

      final points = await db.routePointsForTrip(7);

      expect(points.map((p) => p.lat), [37.50, 37.51]);
      expect(points.last.tripId, 7);
      expect(points.last.accuracyM, 8);
      expect(points.last.stepsSincePrev, 64);
      expect(points.last.state, 'walking');
      expect(points.first.accuracyM, isNull);
      // 세계지도·국가 지도는 여행 점도 그대로 본다.
      expect(await db.routePointsForCountry('KR'), hasLength(3));
      expect((await db.routePointsForCountry('KR')).where((p) => p.tripId == null), hasLength(1));
    });

    test('정지 구간을 저장하고 여행별로 시작 시각순 밀리초 구간으로 돌려준다', () async {
      await db.insertTripStillSpan(
          tripId: 7, startAt: DateTime.utc(2026, 11, 20, 10), endAt: DateTime.utc(2026, 11, 20, 10, 30));
      await db.insertTripStillSpan(
          tripId: 7, startAt: DateTime.utc(2026, 11, 20, 9), endAt: DateTime.utc(2026, 11, 20, 9, 15));
      await db.insertTripStillSpan(
          tripId: 8, startAt: DateTime.utc(2026, 11, 20, 9), endAt: DateTime.utc(2026, 11, 20, 9, 1));

      final spans = await db.stillSpansForTrip(7);

      expect(spans, [
        TimeSpan(DateTime.utc(2026, 11, 20, 9).millisecondsSinceEpoch,
            DateTime.utc(2026, 11, 20, 9, 15).millisecondsSinceEpoch),
        TimeSpan(DateTime.utc(2026, 11, 20, 10).millisecondsSinceEpoch,
            DateTime.utc(2026, 11, 20, 10, 30).millisecondsSinceEpoch),
      ]);
    });

    Future<void> seedTwoTripsAndLegacyPoint() async {
      for (final tripId in [7, 8]) {
        await db.insertTripPoint(tripId: tripId, lat: 37.5, lng: 127.0, countryIso: 'KR',
            recordedAt: DateTime.utc(2026, 11, 20, 9));
        await db.insertTripStillSpan(
            tripId: tripId, startAt: DateTime.utc(2026, 11, 20, 9), endAt: DateTime.utc(2026, 11, 20, 9, 20));
      }
      await db.insertRoutePoint(lat: 37.6, lng: 127.1, countryIso: 'KR', recordedAt: DateTime.utc(2026, 11, 20, 9));
    }

    test('지운 여행의 점과 정지 구간만 지우고 여행에 속하지 않은 점은 남긴다', () async {
      await seedTwoTripsAndLegacyPoint();

      await db.deleteTripRecords([7]);

      expect(await db.routePointsForTrip(7), isEmpty);
      expect(await db.stillSpansForTrip(7), isEmpty);
      expect(await db.routePointsForTrip(8), hasLength(1));
      expect(await db.stillSpansForTrip(8), hasLength(1));
      expect(await db.routePointsForCountry('KR'), hasLength(2));
    });

    test('남길 여행 밖의 여행 기록을 지운다 — 비우면 여행 기록 전부', () async {
      await seedTwoTripsAndLegacyPoint();

      await db.deleteTripRecordsExcept({8});
      expect(await db.routePointsForTrip(7), isEmpty);
      expect(await db.stillSpansForTrip(7), isEmpty);
      expect(await db.routePointsForTrip(8), hasLength(1));

      await db.deleteTripRecordsExcept({});
      expect(await db.routePointsForTrip(8), isEmpty);
      expect(await db.stillSpansForTrip(8), isEmpty);
      expect(await db.routePointsForCountry('KR'), hasLength(1)); // tripId가 없는 기존 점
    });
  });

  test('스키마 2에서 올리면 기존 점은 여행 열이 null로 남고 여행 기록을 쓸 수 있다', () async {
    // setUp이 연 DB와 함께 두 번째 AppDatabase를 여는 것은 의도한 것이다(서로 다른 메모리 DB).
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
    // 스키마 2(R7 전)의 route_points를 만들어 둔 파일을 흉내 낸다. setup은 drift가 마이그레이션을 보기 전에 돈다.
    final old = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
      raw.execute('CREATE TABLE "route_points" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
          '"lat" REAL NOT NULL, "lng" REAL NOT NULL, '
          '"country_iso" TEXT NOT NULL CHECK(length("country_iso") >= 2 AND length("country_iso") <= 2), '
          '"recorded_at" INTEGER NOT NULL);');
      raw.execute('INSERT INTO route_points (lat, lng, country_iso, recorded_at) VALUES (35.6, 139.7, \'JP\', 1792400000);');
      raw.execute('PRAGMA user_version = 2;');
    }));
    addTearDown(old.close);

    final legacy = await old.routePointsForCountry('JP');
    expect(legacy, hasLength(1));
    expect(legacy.single.tripId, isNull);
    expect(legacy.single.state, isNull);

    await old.insertTripPoint(tripId: 3, lat: 35.7, lng: 139.8, countryIso: 'JP',
        recordedAt: DateTime.utc(2026, 11, 20), stepsSincePrev: 10, state: 'walking');
    await old.insertTripStillSpan(
        tripId: 3, startAt: DateTime.utc(2026, 11, 20), endAt: DateTime.utc(2026, 11, 20, 0, 20));
    expect((await old.routePointsForTrip(3)).single.stepsSincePrev, 10);
    expect(await old.stillSpansForTrip(3), hasLength(1));
  });
}
