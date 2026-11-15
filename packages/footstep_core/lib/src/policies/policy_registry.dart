import '../params.dart';
import 'activity_gated_policy.dart';
import 'collection_policy.dart';
import 'continuous_policy.dart';
import 'fixed_interval_policy.dart';
import 'speed_adaptive_policy.dart';
import 'step_budget_policy.dart';
import 'still_suppress_policy.dart';
import 'time_speed_policy.dart';

/// 재생기 CLI와 정책 실행 모드가 받는 정책 id(설계 문서 5-3의 표). 마지막 `step_budget`이 제안 정책이다.
const policyIds = [
  'hourly', 'fixed_30s', 'fixed_1m', 'fixed_5m', 'continuous_10m',
  'speed_adaptive', 'time_speed', 'time_speed_still', 'still_suppress', 'activity_gated', 'step_budget',
];

/// id와 파라미터(문자열 k=v)로 정책을 만든다. 모르는 id·파라미터, 양수가 아닌 숫자는 ArgumentError다.
CollectionPolicy createPolicy(String id, [Map<String, String> params = const {}]) {
  final reader = ParamReader('정책 $id', params);
  switch (id) {
    case 'hourly':
      reader.allowOnly(const {});
      return FixedIntervalPolicy(id: id, intervalMs: 3600000);
    case 'fixed_30s':
      reader.allowOnly(const {});
      return FixedIntervalPolicy(id: id, intervalMs: 30000);
    case 'fixed_1m':
      reader.allowOnly(const {});
      return FixedIntervalPolicy(id: id, intervalMs: 60000);
    case 'fixed_5m':
      reader.allowOnly(const {});
      return FixedIntervalPolicy(id: id, intervalMs: 300000);
    case 'continuous_10m':
      reader.allowOnly(const {});
      return ContinuousPolicy();
    case 'speed_adaptive':
      reader.allowOnly(const {});
      return SpeedAdaptivePolicy();
    case 'time_speed':
      reader.allowOnly(const {'e_m'});
      return TimeSpeedPolicy(errorBudgetM: reader.positive('e_m', 50));
    case 'time_speed_still':
      reader.allowOnly(const {'e_m'});
      return TimeSpeedPolicy(errorBudgetM: reader.positive('e_m', 50), stillGate: true);
    case 'still_suppress':
      reader.allowOnly(const {'interval_s', 'verify_s'});
      return StillSuppressPolicy(
        intervalMs: (reader.positive('interval_s', 60) * 1000).round(),
        verifyMs: (reader.positive('verify_s', 300) * 1000).round(),
      );
    case 'activity_gated':
      reader.allowOnly(const {});
      return ActivityGatedPolicy();
    case 'step_budget':
      reader.allowOnly(const {'e_m', 'stride_m', 'use_steps', 'suppress_still', 'vehicle_probe'});
      return StepBudgetPolicy(
        errorBudgetM: reader.positive('e_m', 50),
        strideM: reader.positive('stride_m', 0.75),
        useSteps: reader.flag('use_steps', true),
        suppressStill: reader.flag('suppress_still', true),
        vehicleProbe: reader.flag('vehicle_probe', true),
      );
    default:
      throw ArgumentError('알 수 없는 정책: $id (가능: ${policyIds.join(', ')})');
  }
}
