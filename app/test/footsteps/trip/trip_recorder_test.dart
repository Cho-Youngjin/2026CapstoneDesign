import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/recording/policy_choice.dart';
import 'package:app/features/footsteps/trip/trip_recorder.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footstep_core/footstep_core.dart';

import 'trip_fakes.dart';

void main() {
  late AppDatabase db;
  late DateTime now;
  late FakeTripSensors sensors;
  late FakeTripLocation location;
  late List<Object> errors;
  final trip = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));

  TripRecorder recorder({
    String policyId = 'step_budget',
    String detectorId = 'os',
    Future<String> Function(double lat, double lng)? countryOf,
  }) {
    final choice = PolicyChoice(policyId: policyId, detectorId: detectorId);
    return TripRecorder(
      trip: trip,
      db: db,
      sources: sensors,
      clock: () => now,
      countryOf: countryOf ?? (lat, lng) async => 'KR',
      policy: createPolicy(policyId),
      detector: createDetector(detectorId),
      location: location,
      scheduler: FakeTripScheduler(),
      needs: PolicySensorNeeds.of(choice),
      onError: errors.add,
    );
  }

  Fix fixAt(DateTime at, {double accuracyM = 6}) =>
      Fix(tMs: at.millisecondsSinceEpoch, lat: 37.55, lng: 126.97, accuracyM: accuracyM);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    now = DateTime.utc(2026, 11, 20, 1);
    sensors = FakeTripSensors(() => now);
    location = FakeTripLocation();
    errors = [];
  });

  tearDown(() => db.close());

  test('정책에 알린 위치를 여행 id·정확도·직전 점 이후 걸음 수·정책 상태와 함께 RoutePoints에 남긴다', () async {
    final r = recorder();
    await r.start();
    // step_budget은 시작하자마자 한 번 잰다. 응답을 기다리는 사이 12걸음을 걸어 정책 상태가 보행이 됐다.
    sensors.step(now, 100);
    sensors.step(now.add(const Duration(seconds: 8)), 112);
    await settle();

    now = now.add(const Duration(seconds: 10));
    location.requests.single.complete(fixAt(now, accuracyM: 7.5));
    await settle();
    await r.stop();

    final points = await db.routePointsForTrip(7);
    expect(points, hasLength(1));
    expect(points.single.countryIso, 'KR');
    expect(points.single.accuracyM, 7.5);
    expect(points.single.stepsSincePrev, 12);
    expect(points.single.state, 'walking');
    expect(points.single.recordedAt.toUtc(), DateTime.utc(2026, 11, 20, 1, 0, 10)); // drift는 현지 시각으로 돌려준다
    expect(errors, isEmpty);
  });

  test('국가를 모르거나 가리다 오류가 나면 여행의 나라로 남기고 기록은 계속한다', () async {
    var calls = 0;
    final r = recorder(
      policyId: 'fixed_1m',
      countryOf: (lat, lng) async {
        calls++;
        if (calls == 1) return 'XX';
        throw StateError('폴리곤 오류');
      },
    );
    await r.start();
    location.requests.last.complete(fixAt(now));
    await settle();
    // 1분 주기라 다음 요청은 깨우기 뒤에 온다 — 여기서는 첫 점만 본다.
    await r.stop();

    final points = await db.routePointsForTrip(7);
    expect(points.single.countryIso, 'KR');
    expect(errors, isEmpty);

    // 두 번째 기록기: 국가 판정이 오류를 내도 점은 남고 오류만 알린다.
    final second = recorder(
      policyId: 'fixed_1m',
      countryOf: (lat, lng) async => throw StateError('폴리곤 오류'),
    );
    await second.start();
    location.requests.last.complete(fixAt(now.add(const Duration(minutes: 1))));
    await settle();
    await second.stop();

    expect(await db.routePointsForTrip(7), hasLength(2));
    expect(errors.single, isA<StateError>());
  });

  test('걸음 감지기의 정지 구간을 남기고, 멈출 때 열린 정지 구간을 지금으로 닫는다', () async {
    final start = now;
    final r = recorder();
    await r.start();
    // OS 센서판: 첫 읽기는 기준값(정지로 첫 분류), 늘어나면 보행, 마지막 걸음 뒤 4초가 지나면 정지.
    sensors.step(start, 100);
    await settle();
    sensors.step(start.add(const Duration(seconds: 60)), 160);
    await settle();
    now = start.add(const Duration(seconds: 70));
    await r.tick(); // 시계를 넘겨 정지로 바꾼다
    now = start.add(const Duration(minutes: 20));
    await r.stop();

    final spans = await db.stillSpansForTrip(7);
    expect(spans, [
      TimeSpan(start.millisecondsSinceEpoch, start.add(const Duration(seconds: 60)).millisecondsSinceEpoch),
      TimeSpan(start.add(const Duration(seconds: 70)).millisecondsSinceEpoch,
          start.add(const Duration(minutes: 20)).millisecondsSinceEpoch),
    ]);
  });

  test('정책이 쓰는 센서만 켜고, 멈추면 끊는다', () async {
    final adaptive = recorder(detectorId: 'adaptive');
    await adaptive.start();
    expect(sensors.accelController.hasListener, isTrue);
    expect(sensors.stepsController.hasListener, isFalse);
    await adaptive.stop();
    expect(sensors.accelController.hasListener, isFalse);

    // 걸음 정보를 쓰지 않는 정책은 걸음 센서를 켜지 않는다.
    final fixed = recorder(policyId: 'fixed_5m');
    await fixed.start();
    expect(sensors.stepsController.hasListener, isFalse);
    expect(sensors.accelController.hasListener, isFalse);
    await fixed.stop();
  });

  test('배터리 잔량은 1분마다 읽는다(20% 미만이면 정책이 E를 키운다)', () async {
    final r = recorder();
    await r.start();
    expect(sensors.batteryReads, 1);

    now = now.add(const Duration(seconds: 30));
    await r.tick();
    expect(sensors.batteryReads, 1);

    now = now.add(const Duration(seconds: 30));
    await r.tick();
    expect(sensors.batteryReads, 2);
    await r.stop();
  });

  test('여행 기록은 제안 정책 step_budget(E=50m)로 돈다', () {
    expect(tripPolicyChoice.policyId, 'step_budget');
    expect(tripPolicyChoice.policyParams, {'e_m': '50'});
    expect(createPolicy(tripPolicyChoice.policyId, tripPolicyChoice.policyParams).params['e_m'], 50.0);
    expect(() => createDetector(tripPolicyChoice.detectorId), returnsNormally);
  });
}
