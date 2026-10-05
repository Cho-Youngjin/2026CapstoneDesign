import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/db/app_database.dart';
import '../data/footsteps_repository.dart';
import '../data/geocoding_country_resolver.dart';
import 'footstep_task_handler.dart';

const footstepTaskName = 'com.travelfootsteps.footstepCheckin';

/// WorkManager가 별도 isolate에서 호출하는 top-level 콜백.
/// Riverpod 컨테이너에 접근할 수 없으므로 의존성을 직접 만든다.
@pragma('vm:entry-point')
void footstepCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != footstepTaskName) return true;

    final db = AppDatabase();
    final repository = FootstepsRepository(
      db: db,
      countryResolver: GeocodingCountryResolver(),
    );

    await handleFootstepTask(
      repository: repository,
      getCurrentPosition: () => Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // 개발/테스트는 에뮬레이터로 진행 중 — .medium은 raw GPS를 켜지 않아
          // 에뮬레이터 주입 좌표가 전달되지 않는다. 실기기 배포 전 .medium으로 되돌릴 것.
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      ),
    );

    await db.close();
    return true;
  });
}

/// 앱 시작 시 1회 호출한다. 이미 등록돼 있으면 `existingWorkPolicy`가
/// 중복 등록을 막는다.
void registerFootstepBackgroundTask() {
  Workmanager().initialize(footstepCallbackDispatcher);
  Workmanager().registerPeriodicTask(
    footstepTaskName,
    footstepTaskName,
    frequency: const Duration(hours: 1),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.notRequired),
  );
}
