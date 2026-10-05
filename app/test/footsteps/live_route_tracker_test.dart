import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/data/checkin.dart';
import 'package:app/features/footsteps/data/country_resolver.dart';
import 'package:app/features/footsteps/data/footsteps_repository.dart';
import 'package:app/features/footsteps/map/live_route_tracker.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class _FixedCountryResolver implements CountryResolver {
  const _FixedCountryResolver(this.iso);
  final String iso;

  @override
  Future<String> resolveIso2(double lat, double lng) async => iso;
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
  late AppDatabase db;
  late FootstepsRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = FootstepsRepository(db: db, countryResolver: const _FixedCountryResolver('JP'));
  });

  tearDown(() => db.close());

  test('위치가 들어올 때마다 지금까지의 전체 경로를 누적해서 낸다', () async {
    final positions = Stream.fromIterable([
      _positionAt(1, 1),
      _positionAt(2, 2),
      _positionAt(3, 3),
    ]);

    final snapshots = await trackAndPersistLiveRoute(
      positions: positions,
      countryResolver: const _FixedCountryResolver('JP'),
      repository: repo,
    ).toList();

    expect(snapshots, [
      [const LatLng(1, 1)],
      [const LatLng(1, 1), const LatLng(2, 2)],
      [const LatLng(1, 1), const LatLng(2, 2), const LatLng(3, 3)],
    ]);
  });

  test('국가가 판정되는 좌표는 영구 기록으로 저장된다', () async {
    final positions = Stream.fromIterable([_positionAt(1, 1), _positionAt(2, 2)]);

    await trackAndPersistLiveRoute(
      positions: positions,
      countryResolver: const _FixedCountryResolver('JP'),
      repository: repo,
    ).drain<void>();

    final saved = await repo.routePointsForCountry('JP');
    expect(saved, hasLength(2));
    expect(saved[0].lat, 1);
    expect(saved[1].lat, 2);
  });

  test('미확인(XX) 좌표는 저장하지 않지만 화면 경로에는 포함한다', () async {
    final positions = Stream.fromIterable([_positionAt(1, 1)]);

    final snapshots = await trackAndPersistLiveRoute(
      positions: positions,
      countryResolver: const _FixedCountryResolver(Checkin.unknownCountry),
      repository: repo,
    ).toList();

    expect(snapshots, [
      [const LatLng(1, 1)],
    ]);
    expect(await repo.routePointsForCountry('XX'), isEmpty);
  });

  test('maxPoints를 넘으면 오래된 좌표부터 버린다', () async {
    final positions = Stream.fromIterable([
      _positionAt(1, 1),
      _positionAt(2, 2),
      _positionAt(3, 3),
    ]);

    final snapshots = await trackAndPersistLiveRoute(
      positions: positions,
      countryResolver: const _FixedCountryResolver('JP'),
      repository: repo,
      maxPoints: 2,
    ).toList();

    expect(snapshots.last, [const LatLng(2, 2), const LatLng(3, 3)]);
  });

  test('위치가 없으면 빈 스트림을 낸다', () async {
    final snapshots = await trackAndPersistLiveRoute(
      positions: const Stream.empty(),
      countryResolver: const _FixedCountryResolver('JP'),
      repository: repo,
    ).toList();

    expect(snapshots, isEmpty);
  });
}
