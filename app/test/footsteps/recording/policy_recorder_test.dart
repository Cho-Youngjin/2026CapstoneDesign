import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/footsteps/recording/mark.dart';
import 'package:app/features/footsteps/recording/policy_choice.dart';
import 'package:app/features/footsteps/recording/policy_recorder.dart';
import 'package:app/features/footsteps/recording/policy_session_files.dart';
import 'package:app/features/footsteps/recording/sensor_samples.dart';
import 'package:app/features/footsteps/recording/session_meta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footstep_core/footstep_core.dart';
import 'package:path/path.dart' as p;

class _FakeSources implements SensorSources {
  _FakeSources(this.clock);

  final DateTime Function() clock;
  final gpsController = StreamController<GpsSample>();
  /// true면 가속도 구독을 끊을 때 오류가 난다(플랫폼 채널 오류 흉내).
  bool cancelThrows = false;
  bool batteryFails = false;
  late final accelController = StreamController<AccelSample>(onCancel: () {
    if (cancelThrows) throw StateError('플랫폼 오류');
  });
  final stepsController = StreamController<OsStepSample>();
  final activityController = StreamController<ActivitySample>();
  int batteryLevel = 87;
  int batteryReads = 0;

  @override
  Stream<GpsSample> gps() => gpsController.stream;

  @override
  Stream<AccelSample> accel() => accelController.stream;

  @override
  Stream<OsStepSample> osSteps() => stepsController.stream;

  @override
  Stream<ActivitySample> activity() => activityController.stream;

  @override
  Future<BatterySample> readBattery() async {
    batteryReads++;
    if (batteryFails) throw StateError('배터리 읽기 실패');
    return BatterySample(
      at: clock(),
      chargeUah: 3012000,
      currentUa: -180,
      levelPct: batteryLevel,
      tempC: 31.5,
      plugged: false,
    );
  }
}

class _FakeLocation implements LocationPort {
  final requests = <Completer<Fix?>>[];

  @override
  Future<Fix?> currentFix({required int timeoutMs}) {
    final completer = Completer<Fix?>();
    requests.add(completer);
    return completer.future;
  }

  @override
  Stream<Fix> continuousFixes({required int intervalMs, required double distanceFilterM}) =>
      const Stream.empty();
}

class _FakeScheduler implements WakeScheduler {
  final scheduled = <({int atMs, void Function() callback})>[];

  @override
  Object schedule(int atMs, void Function() callback) {
    final entry = (atMs: atMs, callback: callback);
    scheduled.add(entry);
    return entry;
  }

  @override
  void cancel(Object handle) => scheduled.remove(handle);
}

/// 시작하자마자 오류를 던지는 정책.
class _ThrowingPolicy implements CollectionPolicy {
  @override
  String get id => 'throwing';

  @override
  Map<String, Object> get params => const {};

