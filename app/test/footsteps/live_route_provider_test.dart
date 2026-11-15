import 'dart:async';

import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/providers/footsteps_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
  // 설계 2026-11-07 9-2: 실시간 경로는 화면 표시용으로만 남는다. 이동 기록은 여행 기간에만 기록 서비스가 남긴다.
  test('실시간 경로는 좌표를 화면에 내기만 하고 RoutePoints에 저장하지 않는다', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final positions = StreamController<Position>();
    addTearDown(positions.close);
    final container = ProviderContainer(overrides: [
      livePositionsProvider.overrideWithValue(() => positions.stream),
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    final seen = <List<LatLng>>[];
    container.listen(liveRouteProvider, (_, next) {
      final value = next.asData?.value;
      if (value != null) seen.add(value);
    });

    positions.add(_positionAt(37.5, 127.0));
    positions.add(_positionAt(37.6, 127.1));
    await pumpEventQueue();

    expect(seen.last, [const LatLng(37.5, 127.0), const LatLng(37.6, 127.1)]);
    expect(await db.select(db.routePoints).get(), isEmpty);
  });
}
