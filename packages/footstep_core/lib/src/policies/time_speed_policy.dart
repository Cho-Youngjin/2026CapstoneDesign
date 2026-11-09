import 'dart:math' as math;

import '../events/policy_action.dart';
import '../events/policy_event.dart';
import 'collection_policy.dart';

/// 시간 × 속도 오차 추정 측위(EnTracked, MobiSys 2009 · RAPS, MobiSys 2010의 원리).
/// '마지막 측위 오차 + 속도 × 경과 시간'이 오차 예산 E를 넘는 시각에 다시 측위한다.
/// 속도는 마지막 측위의 속도를 쓰되 걷기 속도 1.4m/s를 하한으로 둔다 — 서 있다가 걷기 시작해도 오차가 예산을
/// 넘기 전에 다시 재기 위해서다. 제안 정책(R4)은 이 '시간 × 속도' 대신 실제 걸음 수를 쓴다.
class TimeSpeedPolicy implements CollectionPolicy {
  TimeSpeedPolicy({
    this.errorBudgetM = 50,
    this.minSpeedMps = 1.4,
    this.minWaitMs = 5000,
    this.maxWaitMs = 600000,
    this.failureRetryMs = 30000,
  });

  static const _tag = 'next';

  final double errorBudgetM;
  final double minSpeedMps;
  final int minWaitMs;
  final int maxWaitMs;
  final int failureRetryMs;

  @override
  String get id => 'time_speed';

  @override
  Map<String, Object> get params => {'e_m': errorBudgetM};

  @override
  List<PolicyAction> onStart(PolicyContext ctx) => [const RequestFix()];

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    switch (event) {
      case FixResult(:final fix):
        final waitMs = fix == null
            ? failureRetryMs
            : _waitFor(fix.accuracyM, fix.speedMps ?? 0);
        return [WakeAt(tMs: event.tMs + waitMs, tag: _tag)];
      case Wakeup(:final tag) when tag == _tag:
        return [const RequestFix()];
      default:
        return const [];
    }
  }

  int _waitFor(double accuracyM, double speedMps) {
    final remainingM = errorBudgetM - accuracyM;
    if (remainingM <= 0) return minWaitMs;
    final speed = math.max(speedMps, minSpeedMps);
    final waitMs = (remainingM / speed * 1000).round();
    return waitMs.clamp(minWaitMs, maxWaitMs);
  }
}
