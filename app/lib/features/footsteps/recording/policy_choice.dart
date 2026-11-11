import 'package:flutter/foundation.dart' show mapEquals;

/// 정책 실행 모드에서 고른 정책·걸음 감지기와 파라미터. 파라미터는 문자열 k=v 그대로 두고, 해석은
/// footstep_core의 정책·감지기 목록(createPolicy·createDetector)이 맡는다 — 재생기와 같은 이름·검사를 쓴다.
class PolicyChoice {
  const PolicyChoice({
    required this.policyId,
    required this.detectorId,
    this.policyParams = const {},
    this.detectorParams = const {},
  });

  final String policyId;
  final String detectorId;
  final Map<String, String> policyParams;
  final Map<String, String> detectorParams;

  Map<String, Object?> toJson() => {
        'policyId': policyId,
        'policyParams': policyParams,
        'detectorId': detectorId,
        'detectorParams': detectorParams,
      };

  factory PolicyChoice.fromJson(Map<String, Object?> json) => PolicyChoice(
        policyId: json['policyId'] as String,
        detectorId: json['detectorId'] as String,
        policyParams: Map<String, String>.from(json['policyParams'] as Map? ?? const {}),
        detectorParams: Map<String, String>.from(json['detectorParams'] as Map? ?? const {}),
      );

  @override
  bool operator ==(Object other) =>
      other is PolicyChoice &&
      other.policyId == policyId &&
      other.detectorId == detectorId &&
      mapEquals(other.policyParams, policyParams) &&
      mapEquals(other.detectorParams, detectorParams);

  @override
  int get hashCode => Object.hash(
        policyId,
        detectorId,
        Object.hashAllUnordered(policyParams.entries.map((e) => '${e.key}=${e.value}')),
        Object.hashAllUnordered(detectorParams.entries.map((e) => '${e.key}=${e.value}')),
      );

  @override
  String toString() => 'PolicyChoice($policyId $policyParams, $detectorId $detectorParams)';
}

/// 정책 실행 모드에서 켤 센서. 쓰지 않는 센서를 켜면 그 전력이 배터리 측정에 섞인다(설계 5-5).
class PolicySensorNeeds {
  const PolicySensorNeeds({required this.accel, required this.osSteps, required this.activity});

  /// 걸음 정보(StepUpdate)를 쓰는 정책. 나머지 정책은 걸음 감지기를 돌려도 결과가 같아 센서를 켜지 않는다.
  static const stepPolicyIds = {'still_suppress', 'step_budget'};

  final bool accel;
  final bool osSteps;
  final bool activity;

  /// 걸음 정보를 쓰는 정책만 걸음 감지기의 센서를 켠다 — OS 센서판이면 걸음 센서, 가속도판(brajdic·adaptive)이면
  /// 가속도. 활동 인식은 그것을 쓰는 activity_gated만 켠다.
  factory PolicySensorNeeds.of(PolicyChoice choice) {
    final usesSteps = stepPolicyIds.contains(choice.policyId);
    return PolicySensorNeeds(
      accel: usesSteps && choice.detectorId != 'os',
      osSteps: usesSteps && choice.detectorId == 'os',
      activity: choice.policyId == 'activity_gated',
    );
  }
}
