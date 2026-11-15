import '../model/fix.dart';

/// 걸음 감지기가 판단한 지금 상태(설계 5-2). otherMotion은 흔들림은 있는데 걸음 박자가 없을 때다(탈것 의심).
enum StepState { still, walking, otherMotion }

/// 정책이 받는 사건. [tMs]는 사건이 일어난 시각이다.
sealed class PolicyEvent {
  const PolicyEvent({required this.tMs});

  final int tMs;
}

/// 걸음 감지기의 상태나 걸음 수가 바뀌었다.
final class StepUpdate extends PolicyEvent {
  const StepUpdate({
    required super.tMs,
    required this.state,
    required this.totalSteps,
    required this.stepsSinceLastFix,
    this.cadenceHz,
  });

  final StepState state;
  final int totalSteps;
  final int stepsSinceLastFix;

  /// 초당 걸음 수. 감지기가 모르면 null이다(OS 센서판).
  final double? cadenceHz;
}

/// 구글 활동 인식 결과가 들어왔다.
final class ActivityUpdate extends PolicyEvent {
  const ActivityUpdate({required super.tMs, required this.type, required this.confidence});

  final String type;
  final String confidence;
}

/// 정책이 낸 RequestFix의 결과. [fix]가 null이면 제한 시간 안에 위치를 못 받았다.
final class FixResult extends PolicyEvent {
  const FixResult({required super.tMs, this.fix});

  final Fix? fix;

  bool get failed => fix == null;
}

/// 연속 측위 중 들어온 위치.
final class ContinuousFix extends PolicyEvent {
  const ContinuousFix({required super.tMs, required this.fix});

  final Fix fix;
}

/// 정책이 WakeAt으로 예약한 시각이 됐다.
final class Wakeup extends PolicyEvent {
  const Wakeup({required super.tMs, required this.tag});

  final String tag;
}

/// 배터리 잔량(%)이 바뀌었다.
final class BatteryLevel extends PolicyEvent {
  const BatteryLevel({required super.tMs, required this.pct});

  final int pct;
}
