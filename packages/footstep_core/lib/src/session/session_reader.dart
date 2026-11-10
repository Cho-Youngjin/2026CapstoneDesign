import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../model/fix.dart';
import '../model/readings.dart';
import 'csv.dart';
import 'session_schema.dart';

/// 세션 폴더 하나를 읽은 결과. 목록은 모두 시각순이다.
class SessionData {
  const SessionData({
    required this.sessionId,
    this.fixes = const [],
    this.accel = const [],
    this.osSteps = const [],
    this.activities = const [],
    this.battery = const [],
    this.skippedRows = 0,
  });

  final String sessionId;
  final List<Fix> fixes;
  final List<AccelReading> accel;
  final List<OsStepReading> osSteps;
  final List<ActivityReading> activities;
  final List<BatteryLevelReading> battery;

  /// 읽지 못해 건너뛴 행 수(서비스가 쓰다 죽어 잘린 줄 등).
  final int skippedRows;

  /// 가장 이른 기록 시각. 기록이 하나도 없으면 null이다.
  int? get startMs {
    final firsts = [
      if (fixes.isNotEmpty) fixes.first.tMs,
      if (accel.isNotEmpty) accel.first.tMs,
      if (osSteps.isNotEmpty) osSteps.first.tMs,
      if (activities.isNotEmpty) activities.first.tMs,
      if (battery.isNotEmpty) battery.first.tMs,
    ];
    return firsts.isEmpty ? null : firsts.reduce(math.min);
  }

  /// 가장 늦은 기록 시각. 기록이 하나도 없으면 null이다.
  int? get endMs {
    final lasts = [
      if (fixes.isNotEmpty) fixes.last.tMs,
      if (accel.isNotEmpty) accel.last.tMs,
      if (osSteps.isNotEmpty) osSteps.last.tMs,
      if (activities.isNotEmpty) activities.last.tMs,
      if (battery.isNotEmpty) battery.last.tMs,
    ];
    return lasts.isEmpty ? null : lasts.reduce(math.max);
  }
}

/// R1이 쓴 세션 폴더(설계 4-2)를 읽는다. 없는 파일은 빈 목록이고, 읽을 수 없는 행은 건너뛰고 센다.
Future<SessionData> readSession(Directory dir) async {
  var skipped = 0;

  Future<List<T>> load<T>(
    String fileName,
    T? Function(List<String> fields) parse,
    int Function(T item) timeOf,
  ) async {
    final file = File(p.join(dir.path, fileName));
    if (!await file.exists()) return <T>[];
    final items = <T>[];
    for (final record in csvRecords(await file.readAsLines()).skip(1)) {
      if (record.isEmpty) continue;
      final item = parse(splitCsvLine(record));
      if (item == null) {
        skipped++;
      } else {
        items.add(item);
      }
    }
    return _sortedByTime(items, timeOf);
  }

  final fixes = await load(SessionSchema.gpsFile, _parseGps, (Fix f) => f.tMs);
  final accel = await load(SessionSchema.accelFile, _parseAccel, (AccelReading a) => a.tMs);
  final osSteps = await load(SessionSchema.osStepsFile, _parseOsStep, (OsStepReading s) => s.tMs);
  final activities =
      await load(SessionSchema.activityFile, _parseActivity, (ActivityReading a) => a.tMs);
  final battery =
      await load(SessionSchema.batteryFile, _parseBattery, (BatteryLevelReading b) => b.tMs);

  return SessionData(
    sessionId: p.basename(dir.path),
    fixes: fixes,
    accel: accel,
    osSteps: osSteps,
    activities: activities,
    battery: battery,
    skippedRows: skipped,
  );
}

/// 시각순으로 정렬하되 같은 시각은 원래 순서를 지킨다(List.sort는 안정 정렬이 아니다).
List<T> _sortedByTime<T>(List<T> items, int Function(T item) timeOf) {
  final order = List<int>.generate(items.length, (i) => i);
  order.sort((a, b) {
    final byTime = timeOf(items[a]).compareTo(timeOf(items[b]));
    return byTime != 0 ? byTime : a.compareTo(b);
  });
  return [for (final i in order) items[i]];
}

Fix? _parseGps(List<String> f) {
  if (f.length < 5) return null;
  final t = int.tryParse(f[0]);
  final lat = double.tryParse(f[2]);
  final lng = double.tryParse(f[3]);
  final accuracy = double.tryParse(f[4]);
  if (t == null || lat == null || lng == null || accuracy == null) return null;
  return Fix(
    tMs: t,
    lat: lat,
    lng: lng,
    accuracyM: accuracy,
    speedMps: _nonNegative(f, 5),
    bearingDeg: _nonNegative(f, 6),
  );
}

/// geolocator는 모르는 속도·방향을 음수로 준다. 음수와 빈칸은 null('모름')로 읽는다.
double? _nonNegative(List<String> f, int index) {
  if (index >= f.length) return null;
  final value = double.tryParse(f[index]);
  return value == null || value < 0 ? null : value;
}

AccelReading? _parseAccel(List<String> f) {
  if (f.length < 4) return null;
  final t = int.tryParse(f[0]);
  final x = double.tryParse(f[1]);
  final y = double.tryParse(f[2]);
  final z = double.tryParse(f[3]);
  if (t == null || x == null || y == null || z == null) return null;
  return AccelReading(tMs: t, x: x, y: y, z: z);
}

OsStepReading? _parseOsStep(List<String> f) {
  if (f.length < 3) return null;
  final t = int.tryParse(f[0]);
  if (t == null || f[1].isEmpty) return null;
  return OsStepReading(tMs: t, kind: f[1], value: f[2]);
}

ActivityReading? _parseActivity(List<String> f) {
  if (f.length < 3) return null;
  final t = int.tryParse(f[0]);
  if (t == null || f[1].isEmpty) return null;
  return ActivityReading(tMs: t, type: f[1], confidence: f[2]);
}

BatteryLevelReading? _parseBattery(List<String> f) {
  if (f.length < 4) return null;
  final t = int.tryParse(f[0]);
  final level = int.tryParse(f[3]);
  if (t == null || level == null) return null;
  return BatteryLevelReading(tMs: t, levelPct: level);
}
