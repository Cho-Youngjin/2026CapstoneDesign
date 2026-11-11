import 'dart:math' as math;

import '../detectors/step_detector.dart';
import '../detectors/step_timeline.dart';
import '../events/policy_action.dart';
import '../events/policy_event.dart';
import '../geo.dart';
import '../model/fix.dart';
import '../model/readings.dart';
import '../policies/collection_policy.dart';
import '../session/session_reader.dart';
import '../stays/stay_detector.dart';
import '../steps/step_run.dart';
import 'accel_batches.dart';
import 'replay_result.dart';

/// 재생 설정(설계 5-4).
class ReplayConfig {
  const ReplayConfig({this.ttffMs = 0, this.accelBatchMs = 1000, this.stays = const StayParams()});

  /// GPS를 켠 뒤 첫 위치가 나오기까지 걸린다고 가정하는 시간. 기록은 GPS가 계속 켜져 있던 값이라
  /// '켜자마자 위치가 나온다'고 가정하게 되는 약점을 0·5·10초로 바꿔 가며 줄인다.
  final int ttffMs;

  /// 가속도를 걸음 감지기에 넘기는 묶음 길이. 표본 간격은 기기마다 다르다(Galaxy S23은 약 10ms).
  final int accelBatchMs;

  /// 재생이 끝난 뒤 남은 점으로 머문 곳을 묶는 설정(설계 5-6).
  final StayParams stays;
}

/// 세션 기록으로 정책을 재생한다. 정책은 요청한 시각 이후의 정보만 받으므로 미래 정보를 쓸 수 없고,
/// 같은 입력이면 항상 같은 결과가 나온다(설계 5-4).
ReplayResult replaySession(
  SessionData data,
  CollectionPolicy policy,
  StepDetector detector, {
  ReplayConfig config = const ReplayConfig(),
}) {
  // 음수 ttff는 응답이 과거로 예약돼 시계가 거꾸로 가고 GPS 켜짐 시간이 음수가 된다. 묶음 길이가 0 이하면
  // 가속도 묶음이 만들어지지 않거나 표본마다 쪼개진다. 조용히 틀린 결과를 내느니 바로 알린다.
  if (config.ttffMs < 0) throw ArgumentError('ttffMs는 0 이상이어야 합니다: ${config.ttffMs}');
  if (config.accelBatchMs <= 0) {
    throw ArgumentError('accelBatchMs는 양수여야 합니다: ${config.accelBatchMs}');
  }
  config.stays.check();
  return _Replay(data, policy, detector, config).run();
}

sealed class _External {
  const _External(this.tMs, this.order);

  final int tMs;

  /// 같은 시각일 때의 처리 순서(작을수록 먼저).
  final int order;
}

final class _GpsRow extends _External {
  _GpsRow(this.fix) : super(fix.tMs, 0);

  final Fix fix;
}

final class _AccelBatch extends _External {
  _AccelBatch(this.readings) : super(readings.last.tMs, 1);

  final List<AccelReading> readings;
}

final class _OsStep extends _External {
  _OsStep(this.reading) : super(reading.tMs, 2);

  final OsStepReading reading;
}

final class _Activity extends _External {
  _Activity(this.reading) : super(reading.tMs, 3);

  final ActivityReading reading;
}

final class _Battery extends _External {
  _Battery(this.reading) : super(reading.tMs, 4);

  final BatteryLevelReading reading;
}

sealed class _Scheduled {
  _Scheduled(this.tMs);

  final int tMs;
}

final class _Wake extends _Scheduled {
  _Wake(super.tMs, this.tag);

  final String tag;
}

final class _FixResponse extends _Scheduled {
  _FixResponse(super.tMs, {required this.requestMs, this.fix});

  final int requestMs;
  final Fix? fix;
}

class _Replay {
  _Replay(this.data, this.policy, this.detector, this.config);

  final SessionData data;
  final CollectionPolicy policy;
  final StepDetector detector;
  final ReplayConfig config;

  final _fixes = <FixRecord>[];
  final _actions = <ActionRecord>[];

  /// 걸음 감지기 상태가 바뀐 순간들. 머문 곳 묶기가 정지 구간으로 쓴다(걸음 CLI의 step_states.csv와 같은 규칙).
  final _stepStates = <StateChange>[];

  /// 예약 사건. 시각순으로 유지하고, 같은 시각은 예약한 순서대로 둔다.
  final _scheduled = <_Scheduled>[];

  int _nowMs = 0;
  Fix? _lastFix;
  _FixResponse? _pendingFix;
  StartContinuous? _continuous;
  int _continuousSinceMs = 0;
  Fix? _lastContinuous;

  int _fixRequests = 0;
  int _fixSuccesses = 0;
  int _fixFailures = 0;
  int _continuousFixes = 0;
  int _gpsOnMs = 0;

