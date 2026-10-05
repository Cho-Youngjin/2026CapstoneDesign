import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
}

@DriftDatabase(tables: [Checkins, DailySteps, RoutePoints])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 테스트에서 인메모리 DB를 주입하기 위한 생성자.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(routePoints);
          }
        },
      );

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
    return NativeDatabase.createInBackground(File(file));
  });
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
