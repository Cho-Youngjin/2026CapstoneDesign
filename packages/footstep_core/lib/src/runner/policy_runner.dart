import 'dart:async';
import 'dart:math' as math;

import '../detectors/step_detector.dart';
import '../events/policy_action.dart';
import '../events/policy_event.dart';
import '../model/fix.dart';
import '../model/readings.dart';
import '../policies/collection_policy.dart';
import '../replay/accel_batches.dart';
import '../replay/replay_result.dart';
import 'run_summary.dart';
import 'runner_ports.dart';

/// 폰에서 정책을 실제로 돌리는 실행기(설계 5-5, R4 정책 실행 모드·R7 여행 기록이 같이 쓴다).
/// 재생기와 같은 규칙으로 할 일을 실제 동작으로 바꾼다.
/// - RequestFix → 위치 한 번. 응답을 기다리는 중의 새 요청은 합친다.
/// - StartContinuous·StopContinuous → 연속 측위 구독·해제.
/// - WakeAt → 타이머. 실제로 깬 시각으로 Wakeup을 보내고, 늦게 깬 만큼을 기록한다.
/// 위치를 알릴 때는 그때까지의 걸음 수와 상태를 기록하고 걸음 감지기의 onFix를 부른다. 가속도는 재생기와 같은
/// 1초 묶음([AccelBatcher])으로 걸음 감지기에 넣는다. 시계·GPS·타이머는 밖에서 넣어, 테스트가 시간을 손으로 넘긴다.
class PolicyRunner {
  PolicyRunner({
    required this.policy,
    required this.detector,
    required this.location,
    required this.scheduler,
    required this.clock,
    required this.sink,
    int accelBatchMs = 1000,
  }) : _batcher = AccelBatcher(accelBatchMs);

  final CollectionPolicy policy;
  final StepDetector detector;
  final LocationPort location;
  final WakeScheduler scheduler;

  /// 지금 시각(UTC epoch ms).
  final int Function() clock;
  final RunnerSink sink;
  final AccelBatcher _batcher;

  bool _running = false;
  int _startMs = 0;
  Fix? _lastFix;
  int? _lastBatteryPct;

  bool _fixPending = false;
  int _requestStartMs = 0;
  StreamSubscription<Fix>? _continuous;
  int _continuousSinceMs = 0;
  final _wakeHandles = <Object>{};

  int _fixRequests = 0;
  int _fixSuccesses = 0;
  int _fixFailures = 0;
  int _continuousFixes = 0;
  int _gpsOnMs = 0;
  final _wakeDelaysMs = <int>[];

  bool get isRunning => _running;

  Fix? get lastFix => _lastFix;

  int get fixCount => _fixSuccesses + _continuousFixes;

  int get stepsSinceLastFix => detector.stepsSinceLastFix;

  /// fixes.csv의 state 열과 같은 이름. 정책이 상태를 알리면(ReportsState) 그것을, 아니면 걸음 감지기 상태를 쓴다.
  String get stateLabel {
    if (policy case ReportsState(:final stateLabel)) return stateLabel;
    return detector.state.name;
  }

  void start() {
    if (_running) return;
    _running = true;
    _startMs = clock();
    _apply(policy.onStart(_ctx()));
  }

  void addAccel(AccelReading reading) {
    if (!_running) return;
    final batch = _batcher.add(reading);
    if (batch != null) _deliverStep(detector.onAccel(batch.last.tMs, batch));
  }

  void addOsStep(OsStepReading reading) {
    if (!_running) return;
    _deliverStep(detector.onOsStep(reading));
  }

  void addActivity(ActivityReading reading) {
    if (!_running) return;
    _deliver(ActivityUpdate(tMs: reading.tMs, type: reading.type, confidence: reading.confidence));
  }

  /// 배터리 잔량은 바뀔 때만 정책에 알린다(재생기와 같은 규칙).
  void addBatteryLevel(int tMs, int pct) {
    if (!_running || pct == _lastBatteryPct) return;
    _lastBatteryPct = pct;
    _deliver(BatteryLevel(tMs: tMs, pct: pct));
  }

