import '../events/policy_action.dart';
import '../events/policy_event.dart';
import 'collection_policy.dart';

/// 단순 걸음 트리거(비교 정책). 마지막 측위 뒤 걸음 수가 [stepsPerFix]에 이르면 측위한다.
///
/// 걸음·이동량으로 GPS 켤 시점을 정하는 선행연구 계열(Höpfner & Schirmer, MobiDE 2012; SensTrack, IEEE Sensors J.
/// 2013은 가속도로 추정한 거리)을 단순화한 기준선이다. 제안 정책 step_budget과 같은 예산(E ÷ 보폭 걸음)을 쓰되,
/// step_budget이 더한 것 — 마지막 측위 오차를 예산에서 빼기, 멈춤 확인 측위, 걸음 없는 이동(탈것) 판정 — 이 없다.
/// 그래서 이 정책과 step_budget의 차이가 그 장치들의 효과다. 걸음이 없으면(버스·지하철·멈춤) 측위하지 않는다.
///
/// 측위에 실패하면(지하철·실내) 걸음을 [stepsPerFix]만큼 더 걸은 뒤 재시도한다. 실패한 측위는 걸음 감지기의
/// '마지막 측위 이후 걸음'을 0으로 되돌리지 않아, 그대로 두면 다음 걸음마다 다시 요청하게 된다.
class StepTriggerPolicy implements CollectionPolicy {
  StepTriggerPolicy({this.errorBudgetM = 50, this.strideM = 0.75})
      : stepsPerFix = (errorBudgetM / strideM).ceil();

  final double errorBudgetM;
  final double strideM;

  /// 측위 사이 걸음 수. E 50m·보폭 0.75m면 67걸음이다.
  final int stepsPerFix;

  bool _pending = false;

  /// 이 걸음 수(마지막 성공 측위 이후)에 이르면 측위한다.
  int _threshold = 0;

  /// 감지기가 마지막으로 알린 '마지막 측위 이후 걸음'.
  int _steps = 0;

  @override
  String get id => 'step_trigger';

  @override
  Map<String, Object> get params => {'e_m': errorBudgetM, 'stride_m': strideM};

  @override
  List<PolicyAction> onStart(PolicyContext ctx) {
    _threshold = stepsPerFix;
    _steps = 0;
    _pending = true;
    return const [RequestFix()];
  }

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    switch (event) {
      case StepUpdate(:final stepsSinceLastFix):
        _steps = stepsSinceLastFix;
        if (_pending || _steps < _threshold) return const [];
        _pending = true;
        return const [RequestFix()];
      case FixResult(:final failed):
        _pending = false;
        if (failed) {
          _threshold = _steps + stepsPerFix;
        } else {
          // 성공하면 감지기가 '마지막 측위 이후 걸음'을 0으로 되돌린다.
          _steps = 0;
          _threshold = stepsPerFix;
        }
        return const [];
      default:
        return const [];
    }
  }
}
