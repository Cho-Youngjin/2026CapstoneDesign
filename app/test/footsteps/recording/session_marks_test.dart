import 'dart:io';

import 'package:app/features/footsteps/recording/mark.dart';
import 'package:app/features/footsteps/recording/session_marks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('marks.csv 행을 표시로 읽고, 읽을 수 없는 행은 건너뛴다', () {
    final marks = marksFromCsvLines([
      't_ms,kind,value',
      '1000,arrive,',
      '2000,board,bus',
      '3000,nonsense,',
      '4000,note,"카페, ""2층"""',
      '179422x',
      '',
    ]);

    expect(marks.map((m) => m.kind), [MarkKind.arrive, MarkKind.board, MarkKind.note]);
    expect(marks[0].at, DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true));
    expect(marks[1].value, 'bus');
    expect(marks[2].value, '카페, "2층"');
  });

  test('따옴표 안에 줄바꿈이 든 메모도 한 표시로 읽는다', () {
    final marks = marksFromCsvLines(['t_ms,kind,value', '1000,note,"가', '나"', '2000,arrive,']);

    expect(marks.map((m) => m.kind), [MarkKind.note, MarkKind.arrive]);
    expect(marks.first.value, '가\n나');
  });

  test('도착 뒤 탑승을 다시 읽으면 장소 안·탈것 탑승 상태가 되살아난다', () async {
    final dir = await Directory.systemTemp.createTemp('session_marks_test');
    addTearDown(() => dir.delete(recursive: true));
    File(p.join(dir.path, 'marks.csv')).writeAsStringSync(
      't_ms,kind,value\n1000,arrive,\n2000,board,bus\n3000,carry,pocket\n',
    );

    final field = FieldState();
    for (final mark in await readSessionMarks(dir)) {
      field.observe(mark);
    }

    expect(field.atPlace, isTrue);
    expect(field.onVehicle, isTrue);
    expect(field.carry, CarryPosition.pocket);
    expect(field.nextPlaceMark(DateTime.utc(2026)).kind, MarkKind.depart);
    expect(field.nextVehicleMark(DateTime.utc(2026)).kind, MarkKind.alight);
  });

  test('marks.csv가 없으면 빈 목록이다', () async {
    final dir = await Directory.systemTemp.createTemp('session_marks_empty');
    addTearDown(() => dir.delete(recursive: true));

    expect(await readSessionMarks(dir), isEmpty);
  });
}
