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
  final accelController = StreamController<AccelSample>();
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

  Future<PolicyRecorder> recorder(PolicyChoice choice) async {
    files = await PolicySessionFiles.open(dir);
    return PolicyRecorder(
      sources: sources,
      files: files,
      clock: () => now,
      onError: errors.add,
      policy: createPolicy(choice.policyId, choice.policyParams),
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
}
