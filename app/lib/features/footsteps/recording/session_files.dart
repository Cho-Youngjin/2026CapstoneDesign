import 'dart:io';

import 'package:path/path.dart' as p;

import 'csv_writer.dart';
import 'session_meta.dart';
import 'session_schema.dart';

/// 한 세션 폴더의 CSV 여섯 개와 meta.json. 기록 모드는 이 묶음 하나만 받아 쓴다.
class SessionFiles {
  SessionFiles._({
    required this.directory,
    required this.gps,
    required this.accel,
    required this.osSteps,
    required this.activity,
    required this.battery,
    required this.marks,
  }) : meta = SessionMetaStore(File(p.join(directory.path, SessionSchema.metaFile)));

  static Future<SessionFiles> open(Directory directory) async {
    Future<CsvWriter> openCsv(String name, List<String> header) =>
        CsvWriter.open(File(p.join(directory.path, name)), header);

    return SessionFiles._(
      directory: directory,
      gps: await openCsv(SessionSchema.gpsFile, SessionSchema.gpsHeader),
      accel: await openCsv(SessionSchema.accelFile, SessionSchema.accelHeader),
      osSteps: await openCsv(SessionSchema.osStepsFile, SessionSchema.osStepsHeader),
      activity: await openCsv(SessionSchema.activityFile, SessionSchema.activityHeader),
      battery: await openCsv(SessionSchema.batteryFile, SessionSchema.batteryHeader),
      marks: await openCsv(SessionSchema.marksFile, SessionSchema.marksHeader),
    );
  }

  final Directory directory;
  final CsvWriter gps;
  final CsvWriter accel;
  final CsvWriter osSteps;
  final CsvWriter activity;
  final CsvWriter battery;
  final CsvWriter marks;
  final SessionMetaStore meta;

  List<CsvWriter> get all => [gps, accel, osSteps, activity, battery, marks];

  Future<void> flushAll() async {
    for (final writer in all) {
      await writer.flush();
    }
  }

  Future<void> closeAll() async {
    for (final writer in all) {
      await writer.close();
    }
  }
}
