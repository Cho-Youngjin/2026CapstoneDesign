import 'dart:io';

import 'package:app/features/footsteps/recording/recording_mode.dart';
import 'package:app/features/footsteps/recording/session_files.dart';
import 'package:app/features/footsteps/recording/session_meta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

SessionMeta _meta({DateTime? endedAt, List<SessionError> errors = const []}) => SessionMeta(
      sessionId: '20261109-080503-groundTruth',
      mode: RecordingMode.groundTruth,
      deviceModel: 'samsung SM-S921N',
      androidSdk: 35,
      appVersion: '1.0.0',
      startedAt: DateTime.utc(2026, 11, 8, 23, 5, 3),
      endedAt: endedAt,
      carryInitial: 'pocket',
      note: '시청 코스',
      errors: errors,
    );

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('session_files_test'));
  tearDown(() async => dir.delete(recursive: true));

  test('세션 폴더 이름은 현지 시각과 모드로 만든다', () {
    expect(
      sessionDirName(DateTime(2026, 11, 9, 8, 5, 3), RecordingMode.groundTruth),
      '20261109-080503-groundTruth',
    );
  });

  test('open은 여섯 CSV를 설계 문서 4-2의 헤더로 만든다', () async {
    final sessionDir = Directory(p.join(dir.path, 's1'));
    final files = await SessionFiles.open(sessionDir);
    await files.closeAll();

    String header(String name) => File(p.join(sessionDir.path, name)).readAsLinesSync().first;
    expect(header('gps.csv'), 't_ms,fix_t_ms,lat,lng,accuracy_m,speed_mps,bearing_deg,altitude_m');
    expect(header('accel.csv'), 't_ms,x,y,z');
    expect(header('os_steps.csv'), 't_ms,kind,value');
    expect(header('activity.csv'), 't_ms,type,confidence');
    expect(header('battery.csv'), 't_ms,charge_uah,current_ua,level_pct,temp_c,plugged');
    expect(header('marks.csv'), 't_ms,kind,value');
  });

  test('meta.json을 쓰고 다시 읽는다', () async {
    final files = await SessionFiles.open(Directory(p.join(dir.path, 's2')));
    final meta = _meta(
      endedAt: DateTime.utc(2026, 11, 9, 1),
      errors: [SessionError(at: DateTime.utc(2026, 11, 9), source: 'os_steps', message: 'no sensor')],
    );
    await files.meta.write(meta);
    await files.closeAll();

    final read = await files.meta.read();
    expect(read!.toJson(), meta.toJson());
    expect(read.errors.single.source, 'os_steps');
  });

  test('meta.json이 없으면 read는 null을 돌려준다', () async {
    final store = SessionMetaStore(File(p.join(dir.path, 'none', 'meta.json')));
    expect(await store.read(), isNull);
  });

  test('연달아 쓴 meta는 마지막 내용으로 남는다', () async {
    final store = SessionMetaStore(File(p.join(dir.path, 'm', 'meta.json')));
    final base = _meta();
    store.write(base);
    store.write(base.withError(SessionError(at: DateTime.utc(2026), source: 'gps', message: 'a')));
    await store.write(base.copyWith(endedAt: DateTime.utc(2026, 11, 9, 2)));

    final read = await store.read();
    expect(read!.endedAt, DateTime.utc(2026, 11, 9, 2));
    expect(read.errors, isEmpty);
  });
}
