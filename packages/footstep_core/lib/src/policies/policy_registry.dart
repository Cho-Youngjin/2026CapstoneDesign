import 'activity_gated_policy.dart';
import 'collection_policy.dart';
import 'continuous_policy.dart';
import 'fixed_interval_policy.dart';
import 'speed_adaptive_policy.dart';
import 'still_suppress_policy.dart';
import 'time_speed_policy.dart';

/// 재생기 CLI가 받는 정책 id(설계 문서 5-3의 표). R4가 제안 정책 `step_budget`을 더한다.
const policyIds = [
  'hourly', 'fixed_30s', 'fixed_1m', 'fixed_5m', 'continuous_10m',
  'speed_adaptive', 'time_speed', 'still_suppress', 'activity_gated',
];

/// id와 파라미터(문자열 k=v)로 정책을 만든다. 모르는 id·파라미터, 양수가 아닌 숫자는 ArgumentError다 —
/// 실험 설정 오타로 엉뚱한 기본값이 조용히 쓰이는 것을 막는다.
CollectionPolicy createPolicy(String id, [Map<String, String> params = const {}]) {
  void allowOnly(Set<String> keys) {
    final unknown = params.keys.where((k) => !keys.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw ArgumentError('정책 $id에 없는 파라미터: ${unknown.join(', ')}');
    }
  }

  double positive(String key, double fallback) {
    final raw = params[key];
    if (raw == null) return fallback;
    final value = double.tryParse(raw);
    if (value == null || value <= 0) throw ArgumentError('$key는 양수여야 합니다: $raw');
    return value;
  }

  switch (id) {
    case 'hourly':
      allowOnly(const {});
      return FixedIntervalPolicy(id: id, intervalMs: 3600000);
    case 'fixed_30s':
      allowOnly(const {});
      return FixedIntervalPolicy(id: id, intervalMs: 30000);
    case 'fixed_1m':
      allowOnly(const {});
      return FixedIntervalPolicy(id: id, intervalMs: 60000);
    case 'fixed_5m':
      allowOnly(const {});
      return FixedIntervalPolicy(id: id, intervalMs: 300000);
    case 'continuous_10m':
      allowOnly(const {});
      return ContinuousPolicy();
    case 'speed_adaptive':
      allowOnly(const {});
      return SpeedAdaptivePolicy();
    case 'time_speed':
      allowOnly(const {'e_m'});
      return TimeSpeedPolicy(errorBudgetM: positive('e_m', 50));
    case 'still_suppress':
      allowOnly(const {'interval_s'});
      return StillSuppressPolicy(intervalMs: (positive('interval_s', 60) * 1000).round());
    case 'activity_gated':
      allowOnly(const {});
      return ActivityGatedPolicy();
    default:
      throw ArgumentError('알 수 없는 정책: $id (가능: ${policyIds.join(', ')})');
  }
}
