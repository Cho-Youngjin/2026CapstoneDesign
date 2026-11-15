import '../events/policy_action.dart';
import '../events/policy_event.dart';
import 'collection_policy.dart';

/// 고정 주기 측위. `hourly`(현재 앱의 WorkManager 1시간 방식)와 `fixed_30s`·`fixed_1m`·`fixed_5m`이
/// 이 정책이다(설계 5-3). 다음 주기는 깨어난 시각 기준으로 잡아 주기가 밀리지 않게 한다.
class FixedIntervalPolicy implements CollectionPolicy {
  FixedIntervalPolicy({required this.id, required this.intervalMs});

  static const _tag = 'tick';

  @override
  final String id;

  final int intervalMs;

  @override
  Map<String, Object> get params => {'interval_s': intervalMs ~/ 1000};

  @override
  List<PolicyAction> onStart(PolicyContext ctx) =>
      [const RequestFix(), WakeAt(tMs: ctx.nowMs + intervalMs, tag: _tag)];

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    if (event is Wakeup && event.tag == _tag) {
      return [const RequestFix(), WakeAt(tMs: event.tMs + intervalMs, tag: _tag)];
    }
    return const [];
  }
}
