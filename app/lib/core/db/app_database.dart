import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footstep_core/footstep_core.dart' show TimeSpan;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/footsteps/data/checkin.dart';
import '../../features/footsteps/data/daily_step.dart';
import '../../features/footsteps/data/route_point.dart';

part 'app_database.g.dart';

@DataClassName('CheckinRow')
class Checkins extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  TextColumn get countryIso => text().withLength(min: 2, max: 2)();
  DateTimeColumn get recordedAt => dateTime()();
  TextColumn get source => textEnum<CheckinSource>()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  TextColumn get serverId => text().nullable()();
}

@DataClassName('DailyStepRow')
class DailySteps extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  TextColumn get countryIso => text().withLength(min: 2, max: 2)();
  IntColumn get stepCount => integer()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  TextColumn get serverId => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {date, countryIso}
      ];
}

@DataClassName('RoutePointRow')
class RoutePoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  TextColumn get countryIso => text().withLength(min: 2, max: 2)();
  DateTimeColumn get recordedAt => dateTime()();

  // 여행 기록(설계 2026-11-07 9-3, 스키마 3). 실시간 경로·해외 매핑이 남긴 기존 행은 모두 null이라
  // 세계지도·국가 지도는 이 열을 몰라도 그대로 동작한다.
  IntColumn get tripId => integer().nullable()();
  RealColumn get accuracyM => real().nullable()();
  IntColumn get stepsSincePrev => integer().nullable()();
  TextColumn get state => text().nullable()();
}

/// 여행 기록 중 걸음 감지기가 정지였던 구간(스키마 3). 날짜별 보기의 머문 곳 묶기가 도착·출발 시각을 이 구간으로
/// 잡는다(설계 5-6 제안 방식). RoutePoints의 state만으로는 정지가 언제 시작·끝났는지 모른다.
@DataClassName('TripStillSpanRow')
class TripStillSpans extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tripId => integer()();
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime()();
}

