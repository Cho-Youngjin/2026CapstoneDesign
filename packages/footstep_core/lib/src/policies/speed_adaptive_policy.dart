import '../events/policy_action.dart';
import '../events/policy_event.dart';
import 'collection_policy.dart';

/// 속도 적응 측위(Galeana-Zapién 외, Sensors 2014의 원리). 마지막 측위의 속도 구간에 따라 다음 측위 간격을
/// 정한다. 구간 경계와 간격은 우리 재현값이다(정지 0.5m/s 미만 → 2분, 보행 → 30초, 시속 9km 이상 → 10초).
/// 예비용 세션으로 조정할 수 있게 생성자 파라미터로 둔다.
class SpeedAdaptivePolicy implements CollectionPolicy {
  SpeedAdaptivePolicy({
    this.stillSpeedMps = 0.5,
    this.vehicleSpeedMps = 2.5,
    this.stillIntervalMs = 120000,
    this.walkIntervalMs = 30000,
    this.vehicleIntervalMs = 10000,
    this.failureRetryMs = 30000,
  });

  static const _tag = 'next';

  final double stillSpeedMps;
  final double vehicleSpeedMps;
  final int stillIntervalMs;
  final int walkIntervalMs;
  final int vehicleIntervalMs;
  final int failureRetryMs;

  @override
  String get id => 'speed_adaptive';

  @override
  Map<String, Object> get params => {
        'still_speed_mps': stillSpeedMps,
        'vehicle_speed_mps': vehicleSpeedMps,
        'still_interval_s': stillIntervalMs ~/ 1000,
        'walk_interval_s': walkIntervalMs ~/ 1000,
        'vehicle_interval_s': vehicleIntervalMs ~/ 1000,
      };

  @override
  List<PolicyAction> onStart(PolicyContext ctx) => [const RequestFix()];

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    switch (event) {
      case FixResult(:final fix):
        final waitMs = fix == null ? failureRetryMs : _intervalFor(fix.speedMps);
        return [WakeAt(tMs: event.tMs + waitMs, tag: _tag)];
      case Wakeup(:final tag) when tag == _tag:
        return [const RequestFix()];
      default:
        return const [];
    }
  }

  int _intervalFor(double? speedMps) {
    // 속도를 모르면 보행으로 본다 — 정지로 보면 움직이는 사람의 경로를 2분씩 놓친다.
    if (speedMps == null) return walkIntervalMs;
    if (speedMps < stillSpeedMps) return stillIntervalMs;
    if (speedMps >= vehicleSpeedMps) return vehicleIntervalMs;
    return walkIntervalMs;
  }
}
