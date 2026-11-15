/// 정책이 돌려주는 할 일(설계 5-1). 실행기(재생 또는 폰)가 실제 동작으로 바꾼다. 테스트가 결과를 목록으로
/// 비교할 수 있게 값으로 비교한다.
sealed class PolicyAction {
  const PolicyAction();

  /// actions.csv의 action 열.
  String get logName;

  /// actions.csv의 args 열(k=v를 공백으로 구분).
  String get logArgs;
}

/// GPS를 켜서 위치를 한 번 받는다. [timeoutMs] 안에 못 받으면 실패다(현재 앱의 측위 제한 15초).
final class RequestFix extends PolicyAction {
  const RequestFix({this.timeoutMs = 15000});

  final int timeoutMs;

  @override
  String get logName => 'request_fix';

  @override
  String get logArgs => 'timeout_ms=$timeoutMs';

  @override
  bool operator ==(Object other) => other is RequestFix && other.timeoutMs == timeoutMs;

  @override
  int get hashCode => Object.hash('RequestFix', timeoutMs);

  @override
  String toString() => 'RequestFix(timeoutMs: $timeoutMs)';
}

/// 연속 측위를 켠다. 위치는 [intervalMs]마다, 마지막으로 알린 위치에서 [distanceFilterM] 이상 움직였을
/// 때만 알린다(안드로이드 위치 요청의 간격·거리 필터와 같은 뜻).
final class StartContinuous extends PolicyAction {
  const StartContinuous({this.intervalMs = 1000, this.distanceFilterM = 0});

  final int intervalMs;
  final double distanceFilterM;

  @override
  String get logName => 'start_continuous';

  @override
  String get logArgs => 'interval_ms=$intervalMs distance_filter_m=$distanceFilterM';

  @override
  bool operator ==(Object other) =>
      other is StartContinuous &&
      other.intervalMs == intervalMs &&
      other.distanceFilterM == distanceFilterM;

  @override
  int get hashCode => Object.hash('StartContinuous', intervalMs, distanceFilterM);

  @override
  String toString() => 'StartContinuous(intervalMs: $intervalMs, distanceFilterM: $distanceFilterM)';
}

/// 연속 측위를 끈다.
final class StopContinuous extends PolicyAction {
  const StopContinuous();

  @override
  String get logName => 'stop_continuous';

  @override
  String get logArgs => '';

  @override
  bool operator ==(Object other) => other is StopContinuous;

  @override
  int get hashCode => 'StopContinuous'.hashCode;

  @override
  String toString() => 'StopContinuous()';
}

/// [tMs]에 Wakeup([tag]) 사건을 보내 달라고 예약한다.
final class WakeAt extends PolicyAction {
  const WakeAt({required this.tMs, required this.tag});

  final int tMs;
  final String tag;

  @override
  String get logName => 'wake_at';

  @override
  String get logArgs => 't_ms=$tMs tag=$tag';

  @override
  bool operator ==(Object other) => other is WakeAt && other.tMs == tMs && other.tag == tag;

  @override
  int get hashCode => Object.hash('WakeAt', tMs, tag);

  @override
  String toString() => 'WakeAt(tMs: $tMs, tag: $tag)';
}
