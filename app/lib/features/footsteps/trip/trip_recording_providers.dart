import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_user.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/prefs/shared_preferences_provider.dart';
import '../../visa/notifications/alarm_scheduler.dart';
import 'trip_departure_notices.dart';
import 'trip_recording_coordinator.dart';
import 'trip_recording_permissions.dart';
import 'trip_recording_service.dart';
import 'trip_recording_store.dart';

/// 날짜별 보기·여행 상세가 "오늘"을 정할 때 쓰는 시계. 위젯 테스트가 날짜를 고정한다.
final tripClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final tripRecordingStoreProvider = Provider<TripRecordingStore>(
  (ref) => TripRecordingStore(ref.watch(sharedPreferencesProvider)),
);

final tripRecordingServiceProvider =
    Provider<TripRecordingService>((ref) => const ForegroundTripRecordingService());

final tripRecordingPermissionsProvider =
    Provider<TripRecordingPermissions>((ref) => const PermissionHandlerTripRecordingPermissions());

final tripDepartureNoticesProvider = Provider<TripDepartureNotices>(
  (ref) => TripDepartureNotices(
    LocalAlarmBackend(null, tripNoticeDetails),
    ref.watch(tripRecordingStoreProvider),
  ),
);

/// 작업을 한 줄로 세우는 객체라 앱 전체에 하나만 둔다.
final tripRecordingCoordinatorProvider = Provider<TripRecordingCoordinator>(
  (ref) => TripRecordingCoordinator(
    store: ref.watch(tripRecordingStoreProvider),
    service: ref.watch(tripRecordingServiceProvider),
    permissions: ref.watch(tripRecordingPermissionsProvider),
    notices: ref.watch(tripDepartureNoticesProvider),
    db: ref.watch(appDatabaseProvider),
    // 계정 전환·목록 갱신·여행 삭제가 저장소의 일시정지를 바꾸면 화면용 목록도 저장소를 다시 읽는다.
    onPausedChanged: () {
      if (ref.mounted) ref.invalidate(pausedTripIdsProvider);
    },
  ),
);

/// 일시정지한 여행 id(여행 상세가 보여 준다). 저장소가 원본이고 이 목록은 그 사본이다. 바꿀 때는
/// [PausedTripsNotifier.setPaused]로 코디네이터를 거쳐 기록 서비스까지 맞춘다. 코디네이터의 다른 작업(계정 전환·목록 갱신·
/// 여행 삭제)이 저장소를 바꾸면 코디네이터가 이 목록을 다시 만들게 한다(`onPausedChanged`).
class PausedTripsNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => ref.watch(tripRecordingStoreProvider).readPaused();

  /// 코디네이터는 저장소에 먼저 적고 나서 서비스를 맞춘다. 서비스를 맞추다 실패해도 일시정지는 이미 저장됐으므로,
  /// 성공하든 실패하든 저장소 값대로 목록을 맞춘다(화면이 저장된 값과 어긋나지 않게). 오류는 부른 쪽으로 넘어간다.
  Future<void> setPaused(int tripId, bool paused) async {
    try {
      await ref.read(tripRecordingCoordinatorProvider).setPaused(tripId, paused);
    } finally {
      if (ref.mounted) state = ref.read(tripRecordingStoreProvider).readPaused();
    }
  }
}

final pausedTripIdsProvider = NotifierProvider<PausedTripsNotifier, Set<int>>(PausedTripsNotifier.new);

/// 로그아웃하거나 다른 계정으로 바뀌면 이전 계정의 여행 기록을 끄고 정리한다(설계 9-3, PR #32의 비자 알람 계정 가드와
/// 같은 방식). 앱 최상단(main.dart의 _Root)이 watch해서 앱이 떠 있는 동안 계속 지켜본다. 인증 상태를 아직 모를 때(로딩)는
/// 아무것도 하지 않는다 — 로그인한 사용자의 기록을 끄면 안 된다.
final tripRecordingAccountGuardProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<AppUser?>>(authStateProvider, (previous, next) {
    if (!next.hasValue) return;
    unawaited(ref.read(tripRecordingCoordinatorProvider).claimFor(next.value?.uid).catchError((Object e) {
      debugPrint('이전 계정의 여행 기록 정리 실패: $e');
    }));
  }, fireImmediately: true);
});
