import 'dart:io';

import 'package:path/path.dart' as p;

import 'session_schema.dart';

// 이 파일은 dart:io와 path만 쓴다. tool/check_session.dart가 Flutter 없이 `dart run`으로 불러 쓰기 때문이다.

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
  });

  final String file;
  final int rows;
  final int? firstMs;
  final int? lastMs;
  final int? medianGapMs;
  final int? maxGapMs;

  /// 모든 행이 빈칸인 열. 예: 기기가 전하량을 지원하지 않으면 charge_uah가 여기에 나온다.
  final List<String> emptyColumns;

  Duration? get span {
    final first = firstMs;
    final last = lastMs;
    return first == null || last == null ? null : Duration(milliseconds: last - first);
  }
}

/// 따옴표로 감싼 필드(쉼표·이중 따옴표 포함)를 처리하는 CSV 한 줄 분리. CsvWriter의 서식과 짝이다.
List<String> splitCsvLine(String line) {
  final fields = <String>[];
  final current = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        current.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      fields.add(current.toString());
      current.clear();
    } else {
      current.write(c);
    }
  }
  fields.add(current.toString());
  return fields;
}

CsvFileStats statsFromCsvLines(String file, List<String> lines) {
  if (lines.isEmpty) return CsvFileStats(file: file, rows: 0);
  final header = splitCsvLine(lines.first);
  final rows = lines.skip(1).where((l) => l.isNotEmpty).map(splitCsvLine).toList();
  if (rows.isEmpty) return CsvFileStats(file: file, rows: 0);

  // 가속도는 이벤트 시각을 쓰므로 순서가 살짝 뒤바뀔 수 있다. 간격은 정렬한 시각으로 잰다.
  final times = rows.map((r) => int.parse(r.first)).toList()..sort();
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
          '${s.emptyColumns.isEmpty ? '' : '  empty=${s.emptyColumns.join('|')}'}',
  ].join('\n');
}
