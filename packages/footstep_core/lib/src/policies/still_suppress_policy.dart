import '../events/policy_action.dart';
import '../events/policy_event.dart';
import 'collection_policy.dart';

/// 정지 중 측위 억제(Zhuang 외, "Improving Energy Efficiency of Location Sensing on Smartphones",
/// MobiSys 2010의 Sensing suppRession). [intervalMs](1분)마다 상태를 확인해 측위하되, 직전 확인과 이번 확인이
/// 모두 정지일 때만 측위를 건너뛴다(원문 그림 10(b) 8~9행 — 정지가 한 번만 보이면 잠깐 멈춘 것일 수 있다).
/// 억제하는 동안에도 [verifyMs]마다 확인 측위를 한다(원문 3.2절의 확인 장치). 확인 주기는 원문에 값이 없어
/// 제안 정책(step_budget)의 정지 확인 주기 5분과 맞춘다. 원문은 확인 때마다 몇 초씩 가속도를 읽지만,
/// 이 정책은 걸음 감지기가 알려 준 상태를 쓴다. 걸음 정보가 아직 없으면 측위한다.
class StillSuppressPolicy implements CollectionPolicy {
  StillSuppressPolicy({this.intervalMs = 60000, this.verifyMs = 300000});

  static const _tag = 'tick';

  final int intervalMs;
  final int verifyMs;

  StepState? _state;
  bool _previousTickStill = false;
  int _lastRequestMs = 0;

  @override
  String get id => 'still_suppress';

  @override
  Map<String, Object> get params => {'interval_s': intervalMs ~/ 1000, 'verify_s': verifyMs ~/ 1000};

  @override
  List<PolicyAction> onStart(PolicyContext ctx) {
    // 같은 인스턴스를 다시 써도 이전 실행의 상태가 남아 첫 판단을 흐리지 않게 한다.
    _state = null;
    _previousTickStill = false;
    _lastRequestMs = ctx.nowMs;
    return [const RequestFix(), WakeAt(tMs: ctx.nowMs + intervalMs, tag: _tag)];
  }

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    switch (event) {
      case StepUpdate(:final state):
        _state = state;
        return const [];
      case Wakeup(:final tag) when tag == _tag:
        final next = WakeAt(tMs: event.tMs + intervalMs, tag: _tag);
        final still = _state == StepState.still;
        final suppress = still && _previousTickStill;
        _previousTickStill = still;
        if (suppress && event.tMs - _lastRequestMs < verifyMs) return [next];
        _lastRequestMs = event.tMs;
        return [const RequestFix(), next];
      default:
        return const [];
    }
  }
}
