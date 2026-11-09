import '../events/policy_action.dart';
import '../events/policy_event.dart';
import '../model/fix.dart';

/// 정책이 판단할 때 쓰는 현재 정보. [lastFix]는 실행기가 마지막으로 정책에 알린 위치다(단발·연속 모두).
class PolicyContext {
  const PolicyContext({required this.nowMs, this.lastFix});

  final int nowMs;
  final Fix? lastFix;
}

/// 수집 정책(설계 5-1). 시계·GPS·타이머를 직접 쓰지 않고, 사건을 받아 할 일만 돌려준다 — 그래서 같은 정책을
/// 폰 실행기와 PC 재생기에서 똑같이 돌릴 수 있다.
abstract interface class CollectionPolicy {
  /// 정책 id(설계 5-3의 표). summary.json과 결과 폴더 이름에 쓴다.
  String get id;

  /// 결과에 함께 남길 파라미터(예: {'e_m': 50.0}).
  Map<String, Object> get params;

  List<PolicyAction> onStart(PolicyContext ctx);

  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx);
}

/// 정책이 지금 상태를 이름으로 알려 준다(fixes.csv의 state 열). 구현하지 않은 정책은 걸음 감지기 상태를 쓴다.
/// 제안 정책(R4)은 걸음 감지기에 없는 'vehicle' 상태를 이걸로 알린다.
abstract interface class ReportsState {
  String get stateLabel;
}
