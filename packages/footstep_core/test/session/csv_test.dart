import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

void main() {
  test('따옴표 안의 쉼표·이중 따옴표를 한 필드로 읽는다', () {
    expect(splitCsvLine('1,arrive,"카페, 2층"'), ['1', 'arrive', '카페, 2층']);
    expect(splitCsvLine('1,note,"그가 ""여기"""'), ['1', 'note', '그가 "여기"']);
    expect(splitCsvLine('1,,3'), ['1', '', '3']);
  });

  test('따옴표 안 줄바꿈으로 쪼개진 줄을 한 행으로 합친다', () {
    expect(
      csvRecords(['t_ms,kind,value', '1,note,"첫 줄', '둘째 줄"', '2,arrive,']),
      ['t_ms,kind,value', '1,note,"첫 줄\n둘째 줄"', '2,arrive,'],
    );
  });

  test('닫히지 않은 꼬리는 깨진 행 하나로 남긴다', () {
    expect(csvRecords(['1,note,"끝나지 않음']), ['1,note,"끝나지 않음']);
  });

  test('formatCsvField로 쓴 행을 splitCsvLine이 그대로 되읽는다', () {
    final fields = ['카페, 2층', '그가 "여기"', '', '37.5'];
    expect(splitCsvLine(fields.map(formatCsvField).join(',')), fields);
  });

  test('formatCsvField: null·NaN은 빈칸, bool은 1/0', () {
    expect(formatCsvField(null), '');
    expect(formatCsvField(double.nan), '');
    expect(formatCsvField(true), '1');
    expect(formatCsvField(false), '0');
    expect(formatCsvField(1762650000000), '1762650000000');
  });

  test('세션 스키마는 설계 문서 4-2의 파일 이름과 헤더다', () {
    expect(SessionSchema.gpsFile, 'gps.csv');
    expect(SessionSchema.gpsHeader,
        ['t_ms', 'fix_t_ms', 'lat', 'lng', 'accuracy_m', 'speed_mps', 'bearing_deg', 'altitude_m']);
    expect(SessionSchema.batteryHeader,
        ['t_ms', 'charge_uah', 'current_ua', 'level_pct', 'temp_c', 'plugged']);
    expect(SessionSchema.metaFile, 'meta.json');
  });
}
