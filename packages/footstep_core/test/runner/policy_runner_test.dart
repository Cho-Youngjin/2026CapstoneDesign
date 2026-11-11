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
      final due = _entries.where((e) => e.atMs <= nowMs).toList()
        ..sort((a, b) => a.atMs.compareTo(b.atMs));
      if (due.isEmpty) return;
      _entries.remove(due.first);
      due.first.callback();
    }
  }
}

class _FakeLocation implements LocationPort {
  final requests = <({int timeoutMs, Completer<Fix?> completer})>[];
  final streams = <({int intervalMs, double distanceFilterM, StreamController<Fix> controller})>[];

  @override
  Future<Fix?> currentFix({required int timeoutMs}) {
    final completer = Completer<Fix?>();
    requests.add((timeoutMs: timeoutMs, completer: completer));
    return completer.future;
  }

  @override
  Stream<Fix> continuousFixes({required int intervalMs, required double distanceFilterM}) {
    final controller = StreamController<Fix>();
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

  PolicyRunner runner(CollectionPolicy policy, {StepDetector? detector}) => PolicyRunner(
        policy: policy,
        detector: detector ?? OsStepDetector(),
        location: location,
        scheduler: scheduler,
        clock: () => now,
        sink: sink,
      );

  setUp(() {
    now = 0;
    scheduler = _FakeScheduler();
    location = _FakeLocation();
    sink = _Sink();
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
    final policy = _Scripted(startActions: const [RequestFix(), WakeAt(tMs: 60000, tag: 'tick')]);
    final r = runner(policy)..start();
    expect(scheduler.pending, 1);

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
}