  /// 멈추고 요약을 돌려준다. 예약한 깨우기를 취소하고 연속 측위를 끊는다. 그 뒤에 오는 응답은 무시한다.
  Future<RunSummary> stop() async {
    final now = clock();
    if (_running) {
      _running = false;
      for (final handle in _wakeHandles) {
        scheduler.cancel(handle);
      }
      _wakeHandles.clear();
      final continuous = _continuous;
      if (continuous != null) {
        _gpsOnMs += now - _continuousSinceMs;
        _continuous = null;
        await continuous.cancel();
      }
      if (_fixPending) {
        _gpsOnMs += now - _requestStartMs;
        _fixPending = false;
      }
    }
    return RunSummary(
      policyId: policy.id,
      policyParams: policy.params,
      detectorId: detector.id,
      detectorParams: detector.params,
      startMs: _startMs,
      endMs: now,
      fixRequests: _fixRequests,
      fixSuccesses: _fixSuccesses,
      fixFailures: _fixFailures,
      continuousFixes: _continuousFixes,
      gpsOnMs: _gpsOnMs,
      wakeDelaysMs: List.unmodifiable(_wakeDelaysMs),
    );
  }

  PolicyContext _ctx() => PolicyContext(nowMs: clock(), lastFix: _lastFix);

  void _deliverStep(StepUpdate? update) {
    if (update != null) _deliver(update);
  }

  void _deliver(PolicyEvent event) => _apply(policy.onEvent(event, _ctx()));

  void _apply(List<PolicyAction> actions) {
    for (final action in actions) {
      if (!_running) return;
      sink.action(ActionRecord(tMs: clock(), action: action));
      switch (action) {
        case RequestFix(:final timeoutMs):
          _requestFix(timeoutMs);
        case final StartContinuous settings:
          _startContinuous(settings);
        case StopContinuous():
          _stopContinuous();
        case WakeAt(:final tMs, :final tag):
          _scheduleWake(tMs, tag);
      }
    }
  }

  void _requestFix(int timeoutMs) {
    // 응답을 기다리는 중이면 새로 켜지 않는다 — 재생기와 같은 규칙이고, 실제 기기도 진행 중인 요청에 합친다.
    if (_fixPending) return;
    _fixPending = true;
    _fixRequests++;
    _requestStartMs = clock();
    unawaited(location
        .currentFix(timeoutMs: timeoutMs)
        .catchError((Object _) => null) // 위치 서비스 오류도 실패로 다룬다(정책이 다시 시도할 수 있게)
        .then(_onFixResult));
  }

  void _onFixResult(Fix? fix) {
    if (!_running || !_fixPending) return;
    final now = clock();
    _fixPending = false;
    _gpsOnMs += now - _requestStartMs;
    if (fix == null) {
      _fixFailures++;
    } else {
      _fixSuccesses++;
      _record(fix, 'single');
    }
    _deliver(FixResult(tMs: now, fix: fix));
  }

  void _startContinuous(StartContinuous settings) {
    final now = clock();
    final previous = _continuous;
    if (previous != null) {
      // 켜져 있는데 다시 받으면 설정을 바꿔 새로 켠다(재생기와 같은 규칙).
      _gpsOnMs += now - _continuousSinceMs;
      unawaited(previous.cancel());
    }
    _continuousSinceMs = now;
    _continuous = location
        .continuousFixes(intervalMs: settings.intervalMs, distanceFilterM: settings.distanceFilterM)
        .listen(_onContinuousFix, onError: (Object _) {});
  }

  void _stopContinuous() {
    final continuous = _continuous;
    if (continuous == null) return;
    _gpsOnMs += clock() - _continuousSinceMs;
    _continuous = null;
    unawaited(continuous.cancel());
  }

  void _onContinuousFix(Fix fix) {
    if (!_running) return;
    _continuousFixes++;
    _record(fix, 'continuous');
    _deliver(ContinuousFix(tMs: fix.tMs, fix: fix));
  }

  void _record(Fix fix, String kind) {
    sink.fix(FixRecord(
      fix: fix,
      stepsSincePrev: detector.stepsSinceLastFix,
      state: stateLabel,
      kind: kind,
    ));
    detector.onFix();
    _lastFix = fix;
  }

  void _scheduleWake(int atMs, String tag) {
    late final Object handle;
    handle = scheduler.schedule(atMs, () {
      _wakeHandles.remove(handle);
      if (!_running) return;
      final now = clock();
      final record = WakeupRecord(tMs: now, tag: tag, scheduledMs: atMs);
      sink.wakeup(record);
      _wakeDelaysMs.add(math.max(0, record.delayMs));
      // 정책은 실제로 깬 시각을 받는다. 늦게 깨도 다음 예약이 그 시각 기준으로 잡혀 한꺼번에 몰리지 않는다.
      _deliver(Wakeup(tMs: now, tag: tag));
    });
    _wakeHandles.add(handle);
  }
}
