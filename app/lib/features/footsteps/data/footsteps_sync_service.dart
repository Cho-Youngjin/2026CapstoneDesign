import 'footsteps_api.dart';
import 'footsteps_repository.dart';

/// 로컬에 쌓인 체크인·걸음 수를 서버로 올린다.
///
/// 체크인 업로드 실패가 걸음 수 동기화까지 막지 않도록 둘을 분리한다. 서버 country
/// 테이블에 없는 국가 코드(판정 실패 시의 `XX`, seed에 없는 `KR` 등)가 한 줄이라도
/// 섞이면 배치 전체가 400으로 거부되는데, 예전에는 그 줄이 영구히 재시도되면서
/// 이후 모든 체크인과 걸음 수 동기화가 멈췄다.
Future<void> syncFootsteps({
  required FootstepsRepository repository,
  required FootstepsApi api,
}) async {
  await _pushCheckins(repository, api);
  await _pushDailySteps(repository, api);
}

Future<void> _pushCheckins(FootstepsRepository repository, FootstepsApi api) async {
  final unsynced = await repository.unsyncedCheckins();
  if (unsynced.isEmpty) return;

  try {
    final serverIds = await api.pushCheckins(unsynced);
    for (final entry in serverIds.entries) {
      await repository.markCheckinSynced(entry.key, entry.value);
    }
    return;
  } catch (_) {
    // 배치가 통째로 거부됐다. 서버가 어느 줄이 문제인지 알려주지 않으므로 한 줄씩
    // 다시 보내, 정상인 줄은 통과시키고 거부되는 줄만 미동기화로 남긴다.
  }

  for (final checkin in unsynced) {
    try {
      final serverIds = await api.pushCheckins([checkin]);
      for (final entry in serverIds.entries) {
        await repository.markCheckinSynced(entry.key, entry.value);
      }
    } catch (_) {
      // 이 줄만 건너뛴다 — 다음 동기화에서 다시 시도된다.
    }
  }
}

Future<void> _pushDailySteps(FootstepsRepository repository, FootstepsApi api) async {
  final unsynced = await repository.unsyncedDailySteps();
  if (unsynced.isEmpty) return;

  final serverIds = await api.pushDailySteps(unsynced);
  for (final entry in serverIds.entries) {
    await repository.markDailyStepsSynced(entry.key, entry.value);
  }
}
