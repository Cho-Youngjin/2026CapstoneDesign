import 'footsteps_api.dart';
import 'footsteps_repository.dart';

Future<void> syncFootsteps({
  required FootstepsRepository repository,
  required FootstepsApi api,
}) async {
  final unsyncedCheckins = await repository.unsyncedCheckins();
  if (unsyncedCheckins.isNotEmpty) {
    final serverIds = await api.pushCheckins(unsyncedCheckins);
    for (final entry in serverIds.entries) {
      await repository.markCheckinSynced(entry.key, entry.value);
    }
  }

  final unsyncedDailySteps = await repository.unsyncedDailySteps();
  if (unsyncedDailySteps.isNotEmpty) {
    final serverIds = await api.pushDailySteps(unsyncedDailySteps);
    for (final entry in serverIds.entries) {
      await repository.markDailyStepsSynced(entry.key, entry.value);
    }
  }
}
