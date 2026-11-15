import 'dart:async';

import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

/// 시간을 손으로 넘기는 예약기. [runUntil]이 그 시각까지의 예약을 시각 순서로 부른다.
class _FakeScheduler implements WakeScheduler {
  final _entries = <({int handle, int atMs, void Function() callback})>[];
  int _next = 0;

  int get pending => _entries.length;

  @override
  Object schedule(int atMs, void Function() callback) {
    final handle = _next++;
    _entries.add((handle: handle, atMs: atMs, callback: callback));
    return handle;
  }

  @override
  void cancel(Object handle) => _entries.removeWhere((e) => e.handle == handle);

  void runUntil(int nowMs) {
    while (true) {
      final due = _entries.where((e) => e.atMs <= nowMs).toList()..sort((a, b) => a.atMs.compareTo(b.atMs));
      if (due.isEmpty) return;
      _entries.remove(due.first);
      due.first.callback();
    }
  }
}

class _FakeLocation implements LocationPort {
  final requests = <({int timeoutMs, Completer<Fix?> completer})>[];
  final streams = <({int intervalMs, double distanceFilterM, StreamController<Fix> controller})>[];

  /// true면 연속 측위 구독을 끊을 때 오류가 난다(플랫폼 채널 오류 흉내).
  bool cancelThrows = false;

  @override
  Future<Fix?> currentFix({required int timeoutMs}) {
    final completer = Completer<Fix?>();
    requests.add((timeoutMs: timeoutMs, completer: completer));
    return completer.future;
  }

  @override
  Stream<Fix> continuousFixes({required int intervalMs, required double distanceFilterM}) {
    final controller = StreamController<Fix>(onCancel: cancelThrows ? () => throw StateError('플랫폼 오류') : null);
    streams.add((intervalMs: intervalMs, distanceFilterM: distanceFilterM, controller: controller));
    return controller.stream;
  }
}

class _Sink implements RunnerSink {
  final fixes = <FixRecord>[];
  final actions = <ActionRecord>[];
  final wakeups = <WakeupRecord>[];

  @override
  void fix(FixRecord record) => fixes.add(record);

  @override
  void action(ActionRecord record) => actions.add(record);

  @override
  void wakeup(WakeupRecord record) => wakeups.add(record);
}

/// 쓸 때마다 오류를 던지는 기록(디스크가 가득 찬 폰 흉내).
class _ThrowingSink implements RunnerSink {
  @override
  void fix(FixRecord record) => throw StateError('디스크 가득 참');

  @override
  void action(ActionRecord record) => throw StateError('디스크 가득 참');

  @override
  void wakeup(WakeupRecord record) => throw StateError('디스크 가득 참');
}

/// 첫 currentFix에서 바로(동기로) 오류를 던지고, 그다음부터는 [inner]에 넘긴다.
class _ThrowOnceLocation implements LocationPort {
  _ThrowOnceLocation(this.inner);

  final _FakeLocation inner;
  bool _thrown = false;

  @override
  Future<Fix?> currentFix({required int timeoutMs}) {
    if (!_thrown) {
      _thrown = true;
      throw StateError('위치 권한 없음');
    }
    return inner.currentFix(timeoutMs: timeoutMs);
  }

  @override
  Stream<Fix> continuousFixes({required int intervalMs, required double distanceFilterM}) =>
      inner.continuousFixes(intervalMs: intervalMs, distanceFilterM: distanceFilterM);
}

/// 받은 사건을 모으고, 미리 정한 할 일을 돌려주는 정책.
class _Scripted implements CollectionPolicy {
  _Scripted({this.startActions = const [], this.respond});

  final List<PolicyAction> startActions;
  final List<PolicyAction> Function(PolicyEvent event)? respond;
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
    return respond?.call(event) ?? const [];
  }
}

Fix fixAt(int tMs) => Fix(tMs: tMs, lat: 37.5, lng: 127.0, accuracyM: 5);

