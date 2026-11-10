import 'dart:io';

import 'package:app/features/footsteps/recording/recording_mode.dart';
import 'package:app/features/footsteps/recording/session_library.dart';
import 'package:app/features/footsteps/recording/session_meta.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<Directory> _session(Directory root, String id, {DateTime? endedAt}) async {
  final dir = Directory(p.join(root.path, id))..createSync(recursive: true);
  File(p.join(dir.path, 'gps.csv')).writeAsStringSync('t_ms,lat\n1,37.5\n');
  await SessionMetaStore(File(p.join(dir.path, 'meta.json'))).write(SessionMeta(
    sessionId: id,
    mode: RecordingMode.groundTruth,
    deviceModel: 'samsung SM-S921N',
    androidSdk: 35,
    appVersion: '1.0.0',
    startedAt: DateTime.utc(2026, 11, 9, 1),
    endedAt: endedAt,
    carryInitial: 'hand',
  ));
  return dir;
}

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('session_library_test'));
  tearDown(() async => root.delete(recursive: true));

  test('세션을 최신순으로 나열하고 크기·meta·기록 시간을 담는다', () async {
    await _session(root, '20261109-080000-groundTruth', endedAt: DateTime.utc(2026, 11, 9, 2, 2));
    await _session(root, '20261110-090000-groundTruth');

    final sessions = await SessionLibrary(() async => root).list();
    expect(sessions.map((s) => s.id), ['20261110-090000-groundTruth', '20261109-080000-groundTruth']);
    expect(sessions.last.duration, const Duration(hours: 1, minutes: 2));
    expect(sessions.first.duration, isNull); // 아직 끝나지 않았거나 비정상 종료
    expect(sessions.first.sizeBytes, greaterThan(0));
    expect(sessions.first.meta!.deviceModel, 'samsung SM-S921N');
  });

  test('세션 폴더가 아직 없으면 빈 목록이다', () async {
    final missing = Directory(p.join(root.path, 'nope'));
    expect(await SessionLibrary(() async => missing).list(), isEmpty);
  });

  test('meta.json이 깨져 있어도 목록에서 빠지지 않는다', () async {
    final dir = Directory(p.join(root.path, '20261111-100000-groundTruth'))..createSync();
    File(p.join(dir.path, 'meta.json')).writeAsStringSync('{broken');

    final sessions = await SessionLibrary(() async => root).list();
    expect(sessions.single.meta, isNull);
  });

  test('zip은 세션 폴더의 파일을 모두 담는다', () async {
    await _session(root, '20261109-080000-groundTruth');
    final library = SessionLibrary(() async => root);
    final session = (await library.list()).single;
    final out = await Directory.systemTemp.createTemp('zip_out');
    addTearDown(() => out.delete(recursive: true));

    final zip = await library.zip(session, out);
    expect(p.basename(zip.path), '20261109-080000-groundTruth.zip');
    final names = ZipDecoder().decodeBytes(await zip.readAsBytes()).files.map((f) => f.name);
    expect(names.any((n) => n.endsWith('gps.csv')), isTrue);
    expect(names.any((n) => n.endsWith('meta.json')), isTrue);
  });
}
