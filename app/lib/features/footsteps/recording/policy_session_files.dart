import 'dart:io';

import 'package:footstep_core/footstep_core.dart' show ReplaySchema, RunnerSchema;
import 'package:path/path.dart' as p;

import 'csv_writer.dart';
import 'session_schema.dart';

/// 정책 실행 모드의 세션 파일(설계 5-5): 측위 결과(fixes.csv)·할 일(actions.csv)·깨우기 지연(wakeups.csv)·
/// 배터리·관찰 표시와, 끝날 때 쓰는 summary.json. fixes.csv·actions.csv·summary.json은 재생기와 같은 이름·형식이라
/// R6 분석이 재생 결과와 실기기 결과를 같은 코드로 읽는다.
class PolicySessionFiles {
  PolicySessionFiles._({
    required this.directory,
    required this.fixes,
    required this.actions,
    required this.wakeups,
    required this.battery,
    required this.marks,
  });

  static Future<PolicySessionFiles> open(Directory directory) async {
    Future<CsvWriter> openCsv(String name, List<String> header) =>
        CsvWriter.open(File(p.join(directory.path, name)), header);

    return PolicySessionFiles._(
      directory: directory,
      fixes: await openCsv(ReplaySchema.fixesFile, ReplaySchema.fixesHeader),
      actions: await openCsv(ReplaySchema.actionsFile, ReplaySchema.actionsHeader),
      wakeups: await openCsv(RunnerSchema.wakeupsFile, RunnerSchema.wakeupsHeader),
      battery: await openCsv(SessionSchema.batteryFile, SessionSchema.batteryHeader),
      marks: await openCsv(SessionSchema.marksFile, SessionSchema.marksHeader),
    );
  }

  final Directory directory;
  final CsvWriter fixes;
  final CsvWriter actions;
  final CsvWriter wakeups;
  final CsvWriter battery;
  final CsvWriter marks;

  File get summaryFile => File(p.join(directory.path, ReplaySchema.summaryFile));

  List<CsvWriter> get all => [fixes, actions, wakeups, battery, marks];

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
