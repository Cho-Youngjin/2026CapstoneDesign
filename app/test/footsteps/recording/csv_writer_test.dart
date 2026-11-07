import 'dart:io';

import 'package:app/features/footsteps/recording/csv_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('csv_writer_test'));
  tearDown(() async => dir.delete(recursive: true));

  test('새 파일에는 헤더를 쓰고, close 때 모아 둔 행을 쓴다', () async {
    final file = File(p.join(dir.path, 'gps.csv'));
    final writer = await CsvWriter.open(file, ['t_ms', 'lat']);
    writer.add([1, 37.5]);
    writer.add([2, 37.6]);
    await writer.close();

    expect(await file.readAsLines(), ['t_ms,lat', '1,37.5', '2,37.6']);
    expect(writer.totalRows, 2);
  });

  test('flush 전에는 행을 디스크에 쓰지 않는다', () async {
    final file = File(p.join(dir.path, 'a.csv'));
    final writer = await CsvWriter.open(file, ['t_ms']);
    writer.add([123]);

    expect(writer.pendingRows, 1);
    expect(await file.readAsString(), isNot(contains('123')));

    await writer.flush();
    expect(writer.pendingRows, 0);
    expect(await file.readAsString(), contains('123'));
    await writer.close();
  });

  test('동시에 여러 번 flush해도 오류 없이 순서대로 쓴다', () async {
    final file = File(p.join(dir.path, 'c.csv'));
    final writer = await CsvWriter.open(file, ['t_ms']);
    writer.add([1]);
    final first = writer.flush();
    writer.add([2]);
    final second = writer.flush();
    await Future.wait([first, second]);
    await writer.close();

    expect(await file.readAsLines(), ['t_ms', '1', '2']);
  });

  test('이미 내용이 있는 파일을 다시 열면 헤더 없이 이어 쓴다', () async {
    final file = File(p.join(dir.path, 'b.csv'));
    final first = await CsvWriter.open(file, ['t_ms']);
    first.add([1]);
    await first.close();

    final second = await CsvWriter.open(file, ['t_ms']);
    second.add([2]);
    await second.close();

    expect(await file.readAsLines(), ['t_ms', '1', '2']);
  });

  test('close를 두 번 불러도 오류 없이 한 번만 닫는다', () async {
    final file = File(p.join(dir.path, 'd.csv'));
    final writer = await CsvWriter.open(file, ['t_ms']);
    writer.add([1]);
    await writer.close();
    await writer.close();

    expect(await file.readAsLines(), ['t_ms', '1']);
  });

  test('필드 서식: null·NaN은 빈칸, bool은 1/0, 쉼표·따옴표·줄바꿈은 따옴표로 감싼다', () {
    expect(formatCsvField(null), '');
    expect(formatCsvField(double.nan), '');
    expect(formatCsvField(double.infinity), '');
    expect(formatCsvField(true), '1');
    expect(formatCsvField(false), '0');
    expect(formatCsvField('카페, 2층'), '"카페, 2층"');
    expect(formatCsvField('그가 "여기"'), '"그가 ""여기"""');
    expect(formatCsvField('a\nb'), '"a\nb"');
    expect(formatCsvField(37.56651), '37.56651');
    expect(formatCsvField(1762650000000), '1762650000000');
  });
}
