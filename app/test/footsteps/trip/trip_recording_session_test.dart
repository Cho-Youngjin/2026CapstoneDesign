import 'dart:async';

import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/recording/policy_choice.dart';
import 'package:app/features/footsteps/trip/trip_recorder.dart';
import 'package:app/features/footsteps/trip/trip_recording_session.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footstep_core/footstep_core.dart';

import 'trip_fakes.dart';

void main() {
  late AppDatabase db;
  late DateTime now;
  late FakeTripSensors sensors;
  late bool wanted;
  late int wantedChecks;
  late int opened;
  final trip = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));

  // 지도 GeoJSON을 읽는 것처럼 오래 걸리는 열기를 흉내 낸다. 채우기 전에는 openRecorder가 끝나지 않는다.
  Completer<void>? openGate;
  Completer<void>? wantedGate;

  TripRecordingSession session() => TripRecordingSession(
        trip: trip,
        clock: () => now,
        stillWanted: () async {
          wantedChecks++;
          await wantedGate?.future;
          return wanted;
        },
        openRecorder: () async {
          opened++;
          await openGate?.future;
          return TripRecorder(
            trip: trip,
            db: db,
            sources: sensors,
            clock: () => now.toUtc(),
            countryOf: (lat, lng) async => 'KR',
            policy: createPolicy('step_budget'),
            detector: createDetector('os'),
            location: FakeTripLocation(),
            scheduler: FakeTripScheduler(),
            needs: PolicySensorNeeds.of(const PolicyChoice(policyId: 'step_budget', detectorId: 'os')),
          );
        },
      );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    now = DateTime(2026, 11, 21, 9);
    sensors = FakeTripSensors(() => now.toUtc());
    wanted = true;
    wantedChecks = 0;
    opened = 0;
    openGate = null;
    wantedGate = null;
  });

  tearDown(() => db.close());

  test('여행 기간 안이고 일정에 남아 있으면 기록기를 켠다', () async {
    final s = session();

    expect(await s.start(), isTrue);
    expect(opened, 1);
    expect(sensors.stepsController.hasListener, isTrue);
    await s.stop();
    expect(sensors.stepsController.hasListener, isFalse);
  });

  test('기록기를 여는 동안 서비스가 멈추면(onDestroy) 멈춘 뒤에 기록기를 켜지 않는다', () async {
    openGate = Completer<void>();
    final s = session();

    final started = s.start();
    await settle();
    expect(opened, 1);

    await s.stop(); // 기록기가 열리는 중에 서비스가 꺼졌다
    openGate!.complete();

    expect(await started, isFalse);
    expect(sensors.stepsController.hasListener, isFalse);
    expect(sensors.accelController.hasListener, isFalse);
    expect(await s.tick(), isFalse);
  });

  test('저장소를 읽는 동안 서비스가 멈춰도 기록기를 열지 않는다', () async {
    wantedGate = Completer<void>();
    final s = session();

    final started = s.start();
    await settle();
    await s.stop();
    wantedGate!.complete();

    expect(await started, isFalse);
    expect(opened, 0);
  });

  test('이미 기간이 끝났거나 지워졌거나 일시정지면 켜지 않는다(서비스를 끈다)', () async {
    now = DateTime(2026, 11, 23); // 귀국 다음 날 0시
    expect(await session().start(), isFalse);

    now = DateTime(2026, 11, 21, 9);
    wanted = false;
    expect(await session().start(), isFalse);
    expect(opened, 0);
  });

  test('귀국일 다음 날 0시가 지나면 깰 때 스스로 끝낸다', () async {
    final s = session();
    await s.start();

    now = DateTime(2026, 11, 22, 23, 59, 55);
    expect(await s.tick(), isTrue);

    now = DateTime(2026, 11, 23, 0, 0, 0);
    expect(await s.tick(), isFalse);
    expect(sensors.stepsController.hasListener, isFalse); // 기록기를 멈췄다
    expect(await s.tick(), isFalse);
  });

  test('저장소는 1분마다 다시 읽고, 여행이 지워졌거나 일시정지면 끝낸다', () async {
    final s = session();
    await s.start();
    expect(wantedChecks, 1);

    now = now.add(const Duration(seconds: 55));
    expect(await s.tick(), isTrue);
    expect(wantedChecks, 1); // 아직 1분이 안 됐다

    wanted = false;
    now = now.add(const Duration(seconds: 5));
    expect(await s.tick(), isFalse);
    expect(wantedChecks, 2);
    expect(sensors.stepsController.hasListener, isFalse);
  });
}
