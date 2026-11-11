import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

void main() {
  test('설계 문서 5-3의 정책 id로 정책을 만든다', () {
    expect(policyIds, [
      'hourly', 'fixed_30s', 'fixed_1m', 'fixed_5m', 'continuous_10m',
      'speed_adaptive', 'time_speed', 'still_suppress', 'activity_gated', 'step_budget',
    ]);
    for (final id in policyIds) {
      expect(createPolicy(id).id, id);
    }
    expect(createPolicy('hourly').params, {'interval_s': 3600});
    expect(createPolicy('fixed_5m').params, {'interval_s': 300});
  });

  test('파라미터를 받는 정책은 값을 바꿀 수 있다', () {
    expect(createPolicy('time_speed', {'e_m': '25'}).params, {'e_m': 25.0});
    expect(createPolicy('still_suppress', {'interval_s': '120'}).params,
        {'interval_s': 120, 'verify_s': 300});
    expect(createPolicy('still_suppress', {'verify_s': '600'}).params, {'interval_s': 60, 'verify_s': 600});
  });

  test('제안 정책 step_budget은 E·보폭과 절제 실험 스위치를 받는다', () {
    expect(createPolicy('step_budget', {'e_m': '25', 'use_steps': 'false', 'vehicle_probe': '0'}).params, {
      'e_m': 25.0,
      'stride_m': 0.75,
      'use_steps': false,
      'suppress_still': true,
      'vehicle_probe': false,
    });
    expect(createPolicy('step_budget', {'use_steps': 'true', 'suppress_still': '1', 'vehicle_probe': 'false'}).params, {
      'e_m': 50.0,
      'stride_m': 0.75,
      'use_steps': true,
      'suppress_still': true,
      'vehicle_probe': false,
    });
    expect(() => createPolicy('step_budget', {'use_steps': 'no'}), throwsArgumentError);
    expect(() => createPolicy('step_budget', {'e_m': '0'}), throwsArgumentError);
  });

  test('모르는 정책·파라미터·잘못된 숫자는 ArgumentError다', () {
    expect(() => createPolicy('nope'), throwsArgumentError);
    expect(() => createPolicy('fixed_1m', {'e_m': '25'}), throwsArgumentError);
    expect(() => createPolicy('time_speed', {'e_m': 'abc'}), throwsArgumentError);
    expect(() => createPolicy('time_speed', {'e_m': '-5'}), throwsArgumentError);
  });

  test('NaN·Infinity 파라미터는 ArgumentError다', () {
    expect(() => createPolicy('time_speed', {'e_m': 'NaN'}), throwsArgumentError);
    expect(() => createPolicy('time_speed', {'e_m': 'Infinity'}), throwsArgumentError);
    expect(() => createPolicy('still_suppress', {'interval_s': 'Infinity'}), throwsArgumentError);
    expect(() => createPolicy('still_suppress', {'interval_s': 'NaN'}), throwsArgumentError);
  });

  test('설계 문서 5-4의 걸음 감지기 id로 감지기를 만든다', () {
    expect(detectorIds, ['os', 'brajdic', 'adaptive']);
    for (final id in detectorIds) {
      expect(createDetector(id).id, id);
    }
    expect(createDetector('brajdic', {'std_th': '0.8', 'smooth_s': '0.1'}).params,
        {'std_th': 0.8, 'smooth_s': 0.1, 'peak_win_s': 0.59});
    expect(createDetector('adaptive', {'n_confirm': '6', 'ac_th': '0.5'}).params,
        {'std_th': 0.6, 'band_std_th': 0.3, 'ac_th': 0.5, 'n_confirm': 6, 'max_gap_s': 1.5});
  });

  test('모르는 감지기·파라미터·잘못된 숫자는 ArgumentError다', () {
    expect(() => createDetector('nope'), throwsArgumentError);
    expect(() => createDetector('os', {'std_th': '0.6'}), throwsArgumentError);
    expect(() => createDetector('adaptive', {'n_confirm': '2.5'}), throwsArgumentError);
    expect(() => createDetector('adaptive', {'n_confirm': '0'}), throwsArgumentError);
    expect(() => createDetector('brajdic', {'std_th': 'NaN'}), throwsArgumentError);
  });
}
