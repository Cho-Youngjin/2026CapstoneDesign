import 'dart:async';
import 'dart:math' as math;

import '../detectors/os_step_detector.dart';
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
/// - WakeAt → 타이머(지난 시각은 지금으로 당긴다). 실제로 깬 시각으로 Wakeup을 보내고, 늦게 깬 만큼을 기록한다.
/// 위치를 알릴 때는 그때까지의 걸음 수와 상태를 기록하고 걸음 감지기의 onFix를 부른다. 가속도는 재생기와 같은
/// 1초 묶음([AccelBatcher])으로 걸음 감지기에 넣는다. 시계·GPS·타이머는 밖에서 넣어, 테스트가 시간을 손으로 넘긴다.
///
/// 몇 시간씩 도는 기록이라 한 곳의 오류가 수집 전체를 멈추지 않게 한다. 기록(sink)·정책·걸음 감지기·GPS에서 난
/// 오류는 [onError]로 알리고 계속 돈다. GPS 포트가 끝내 답하지 않으면 시간 제한 + [watchdogMarginMs] 뒤 실패로 본다.
/// [start]는 한 번만 부를 수 있고, 그 전에 들어온 센서 값은 버린다.
class PolicyRunner {
  PolicyRunner({
    required this.policy,
    required this.detector,
    required this.location,
    required this.scheduler,
    required this.clock,
    required this.sink,
    this.onError,
    int accelBatchMs = 1000,
  }) : _batcher = AccelBatcher(accelBatchMs);

  /// GPS 포트가 시간 제한을 넘기고도 답하지 않을 때(플러그인 멈춤 등) 실패로 보기까지 더 기다리는 시간.
  static const watchdogMarginMs = 5000;

  final CollectionPolicy policy;
  final StepDetector detector;
  final LocationPort location;
  final WakeScheduler scheduler;

  /// 지금 시각(UTC epoch ms).
  final int Function() clock;
  final RunnerSink sink;

  /// 기록·정책·걸음 감지기·GPS에서 난 오류를 받는다(폰에서는 meta.json의 errors로 간다). 없으면 버린다.
  final void Function(Object error, StackTrace stack)? onError;
  final AccelBatcher _batcher;

  bool _started = false;
  bool _running = false;
  Future<RunSummary>? _summary;
  int _startMs = 0;
  Fix? _lastFix;
  int? _lastBatteryPct;

  bool _fixPending = false;
  int _requestSeq = 0;
  int _requestStartMs = 0;
  Object? _watchdog;
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

  /// 기록을 시작한다. 이미 돌고 있으면 아무것도 하지 않는다. 멈춘 뒤 다시 시작할 수는 없다 — 앞 실행의 늦은 응답이
  /// 새 실행의 요청에 대한 답으로 섞이지 않게, 실행마다 새 실행기를 만든다.
  void start() {
    if (_running) return;
    if (_started) throw StateError('PolicyRunner는 한 번만 시작할 수 있다. 새 실행기를 만든다.');
    _started = true;
    _running = true;
    _startMs = clock();
    _apply(_guard(() => policy.onStart(_ctx()), const <PolicyAction>[]));
  }

  void addAccel(AccelReading reading) {
    if (!_running) return;
    final batch = _batcher.add(reading);
    if (batch != null) _deliverStep(_guard(() => detector.onAccel(batch.last.tMs, batch), null));
  }

  void addOsStep(OsStepReading reading) {
    if (!_running) return;
    _deliverStep(_guard(() => detector.onOsStep(reading), null));
  }

  void addActivity(ActivityReading reading) {
    if (!_running) return;
    _deliver(ActivityUpdate(tMs: reading.tMs, type: reading.type, confidence: reading.confidence));
  }

