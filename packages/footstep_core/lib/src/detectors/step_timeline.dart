/// 걸음마다 시각을 알려 주는 감지기. 걸음 감지 평가(steps.csv)에 쓴다. StepUpdate는 묶음 끝 시각에 나오고
/// 소급 카운트한 걸음도 그 시각에 더해지므로, 걸음 세기 구간 경계에서 개수를 정확히 나누려면 걸음 자체의
/// 시각이 필요하다.
abstract interface class StepTimeline {
  /// 마지막으로 부른 뒤 새로 센 걸음의 시각(소급분 포함). 부르면 비운다.
  List<int> takeStepTimes();
}
