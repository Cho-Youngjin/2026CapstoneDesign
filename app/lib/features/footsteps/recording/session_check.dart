import 'dart:io';

import 'package:footstep_core/footstep_core.dart' show csvRecords, splitCsvLine;
export 'package:footstep_core/footstep_core.dart' show csvRecords, splitCsvLine;
import 'package:path/path.dart' as p;

import 'session_schema.dart';

// 이 파일은 dart:io, path, 순수 Dart 패키지 footstep_core만 쓴다. tool/check_session.dart가 Flutter 없이
// `dart run`으로 불러 쓰기 때문이다.

/// 세션 파일 하나의 요약. 실기기 점검(설계 4-4)에서 "화면이 꺼진 동안에도 센서가 제 빈도로 값을 냈는가"를
/// 이 숫자로 판단한다.
class CsvFileStats {
  const CsvFileStats({
    required this.file,
    required this.rows,
    this.firstMs,
    this.lastMs,
    this.medianGapMs,
    this.maxGapMs,
    this.emptyColumns = const [],
    this.skippedRows = 0,
  });

  final String file;
  final int rows;
  final int? firstMs;
  final int? lastMs;
  final int? medianGapMs;
  final int? maxGapMs;

  /// 모든 행이 빈칸인 열. 예: 기기가 전하량을 지원하지 않으면 charge_uah가 여기에 나온다.
  final List<String> emptyColumns;

  /// 시각을 읽을 수 없어 세지 않은 행. 서비스가 쓰다 죽어 깨진 마지막 줄 등이다.
  final int skippedRows;

  Duration? get span {
    final first = firstMs;
    final last = lastMs;
    return first == null || last == null ? null : Duration(milliseconds: last - first);
  }
}

CsvFileStats statsFromCsvLines(String file, List<String> lines) {
  final records = csvRecords(lines);
  if (records.isEmpty) return CsvFileStats(file: file, rows: 0);
  final header = splitCsvLine(records.first);
  final rawRows = records.skip(1).where((l) => l.isNotEmpty).map(splitCsvLine).toList();

  // 시각을 읽을 수 없는 행은 세션 전체 보고를 막지 않도록 건너뛰고 개수만 남긴다.
  final rows = <List<String>>[];
  final times = <int>[];
  for (final row in rawRows) {
    final t = int.tryParse(row.first);
    if (t == null) continue;
    rows.add(row);
    times.add(t);
  }
  final skipped = rawRows.length - rows.length;
  if (rows.isEmpty) return CsvFileStats(file: file, rows: 0, skippedRows: skipped);

  // 가속도는 이벤트 시각을 쓰므로 순서가 살짝 뒤바뀔 수 있다. 간격은 정렬한 시각으로 잰다.
  times.sort();
  final gaps = [for (var i = 1; i < times.length; i++) times[i] - times[i - 1]]..sort();
  final emptyColumns = [
    for (var c = 0; c < header.length; c++)
      if (rows.every((r) => c >= r.length || r[c].isEmpty)) header[c],
  ];
  return CsvFileStats(
    file: file,
    rows: rows.length,
    firstMs: times.first,
    lastMs: times.last,
    medianGapMs: gaps.isEmpty ? null : gaps[gaps.length ~/ 2],
    maxGapMs: gaps.isEmpty ? null : gaps.last,
    emptyColumns: emptyColumns,
    skippedRows: skipped,
  );
}

const _sessionCsvFiles = [
  SessionSchema.gpsFile,
  SessionSchema.accelFile,
  SessionSchema.osStepsFile,
  SessionSchema.activityFile,
  SessionSchema.batteryFile,
  SessionSchema.marksFile,
];

Future<List<CsvFileStats>> checkSession(Directory dir) async {
  return [
    for (final name in _sessionCsvFiles)
      await () async {
        final file = File(p.join(dir.path, name));
        if (!await file.exists()) return CsvFileStats(file: name, rows: 0);
        return statsFromCsvLines(name, await file.readAsLines());
      }(),
  ];
}

String formatSessionReport(List<CsvFileStats> stats) {
  String two(int n) => n.toString().padLeft(2, '0');
  String span(Duration? d) => d == null ? '-' : '${d.inMinutes}:${two(d.inSeconds % 60)}';
  return [
    for (final s in stats)
      '${s.file.padRight(13)} rows=${s.rows}  span=${span(s.span)}'
          '  median=${s.medianGapMs ?? '-'}ms  max=${s.maxGapMs ?? '-'}ms'
          '${s.emptyColumns.isEmpty ? '' : '  empty=${s.emptyColumns.join('|')}'}'
          '${s.skippedRows == 0 ? '' : '  skipped=${s.skippedRows}'}',
  ].join('\n');
}