  /// OS 센서판 걸음 감지기의 시계를 지금으로 넘긴다. 이 감지기는 마지막 걸음 뒤 [OsStepDetector.walkingWindowMs]가
  /// 지나야 정지로 바뀌고, 그 시각을 가속도 묶음 시각으로 안다. 그런데 정책 실행 모드는 배터리를 아끼려고 OS
  /// 센서판에 가속도를 켜지 않는다. 안드로이드 걸음 센서는 멈춘 지 약 2초 뒤 'stopped'를 한 번 보내고 조용해지므로,
  /// 시계를 넘겨 주지 않으면 멈춘 뒤에도 영영 보행으로 남는다. 기록 서비스의 주기(5초)마다 부른다 — 그래서 정지로
  /// 바뀌는 시각이 재생(1초 묶음)보다 최대 5초 늦을 수 있다. 가속도를 듣는 감지기에는 아무것도 하지 않는다.
  void advanceDetectorClock() {
    if (!_running || detector is! OsStepDetector) return;
    _deliverStep(_guard(() => detector.onAccel(clock(), const []), null));
  }

  /// 배터리 잔량은 바뀔 때만 정책에 알린다(재생기와 같은 규칙).
  void addBatteryLevel(int tMs, int pct) {
    if (!_running || pct == _lastBatteryPct) return;
    _lastBatteryPct = pct;
    _deliver(BatteryLevel(tMs: tMs, pct: pct));
  }

  /// 멈추고 요약을 돌려준다. 예약한 깨우기를 취소하고 연속 측위를 끊는다. 그 뒤에 오는 응답은 무시한다.
  /// 여러 번 불러도 처음의 요약을 그대로 돌려준다. 마지막 1초 묶음이 덜 찬 가속도는 버린다(멈춘 뒤라 알리지 않는다).
  Future<RunSummary> stop() => _summary ??= _stop();

