import '../events/policy_action.dart';
import '../events/policy_event.dart';
import 'collection_policy.dart';

/// 상용 방식: 구글 활동 인식 연동(설계 2장 D6). 활동 인식이 확실한 정지(STILL)라고 하면 연속 측위를 끄고,
/// 확실한 움직임이면 다시 켠다. 구글이 소개한 Life360 사례와 Transistorsoft 위치 라이브러리의 원리다.
/// 처음에는 움직이는 중으로 보고 켠다 — 정지로 시작하면 활동 인식 첫 결과가 오기 전의 이동을 놓친다.
class ActivityGatedPolicy implements CollectionPolicy {
  ActivityGatedPolicy({this.intervalMs = 1000, this.distanceFilterM = 10});

  static const _moving = {'WALKING', 'RUNNING', 'ON_BICYCLE', 'IN_VEHICLE'};
  static const _confident = {'HIGH', 'MEDIUM'};

  final int intervalMs;
  final double distanceFilterM;
  bool _on = false;

  @override
  String get id => 'activity_gated';

  @override
  Map<String, Object> get params =>
      {'interval_ms': intervalMs, 'distance_filter_m': distanceFilterM};

  StartContinuous get _start =>
      StartContinuous(intervalMs: intervalMs, distanceFilterM: distanceFilterM);

  @override
  List<PolicyAction> onStart(PolicyContext ctx) {
    _on = true;
    return [_start];
  }

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    if (event is! ActivityUpdate || !_confident.contains(event.confidence)) return const [];
    if (event.type == 'STILL' && _on) {
      _on = false;
      return const [StopContinuous()];
    }
    if (_moving.contains(event.type) && !_on) {
      _on = true;
      return [_start];
    }
    return const [];
  }
}
