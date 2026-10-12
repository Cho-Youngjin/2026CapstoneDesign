import 'package:workmanager/workmanager.dart';

import '../../features/footsteps/background/footstep_workmanager.dart';
import '../../features/rate_alert/background/rate_alert_scheduler.dart';
import '../../features/rate_alert/background/rate_alert_task.dart';

typedef BackgroundTaskRunner = Future<bool> Function();

/// 작업 이름으로 실행할 함수를 고른다. 모르는 이름(예전 버전이 등록한 작업 등)은
/// 성공(true)으로 끝내 WorkManager가 재시도하지 않게 한다.
Future<bool> dispatchBackgroundTask(String taskName, Map<String, BackgroundTaskRunner> runners) {
  final runner = runners[taskName];
  return runner == null ? Future.value(true) : runner();
}

/// WorkManager가 별도 isolate에서 호출하는 top-level 콜백. 앱 전체에 하나만 둘 수 있어
/// 발걸음·환율 알림 작업을 여기서 나눈다(설계 §6.6).
@pragma('vm:entry-point')
void appCallbackDispatcher() {
  Workmanager().executeTask((taskName, _) => dispatchBackgroundTask(taskName, {
        footstepTaskName: runFootstepTask,
        rateAlertTaskName: runRateAlertTask,
      }));
}

/// 앱 시작 시 작업을 등록하기 전에 한 번 부른다.
Future<void> initializeBackgroundWork() => Workmanager().initialize(appCallbackDispatcher);
