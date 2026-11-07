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

  test('close 뒤의 add는 무시하고 totalRows에도 세지 않는다', () async {
    final file = File(p.join(dir.path, 'e.csv'));
    final writer = await CsvWriter.open(file, ['t_ms']);
    writer.add([1]);
    await writer.close();
    final before = await file.readAsString();

    writer.add([2]);

    expect(writer.totalRows, 1);
    expect(await file.readAsString(), before);
  });

  test('실패한 flush가 있어도 이후 flush는 계속 쓴다', () async {
    final file = File(p.join(dir.path, 'f.csv'));
    late _FlakySink sink;
    final writer = await CsvWriter.openWithSink(
      file,
      ['t_ms'],
      (f) => sink = _FlakySink(f.openWrite(mode: FileMode.append)),
    );
    // open()이 헤더를 flush하므로 실패는 open이 끝난 뒤에 건다.
    sink.failingFlushes = 1;
    writer.add([1]);
    final failed = writer.flush();
    await expectLater(failed, throwsA(isA<FileSystemException>()));

    writer.add([2]);
    await writer.flush();
    await writer.close();

    expect(await file.readAsLines(), ['t_ms', '1', '2']);
  });

  test('마지막 flush가 실패해도 close는 파일을 닫고 오류를 알린다', () async {
    final file = File(p.join(dir.path, 'g.csv'));
    late _FlakySink sink;
    final writer = await CsvWriter.openWithSink(
      file,
      ['t_ms'],
      (f) => sink = _FlakySink(f.openWrite(mode: FileMode.append)),
    );
    sink.failingFlushes = 1;
    writer.add([1]);

    // 같은 future를 돌려주므로 동시에 두 번 불러도 둘 다 같은 오류를 받는다.
    final first = writer.close();
    final second = writer.close();
    await expectLater(first, throwsA(isA<FileSystemException>()));
    await expectLater(second, throwsA(isA<FileSystemException>()));

    // done은 IOSink가 닫힐 때 완료된다 — 핸들이 실제로 닫혔는지 확인한다.
    await expectLater(sink.done, completes);
  });
}

/// 쓰기 실패를 흉내 내는 IOSink 대역. 실제 sink에 모든 호출을 넘기고, flush만
/// [failingFlushes]번 실패시킨다. CsvWriter가 쓰는 메서드(write, writeln, flush, close, done)만
/// 직접 구현하고 나머지는 실제 sink로 넘긴다.
class _FlakySink implements IOSink {
  _FlakySink(this._inner);

  final IOSink _inner;
  int failingFlushes = 0;

  @override
  void write(Object? obj) => _inner.write(obj);

  @override
  void writeln([Object? object = '']) => _inner.writeln(object);

  @override
  Future<void> flush() async {
    if (failingFlushes > 0) {
      failingFlushes--;
      throw const FileSystemException('simulated write failure');
    }
    return _inner.flush();
  }

  @override
  Future<void> close() => _inner.close();

  @override
  Future<void> get done => _inner.done;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