@DriftDatabase(tables: [Checkins, DailySteps, RoutePoints, TripStillSpans])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 테스트에서 인메모리 DB를 주입하기 위한 생성자.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // 지금 정의(스키마 3의 여행 열 포함)로 만든다 — 아래 열 추가는 하지 않는다.
            await m.createTable(routePoints);
          } else if (from < 3) {
            // drift는 onUpgrade를 트랜잭션으로 감싸지 않고 user_version은 끝나야 쓴다. 이전 실행이 열을 더하다 끝났거나,
            // 앱 업데이트 직후 화면·기록 서비스·WorkManager isolate가 함께 올리면 열 일부가 이미 있다. 그 열을 다시 더하면
            // "duplicate column name"으로 이 연결을 못 쓰게 되므로 있는 열은 건너뛴다.
            for (final column in [
              routePoints.tripId,
              routePoints.accuracyM,
              routePoints.stepsSincePrev,
              routePoints.state,
            ]) {
              await _addColumnOnce(m, routePoints, column);
            }
          }
          if (from < 3) {
            await m.createTable(tripStillSpans); // CREATE TABLE IF NOT EXISTS라 두 번 돌아도 된다.
          }
        },
      );

  /// [column]이 [table]에 없을 때만 더한다. 확인과 추가 사이에 다른 isolate가 먼저 더해 실패했으면 넘어간다.
  Future<void> _addColumnOnce(Migrator m, TableInfo table, GeneratedColumn column) async {
    Future<bool> exists() async {
      final rows = await customSelect('PRAGMA table_info("${table.actualTableName}")').get();
      return rows.any((row) => row.read<String>('name') == column.name);
    }

    if (await exists()) return;
    try {
      await m.addColumn(table, column);
    } on Exception {
      if (!await exists()) rethrow;
    }
  }

  Future<int> insertCheckin({
    required double lat,
    required double lng,
    required String countryIso,
    required DateTime recordedAt,
    required CheckinSource source,
  }) {
    return into(checkins).insert(CheckinsCompanion.insert(
      lat: lat,
      lng: lng,
      countryIso: countryIso,
      recordedAt: recordedAt,
      source: source,
    ));
  }

  Future<List<Checkin>> allCheckins() async {
    final rows = await select(checkins).get();
    return rows.map(_toDomainCheckin).toList();
  }

  Future<List<Checkin>> checkinsForCountry(String iso) async {
    final rows = await (select(checkins)
          ..where((t) => t.countryIso.equals(iso))
          ..orderBy([(t) => OrderingTerm.asc(t.recordedAt)]))
        .get();
    return rows.map(_toDomainCheckin).toList();
  }

  Future<List<Checkin>> unsyncedCheckins() async {
    final rows =
        await (select(checkins)..where((t) => t.synced.equals(false))).get();
    return rows.map(_toDomainCheckin).toList();
  }

  Future<void> markCheckinSynced(int id, String serverId) {
    return (update(checkins)..where((t) => t.id.equals(id))).write(
      CheckinsCompanion(synced: const Value(true), serverId: Value(serverId)),
    );
  }

  // insertOnConflictUpdate()는 기본키(id) 충돌만 감지한다. 이 테이블의 실제 유니크
  // 제약은 (date, countryIso)이므로 충돌 대상을 명시하지 않으면 새 id로 계속 insert를
  // 시도하다 UNIQUE constraint failed로 실패한다.
  Future<void> upsertDailySteps(DateTime date, String countryIso, int stepCount) {
    return into(dailySteps).insert(
      DailyStepsCompanion.insert(
        date: date,
        countryIso: countryIso,
        stepCount: stepCount,
        synced: const Value(false),
      ),
      onConflict: DoUpdate(
        (_) => DailyStepsCompanion(
          stepCount: Value(stepCount),
          synced: const Value(false),
        ),
        target: [dailySteps.date, dailySteps.countryIso],
      ),
    );
  }

  Future<List<DailyStep>> allDailySteps() async {
    final rows = await select(dailySteps).get();
    return rows.map(_toDomainDailyStep).toList();
  }

  Future<List<DailyStep>> unsyncedDailySteps() async {
    final rows = await (select(dailySteps)..where((t) => t.synced.equals(false)))
        .get();
    return rows.map(_toDomainDailyStep).toList();
  }

  Future<void> markDailyStepsSynced(int id, String serverId) {
    return (update(dailySteps)..where((t) => t.id.equals(id))).write(
      DailyStepsCompanion(synced: const Value(true), serverId: Value(serverId)),
    );
  }

  Future<Map<String, int>> cumulativeStepsByCountry() async {
    final rows = await allDailySteps();
    final totals = <String, int>{};
    for (final row in rows) {
      totals.update(row.countryIso, (v) => v + row.stepCount,
          ifAbsent: () => row.stepCount);
    }
    return totals;
  }

  Future<void> insertRoutePoint({
    required double lat,
    required double lng,
    required String countryIso,
    required DateTime recordedAt,
  }) {
    return into(routePoints).insert(RoutePointsCompanion.insert(
      lat: lat,
      lng: lng,
      countryIso: countryIso,
      recordedAt: recordedAt,
    ));
  }

  Future<List<RoutePoint>> routePointsForCountry(String iso) async {
    final rows = await (select(routePoints)
          ..where((t) => t.countryIso.equals(iso))
          ..orderBy([(t) => OrderingTerm.asc(t.recordedAt)]))
        .get();
    return rows.map(_toDomainRoutePoint).toList();
  }

  /// 여행 기록 서비스가 측위 결과 하나를 남긴다(설계 9-3). 기록 좌표는 폰에만 둔다.
  Future<int> insertTripPoint({
    required int tripId,
    required double lat,
    required double lng,
    required String countryIso,
    required DateTime recordedAt,
    double? accuracyM,
    int? stepsSincePrev,
    String? state,
  }) {
    return into(routePoints).insert(RoutePointsCompanion.insert(
      lat: lat,
      lng: lng,
      countryIso: countryIso,
      recordedAt: recordedAt,
      tripId: Value(tripId),
      accuracyM: Value(accuracyM),
      stepsSincePrev: Value(stepsSincePrev),
      state: Value(state),
    ));
  }

  /// 한 여행이 남긴 점(시각순). 날짜별 보기가 기기 현지 날짜로 다시 묶는다.
  Future<List<RoutePoint>> routePointsForTrip(int tripId) async {
    final rows = await (select(routePoints)
          ..where((t) => t.tripId.equals(tripId))
          ..orderBy([(t) => OrderingTerm.asc(t.recordedAt), (t) => OrderingTerm.asc(t.id)]))
        .get();
    return rows.map(_toDomainRoutePoint).toList();
  }

  Future<int> insertTripStillSpan({
    required int tripId,
    required DateTime startAt,
    required DateTime endAt,
  }) {
    return into(tripStillSpans).insert(
      TripStillSpansCompanion.insert(tripId: tripId, startAt: startAt, endAt: endAt),
    );
  }

  /// 한 여행의 정지 구간(시작 시각순). footstep_core의 머문 곳 묶기(detectStays)에 그대로 넘긴다.
  Future<List<TimeSpan>> stillSpansForTrip(int tripId) async {
    final rows = await (select(tripStillSpans)
          ..where((t) => t.tripId.equals(tripId))
          ..orderBy([(t) => OrderingTerm.asc(t.startAt)]))
        .get();
    return [
      for (final row in rows)
        TimeSpan(row.startAt.millisecondsSinceEpoch, row.endAt.millisecondsSinceEpoch),
    ];
  }

  /// 지운 여행의 좌표·정지 구간을 지운다(설계 9-3). 여행에 속하지 않은 기존 점(tripId null)은 건드리지 않는다.
  Future<void> deleteTripRecords(Iterable<int> tripIds) async {
    final ids = tripIds.toList();
    if (ids.isEmpty) return;
    await transaction(() async {
      await (delete(routePoints)..where((t) => t.tripId.isIn(ids))).go();
      await (delete(tripStillSpans)..where((t) => t.tripId.isIn(ids))).go();
    });
  }

  /// [keep]에 없는 여행의 기록을 모두 지운다(서버 목록에서 사라진 여행, 계정 전환). [keep]이 비면 여행 기록 전부다.
  Future<void> deleteTripRecordsExcept(Set<int> keep) async {
    final ids = keep.toList();
    await transaction(() async {
      await (delete(routePoints)
            ..where((t) => t.tripId.isNotNull() & t.tripId.isNotIn(ids)))
          .go();
      await (delete(tripStillSpans)..where((t) => t.tripId.isNotIn(ids))).go();
    });
  }

  Checkin _toDomainCheckin(CheckinRow row) => Checkin(
        id: row.id,
        lat: row.lat,
        lng: row.lng,
        countryIso: row.countryIso,
        recordedAt: row.recordedAt,
        source: row.source,
        synced: row.synced,
        serverId: row.serverId,
      );

  RoutePoint _toDomainRoutePoint(RoutePointRow row) => RoutePoint(
        lat: row.lat,
        lng: row.lng,
        countryIso: row.countryIso,
        recordedAt: row.recordedAt,
        tripId: row.tripId,
        accuracyM: row.accuracyM,
        stepsSincePrev: row.stepsSincePrev,
        state: row.state,
      );

  DailyStep _toDomainDailyStep(DailyStepRow row) => DailyStep(
        id: row.id,
        date: row.date,
        countryIso: row.countryIso,
        stepCount: row.stepCount,
        synced: row.synced,
        serverId: row.serverId,
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = p.join(dbFolder.path, 'travelfootsteps.sqlite');
    // 화면·WorkManager·여행 기록 서비스(R7)가 각자의 isolate에서 같은 파일을 연다. 다른 연결이 쓰는 중이면
    // 바로 'database is locked'로 실패하지 않고 5초까지 기다리게 한다.
    return NativeDatabase.createInBackground(
      File(file),
      setup: (database) => database.execute('PRAGMA busy_timeout = 5000;'),
    );
  });
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
