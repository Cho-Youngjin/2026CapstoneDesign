import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/data/checkin.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
