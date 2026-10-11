import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

/// WorkManager 작업 이름. 발걸음 작업(com.travelfootsteps.footstepCheckin)과 같은 규칙.
const rateAlertTaskName = 'com.travelfootsteps.rateAlert';

/// 환율 알림 백그라운드 작업 등록/취소(설계 §6.3).
abstract interface class RateAlertScheduler {
  /// [enabled]면 3시간 주기 작업을 등록하고(이미 있으면 그대로 둔다), 아니면 취소한다.
  Future<void> sync({required bool enabled});
}

class WorkmanagerRateAlertScheduler implements RateAlertScheduler {
  const WorkmanagerRateAlertScheduler();

  @override
  Future<void> sync({required bool enabled}) {
    if (!enabled) return Workmanager().cancelByUniqueName(rateAlertTaskName);
    return Workmanager().registerPeriodicTask(
      rateAlertTaskName,
      rateAlertTaskName,
      // 고시 환율은 하루 1회 바뀌지만, 고시 시각(11시경)이 지나면 몇 시간 안에 알리려고 3시간마다 확인한다.
      frequency: const Duration(hours: 3),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }
}

final rateAlertSchedulerProvider = Provider<RateAlertScheduler>((ref) {
  return const WorkmanagerRateAlertScheduler();
});
