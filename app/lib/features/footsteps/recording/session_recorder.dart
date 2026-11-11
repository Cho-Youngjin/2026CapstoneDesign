import 'mark.dart';
import 'recorder_status.dart';

/// 기록 서비스가 모드와 상관없이 기록기를 다루는 창구(정답 기록·정책 실행). 서비스는 시작·5초 tick·관찰 표시·
/// 종료만 알면 되고, 어떤 센서를 켜고 무엇을 쓸지는 모드별 기록기가 정한다.
abstract interface class SessionRecorder {
  /// 지금 장소 안인지, 탈것에 탔는지. 알림 버튼 토글이 다음 표시를 정할 때 쓴다.
  FieldState get field;

  Future<void> start();

  /// 서비스의 반복 이벤트(5초)마다 부른다. 배터리 읽기와 디스크 쓰기를 맡긴다.
  Future<void> tick();

  void mark(Mark mark);

  RecorderStatus get status;

  Future<void> stop();
}
