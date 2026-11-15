import 'dart:convert';

import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/background/footstep_task_handler.dart';
import 'package:app/features/footsteps/background/footstep_workmanager.dart';
import 'package:app/features/footsteps/trip/trip_recording_store.dart';
import 'package:app/features/footsteps/data/checkin.dart';
import 'package:app/features/footsteps/data/country_resolver.dart';
import 'package:app/features/footsteps/data/footsteps_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'trip/trip_fakes.dart' show period;

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

  test('여행 기간이면 좌표를 얻어 AUTO 소스로 체크인을 저장한다', () async {
    await handleFootstepTask(
      repository: repo,
      isTripPeriod: () async => true,
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
      isTripPeriod: () async => true,
      getCurrentPosition: () async => throw StateError('위치 서비스 꺼짐'),
    );

    expect(await repo.allCheckins(), isEmpty);
  });

  test('여행 기간이 아니면 측위 없이 끝낸다', () async {
    var asked = 0;
    await handleFootstepTask(
      repository: repo,
      isTripPeriod: () async => false,
      getCurrentPosition: () async {
        asked++;
        return _fakePosition(35.6, 139.7);
      },
    );

    expect(asked, 0);
    expect(await repo.allCheckins(), isEmpty);
  });

  test('WorkManager isolate는 화면이 저장해 둔 여행 기록 일정·일시정지로 여행 기간을 본다', () async {
    final trip = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));
    SharedPreferences.setMockInitialValues({TripRecordingStore.tripsKey: jsonEncode([trip.toJson()])});

    expect(await isTripPeriodNow(DateTime(2026, 11, 21, 9)), isTrue);
    expect(await isTripPeriodNow(DateTime(2026, 11, 23)), isFalse);

    SharedPreferences.setMockInitialValues({
      TripRecordingStore.tripsKey: jsonEncode([trip.toJson()]),
      TripRecordingStore.pausedKey: jsonEncode([7]),
    });
    expect(await isTripPeriodNow(DateTime(2026, 11, 21, 9)), isFalse);
  });
}
