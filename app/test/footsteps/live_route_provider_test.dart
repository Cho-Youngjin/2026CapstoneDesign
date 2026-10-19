import 'dart:async';

import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/data/country_resolver.dart';
import 'package:app/features/footsteps/data/footsteps_repository.dart';
import 'package:app/features/footsteps/providers/footsteps_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

/// 국가 판정을 [gate]가 끝날 때까지 붙잡아 둔다 — 판정 도중에 구독이 끊기는 순간을 만든다.
class _GatedResolver implements CountryResolver {
  final gate = Completer<void>();
  final started = Completer<void>();

  @override
  Future<String> resolveIso2(double lat, double lng) async {
    if (!started.isCompleted) started.complete();
    await gate.future;
    return 'KR';
  }
}

Position _positionAt(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  // 실기기 로그에서 본 오류: 국가 판정을 기다리는 사이 실시간 추적이 꺼져(백그라운드 전환) provider가
  // 사라지면, 판정이 끝난 뒤 저장 여부를 묻다가 "disposed된 Ref를 썼다"는 예외가 처리되지 않고 났다.
  test('국가 판정 도중에 실시간 추적이 꺼져도 예외 없이 끝나고, 그 좌표는 저장하지 않는다', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final resolver = _GatedResolver();
    final positions = StreamController<Position>();
    addTearDown(positions.close);
    final container = ProviderContainer(overrides: [
      livePositionsProvider.overrideWithValue(() => positions.stream),
      realtimeCountryResolverProvider.overrideWithValue(resolver),
      footstepsRepositoryProvider
          .overrideWithValue(FootstepsRepository(db: db, countryResolver: resolver)),
    ]);
    addTearDown(container.dispose);
    container.listen(liveRouteProvider, (_, _) {});

    positions.add(_positionAt(37.5, 127.0));
    await resolver.started.future;
    container.read(realtimeTrackingEnabledProvider.notifier).state = false; // 앱이 백그라운드로 갔다
    await pumpEventQueue();

    // 처리되지 않은 비동기 예외가 나면 테스트 자체가 실패한다.
    resolver.gate.complete();
    await pumpEventQueue();

    expect(await db.select(db.routePoints).get(), isEmpty);
  });
}
