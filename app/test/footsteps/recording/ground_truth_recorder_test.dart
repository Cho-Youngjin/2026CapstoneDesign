import 'dart:async';
import 'dart:io';

import 'package:app/features/footsteps/recording/ground_truth_recorder.dart';
import 'package:app/features/footsteps/recording/mark.dart';
import 'package:app/features/footsteps/recording/recorder_status.dart';
import 'package:app/features/footsteps/recording/sensor_samples.dart';
import 'package:app/features/footsteps/recording/session_files.dart';
import 'package:app/features/footsteps/recording/session_meta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeSources implements SensorSources {
  _FakeSources(this.clock);

  final DateTime Function() clock;
  final gpsController = StreamController<GpsSample>();
  final accelController = StreamController<AccelSample>();
  final stepsController = StreamController<OsStepSample>();
  final activityController = StreamController<ActivitySample>();
  final batteryReads = <DateTime>[];
  Object? batteryError;

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
    final at = clock();
    batteryReads.add(at);
    final error = batteryError;
    if (error != null) throw error;
    return BatterySample(
      at: at,
      chargeUah: 3012000,
      currentUa: -250000,
      levelPct: 87,
      tempC: 31.5,
      plugged: false,
    );
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late Directory dir;
  late DateTime now;
  late _FakeSources sources;
  late SessionFiles files;
  late List<SessionError> errors;
  late GroundTruthRecorder recorder;

  List<String> lines(String name) => File(p.join(dir.path, name)).readAsLinesSync();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('recorder_test');
    now = DateTime.utc(2026, 11, 9, 1);
    sources = _FakeSources(() => now);
    files = await SessionFiles.open(dir);
    errors = [];
    recorder = GroundTruthRecorder(
      sources: sources,
      files: files,
      clock: () => now,
      onError: errors.add,
    );
  });

  tearDown(() async {
    // Windows는 열린 파일이 있으면 폴더를 지우지 못한다. stop을 부른 테스트도 있어 close는 여러 번 불러도 된다.
    await files.closeAll();
    await dir.delete(recursive: true);
  });

  test('start하면 배터리를 한 번 읽고, 각 센서 값을 해당 CSV에 쓴다', () async {
    await recorder.start();
    final t = now.millisecondsSinceEpoch;
    sources.gpsController.add(GpsSample(
      at: now,
      fixTime: now.subtract(const Duration(seconds: 1)),
      lat: 37.5665,
      lng: 126.978,
      accuracyM: 8.0,
      speedMps: 1.2,
      bearingDeg: 90.0,
      altitudeM: 35.0,
    ));
    sources.accelController.add(AccelSample(at: now, x: 0.1, y: 9.8, z: -0.2));
    sources.stepsController.add(OsStepSample(at: now, kind: OsStepKind.count, value: '1520'));
    sources.stepsController.add(OsStepSample(at: now, kind: OsStepKind.status, value: 'walking'));
    sources.activityController.add(ActivitySample(at: now, type: 'WALKING', confidence: 'HIGH'));
    await _settle();
    await recorder.tick();

    expect(sources.batteryReads, hasLength(1));
    expect(lines('gps.csv')[1], '$t,${t - 1000},37.5665,126.978,8.0,1.2,90.0,35.0');
    expect(lines('accel.csv')[1], '$t,0.1,9.8,-0.2');
    expect(lines('os_steps.csv').sublist(1), ['$t,count,1520', '$t,status,walking']);
    expect(lines('activity.csv')[1], '$t,WALKING,HIGH');
    expect(lines('battery.csv')[1], '$t,3012000,-250000,87,31.5,0');
  });

  test('배터리는 30초가 지나야 다시 읽는다', () async {
    await recorder.start();
    now = now.add(const Duration(seconds: 5));
    await recorder.tick();
    expect(sources.batteryReads, hasLength(1));

    now = now.add(const Duration(seconds: 25));
    await recorder.tick();
    expect(sources.batteryReads, hasLength(2));
  });

  test('센서 하나가 오류를 내도 오류를 남기고 다른 센서는 계속 쓴다', () async {
    await recorder.start();
    sources.stepsController.addError(StateError('no step sensor'));
    sources.accelController.add(AccelSample(at: now, x: 0, y: 0, z: 9.8));
    await _settle();
    await recorder.tick();

    expect(errors.single.source, 'os_steps');
    expect(errors.single.message, contains('no step sensor'));
    expect(lines('accel.csv'), hasLength(2));
    expect(recorder.status.errorCount, 1);
  });

  test('배터리 읽기 실패는 오류로 남기고 행은 쓰지 않는다', () async {
    sources.batteryError = StateError('probe failed');
    await recorder.start();
    await recorder.tick();

    expect(errors.single.source, 'battery');
    expect(lines('battery.csv'), hasLength(1)); // 헤더만
  });

  test('mark는 marks.csv에 쓰고 현장 상태를 바꾼다', () async {
    await recorder.start();
    recorder.mark(Mark(at: now, kind: MarkKind.board, value: VehicleType.subway));
    await recorder.tick();

    expect(lines('marks.csv')[1], '${now.millisecondsSinceEpoch},board,subway');
    expect(recorder.field.onVehicle, isTrue);
    expect(recorder.status.onVehicle, isTrue);
  });

  test('stop하면 구독을 끊고 남은 행을 쓴다', () async {
    await recorder.start();
    sources.accelController.add(AccelSample(at: now, x: 1, y: 2, z: 3));
    await _settle();
    await recorder.stop();

    expect(lines('accel.csv'), hasLength(2));
    expect(sources.gpsController.hasListener, isFalse);
    expect(sources.accelController.hasListener, isFalse);
  });

  test('status는 행 수와 마지막 값을 담고 json으로 오간다', () async {
    await recorder.start();
    sources.gpsController.add(GpsSample(at: now, fixTime: now, lat: 37, lng: 127, accuracyM: 4.5));
    sources.stepsController.add(OsStepSample(at: now, kind: OsStepKind.count, value: '10'));
    await _settle();

    final status = recorder.status;
    expect(status.rowCounts['gps.csv'], 1);
    expect(status.rowCounts['battery.csv'], 1);
    expect(status.lastGpsAccuracyM, 4.5);
    expect(status.lastOsSteps, 10);
    expect(status.lastChargeUah, 3012000);
    expect(status.lastLevelPct, 87);

    final back = RecorderStatus.fromJson(status.toJson());
    expect(back.toJson(), status.toJson());
  });
}
