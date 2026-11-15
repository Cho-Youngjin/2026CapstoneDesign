import 'dart:async';

import 'package:app/core/auth/app_user.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/footsteps/trip/trip_recording_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'trip_fakes.dart';

void main() {
  test('인증 상태를 알 때마다 기록의 주인을 맞추고, 아직 모를 때는 아무것도 하지 않는다', () async {
    final auth = StreamController<AppUser?>();
    addTearDown(auth.close);
    final coordinator = FakeTripRecordingCoordinator();
    final container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => auth.stream),
      tripRecordingCoordinatorProvider.overrideWithValue(coordinator),
    ]);
    addTearDown(container.dispose);
    container.listen(tripRecordingAccountGuardProvider, (_, _) {});

    await pumpEventQueue();
    expect(coordinator.claims, isEmpty, reason: '로딩 중에는 로그인한 사용자의 기록을 끄면 안 된다');

    auth.add(const AppUser(uid: 'uid-a'));
    await pumpEventQueue();
    auth.add(null);
    await pumpEventQueue();
    auth.add(const AppUser(uid: 'uid-b'));
    await pumpEventQueue();

    expect(coordinator.claims, ['uid-a', null, 'uid-b']);
  });
}
