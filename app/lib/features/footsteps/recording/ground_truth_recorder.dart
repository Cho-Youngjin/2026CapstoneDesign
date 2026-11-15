import 'dart:async';

import 'csv_writer.dart';
import 'mark.dart';
import 'recorder_status.dart';
import 'sensor_samples.dart';
import 'session_files.dart';
import 'session_meta.dart';
import 'session_recorder.dart';
import 'session_schema.dart';

/// 정답 기록 모드(설계 4-2). 모든 센서를 최대 빈도로 받아 세션 폴더의 CSV에 쓴다.
///
/// 타이머를 안에 두지 않는다. 기록 서비스가 5초마다 [tick]을 불러 배터리 읽기와 디스크 쓰기를
/// 맡기고, 테스트는 시각을 직접 넘긴다.
class GroundTruthRecorder implements SessionRecorder {
  GroundTruthRecorder({
    required this.sources,
    required this.files,
    required this.clock,
    required this.onError,
    this.batteryInterval = const Duration(seconds: 30),
  });

  final SensorSources sources;
  final SessionFiles files;
  final DateTime Function() clock;
  final void Function(SessionError error) onError;
  final Duration batteryInterval;

  /// 지금 장소 안인지, 탈것에 탔는지. 알림 버튼 토글이 다음 표시를 정할 때 쓴다.
  @override
  final FieldState field = FieldState();

  final _subscriptions = <StreamSubscription<Object?>>[];
  DateTime? _startedAt;
  DateTime? _lastBatteryAt;
  int _errorCount = 0;
  double? _lastGpsAccuracyM;
  int? _lastOsSteps;
  int? _lastChargeUah;
  int? _lastLevelPct;

  @override
  Future<void> start() async {
    _startedAt = clock();
    _listen(sources.gps(), 'gps', (GpsSample s) {
      files.gps.add(s.toCsvRow());
      _lastGpsAccuracyM = s.accuracyM;
    });
    _listen(sources.accel(), 'accel', (AccelSample s) => files.accel.add(s.toCsvRow()));
    _listen(sources.osSteps(), 'os_steps', (OsStepSample s) {
      files.osSteps.add(s.toCsvRow());
      if (s.kind == OsStepKind.count) _lastOsSteps = int.tryParse(s.value);
    });
    _listen(
      sources.activity(),
      'activity',
      (ActivitySample s) => files.activity.add(s.toCsvRow()),
    );
    await _readBattery();
  }

  /// 센서 하나가 실패해도 나머지는 계속 기록한다(설계 4-2). 실패는 meta.json의 errors로 남긴다.
  void _listen<T>(Stream<T> stream, String source, void Function(T sample) onSample) {
    _subscriptions.add(stream.listen(onSample, onError: (Object e) => _reportError(source, e)));
  }

  /// 서비스의 반복 이벤트(5초)마다 부른다. 배터리는 [batteryInterval]마다만 읽는다.
  @override
  Future<void> tick() async {
    final last = _lastBatteryAt;
    if (last == null || clock().difference(last) >= batteryInterval) await _readBattery();
    await files.flushAll();
  }

  @override
  void mark(Mark mark) {
    field.observe(mark);
    files.marks.add(mark.toCsvRow());
  }

  @override
  RecorderStatus get status {
    final writers = <String, CsvWriter>{
      SessionSchema.gpsFile: files.gps,
      SessionSchema.accelFile: files.accel,
      SessionSchema.osStepsFile: files.osSteps,
      SessionSchema.activityFile: files.activity,
      SessionSchema.batteryFile: files.battery,
      SessionSchema.marksFile: files.marks,
    };
    return RecorderStatus(
      startedAt: _startedAt ?? clock(),
      rowCounts: {for (final e in writers.entries) e.key: e.value.totalRows},
      errorCount: _errorCount,
      atPlace: field.atPlace,
      onVehicle: field.onVehicle,
      carry: field.carry,
      lastGpsAccuracyM: _lastGpsAccuracyM,
      lastOsSteps: _lastOsSteps,
      lastChargeUah: _lastChargeUah,
      lastLevelPct: _lastLevelPct,
    );
  }

  @override
  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await files.closeAll();
  }

  Future<void> _readBattery() async {
    _lastBatteryAt = clock();
    try {
      final battery = await sources.readBattery();
      files.battery.add(battery.toCsvRow());
      _lastChargeUah = battery.chargeUah;
      _lastLevelPct = battery.levelPct;
    } catch (e) {
      _reportError('battery', e);
    }
  }

  void _reportError(String source, Object error) {
    _errorCount++;
    onError(SessionError(at: clock(), source: source, message: '$error'));
  }
}
