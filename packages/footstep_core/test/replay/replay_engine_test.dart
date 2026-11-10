import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

/// 정해 둔 할 일을 돌려주고 받은 사건을 모으는 시험용 정책.
class _Scripted implements CollectionPolicy {
  _Scripted({this.startActions = const [], this.onWake = const {}});

  final List<PolicyAction> startActions;
  final Map<String, List<PolicyAction>> onWake;
  final events = <PolicyEvent>[];

  @override
  String get id => 'scripted';

  @override
  Map<String, Object> get params => const {};

  @override
  List<PolicyAction> onStart(PolicyContext ctx) => startActions;

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    events.add(event);
    if (event is Wakeup) return onWake[event.tag] ?? const [];
    return const [];
  }
}

Fix gps(int tMs, {double lat = 37.5, double lng = 127.0}) =>
    Fix(tMs: tMs, lat: lat, lng: lng, accuracyM: 5);

List<Fix> everySecond(int fromMs, int toMs) => [for (var t = fromMs; t <= toMs; t += 1000) gps(t)];

SessionData session({
  List<Fix> fixes = const [],
  List<AccelReading> accel = const [],
  List<OsStepReading> osSteps = const [],
}) =>
    SessionData(sessionId: 'test', fixes: fixes, accel: accel, osSteps: osSteps);

OsStepReading count(int tMs, int value) =>
    OsStepReading(tMs: tMs, kind: OsStepReading.count, value: '$value');

