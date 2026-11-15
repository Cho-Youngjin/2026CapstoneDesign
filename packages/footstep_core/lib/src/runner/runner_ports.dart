import '../model/fix.dart';
import '../replay/replay_result.dart';

/// 실행기가 GPS를 다루는 창구. 폰에서는 geolocator, 테스트에서는 가짜를 넣는다.
abstract interface class LocationPort {
  /// 위치를 한 번 받는다. [timeoutMs] 안에 못 받으면 null이다.
  Future<Fix?> currentFix({required int timeoutMs});

  /// 연속 측위. [intervalMs]·[distanceFilterM]은 기기의 위치 요청 설정으로 넘긴다. 구독을 끊으면 GPS를 끈다.
  Stream<Fix> continuousFixes({required int intervalMs, required double distanceFilterM});
}

/// 깨우기 예약. 폰에서는 Timer, 테스트에서는 시간을 손으로 넘기는 가짜를 쓴다.
abstract interface class WakeScheduler {
  /// [atMs](UTC epoch ms, 지났으면 바로)에 [callback]을 부른다. [schedule] 안에서 바로 부르지는 않는다.
  /// 돌려준 값을 [cancel]에 넘겨 취소한다.
  Object schedule(int atMs, void Function() callback);

  void cancel(Object handle);
}

/// 깨우기 하나의 기록(wakeups.csv의 행). 화면이 꺼지면 타이머가 늦게 깰 수 있어(설계 10장 위험 3) 예약 시각과
/// 실제 깬 시각을 함께 남긴다.
class WakeupRecord {
  const WakeupRecord({required this.tMs, required this.tag, required this.scheduledMs});

  /// 실제로 깬 시각.
  final int tMs;
  final String tag;
  final int scheduledMs;

  int get delayMs => tMs - scheduledMs;
}

/// 실행기가 남기는 기록을 받는 곳. 폰에서는 세션 폴더의 CSV에 쓴다.
abstract interface class RunnerSink {
  void fix(FixRecord record);

  void action(ActionRecord record);

  void wakeup(WakeupRecord record);
}

/// 정책 실행 모드가 세션 폴더에 쓰는 파일 중 재생기에 없는 것(R6 분석이 읽는다). fixes.csv·actions.csv는
/// 재생기와 같은 형식([ReplaySchema])이다.
abstract final class RunnerSchema {
  static const wakeupsFile = 'wakeups.csv';
  static const wakeupsHeader = ['t_ms', 'tag', 'scheduled_ms', 'delay_ms'];
}