  @override
  List<PolicyAction> onStart(PolicyContext ctx) => throw StateError('정책 오류');

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) => const [];
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late Directory dir;
  late DateTime now;
  late _FakeSources sources;
  late _FakeLocation location;
  late _FakeScheduler scheduler;
  late PolicySessionFiles files;
  late List<SessionError> errors;

  List<String> lines(String name) => File(p.join(dir.path, name)).readAsLinesSync();

  Future<PolicyRecorder> recorder(PolicyChoice choice, {CollectionPolicy? policy}) async {
    files = await PolicySessionFiles.open(dir);
    return PolicyRecorder(
      sources: sources,
      files: files,
      clock: () => now,
      onError: errors.add,
      policy: policy ?? createPolicy(choice.policyId, choice.policyParams),
      detector: createDetector(choice.detectorId, choice.detectorParams),
      location: location,
      scheduler: scheduler,
      needs: PolicySensorNeeds.of(choice),
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('policy_recorder_test');
    now = DateTime.utc(2026, 11, 11, 1);
    sources = _FakeSources(() => now);
    location = _FakeLocation();
    scheduler = _FakeScheduler();
    errors = [];
  });

  tearDown(() async {
    await files.closeAll();
    await dir.delete(recursive: true);
  });

  test('정책 실행 모드는 정책이 쓰는 센서만 켜고, 측위 결과·할 일·배터리를 재생기와 같은 형식으로 쓴다', () async {
    final r = await recorder(const PolicyChoice(policyId: 'step_budget', detectorId: 'adaptive'));
    await r.start();

    expect(sources.accelController.hasListener, isTrue);
    expect(sources.stepsController.hasListener, isFalse);
    expect(sources.activityController.hasListener, isFalse);
    expect(sources.gpsController.hasListener, isFalse); // 1초 GPS는 쓰지 않는다
    expect(location.requests, hasLength(1)); // step_budget은 시작하자마자 한 번 잰다

    final t0 = now.millisecondsSinceEpoch;
    now = now.add(const Duration(seconds: 3));
    location.requests.single.complete(
        Fix(tMs: now.millisecondsSinceEpoch, lat: 37.5665, lng: 126.978, accuracyM: 6.5));
    await _settle();
    await r.tick();

    final t1 = now.millisecondsSinceEpoch;
    expect(lines('fixes.csv'), [
      't_ms,lat,lng,accuracy_m,steps_since_prev,state,kind',
      '$t1,37.5665,126.978,6.5,0,unknown,single',
    ]);
    expect(lines('actions.csv'), ['t_ms,action,args', '$t0,request_fix,timeout_ms=15000']);
    expect(lines('battery.csv')[1], '$t0,3012000,-180,87,31.5,0');
    expect(lines('wakeups.csv'), ['t_ms,tag,scheduled_ms,delay_ms']);

    final status = r.status;
    expect(status.policyState, 'unknown');
    expect(status.lastGpsAccuracyM, 6.5);
    expect(status.rowCounts['fixes.csv'], 1);
  });

  test('걸음을 쓰지 않는 정책은 걸음 센서를 켜지 않고, activity_gated는 활동 인식만 켠다', () async {
    final fixed = await recorder(const PolicyChoice(policyId: 'fixed_1m', detectorId: 'adaptive'));
    await fixed.start();
    expect(sources.accelController.hasListener, isFalse);
    expect(sources.stepsController.hasListener, isFalse);
    expect(sources.activityController.hasListener, isFalse);
    await fixed.stop();

    sources = _FakeSources(() => now);
    final gated = await recorder(const PolicyChoice(policyId: 'activity_gated', detectorId: 'os'));
    await gated.start();
    expect(sources.activityController.hasListener, isTrue);
    expect(sources.stepsController.hasListener, isFalse);
  });

  test('관찰 표시는 marks.csv에 쓰고 알림 버튼 상태에 반영한다', () async {
    final r = await recorder(const PolicyChoice(policyId: 'fixed_1m', detectorId: 'os'));
    await r.start();
    r.mark(Mark(at: now, kind: MarkKind.board, value: 'bus'));
    await r.tick();

    expect(lines('marks.csv')[1], '${now.millisecondsSinceEpoch},board,bus');
    expect(r.field.onVehicle, isTrue);
  });

  test('stop하면 summary.json을 쓰고, 예약한 깨우기를 거둔다', () async {
    final r = await recorder(const PolicyChoice(policyId: 'fixed_1m', detectorId: 'os'));
    await r.start();
    expect(scheduler.scheduled, hasLength(2)); // 1분 뒤 다음 측위와 위치 요청 감시 타이머

    now = now.add(const Duration(minutes: 2));
    await r.stop();

    expect(scheduler.scheduled, isEmpty);
    final summary =
        jsonDecode(File(p.join(dir.path, 'summary.json')).readAsStringSync()) as Map<String, Object?>;
    expect(summary['policy_id'], 'fixed_1m');
    expect(summary['detector_id'], 'os');
    expect(summary['fix_requests'], 1);
    expect(summary['duration_s'], 120.0);
  });

  group('센서 값은 실행기로 간다', () {
    test('OS 걸음 센서 값은 걸음 감지기로 가서 측위 뒤 걸음 수가 된다', () async {
      final r = await recorder(const PolicyChoice(policyId: 'still_suppress', detectorId: 'os'));
      await r.start();
      expect(sources.stepsController.hasListener, isTrue);

      sources.stepsController
        ..add(OsStepSample(at: now, kind: OsStepKind.count, value: '100'))
        ..add(OsStepSample(at: now.add(const Duration(seconds: 1)), kind: OsStepKind.count, value: '112'));
      await _settle();
      expect(r.status.stepsSinceFix, 12);
    });

    test('OS 센서판은 가속도 없이 기록 서비스의 주기를 시계로 써서, 멈춘 뒤 정지로 바뀐다', () async {
      final r = await recorder(const PolicyChoice(policyId: 'step_budget', detectorId: 'os'));
      await r.start();
      expect(sources.accelController.hasListener, isFalse);

      sources.stepsController
        ..add(OsStepSample(at: now, kind: OsStepKind.count, value: '100'))
        ..add(OsStepSample(at: now.add(const Duration(seconds: 1)), kind: OsStepKind.count, value: '112'))
        ..add(OsStepSample(at: now.add(const Duration(seconds: 3)), kind: OsStepKind.status, value: 'stopped'));
      await _settle();
      expect(r.status.policyState, 'walking');

      now = now.add(const Duration(seconds: 6)); // 마지막 걸음 뒤 5초
      await r.tick();
      expect(r.status.policyState, 'still');
    });

    test('가속도는 1초 묶음으로 걸음 감지기에 가서 정책 상태를 바꾼다', () async {
      final r = await recorder(const PolicyChoice(policyId: 'step_budget', detectorId: 'adaptive'));
      await r.start();
      expect(r.status.policyState, 'unknown');

      for (var ms = 0; ms <= 2000; ms += 10) {
        sources.accelController.add(AccelSample(at: now.add(Duration(milliseconds: ms)), x: 0, y: 9.81, z: 0));
      }
      await _settle();
      expect(r.status.policyState, 'still'); // 제안판 감지기가 첫 1초 묶음에서 정지를 알렸다
    });

    test('활동 인식 값은 activity_gated로 가서, 확실한 정지면 연속 측위를 끈다', () async {
      final r = await recorder(const PolicyChoice(policyId: 'activity_gated', detectorId: 'os'));
      await r.start();

      sources.activityController.add(ActivitySample(at: now, type: 'STILL', confidence: 'HIGH'));
      await _settle();
      await r.tick();
      expect(lines('actions.csv').skip(1).map((l) => l.split(',')[1]), ['start_continuous', 'stop_continuous']);
    });
  });

  test('배터리는 시작할 때와 그 뒤 30초마다 읽는다', () async {
    final r = await recorder(const PolicyChoice(policyId: 'fixed_1m', detectorId: 'os'));
    await r.start();
    expect(sources.batteryReads, 1);

    now = now.add(const Duration(seconds: 29));
    await r.tick();
    expect(sources.batteryReads, 1);
    now = now.add(const Duration(seconds: 1));
    await r.tick();
    expect(sources.batteryReads, 2);
    expect(lines('battery.csv'), hasLength(3)); // 머리줄 + 두 번
  });

  group('오류가 나도 기록을 이어간다', () {
    test('센서 하나가 오류를 내면 오류를 남기고 계속 듣는다', () async {
      final r = await recorder(const PolicyChoice(policyId: 'step_budget', detectorId: 'adaptive'));
      await r.start();

      sources.accelController.addError(StateError('센서 끊김'));
      await _settle();
      expect(errors.single.source, 'accel');
      expect(r.status.errorCount, 1);
      expect(sources.accelController.hasListener, isTrue);
    });

    test('배터리 읽기가 실패해도 오류를 남기고 정책은 그대로 돈다', () async {
      sources.batteryFails = true;
      final r = await recorder(const PolicyChoice(policyId: 'fixed_1m', detectorId: 'os'));
      await r.start();

      expect(errors.single.source, 'battery');
      expect(location.requests, hasLength(1));
    });

    test('실행기가 알린 오류(정책 오류)도 오류로 남긴다', () async {
      final r = await recorder(const PolicyChoice(policyId: 'fixed_1m', detectorId: 'os'), policy: _ThrowingPolicy());
      await r.start();

      expect(errors.single.source, 'runner');
    });

    test('센서를 끊다 오류가 나도 summary.json을 쓰고 마친다', () async {
      sources.cancelThrows = true;
      final r = await recorder(const PolicyChoice(policyId: 'step_budget', detectorId: 'adaptive'));
      await r.start();

      await r.stop();
      expect(errors.map((e) => e.source), contains('stop'));
      expect(File(p.join(dir.path, 'summary.json')).existsSync(), isTrue);
    });
  });

  test('stop하면 센서 구독을 끊고, start·stop을 두 번 불러도 괜찮다', () async {
    final r = await recorder(const PolicyChoice(policyId: 'step_budget', detectorId: 'adaptive'));
    await r.start();
    await r.start(); // 단일 구독 스트림을 두 번 들으면 StateError가 난다
    expect(sources.batteryReads, 1);

    await r.stop();
    expect(sources.accelController.hasListener, isFalse);
    await r.stop();
  });
}
