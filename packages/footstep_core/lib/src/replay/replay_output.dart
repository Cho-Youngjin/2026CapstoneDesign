import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../session/csv.dart';
import 'replay_result.dart';

/// 재생 결과 파일 이름과 헤더(설계 문서 5-4). R5 복원·R6 분석이 이 이름으로 읽는다.
abstract final class ReplaySchema {
  static const fixesFile = 'fixes.csv';
  static const fixesHeader = [
    't_ms', 'lat', 'lng', 'accuracy_m', 'steps_since_prev', 'state', 'kind',
  ];

  static const actionsFile = 'actions.csv';
  static const actionsHeader = ['t_ms', 'action', 'args'];

  static const summaryFile = 'summary.json';
}

/// 재생 결과를 [outDir]에 쓴다. 폴더가 없으면 만든다.
Future<void> writeReplayOutput(ReplayResult result, Directory outDir) async {
  await outDir.create(recursive: true);

  String csv(List<String> header, Iterable<List<Object?>> rows) {
    final buffer = StringBuffer()..writeln(header.join(','));
    for (final row in rows) {
      buffer.writeln(row.map(formatCsvField).join(','));
    }
    return buffer.toString();
  }

  await File(p.join(outDir.path, ReplaySchema.fixesFile)).writeAsString(
    csv(ReplaySchema.fixesHeader, [
      for (final r in result.fixes)
        [r.tMs, r.fix.lat, r.fix.lng, r.fix.accuracyM, r.stepsSincePrev, r.state, r.kind],
    ]),
    flush: true,
  );
  await File(p.join(outDir.path, ReplaySchema.actionsFile)).writeAsString(
    csv(ReplaySchema.actionsHeader, [
      for (final r in result.actions) [r.tMs, r.action.logName, r.action.logArgs],
    ]),
    flush: true,
  );
  await File(p.join(outDir.path, ReplaySchema.summaryFile)).writeAsString(
    const JsonEncoder.withIndent('  ').convert(result.summary.toJson()),
    flush: true,
  );
}
