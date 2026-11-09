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

/// 물리적 줄 목록을 논리적 CSV 행으로 합친다. 따옴표 안의 줄바꿈(메모 등)이 readAsLines에서 두 줄로
/// 쪼개지므로, 따옴표가 닫히지 않은 줄은 다음 줄과 줄바꿈으로 이어 붙인다. 이미 합쳐진 행을 넣어도 같다.
List<String> csvRecords(List<String> lines) {
  final records = <String>[];
  StringBuffer? open;
  var openQuotes = 0;
  for (final line in lines) {
    final pending = open;
    if (pending == null) {
      final quotes = '"'.allMatches(line).length;
      if (quotes.isEven) {
        records.add(line);
      } else {
        open = StringBuffer(line);
        openQuotes = quotes;
      }
    } else {
      pending.write('\n');
      pending.write(line);
      openQuotes += '"'.allMatches(line).length;
      if (openQuotes.isEven) {
        records.add(pending.toString());
        open = null;
      }
    }
  }
  // 따옴표가 끝내 안 닫힌 꼬리는 깨진 행으로 그대로 남겨, 호출하는 쪽이 건너뛰게 한다.
  if (open != null) records.add(open.toString());
  return records;
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