AccelReading accel(int tMs) => AccelReading(tMs: tMs, x: 0, y: 9.81, z: 0);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late int now;
  late _FakeScheduler scheduler;
  late _FakeLocation location;
  late _Sink sink;
  late List<Object> errors;

  PolicyRunner runner(CollectionPolicy policy, {StepDetector? detector, LocationPort? port, RunnerSink? out}) =>
      PolicyRunner(
        policy: policy,
        detector: detector ?? OsStepDetector(),
        location: port ?? location,
        scheduler: scheduler,
        clock: () => now,
        sink: out ?? sink,
        onError: (error, _) => errors.add(error),
      );

  setUp(() {
    now = 0;
    scheduler = _FakeScheduler();
    location = _FakeLocation();
    sink = _Sink();
    errors = [];
  });

  test('RequestFix는 위치를 한 번 요청하고, 응답을 기록한 뒤 정책에 FixResult로 알린다', () async {
    final r = runner(TimeSpeedPolicy())..start();
    expect(location.requests.single.timeoutMs, 15000);
    expect(sink.actions.map((a) => a.action), [const RequestFix()]);

    now = 3000;
    location.requests.single.completer.complete(fixAt(3000));
    await settle();

    expect(sink.fixes.single.kind, 'single');
    expect(sink.fixes.single.state, 'still'); // OS 센서판 감지기의 처음 상태
    // TimeSpeed: (50 − 5) / 1.4 = 32.143초 뒤
    expect(sink.actions.last.action, const WakeAt(tMs: 35143, tag: 'next'));
    expect(r.lastFix?.tMs, 3000);
    expect(r.fixCount, 1);
  });

  test('WakeAt은 예약한 시각에 깨우고, 늦게 깬 만큼을 기록하며 실제로 깬 시각으로 알린다', () async {
    final policy = _Scripted(
      startActions: const [WakeAt(tMs: 10000, tag: 'tick')],
      respond: (e) => e is Wakeup ? const [RequestFix()] : const [],
    );
    runner(policy).start();

    now = 10500;
    scheduler.runUntil(now);

    expect(sink.wakeups.single.scheduledMs, 10000);
    expect(sink.wakeups.single.delayMs, 500);
    expect((policy.events.single as Wakeup).tMs, 10500);
    expect(location.requests, hasLength(1));
  });

  test('응답을 기다리는 중의 RequestFix는 합친다(위치 요청은 한 번)', () async {
    final r = runner(_Scripted(startActions: const [RequestFix(), RequestFix()]))..start();

    expect(sink.actions, hasLength(2));
    expect(location.requests, hasLength(1));
    final summary = await r.stop();
    expect(summary.fixRequests, 1);
  });

  test('위치를 못 받거나(null) 오류가 나면 실패로 세고 FixResult(null)을 알린다', () async {
    final policy = _Scripted(
      startActions: const [RequestFix()],
      respond: (e) => e is FixResult && e.failed ? const [RequestFix()] : const [],
    );
    final r = runner(policy)..start();

    now = 15000;
    location.requests.single.completer.complete(null);
    await settle();
    expect((policy.events.single as FixResult).failed, isTrue);

    now = 16000;
    location.requests.last.completer.completeError(StateError('위치 서비스 꺼짐'));
    await settle();
    expect(policy.events.whereType<FixResult>().where((e) => e.failed), hasLength(2));

    final summary = await r.stop();
    expect(summary.fixFailures, 2);
    expect(sink.fixes, isEmpty);
  });

  test('연속 측위는 간격·거리 필터로 구독하고 들어온 위치를 continuous로 기록하며, 끄면 켜진 시간을 센다', () async {
    final policy = _Scripted(
      startActions: const [StartContinuous(intervalMs: 1000, distanceFilterM: 10)],
      respond: (e) => e is ContinuousFix && e.tMs >= 2000 ? const [StopContinuous()] : const [],
    );
    final r = runner(policy)..start();
    final stream = location.streams.single;
    expect((stream.intervalMs, stream.distanceFilterM), (1000, 10.0));

    now = 1000;
    stream.controller.add(fixAt(1000));
    await settle();
    now = 2000;
    stream.controller.add(fixAt(2000));
    await settle();

    expect(sink.fixes.map((f) => (f.tMs, f.kind)), [(1000, 'continuous'), (2000, 'continuous')]);
    expect(stream.controller.hasListener, isFalse); // StopContinuous로 끊었다

    now = 5000;
    final summary = await r.stop();
    expect(summary.continuousFixes, 2);
    expect(summary.gpsOnMs, 2000);
  });

  test('가속도는 1초 묶음으로 걸음 감지기에 넣고, 나온 StepUpdate를 정책에 알린다', () async {
    final policy = _Scripted();
    final r = runner(policy, detector: AdaptiveStepDetector())..start();

    for (var t = 0; t <= 2000; t += 10) {
      r.addAccel(accel(t));
    }

    // 0~990ms 묶음이 1000ms 표본에서 닫히고, 1000~1990ms 묶음이 2000ms 표본에서 닫힌다.
    final updates = policy.events.whereType<StepUpdate>().toList();
    expect(updates.single.tMs, 990); // 정지를 처음 알린 묶음 끝
    expect(updates.single.state, StepState.still);
  });

  test('걸음 감지기의 StepUpdate를 정책보다 먼저 onStepUpdate로 알리고, 그 오류로 수집을 멈추지 않는다', () {
    final policy = _Scripted();
    final seen = <String>[];
    final r = PolicyRunner(
      policy: policy,
      detector: OsStepDetector(),
      location: location,
      scheduler: scheduler,
      clock: () => now,
      sink: sink,
      onError: (error, _) => errors.add(error),
      onStepUpdate: (update) {
        seen.add('${update.tMs}:${update.state.name}:${policy.events.length}');
        throw StateError('기록 실패');
      },
    )..start();

    r.addOsStep(const OsStepReading(tMs: 100, kind: OsStepReading.count, value: '100'));
    r.addOsStep(const OsStepReading(tMs: 1000, kind: OsStepReading.count, value: '112'));

    // 첫 읽기는 기준값이라 정지로 처음 분류하고, 늘어난 둘째 읽기에서 보행이 된다. 둘 다 정책이 받기 전(받은 사건 수
    // 0, 1)에 알렸고, 오류가 나도 정책은 두 사건을 다 받았다.
    expect(seen, ['100:still:0', '1000:walking:1']);
    expect(policy.events.whereType<StepUpdate>(), hasLength(2));
    expect(errors, hasLength(2));
  });

  test('가속도 없이 도는 OS 센서판 감지기는 시계를 넘겨 받아야 멈춘 뒤 정지로 바뀐다', () {
    final policy = _Scripted();
    final r = runner(policy)..start();
    r.addOsStep(const OsStepReading(tMs: 100, kind: OsStepReading.count, value: '100'));
    r.addOsStep(const OsStepReading(tMs: 1000, kind: OsStepReading.count, value: '112'));
    // 안드로이드는 멈춘 지 약 2초 뒤 'stopped'를 한 번 보낸다. 아직 마지막 걸음 뒤 4초 안이라 보행이다.
    r.addOsStep(const OsStepReading(tMs: 3000, kind: OsStepReading.status, value: 'stopped'));
    expect(r.stateLabel, 'walking');

    now = 4000; // 마지막 걸음 뒤 3초: 아직 보행
    r.advanceDetectorClock();
    expect(r.stateLabel, 'walking');

    now = 6000; // 기록 서비스의 다음 주기: 4초가 지나 정지
    r.advanceDetectorClock();
    expect(r.stateLabel, 'still');
    expect(policy.events.whereType<StepUpdate>().last.state, StepState.still);
  });

  test('가속도를 듣는 감지기에는 시계 넘기기가 아무 일도 하지 않는다', () {
    final policy = _Scripted();
    final r = runner(policy, detector: AdaptiveStepDetector())..start();

    now = 5000;
    r.advanceDetectorClock();
    expect(policy.events, isEmpty);
    expect(errors, isEmpty);
  });

  test('배터리 잔량은 바뀔 때만 알린다', () {
    final policy = _Scripted();
    final r = runner(policy)..start();

    r.addBatteryLevel(1000, 80);
    r.addBatteryLevel(31000, 80);
    r.addBatteryLevel(61000, 79);

    expect(policy.events.whereType<BatteryLevel>().map((e) => e.pct), [80, 79]);
  });

  test('위치를 알릴 때 그때까지의 걸음 수를 기록하고 걸음 감지기의 onFix를 부른다', () async {
    final r = runner(_Scripted(startActions: const [RequestFix()]))..start();
    r.addOsStep(const OsStepReading(tMs: 100, kind: OsStepReading.count, value: '100'));
    r.addOsStep(const OsStepReading(tMs: 200, kind: OsStepReading.count, value: '112'));
    expect(r.stepsSinceLastFix, 12);

    now = 3000;
    location.requests.single.completer.complete(fixAt(3000));
    await settle();

    expect(sink.fixes.single.stepsSincePrev, 12);
    expect(sink.fixes.single.state, 'walking');
    expect(r.stepsSinceLastFix, 0);
  });

  test('stop은 예약을 취소하고 그 뒤에 온 응답을 무시하며, 요약을 돌려준다', () async {
    final policy = _Scripted(
      startActions: const [
        RequestFix(),
        WakeAt(tMs: 60000, tag: 'tick'),
      ],
    );
    final r = runner(policy)..start();
    expect(scheduler.pending, 2); // 'tick' 예약과 위치 요청 감시 타이머

    now = 4000;
    final summary = await r.stop();
    expect(scheduler.pending, 0);
    expect(summary.fixRequests, 1);
    expect(summary.gpsOnMs, 4000); // 응답을 기다리던 동안
    expect(summary.endMs, 4000);
    expect(summary.toJson()['policy_id'], 'scripted');

    location.requests.single.completer.complete(fixAt(5000));
    await settle();
    expect(sink.fixes, isEmpty);
    expect(policy.events, isEmpty);
  });

  test('제안 정책은 실행기에서도 상태 이름(ReportsState)을 기록에 남긴다', () async {
    final r = runner(StepBudgetPolicy())..start();
    expect(r.stateLabel, 'unknown');

    now = 2000;
    location.requests.single.completer.complete(fixAt(2000));
    await settle();
    expect(sink.fixes.single.state, 'unknown');
  });

  group('오류가 나도 수집을 이어간다', () {
    test('기록(sink)에서 오류가 나도 정책에 FixResult를 알리고 다음 예약을 걸며, 오류를 알린다', () async {
      final policy = _Scripted(
        startActions: const [RequestFix()],
        respond: (e) => e is FixResult ? const [WakeAt(tMs: 60000, tag: 'next')] : const [],
      );
      final r = runner(policy, out: _ThrowingSink())..start();

      now = 3000;
      location.requests.single.completer.complete(fixAt(3000));
      await settle();

      expect(policy.events.single, isA<FixResult>());
      expect(r.lastFix?.tMs, 3000);
      expect(scheduler.pending, 1); // 'next' 예약만 남는다(감시 타이머는 응답과 함께 취소)
      expect(errors, hasLength(3)); // RequestFix·위치·WakeAt 기록
    });

    test('GPS 포트가 바로 오류를 던져도 실패로 다루고, 다음 요청을 막지 않는다', () async {
      final policy = _Scripted(
        startActions: const [RequestFix()],
        respond: (e) => e is FixResult && e.failed ? const [RequestFix()] : const [],
      );
      final r = runner(policy, port: _ThrowOnceLocation(location))..start();
      expect(policy.events, isEmpty); // 정책에는 다음 차례에 알린다
      await settle();

      expect((policy.events.single as FixResult).failed, isTrue);
      expect(location.requests, hasLength(1)); // 실패 뒤 다시 낸 요청은 포트에 닿았다
      expect(errors.single, isA<StateError>());
      final summary = await r.stop();
      expect((summary.fixRequests, summary.fixFailures), (2, 1));
    });

    test('GPS 포트가 끝내 답하지 않으면 시간 제한 + 5초 뒤 실패로 보고, 늦게 온 응답은 다음 요청의 답으로 쓰지 않는다', () async {
      final policy = _Scripted(
        startActions: const [RequestFix()],
        respond: (e) => e is FixResult && e.failed ? const [RequestFix()] : const [],
      );
      final r = runner(policy)..start();

      now = 20000; // 15초 제한 + 5초
      scheduler.runUntil(now);
      expect((policy.events.single as FixResult).failed, isTrue);
      expect(location.requests, hasLength(2)); // 정책이 다시 요청했다

      location.requests.first.completer.complete(fixAt(21000)); // 첫 요청의 늦은 응답
      await settle();
      expect(sink.fixes, isEmpty);
      expect(policy.events, hasLength(1));

      now = 22000;
      location.requests.last.completer.complete(fixAt(22000));
      await settle();
      expect(sink.fixes.single.tMs, 22000);
      final summary = await r.stop();
      expect((summary.fixRequests, summary.fixSuccesses, summary.fixFailures), (2, 1, 1));
      expect(summary.gpsOnMs, 22000);
    });

    test('정책이 오류를 던져도 실행기는 멈추지 않고 다음 사건을 알린다', () {
      final policy = _Scripted(respond: (e) => e is BatteryLevel && e.pct == 80 ? throw StateError('정책 오류') : const []);
      final r = runner(policy)..start();

      r.addBatteryLevel(1000, 80);
      r.addBatteryLevel(2000, 79);
      expect(policy.events.whereType<BatteryLevel>().map((e) => e.pct), [80, 79]);
      expect(errors.single, isA<StateError>());
    });
  });

  test('지난 시각의 WakeAt은 지금으로 당겨, 깨우기 지연에 정책의 늦은 예약을 넣지 않는다', () {
    now = 5000;
    final policy = _Scripted(startActions: const [WakeAt(tMs: 1000, tag: 'late')]);
    runner(policy).start();

    scheduler.runUntil(5000);
    expect(sink.wakeups.single.scheduledMs, 5000);
    expect(sink.wakeups.single.delayMs, 0);
    expect((policy.events.single as Wakeup).tMs, 5000);
  });

  test('stop은 여러 번 불러도 처음 요약을 돌려주고, 연속 측위를 끊다 오류가 나도 요약을 돌려준다', () async {
    location.cancelThrows = true;
    final r = runner(_Scripted(startActions: const [StartContinuous(intervalMs: 1000, distanceFilterM: 0)]))..start();

    now = 3000;
    final first = r.stop();
    now = 9000;
    expect(identical(r.stop(), first), isTrue);
    final summary = await first;
    expect((summary.endMs, summary.gpsOnMs), (3000, 3000));
    expect(errors.single, isA<StateError>());
  });

  test('멈춘 실행기는 다시 시작할 수 없다(실행마다 새 실행기를 만든다)', () async {
    final r = runner(_Scripted())..start();
    r.start(); // 도는 중에는 아무것도 하지 않는다
    await r.stop();
    expect(r.start, throwsStateError);
  });

  test('연속 측위가 스스로 끝나면(GPS 꺼짐) 켜진 시간을 거기까지만 센다', () async {
    final r = runner(_Scripted(startActions: const [StartContinuous(intervalMs: 1000, distanceFilterM: 0)]))..start();

    now = 2000;
    await location.streams.single.controller.close();
    await settle();
    now = 10000;
    final summary = await r.stop();
    expect(summary.gpsOnMs, 2000);
  });
}
