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
}
