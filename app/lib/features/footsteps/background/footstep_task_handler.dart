import 'package:geolocator/geolocator.dart';

import '../data/checkin.dart';
import '../data/footsteps_repository.dart';

/// WorkManager 콜백의 실제 판단 로직. isolate 엔트리포인트에서 분리해
/// 단위 테스트가 가능하게 한다.
///
/// 여행 기간에만 체크인한다(설계 2026-11-07 9-2). 작업은 늘 등록해 두되, [isTripPeriod]가 false면 측위 없이 끝낸다 —
/// 여행이 아닌 날 1시간마다 GPS를 켜지 않는다.
Future<void> handleFootstepTask({
  required FootstepsRepository repository,
  required Future<Position> Function() getCurrentPosition,
  required Future<bool> Function() isTripPeriod,
}) async {
  try {
    if (!await isTripPeriod()) return;
    final position = await getCurrentPosition();
    await repository.recordCheckinAt(
      position.latitude,
      position.longitude,
      DateTime.now().toUtc(),
      CheckinSource.auto,
    );
  } catch (_) {
    // 권한 거부, GPS 꺼짐, 오프라인 등. 다음 1시간 주기가 다시 시도하므로
    // 여기서 재시도하지 않는다 — WorkManager에 실패로 보고하면 짧은
    // 백오프로 재시도가 몰려 배터리를 더 쓰게 된다.
  }
}
