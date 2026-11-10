import 'dart:io';

import 'package:app/features/footsteps/recording/session_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('따옴표 안의 쉼표와 이중 따옴표를 하나의 필드로 읽는다', () {
    expect(splitCsvLine('1,arrive,"카페, 2층"'), ['1', 'arrive', '카페, 2층']);
    expect(splitCsvLine('1,note,"그가 ""여기"""'), ['1', 'note', '그가 "여기"']);
    expect(splitCsvLine('1,,3'), ['1', '', '3']);
  });

  test('행 수, 처음·마지막 시각, 간격 중앙값·최대, 빈 열을 계산한다', () {
    final stats = statsFromCsvLines('battery.csv', [
      't_ms,charge_uah,current_ua,level_pct,temp_c,plugged',
      '1000,,-250000,87,31.5,0',
      '31000,,-251000,87,31.6,0',
      '61000,,-249000,86,31.6,0',
      '151000,,-250000,86,31.7,0',
    ]);

    expect(stats.rows, 4);
    expect(stats.firstMs, 1000);
    expect(stats.lastMs, 151000);
    expect(stats.span, const Duration(seconds: 150));
    expect(stats.medianGapMs, 30000);
    expect(stats.maxGapMs, 90000);
    expect(stats.emptyColumns, ['charge_uah']);
  });

  test('헤더만 있거나 빈 파일이면 0행이다', () {
    expect(statsFromCsvLines('gps.csv', ['t_ms,lat']).rows, 0);
    expect(statsFromCsvLines('gps.csv', const []).rows, 0);
  });

  test('checkSession은 여섯 파일을 모두 보고, 없는 파일은 0행으로 둔다', () async {
    final dir = await Directory.systemTemp.createTemp('session_check_test');
    addTearDown(() => dir.delete(recursive: true));
    File(p.join(dir.path, 'gps.csv')).writeAsStringSync('t_ms,fix_t_ms,lat\n1000,900,37.5\n2000,1900,37.5\n');

    final stats = await checkSession(dir);
    expect(stats.map((s) => s.file), [
      'gps.csv', 'accel.csv', 'os_steps.csv', 'activity.csv', 'battery.csv', 'marks.csv',
    ]);
    expect(stats.first.rows, 2);
    expect(stats.first.medianGapMs, 1000);
    expect(stats[1].rows, 0);

    final report = formatSessionReport(stats);
    expect(report, contains('gps.csv'));
    expect(report, contains('rows=2'));
    expect(report, contains('median=1000ms'));
  });

  test('따옴표 안에 줄바꿈이 든 필드는 한 행으로 센다', () {
    // 메모에 줄바꿈이 들어가면 readAsLines는 한 행을 두 줄로 쪼갠다.
    final stats = statsFromCsvLines('marks.csv', [
      't_ms,kind,value',
      '1000,note,"첫 줄',
      '둘째 줄"',
      '2000,arrive,',
    ]);

    expect(stats.rows, 2);
    expect(stats.skippedRows, 0);
    expect(stats.firstMs, 1000);
    expect(stats.lastMs, 2000);
  });

  test('시각을 읽을 수 없는 행(서비스가 쓰다 죽은 마지막 줄 등)은 건너뛰고 센다', () {
    final stats = statsFromCsvLines('gps.csv', [
      't_ms,lat',
      '1000,37.5',
      '2000,37.5',
      '179422x',
    ]);

    expect(stats.rows, 2);
    expect(stats.skippedRows, 1);
    expect(stats.lastMs, 2000);
  });

  test('보고서는 건너뛴 행이 있을 때만 skipped를 보여 준다', () {
    final clean = formatSessionReport([const CsvFileStats(file: 'gps.csv', rows: 2)]);
    final damaged = formatSessionReport([const CsvFileStats(file: 'gps.csv', rows: 2, skippedRows: 3)]);

    expect(clean, isNot(contains('skipped')));
    expect(damaged, contains('skipped=3'));
  });

  test('checkSession은 줄바꿈이 든 필드와 깨진 마지막 줄이 있어도 보고서를 낸다', () async {
    final dir = await Directory.systemTemp.createTemp('session_check_damaged');
    addTearDown(() => dir.delete(recursive: true));
    File(p.join(dir.path, 'marks.csv')).writeAsStringSync(
      't_ms,kind,value\n1000,note,"가\n나"\n2000,arrive,\n179422x',
    );

    final marks = (await checkSession(dir)).last;
    expect(marks.rows, 2);
    expect(marks.skippedRows, 1);
  });
}