void main() {
  test('RequestFix는 요청 시각 이후의 첫 GPS 행을 그 행의 시각에 돌려준다', () {
    final policy = _Scripted(
      startActions: [const WakeAt(tMs: 2500, tag: 'a')],
      onWake: {'a': [const RequestFix()]},
    );

    final result = replaySession(session(fixes: everySecond(0, 10000)), policy, OsStepDetector());

    expect(result.fixes.single.tMs, 3000);
    expect(result.fixes.single.kind, 'single');
    final response = policy.events.whereType<FixResult>().single;
    expect(response.tMs, 3000);
    expect(response.fix!.tMs, greaterThanOrEqualTo(2500)); // 미래 정보 없음
    expect(result.summary.fixRequests, 1);
    expect(result.summary.fixSuccesses, 1);
    expect(result.summary.gpsOnMs, 500);
  });

  test('ttff만큼 늦은 첫 행을 받는다', () {
    final policy = _Scripted(
      startActions: [const WakeAt(tMs: 2500, tag: 'a')],
      onWake: {'a': [const RequestFix()]},
    );

    final result = replaySession(session(fixes: everySecond(0, 10000)), policy, OsStepDetector(),
        config: const ReplayConfig(ttffMs: 5000));

    expect(result.fixes.single.tMs, 8000);
    expect(result.summary.gpsOnMs, 5500);
  });

  test('GPS 공백이 제한 시간보다 길면 제한 시간에 실패를 알린다', () {
    final policy = _Scripted(
      startActions: [const WakeAt(tMs: 2500, tag: 'a')],
      onWake: {'a': [const RequestFix()]},
    );
    final fixes = [...everySecond(0, 2000), ...everySecond(30000, 40000)];

    final result = replaySession(session(fixes: fixes), policy, OsStepDetector());

    final response = policy.events.whereType<FixResult>().single;
    expect(response.tMs, 17500);
    expect(response.failed, isTrue);
    expect(result.fixes, isEmpty);
    expect(result.summary.fixFailures, 1);
    expect(result.summary.gpsOnMs, 15000);
  });

  test('연속 측위는 간격·거리 필터대로 행을 흘려보내고 켜진 시간을 센다', () {
    // 1초에 북쪽으로 3m씩 움직인다 → 10m 필터면 4초(12m)마다 알린다.
    const degPerMeter = 1 / 111195;
    final fixes = [
      for (var s = 0; s <= 30; s++) gps(s * 1000, lat: 37.5 + s * 3 * degPerMeter),
    ];
    final policy = _Scripted(
      startActions: [
        const StartContinuous(intervalMs: 1000, distanceFilterM: 10),
        const WakeAt(tMs: 20000, tag: 'stop'),
      ],
      onWake: {'stop': [const StopContinuous()]},
    );

    final result = replaySession(session(fixes: fixes), policy, OsStepDetector());

    expect(result.fixes.map((f) => f.tMs), [0, 4000, 8000, 12000, 16000]);
    expect(result.fixes.every((f) => f.kind == 'continuous'), isTrue);
    expect(result.summary.continuousFixes, 5);
    expect(result.summary.gpsOnMs, 20000);
  });

  test('가속도 묶음과 OS 걸음이 걸음 감지기를 거쳐 정책에 간다', () {
    final policy = _Scripted();
    final accel = [
      for (var t = 0; t <= 8000; t += 10) AccelReading(tMs: t, x: 0, y: 9.8, z: 0),
    ];

    replaySession(session(accel: accel, osSteps: [count(0, 100), count(1000, 103)]), policy,
        OsStepDetector());

    final updates = policy.events.whereType<StepUpdate>().toList();
    expect(updates.map((u) => (u.tMs, u.state)), [(1000, StepState.walking), (5990, StepState.still)]);
  });

  test('측위 기록에 직전 측위 이후 걸음 수와 상태가 들어간다', () {
    final policy = _Scripted(
      startActions: [const WakeAt(tMs: 2000, tag: 'a'), const WakeAt(tMs: 4000, tag: 'b')],
      onWake: {'a': [const RequestFix()], 'b': [const RequestFix()]},
    );
    final data = session(
      fixes: everySecond(0, 5000),
      osSteps: [count(0, 0), count(1000, 10), count(3000, 15)],
    );

    final result = replaySession(data, policy, OsStepDetector());

    expect(result.fixes.map((f) => f.stepsSincePrev), [10, 5]);
    expect(result.fixes.map((f) => f.state), ['walking', 'walking']);
  });

  test('1분 고정 주기로 10분을 재생하면 측위 11번(0분~10분)이다', () {
    final data = session(fixes: everySecond(0, 600000));

    final instant = replaySession(
        data, FixedIntervalPolicy(id: 'fixed_1m', intervalMs: 60000), OsStepDetector());
    expect(instant.summary.fixRequests, 11);
    expect(instant.summary.fixSuccesses, 11);
    expect(instant.summary.gpsOnMs, 0);

    final delayed = replaySession(
        data, FixedIntervalPolicy(id: 'fixed_1m', intervalMs: 60000), OsStepDetector(),
        config: const ReplayConfig(ttffMs: 5000));
    expect(delayed.summary.fixSuccesses, 10); // 마지막 요청의 응답은 세션이 끝난 뒤다
    expect(delayed.summary.gpsOnMs, 50000);
  });

  test('같은 입력이면 항상 같은 결과다', () {
    final data = session(fixes: everySecond(0, 300000));
    ReplayResult run() =>
        replaySession(data, FixedIntervalPolicy(id: 'fixed_30s', intervalMs: 30000), OsStepDetector());

    final a = run();
    final b = run();
    expect(a.summary.toJson(), b.summary.toJson());
    expect(a.fixes.map((f) => f.tMs), b.fixes.map((f) => f.tMs));
    expect(a.actions.map((r) => '${r.tMs} ${r.action}'), b.actions.map((r) => '${r.tMs} ${r.action}'));
  });

  test('summary는 R6 분석이 읽을 키로 내보낸다', () {
    final result = replaySession(session(fixes: everySecond(0, 3600000)),
        FixedIntervalPolicy(id: 'fixed_5m', intervalMs: 300000), OsStepDetector());

    final json = result.summary.toJson();
    expect(json['session_id'], 'test');
    expect(json['policy_id'], 'fixed_5m');
    expect(json['policy_params'], {'interval_s': 300});
    expect(json['detector_id'], 'os');
    expect(json['duration_s'], 3600.0);
    expect(json['total_fixes'], 13);
    expect(json['fixes_per_hour'], 13.0);
  });

  test('기록이 없는 세션은 ArgumentError다', () {
    expect(() => replaySession(session(), _Scripted(), OsStepDetector()), throwsArgumentError);
  });
}
