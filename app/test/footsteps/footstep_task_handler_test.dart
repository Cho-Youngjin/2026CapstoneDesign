import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/background/footstep_task_handler.dart';
import 'package:app/features/footsteps/data/checkin.dart';
import 'package:app/features/footsteps/data/country_resolver.dart';
import 'package:app/features/footsteps/data/footsteps_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

class _FixedCountryResolver implements CountryResolver {
  @override
  Future<String> resolveIso2(double lat, double lng) async => 'JP';
}

Position _fakePosition(double lat, double lng) => Position(
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
    repo = FootstepsRepository(db: db, countryResolver: _FixedCountryResolver());
  });

  tearDown(() => db.close());

  test('좌표를 얻으면 AUTO 소스로 체크인을 저장한다', () async {
    await handleFootstepTask(
      repository: repo,
      getCurrentPosition: () async => _fakePosition(35.6, 139.7),
    );

    final all = await repo.allCheckins();
    expect(all, hasLength(1));
    expect(all.first.source, CheckinSource.auto);
    expect(all.first.countryIso, 'JP');
  });

  test('위치를 얻지 못해도 예외를 밖으로 던지지 않는다', () async {
    await handleFootstepTask(
      repository: repo,
      getCurrentPosition: () async => throw StateError('위치 서비스 꺼짐'),
    );

    expect(await repo.allCheckins(), isEmpty);
  });
}
