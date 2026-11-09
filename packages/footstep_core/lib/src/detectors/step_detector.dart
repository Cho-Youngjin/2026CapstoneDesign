import '../events/policy_event.dart';
import '../model/readings.dart';

/// 걸음 감지기(모듈 A, 설계 5-2). 가속도 묶음이나 OS 걸음 읽기를 받아, 상태나 걸음 수가 바뀌었을 때만
/// [StepUpdate]를 돌려준다. 바뀐 게 없으면 null이다.
abstract interface class StepDetector {
  String get id;

  StepState get state;

  int get totalSteps;

  /// 마지막 [onFix] 이후 걸음 수. fixes.csv의 steps_since_prev 열이 된다.
  int get stepsSinceLastFix;

  /// 가속도 묶음(약 1초 분량). [tMs]는 묶음의 마지막 표본 시각이다 — 감지기는 이것을 시계로도 쓴다.
  StepUpdate? onAccel(int tMs, List<AccelReading> batch);

  StepUpdate? onOsStep(OsStepReading reading);

  /// 실행기가 위치를 정책에 알린 직후 부른다.
  void onFix();
}