  ReplayResult run() {
    final start = data.startMs;
    final end = data.endMs;
    if (start == null || end == null) {
      throw ArgumentError('세션에 기록이 없습니다: ${data.sessionId}');
    }
    final timeline = _buildTimeline();

    _nowMs = start;
    _apply(policy.onStart(_ctx()));

    var next = 0;
    while (true) {
      final external = next < timeline.length ? timeline[next] : null;
      final scheduled = _scheduled.isEmpty ? null : _scheduled.first;
      if (external == null && scheduled == null) break;
      // 같은 시각이면 예약 사건(깨우기·측위 응답)을 먼저 처리한다 — 결정적인 순서를 위해서다.
      if (scheduled != null && (external == null || scheduled.tMs <= external.tMs)) {
        if (scheduled.tMs > end) break;
        _nowMs = scheduled.tMs;
        _scheduled.removeAt(0);
        _handleScheduled(scheduled);
      } else if (external != null) {
        if (external.tMs > end) break;
        _nowMs = external.tMs;
        next++;
        _handleExternal(external);
      }
    }

    // 끝 시각에 켜져 있거나 응답을 기다리는 중이면 끝 시각까지 GPS가 켜져 있던 것으로 센다.
    if (_continuous != null) _gpsOnMs += end - _continuousSinceMs;
    final pending = _pendingFix;
    if (pending != null) _gpsOnMs += end - pending.requestMs;

    final fixes = _recountSteps(_fixes);
    final stays = detectStays(
      [for (final record in fixes) record.fix],
      stillSpans: stillSpans(_stepStates, end),
      params: config.stays,
    );
    return ReplayResult(
      fixes: List.unmodifiable(fixes),
      actions: List.unmodifiable(_actions),
      stays: List.unmodifiable(stays),
      summary: ReplaySummary(
        sessionId: data.sessionId,
        policyId: policy.id,
        policyParams: policy.params,
        detectorId: detector.id,
        detectorParams: detector.params,
        ttffMs: config.ttffMs,
        startMs: start,
        endMs: end,
        fixRequests: _fixRequests,
        fixSuccesses: _fixSuccesses,
        fixFailures: _fixFailures,
        continuousFixes: _continuousFixes,
        gpsOnMs: _gpsOnMs,
        stayParams: config.stays.params,
        stayCount: stays.length,
      ),
    );
  }

  PolicyContext _ctx() => PolicyContext(nowMs: _nowMs, lastFix: _lastFix);

  List<_External> _buildTimeline() {
    final items = <_External>[
      for (final fix in data.fixes) _GpsRow(fix),
      for (final batch in accelBatches(data.accel, config.accelBatchMs)) _AccelBatch(batch),
      for (final reading in data.osSteps) _OsStep(reading),
      for (final reading in data.activities) _Activity(reading),
      ..._batteryChanges(),
    ];
    final order = List<int>.generate(items.length, (i) => i);
    order.sort((a, b) {
      final x = items[a];
      final y = items[b];
      final byTime = x.tMs.compareTo(y.tMs);
      if (byTime != 0) return byTime;
      final byKind = x.order.compareTo(y.order);
      return byKind != 0 ? byKind : a.compareTo(b);
    });
    return [for (final i in order) items[i]];
  }

  Iterable<_Battery> _batteryChanges() sync* {
    int? last;
    for (final reading in data.battery) {
      if (reading.levelPct != last) {
        last = reading.levelPct;
        yield _Battery(reading);
      }
    }
  }

  void _handleExternal(_External event) {
    switch (event) {
      case _GpsRow(:final fix):
        _maybeDeliverContinuous(fix);
      case _AccelBatch(:final readings):
        _deliverStep(detector.onAccel(event.tMs, readings));
      case _OsStep(:final reading):
        _deliverStep(detector.onOsStep(reading));
      case _Activity(:final reading):
        _deliver(ActivityUpdate(tMs: event.tMs, type: reading.type, confidence: reading.confidence));
      case _Battery(:final reading):
        _deliver(BatteryLevel(tMs: event.tMs, pct: reading.levelPct));
    }
  }

  void _handleScheduled(_Scheduled event) {
    switch (event) {
      case _Wake(:final tag):
        _deliver(Wakeup(tMs: event.tMs, tag: tag));
      case _FixResponse(:final requestMs, :final fix):
        _pendingFix = null;
        _gpsOnMs += event.tMs - requestMs;
        if (fix == null) {
          _fixFailures++;
        } else {
          _fixSuccesses++;
          _recordFix(fix, 'single');
        }
        _deliver(FixResult(tMs: event.tMs, fix: fix));
    }
  }

