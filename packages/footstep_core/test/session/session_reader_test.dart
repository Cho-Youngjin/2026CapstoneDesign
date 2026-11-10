import 'dart:io';

import 'package:footstep_core/footstep_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory session;

  void write(String name, List<String> lines) =>
      File(p.join(session.path, name)).writeAsStringSync('${lines.join('\n')}\n');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('session_reader_test');
    session = Directory(p.join(root.path, '20261109-213324-groundTruth'))..createSync();
  });

  tearDown(() async => root.delete(recursive: true));

  test('각 CSV를 시각순으로 읽고, 깨진 행은 건너뛰며 센다', () async {
    write('gps.csv', [
      't_ms,fix_t_ms,lat,lng,accuracy_m,speed_mps,bearing_deg,altitude_m',
      '2000,1990,37.5,127.0,8.5,1.2,90,30',
      '1000,990,37.4,126.9,5.0,-1,-1,30',
      'broken',
    ]);
    write('accel.csv', ['t_ms,x,y,z', '1010,0.1,9.8,0.2', '1000,0,9.7,0']);
    write('os_steps.csv', ['t_ms,kind,value', '1000,count,1520', '1500,status,walking']);
    write('activity.csv', ['t_ms,type,confidence', '1200,WALKING,HIGH']);
    write('battery.csv', [
      't_ms,charge_uah,current_ua,level_pct,temp_c,plugged',
      '1000,3705000,-193,90,30.8,0',
      '31000,,-150,,30.8,0',
    ]);

    final data = await readSession(session);

    expect(data.sessionId, '20261109-213324-groundTruth');
    expect(data.fixes.map((f) => f.tMs), [1000, 2000]);
    expect(data.fixes.first.speedMps, isNull); // 음수 속도는 '모름'
    expect(data.fixes.first.bearingDeg, isNull);
    expect(data.fixes.last.speedMps, 1.2);
    expect(data.fixes.last.accuracyM, 8.5);
    expect(data.accel.map((a) => a.tMs), [1000, 1010]);
    expect(data.osSteps.map((s) => s.kind), [OsStepReading.count, OsStepReading.status]);
    expect(data.activities.single.type, 'WALKING');
    expect(data.battery.single.levelPct, 90);
    expect(data.skippedRows, 2); // gps의 'broken', 잔량이 빈 배터리 행
    expect(data.startMs, 1000);
    expect(data.endMs, 2000);
  });

  test('같은 시각의 행은 파일 순서를 지킨다', () async {
    write('os_steps.csv', ['t_ms,kind,value', '1000,count,10', '1000,status,walking']);

    final data = await readSession(session);
    expect(data.osSteps.map((s) => s.kind), [OsStepReading.count, OsStepReading.status]);
  });

  test('파일이 없으면 빈 목록이고 시작·끝 시각은 null이다', () async {
    final data = await readSession(session);

    expect(data.fixes, isEmpty);
    expect(data.accel, isEmpty);
    expect(data.startMs, isNull);
    expect(data.endMs, isNull);
  });

  test('관찰 표시(marks.csv)를 시각순으로 읽고, 따옴표 안 쉼표와 빈 값을 지킨다', () async {
    write('marks.csv', [
      't_ms,kind,value',
      '61000,count_end,100',
      '1000,count_start,',
      '70000,note,"버스, 앞자리"',
      'broken',
    ]);
    write('gps.csv', [
      't_ms,fix_t_ms,lat,lng,accuracy_m,speed_mps,bearing_deg,altitude_m',
      '5000,4990,37.5,127.0,5.0,0,0,30',
    ]);

    final data = await readSession(session);

    expect(data.marks.map((m) => (m.tMs, m.kind, m.value)), [
      (1000, MarkReading.countStart, ''),
      (61000, MarkReading.countEnd, '100'),
      (70000, 'note', '버스, 앞자리'),
    ]);
    expect(data.skippedRows, 1);
    // 관찰 표시는 사람이 누른 시각이라 세션 시작·끝(센서 기록 범위)을 바꾸지 않는다.
    expect(data.startMs, 5000);
    expect(data.endMs, 5000);
  });
}
