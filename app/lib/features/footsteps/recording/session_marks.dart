import 'dart:io';

import 'package:path/path.dart' as p;

import 'mark.dart';
import 'session_check.dart';
import 'session_schema.dart';

/// marks.csv 줄들을 표시로 읽는다. 헤더·깨진 행·모르는 종류의 행은 건너뛴다 — 서비스가 쓰다 죽어
/// 마지막 줄이 잘렸더라도 나머지 표시로 상태를 되살려야 하기 때문이다.
List<Mark> marksFromCsvLines(List<String> lines) {
  final marks = <Mark>[];
  for (final record in csvRecords(lines)) {
    if (record.isEmpty) continue;
    final fields = splitCsvLine(record);
    final ms = int.tryParse(fields.first);
    if (ms == null || fields.length < 2) continue; // 헤더나 깨진 행
    final MarkKind kind;
    try {
      kind = MarkKind.fromCsvName(fields[1]);
    } on StateError {
      continue;
    }
    marks.add(Mark(
      at: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
      kind: kind,
      value: fields.length > 2 ? fields[2] : '',
    ));
  }
  return marks;
}

/// 세션 폴더의 marks.csv에 이미 남은 표시. 서비스가 다시 떠서 같은 폴더에 이어 쓸 때, 알림 버튼 토글
/// (도착/출발, 탑승/하차)과 휴대 위치 상태를 되살리는 데 쓴다.
Future<List<Mark>> readSessionMarks(Directory dir) async {
  final file = File(p.join(dir.path, SessionSchema.marksFile));
  if (!await file.exists()) return const [];
  return marksFromCsvLines(await file.readAsLines());
}
