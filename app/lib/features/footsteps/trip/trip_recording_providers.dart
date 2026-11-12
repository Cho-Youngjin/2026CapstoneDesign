import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import 'trip_recording_coordinator.dart';
import 'trip_recording_permissions.dart';
import 'trip_recording_service.dart';
import 'trip_recording_store.dart';

final tripRecordingStoreProvider = Provider<TripRecordingStore>(
  (ref) => TripRecordingStore(ref.watch(sharedPreferencesProvider)),
);

final tripRecordingServiceProvider =
    Provider<TripRecordingService>((ref) => const ForegroundTripRecordingService());

final tripRecordingPermissionsProvider =
    Provider<TripRecordingPermissions>((ref) => const PermissionHandlerTripRecordingPermissions());

/// 작업을 한 줄로 세우는 객체라 앱 전체에 하나만 둔다.
final tripRecordingCoordinatorProvider = Provider<TripRecordingCoordinator>(
  (ref) => TripRecordingCoordinator(
    store: ref.watch(tripRecordingStoreProvider),
    service: ref.watch(tripRecordingServiceProvider),
    permissions: ref.watch(tripRecordingPermissionsProvider),
  ),
);