  void _maybeDeliverContinuous(Fix row) {
    final settings = _continuous;
    if (settings == null) return;
    // 연속 측위를 켜도 첫 위치는 ttff 뒤에 나온다.
    if (row.tMs < _continuousSinceMs + config.ttffMs) return;
    final last = _lastContinuous;
    if (last != null) {
      // 간격은 10% 여유를 둔다 — 1초를 요청해도 실제 기록 간격은 990~1010ms로 흔들린다.
      if (row.tMs - last.tMs < settings.intervalMs * 0.9) return;
      if (settings.distanceFilterM > 0 &&
          haversineMeters(last.lat, last.lng, row.lat, row.lng) < settings.distanceFilterM) {
        return;
      }
    }
    _lastContinuous = row;
    _continuousFixes++;
    _recordFix(row, 'continuous');
    _deliver(ContinuousFix(tMs: row.tMs, fix: row));
  }

  void _recordFix(Fix fix, String kind) {
    _fixes.add(FixRecord(
      fix: fix,
      stepsSincePrev: detector.stepsSinceLastFix,
      state: _stateLabel(),
      kind: kind,
    ));
    detector.onFix();
    _lastFix = fix;
  }

  String _stateLabel() {
    if (policy case ReportsState(:final stateLabel)) return stateLabel;
    return detector.state.name;
  }

  /// fixes.csv의 steps_since_prev를 걸음 시각으로 다시 센다: 직전 측위 시각 이상 ~ 이 측위 시각 미만의 걸음 수.
  ///
  /// 정책에 알린 stepsSinceLastFix는 그 순간까지 센 걸음뿐이다. 제안판 감지기는 연속 5걸음을 확인한 뒤 앞선 걸음을
  /// 소급해 세므로, 걷기 시작하고 몇 초 안에 측위하면 그 앞 걸음은 측위 이전 몫으로 늦게 셈해져 어느 행에도
  /// 남지 않았다. 정책은 미래를 보면 안 되므로 그대로 두고, 결과 파일만 재생이 끝난 뒤 바로잡는다. 걸음 시각을
  /// 모르는 감지기는 알린 값을 그대로 쓴다.
  List<FixRecord> _recountSteps(List<FixRecord> fixes) {
    if (detector case final StepTimeline timeline) {
      final times = timeline.takeStepTimes()..sort();
      final recounted = <FixRecord>[];
      var next = 0;
      for (final record in fixes) {
        final from = next;
        while (next < times.length && times[next] < record.tMs) {
          next++;
        }
        recounted.add(FixRecord(
          fix: record.fix,
          stepsSincePrev: next - from,
          state: record.state,
          kind: record.kind,
        ));
      }
      return recounted;
    }
    return fixes;
  }

  void _deliverStep(StepUpdate? update) {
    if (update == null) return;
    if (_stepStates.isEmpty || _stepStates.last.state != update.state) {
      _stepStates.add(StateChange(tMs: update.tMs, state: update.state, cadenceHz: update.cadenceHz));
    }
    _deliver(update);
  }

  void _deliver(PolicyEvent event) => _apply(policy.onEvent(event, _ctx()));

  void _apply(List<PolicyAction> actions) {
    for (final action in actions) {
      _actions.add(ActionRecord(tMs: _nowMs, action: action));
      switch (action) {
        case RequestFix(:final timeoutMs):
          _requestFix(timeoutMs);
        case final StartContinuous start:
          if (_continuous != null) _gpsOnMs += _nowMs - _continuousSinceMs;
          _continuous = start;
          _continuousSinceMs = _nowMs;
          _lastContinuous = null;
        case StopContinuous():
          if (_continuous != null) {
            _gpsOnMs += _nowMs - _continuousSinceMs;
            _continuous = null;
          }
        case WakeAt(:final tMs, :final tag):
          _schedule(_Wake(math.max(tMs, _nowMs), tag));
      }
    }
  }

  void _requestFix(int timeoutMs) {
    // 이미 응답을 기다리는 중이면 새로 켜지 않는다 — 실제 기기도 진행 중인 요청에 합쳐진다.
    if (_pendingFix != null) return;
    _fixRequests++;
    final deadline = _nowMs + timeoutMs;
    final index = _firstFixAtOrAfter(_nowMs + config.ttffMs);
    final row = index < data.fixes.length ? data.fixes[index] : null;
    final response = row != null && row.tMs <= deadline
        ? _FixResponse(row.tMs, requestMs: _nowMs, fix: row)
        : _FixResponse(deadline, requestMs: _nowMs);
    _pendingFix = response;
    _schedule(response);
  }

  int _firstFixAtOrAfter(int tMs) {
    var low = 0;
    var high = data.fixes.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (data.fixes[mid].tMs < tMs) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  void _schedule(_Scheduled event) {
    // 같은 시각인 사건 뒤에 넣어 예약한 순서를 지킨다.
    var i = _scheduled.length;
    while (i > 0 && _scheduled[i - 1].tMs > event.tMs) {
      i--;
    }
    _scheduled.insert(i, event);
  }
}
