import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

void main() {
  test('설계 문서 5-3의 정책 id로 정책을 만든다', () {
    expect(policyIds, [
      'hourly', 'fixed_30s', 'fixed_1m', 'fixed_5m', 'continuous_10m',
      'speed_adaptive', 'time_speed', 'still_suppress', 'activity_gated',
    ]);
    for (final id in policyIds) {
      expect(createPolicy(id).id, id);
    }
    expect(createPolicy('hourly').params, {'interval_s': 3600});
    expect(createPolicy('fixed_5m').params, {'interval_s': 300});
  });

  test('파라미터를 받는 정책은 값을 바꿀 수 있다', () {
    expect(createPolicy('time_speed', {'e_m': '25'}).params, {'e_m': 25.0});
    expect(createPolicy('still_suppress', {'interval_s': '120'}).params, {'interval_s': 120});
  });

  test('모르는 정책·파라미터·잘못된 숫자는 ArgumentError다', () {
    expect(() => createPolicy('nope'), throwsArgumentError);
    expect(() => createPolicy('fixed_1m', {'e_m': '25'}), throwsArgumentError);
    expect(() => createPolicy('time_speed', {'e_m': 'abc'}), throwsArgumentError);
    expect(() => createPolicy('time_speed', {'e_m': '-5'}), throwsArgumentError);
  });

  test('걸음 감지기 id로 감지기를 만든다', () {
    expect(detectorIds, ['os']);
    expect(createDetector('os').id, 'os');
    expect(() => createDetector('adaptive'), throwsArgumentError);
  });
}
