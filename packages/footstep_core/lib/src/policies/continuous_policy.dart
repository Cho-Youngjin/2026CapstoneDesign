import '../events/policy_action.dart';
import '../events/policy_event.dart';
import 'collection_policy.dart';

/// 연속 측위. `continuous_10m`은 현재 앱의 실시간 경로 방식(1초, 거리 필터 10m)이다(설계 5-3).
class ContinuousPolicy implements CollectionPolicy {
  ContinuousPolicy({this.id = 'continuous_10m', this.intervalMs = 1000, this.distanceFilterM = 10});

  @override
  final String id;

  final int intervalMs;
  final double distanceFilterM;

  @override
  Map<String, Object> get params =>
      {'interval_ms': intervalMs, 'distance_filter_m': distanceFilterM};

  @override
  List<PolicyAction> onStart(PolicyContext ctx) =>
      [StartContinuous(intervalMs: intervalMs, distanceFilterM: distanceFilterM)];

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) => const [];
}
