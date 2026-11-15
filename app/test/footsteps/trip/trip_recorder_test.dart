import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/recording/policy_choice.dart';
import 'package:app/features/footsteps/trip/trip_recorder.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footstep_core/footstep_core.dart';

import 'trip_fakes.dart';

/// 대본대로 움직이는 걸음 감지기. [next]를 채워 두고 OS 걸음 읽기를 흘리면 그 갱신을 돌려준다. 정책이 보는
/// stepsSinceLastFix는 [live]로 따로 정한다 — 늦게 확인된 걸음처럼 실시간 값과 걸음 시각 목록이 다른 상황을 만든다.
class PlainDetector implements StepDetector {
  int live = 0;
  StepUpdate? next;

  @override
  String get id => 'plain';

  @override
  Map<String, Object> get params => const {};

  @override
  StepState get state => StepState.still;

  @override
  int get totalSteps => live;

  @override
  int get stepsSinceLastFix => live;

  @override
  StepUpdate? onAccel(int tMs, List<AccelReading> batch) => null;

  @override
  StepUpdate? onOsStep(OsStepReading reading) {
    final update = next;
    next = null;
    return update;
  }

  @override
  void onFix() {}
}

/// 걸음 시각 목록도 내놓는 감지기(StepTimeline). 목록은 [takeStepTimes]가 비운다.
class TimelineDetector extends PlainDetector implements StepTimeline {
  final times = <int>[];

  @override
  List<int> takeStepTimes() {
    final taken = List<int>.of(times);
    times.clear();
    return taken;
  }
}

/// 예약을 붙잡아 두는 타이머 대역. [fire]가 예약된 깨우기를 부른다.
class CapturingScheduler implements WakeScheduler {
  final _callbacks = <Object, void Function()>{};

  @override
  Object schedule(int atMs, void Function() callback) {
    final handle = Object();
    _callbacks[handle] = callback;
    return handle;
  }

  @override
  void cancel(Object handle) => _callbacks.remove(handle);

  void fire() {
    final pending = _callbacks.values.toList();
    _callbacks.clear();
    for (final callback in pending) {
      callback();
    }
  }
}

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
    StepDetector? detector,
    WakeScheduler? scheduler,
  }) {
    final choice = PolicyChoice(policyId: policyId, detectorId: detectorId);
    return TripRecorder(
      trip: trip,
      db: db,
      sources: sensors,
      clock: () => now,
      countryOf: countryOf ?? (lat, lng) async => 'KR',
      policy: createPolicy(policyId),
      detector: detector ?? createDetector(detectorId),
      location: location,
      scheduler: scheduler ?? FakeTripScheduler(),
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

  test('폴리곤이 가린 나라가 여행의 나라와 다르면 가린 나라로 남긴다', () async {
    final r = recorder(countryOf: (lat, lng) async => 'JP');
    await r.start();
    location.requests.single.complete(fixAt(now));
    await settle();
    await r.stop();

    expect((await db.routePointsForTrip(7)).single.countryIso, 'JP');
  });

  test('걸음 수는 감지기의 걸음 시각 목록을 비우며 센다 — 늦게 확인된 걸음은 사라지지 않고 목록은 자라지 않는다', () async {
    final detector = TimelineDetector();
    final scheduler = CapturingScheduler();
    final r = recorder(policyId: 'fixed_1m', detector: detector, scheduler: scheduler);
    await r.start();

    // 첫 점: 실시간 값은 5인데 시각 목록에는 2걸음뿐이다(나머지는 아직 확인 전). 목록의 2를 쓰고 목록은 비운다.
    detector.live = 5;
    detector.times.addAll([1000, 2000]);
    location.requests.last.complete(fixAt(now));
    await settle();
    expect(detector.times, isEmpty);

    // 둘째 점: 실시간 값은 0인데, 그사이 확인된 걸음 3개(첫 점 이전 시각 포함)가 목록에 들어왔다. 버려지지 않고 이 행에 든다.
    detector.live = 0;
    detector.times.addAll([500, 3000, 4000]);
    now = now.add(const Duration(minutes: 1));
    scheduler.fire();
    await settle();
    location.requests.last.complete(fixAt(now));
    await settle();
    await r.stop();

    final points = await db.routePointsForTrip(7);
    expect(points.map((p) => p.stepsSincePrev), [2, 3]);
    expect(detector.times, isEmpty);
  });

  test('걸음 시각 목록이 없는 감지기는 감지기가 말하는 걸음 수를 그대로 쓴다', () async {
    final detector = PlainDetector()..live = 4;
    final r = recorder(policyId: 'fixed_1m', detector: detector);
    await r.start();
    location.requests.last.complete(fixAt(now));
    await settle();
    await r.stop();

    expect((await db.routePointsForTrip(7)).single.stepsSincePrev, 4);
  });

  test('OS 센서판도 점을 남길 때 걸음 시각을 비운다', () async {
    final detector = OsStepDetector();
    final r = recorder(detector: detector);
    await r.start();
    sensors.step(now, 100);
    sensors.step(now.add(const Duration(seconds: 8)), 112);
    await settle();
    now = now.add(const Duration(seconds: 10));
    location.requests.single.complete(fixAt(now));
    await settle();
    await r.stop();

    expect((await db.routePointsForTrip(7)).single.stepsSincePrev, 12);
    expect(detector.takeStepTimes(), isEmpty);
  });

  test('시각이 거꾸로 가서 정지 구간이 겹치려 하면 앞 구간이 끝난 시각부터 시작한다', () async {
    final detector = PlainDetector();
    final start = now;
    final r = recorder(detector: detector);
    await r.start();

    Future<void> update(int seconds, StepState state) async {
      final at = start.add(Duration(seconds: seconds));
      detector.next = StepUpdate(tMs: at.millisecondsSinceEpoch, state: state, totalSteps: 0, stepsSinceLastFix: 0);
      sensors.step(at, seconds);
      await settle();
    }

    await update(10, StepState.still);
    await update(60, StepState.walking); // 첫 구간 [10, 60]
    await update(40, StepState.still); // 시계가 20초 거꾸로 갔다
    await update(90, StepState.walking); // 둘째 구간은 [60, 90]이어야 한다
    await r.stop();

    int ms(int seconds) => start.add(Duration(seconds: seconds)).millisecondsSinceEpoch;
    expect(await db.stillSpansForTrip(7), [TimeSpan(ms(10), ms(60)), TimeSpan(ms(60), ms(90))]);
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
