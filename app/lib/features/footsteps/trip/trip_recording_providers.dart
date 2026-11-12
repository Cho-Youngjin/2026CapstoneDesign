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
  ),
);

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
