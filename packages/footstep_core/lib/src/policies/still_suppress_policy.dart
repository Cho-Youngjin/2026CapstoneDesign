import '../events/policy_action.dart';
import '../events/policy_event.dart';
import 'collection_policy.dart';

/// 정지 중 측위 억제(Zhuang 외, MobiSys 2010의 원리). 고정 주기로 측위하되, 걸음 감지기가 정지라고 하면
/// 그 주기의 측위를 건너뛴다. 걸음 정보가 아직 없으면 측위한다.
class StillSuppressPolicy implements CollectionPolicy {
  StillSuppressPolicy({this.intervalMs = 60000});

  static const _tag = 'tick';

  final int intervalMs;
  StepState? _state;

  @override
  String get id => 'still_suppress';

  @override
  Map<String, Object> get params => {'interval_s': intervalMs ~/ 1000};

  @override
  List<PolicyAction> onStart(PolicyContext ctx) =>
      [const RequestFix(), WakeAt(tMs: ctx.nowMs + intervalMs, tag: _tag)];

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    switch (event) {
      case StepUpdate(:final state):
        _state = state;
        return const [];
      case Wakeup(:final tag) when tag == _tag:
        final next = WakeAt(tMs: event.tMs + intervalMs, tag: _tag);
        return _state == StepState.still ? [next] : [const RequestFix(), next];
      default:
        return const [];
    }
  }
}
