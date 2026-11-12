import 'package:app/features/footsteps/map/live_route_tracker.dart';
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
  test('위치가 들어올 때마다 지금까지의 전체 경로를 누적해서 낸다', () async {
    final positions = Stream.fromIterable([
      _positionAt(1, 1),
      _positionAt(2, 2),
      _positionAt(3, 3),
    ]);

    final snapshots = await trackLiveRoute(positions).toList();

    expect(snapshots, [
      [const LatLng(1, 1)],
      [const LatLng(1, 1), const LatLng(2, 2)],
      [const LatLng(1, 1), const LatLng(2, 2), const LatLng(3, 3)],
    ]);
  });

  test('maxPoints를 넘으면 오래된 좌표부터 버린다', () async {
    final positions = Stream.fromIterable([
      _positionAt(1, 1),
      _positionAt(2, 2),
      _positionAt(3, 3),
    ]);

    final snapshots = await trackLiveRoute(positions, maxPoints: 2).toList();

    expect(snapshots.last, [const LatLng(2, 2), const LatLng(3, 3)]);
  });

  test('위치가 없으면 빈 스트림을 낸다', () async {
    expect(await trackLiveRoute(const Stream.empty()).toList(), isEmpty);
  });
}
