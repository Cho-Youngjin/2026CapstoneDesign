import 'dart:async';
import 'dart:convert';

import 'package:footstep_core/footstep_core.dart';

import 'mark.dart';
import 'policy_choice.dart';
import 'policy_session_files.dart';
import 'recorder_status.dart';
import 'sensor_samples.dart';
import 'session_meta.dart';
import 'session_recorder.dart';

/// 정책 실행 모드(설계 4-1·5-5, 배터리 실험). 고른 정책 하나를 걸음 감지기와 함께 폰에서 돌리고, 측위 결과·할 일·
/// 깨우기 지연·배터리·관찰 표시만 쓴다. 1초 GPS와 가속도 원본은 쓰지 않는다 — 정답 기록을 같이 돌리면 배터리
/// 측정이 오염된다. 센서도 정책이 쓰는 것만 켠다([PolicySensorNeeds]).
///
/// 타이머를 안에 두지 않는다. 기록 서비스가 5초마다 [tick]을 불러 배터리 읽기와 디스크 쓰기를 맡긴다.
class PolicyRecorder implements SessionRecorder {
  PolicyRecorder({
    required this.sources,
    required this.files,
    required this.clock,
    required this.onError,
    required CollectionPolicy policy,
    required StepDetector detector,
    required LocationPort location,
    required WakeScheduler scheduler,
    required this.needs,
    this.batteryInterval = const Duration(seconds: 30),
  }) {
    _runner = PolicyRunner(
      policy: policy,
      detector: detector,
      location: location,
      scheduler: scheduler,
      clock: () => clock().millisecondsSinceEpoch,
      sink: _FileSink(files),
      onError: (error, _) => _reportError('runner', error),
    );
  }

  final SensorSources sources;
  final PolicySessionFiles files;
  final DateTime Function() clock;
  final void Function(SessionError error) onError;
  final PolicySensorNeeds needs;
  final Duration batteryInterval;
  late final PolicyRunner _runner;

  @override
  final FieldState field = FieldState();

  final _subscriptions = <StreamSubscription<Object?>>[];
  DateTime? _startedAt;
  DateTime? _lastBatteryAt;
  int _errorCount = 0;
  int? _lastChargeUah;
  int? _lastLevelPct;

  @override
  Future<void> start() async {
    _startedAt = clock();
    _runner.start();
    if (needs.accel) {
      _listen(sources.accel(), 'accel', (AccelSample s) {
        _runner.addAccel(AccelReading(tMs: s.at.millisecondsSinceEpoch, x: s.x, y: s.y, z: s.z));
      });
    }
    if (needs.osSteps) {
      _listen(sources.osSteps(), 'os_steps', (OsStepSample s) {
        _runner.addOsStep(
            OsStepReading(tMs: s.at.millisecondsSinceEpoch, kind: s.kind, value: s.value));
      });
    }
    if (needs.activity) {
      _listen(sources.activity(), 'activity', (ActivitySample s) {
        _runner.addActivity(ActivityReading(
            tMs: s.at.millisecondsSinceEpoch, type: s.type, confidence: s.confidence));
      });
    }
    await _readBattery();
  }

  /// 센서 하나가 실패해도 나머지는 계속 돈다. 실패는 meta.json의 errors로 남긴다.
  void _listen<T>(Stream<T> stream, String source, void Function(T sample) onSample) {
    _subscriptions.add(stream.listen(onSample, onError: (Object e) => _reportError(source, e)));
  }

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
    return RecorderStatus(
      startedAt: _startedAt ?? clock(),
      rowCounts: {
        ReplaySchema.fixesFile: files.fixes.totalRows,
        ReplaySchema.actionsFile: files.actions.totalRows,
        RunnerSchema.wakeupsFile: files.wakeups.totalRows,
        SessionSchema.batteryFile: files.battery.totalRows,
        SessionSchema.marksFile: files.marks.totalRows,
      },
      errorCount: _errorCount,
      atPlace: field.atPlace,
      onVehicle: field.onVehicle,
      carry: field.carry,
      lastGpsAccuracyM: _runner.lastFix?.accuracyM,
      lastChargeUah: _lastChargeUah,
      lastLevelPct: _lastLevelPct,
      policyState: _runner.stateLabel,
      stepsSinceFix: _runner.stepsSinceLastFix,
    );
  }

  @override
  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final summary = await _runner.stop();
    try {
      await files.summaryFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(summary.toJson()),
        flush: true,
      );
    } catch (e) {
      _reportError('summary', e);
    }
    await files.closeAll();
  }

  Future<void> _readBattery() async {
    _lastBatteryAt = clock();
    try {
      final battery = await sources.readBattery();
      files.battery.add(battery.toCsvRow());
      _lastChargeUah = battery.chargeUah;
      final level = battery.levelPct;
      _lastLevelPct = level;
      // 정책이 배터리 20% 미만 대응을 할 수 있게 잔량을 알린다(바뀔 때만 — 실행기가 거른다).
      if (level != null) _runner.addBatteryLevel(battery.at.millisecondsSinceEpoch, level);
    } catch (e) {
      _reportError('battery', e);
    }
  }

  void _reportError(String source, Object error) {
    _errorCount++;
    onError(SessionError(at: clock(), source: source, message: '$error'));
  }
}

/// 실행기의 기록을 세션 CSV에 쓴다. 열 순서는 재생기 결과와 같다.
class _FileSink implements RunnerSink {
  _FileSink(this.files);

  final PolicySessionFiles files;

  @override
  void fix(FixRecord record) => files.fixes.add([
        record.tMs,
        record.fix.lat,
        record.fix.lng,
        record.fix.accuracyM,
        record.stepsSincePrev,
        record.state,
        record.kind,
      ]);

  @override
  void action(ActionRecord record) =>
      files.actions.add([record.tMs, record.action.logName, record.action.logArgs]);

  @override
  void wakeup(WakeupRecord record) =>
      files.wakeups.add([record.tMs, record.tag, record.scheduledMs, record.delayMs]);
}