  Future<RunSummary> _stop() async {
    final now = clock();
    if (!_started) _startMs = now;
    _started = true;
    _running = false;
    for (final handle in _wakeHandles) {
      _safely(() => scheduler.cancel(handle));
    }
    _wakeHandles.clear();
    _cancelWatchdog();
    if (_fixPending) {
      _gpsOnMs += now - _requestStartMs;
      _fixPending = false;
    }
    final continuous = _continuous;
    if (continuous != null) {
      _gpsOnMs += now - _continuousSinceMs;
      _continuous = null;
    }
    // 요약에 들어갈 값은 모두 정했다. 구독을 끊다 오류가 나도(플랫폼 채널) 요약은 돌려준다.
    final summary = RunSummary(
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
    if (continuous != null) {
      try {
        await continuous.cancel();
      } catch (error, stack) {
        _report(error, stack);
      }
    }
    return summary;
  }

  PolicyContext _ctx() => PolicyContext(nowMs: clock(), lastFix: _lastFix);

  void _deliverStep(StepUpdate? update) {
    if (update != null) _deliver(update);
  }

  void _deliver(PolicyEvent event) => _apply(_guard(() => policy.onEvent(event, _ctx()), const <PolicyAction>[]));

  void _apply(List<PolicyAction> actions) {
    for (final action in actions) {
      if (!_running) return;
      _safely(() => sink.action(ActionRecord(tMs: clock(), action: action)));
      switch (action) {
        case RequestFix(:final timeoutMs):
          _requestFix(timeoutMs);
        case final StartContinuous settings:
          _startContinuous(settings);
        case StopContinuous():
          _endContinuous(clock());
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
    // 요청마다 번호를 붙여, 감시 타이머로 실패 처리한 뒤에 온 늦은 응답이 다음 요청의 답으로 섞이지 않게 한다.
    final seq = ++_requestSeq;
    // GPS 포트가 끝내 답하지 않아도 수집이 멈추지 않게 한다. 재생기는 요청을 언제나 시간 제한 안에 끝낸다.
    _watchdog = scheduler.schedule(_requestStartMs + timeoutMs + watchdogMarginMs, () {
      _watchdog = null;
      _onFixResult(seq, null);
    });
    Future<Fix?> request;
    try {
      request = location.currentFix(timeoutMs: timeoutMs);
    } catch (error, stack) {
      _report(error, stack);
      request = Future.value(null); // 바로 던진 오류도 실패로 다루되, 정책에는 다음 차례에 알린다
    }
    unawaited(
      request.then(
        (fix) => _onFixResult(seq, fix),
        onError: (Object error, StackTrace stack) {
          _report(error, stack);
          _onFixResult(seq, null); // 위치 서비스 오류도 실패로 다룬다(정책이 다시 시도할 수 있게)
        },
      ),
    );
  }

  void _onFixResult(int seq, Fix? fix) {
    if (!_running || !_fixPending || seq != _requestSeq) return;
    _cancelWatchdog();
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

  void _cancelWatchdog() {
    final watchdog = _watchdog;
    if (watchdog == null) return;
    _watchdog = null;
    _safely(() => scheduler.cancel(watchdog));
  }

  void _startContinuous(StartContinuous settings) {
    final now = clock();
    // 켜져 있는데 다시 받으면 설정을 바꿔 새로 켠다(재생기와 같은 규칙).
    _endContinuous(now);
    try {
      late final StreamSubscription<Fix> subscription;
      subscription = location
          .continuousFixes(intervalMs: settings.intervalMs, distanceFilterM: settings.distanceFilterM)
          .listen(
            _onContinuousFix,
            onError: _report,
            // 스트림이 스스로 끝나면 GPS도 꺼진 것이다: 켜진 시간을 거기까지만 센다.
            onDone: () {
              if (identical(_continuous, subscription)) _endContinuous(clock());
            },
          );
      _continuous = subscription;
      _continuousSinceMs = now;
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  void _endContinuous(int now) {
    final continuous = _continuous;
    if (continuous == null) return;
    _gpsOnMs += now - _continuousSinceMs;
    _continuous = null;
    unawaited(continuous.cancel().catchError(_report));
  }

  void _onContinuousFix(Fix fix) {
    if (!_running) return;
    _continuousFixes++;
    _record(fix, 'continuous');
    _deliver(ContinuousFix(tMs: fix.tMs, fix: fix));
  }

  void _record(Fix fix, String kind) {
    _safely(
      () => sink.fix(FixRecord(fix: fix, stepsSincePrev: detector.stepsSinceLastFix, state: stateLabel, kind: kind)),
    );
    _safely(detector.onFix);
    _lastFix = fix;
  }

  void _scheduleWake(int atMs, String tag) {
    // 지난 시각은 지금으로 당긴다(재생기와 같은 규칙). 그래야 깨우기 지연에 정책의 늦은 예약이 섞이지 않고, 타이머가
    // 늦게 깬 만큼만 남는다.
    final scheduledMs = math.max(atMs, clock());
    late final Object handle;
    handle = scheduler.schedule(scheduledMs, () {
      _wakeHandles.remove(handle);
      if (!_running) return;
      final now = clock();
      final record = WakeupRecord(tMs: now, tag: tag, scheduledMs: scheduledMs);
      _safely(() => sink.wakeup(record));
      _wakeDelaysMs.add(math.max(0, record.delayMs));
      // 정책은 실제로 깬 시각을 받는다. 늦게 깨도 다음 예약이 그 시각 기준으로 잡혀 한꺼번에 몰리지 않는다.
      _deliver(Wakeup(tMs: now, tag: tag));
    });
    _wakeHandles.add(handle);
  }

  /// [body]를 부르고, 오류가 나면 알린 뒤 [fallback]을 돌려준다(정책·걸음 감지기 호출).
  T _guard<T>(T Function() body, T fallback) {
    try {
      return body();
    } catch (error, stack) {
      _report(error, stack);
      return fallback;
    }
  }

  void _safely(void Function() body) {
    try {
      body();
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  void _report(Object error, StackTrace stack) {
    final handler = onError;
    if (handler == null) return;
    try {
      handler(error, stack);
    } catch (_) {
      // 오류를 받는 곳의 오류까지 퍼뜨리면 수집이 멈춘다. 더 알릴 곳이 없어 버린다.
    }
  }
}
