import 'dart:math' as math;

import '../events/policy_action.dart';
import '../events/policy_event.dart';
import '../geo.dart';
import '../model/fix.dart';
import 'collection_policy.dart';

/// 지금 정책이 보는 이동 상태. 이름이 fixes.csv의 state 열이 된다.
enum _Mode { unknown, walking, still, otherMotion, vehicle }

/// 측위를 요청한 까닭. 응답이 오면 이 까닭에 따라 다음 할 일을 정한다.
enum _Purpose { start, budget, stay, check, probe1, probe2, vehicle }

/// 제안 수집 정책(설계 5-3). 오차 예산 E 안에서 GPS를 가장 적게 켜도록, 실제로 움직인 만큼만 잰다.
/// - 보행: '마지막 측위 오차 + 그 뒤 걸음 수 × 보폭'이 E를 넘으면 잰다(time_speed는 시간 × 속도로 짐작한다).
/// - 정지: 정지가 30초 이어지면 한 번 재어 머문 곳을 남기고, 그 뒤로는 5분마다 확인만 한다. 확인한 위치가 머문
///   곳에서 벗어났으면 걸음 없이 움직이는 것(버스·지하철)으로 보고 탈것 상태로 바꾼다.
/// - 기타 움직임: 30초 이어지면 30초 간격 확인 측위 두 번으로 속도를 보고, 시속 12km 이상이면 탈것이다.
///   아니면 정지처럼 다룬다.
/// - 탈것: time_speed 규칙('오차 + 속도 × 경과 시간 > E'가 되는 시각에 잰다)으로 잰다. 걸음이 다시 나오면 보행이다.
/// - 측위가 거듭 실패하면(지하철·실내) 다시 시도하는 간격을 30초 → 1분 → 2분 → 5분으로 늘린다.
/// - 배터리가 20% 미만이면 E를 2배로 키운다.
class StepBudgetPolicy implements CollectionPolicy, ReportsState {
  StepBudgetPolicy({
    this.errorBudgetM = 50,
    this.strideM = 0.75,
    this.useSteps = true,
    this.suppressStill = true,
    this.vehicleProbe = true,
  });

  /// 오차 예산 E(m).
  final double errorBudgetM;

  /// 보폭(m). 걸음 수를 움직인 거리로 바꾼다.
  final double strideM;

  /// 절제 실험 스위치. false면 걸음 수 대신 '경과 시간 × 1.4m/s'로 움직인 거리를 짐작한다.
  final bool useSteps;

  /// 절제 실험 스위치. false면 정지해도 측위를 줄이지 않는다(걷기 속도로 움직인다고 보고 계속 잰다).
  final bool suppressStill;

  /// 절제 실험 스위치. false면 기타 움직임에서 탈것 확인 측위를 하지 않고 정지처럼 다룬다.
  final bool vehicleProbe;

  /// 걸음 수를 쓰지 않을 때 가정하는 걷기 속도(m/s, time_speed와 같은 값).
  static const walkingSpeedMps = 1.4;

  /// 이 속도(시속 12km) 이상으로 움직이면 탈것이다.
  static const vehicleSpeedMps = 12 / 3.6;
  /// 정지·기타 움직임이 이만큼 이어져야 그 상태로 측위한다. 폰을 만지거나 신호에 잠깐 멈출 때마다 상태가 몇 초
  /// 단위로 바뀌는데, 바뀔 때마다 재면 실제 세션의 첫 1분에만 15번을 쟀다.
  static const settleMs = 30000;
  static const stillCheckMs = 300000;
  static const probeGapMs = 30000;
  static const minWaitMs = 5000;
  static const maxWaitMs = 600000;
  static const retryDelaysMs = [30000, 60000, 120000, 300000];
  static const lowBatteryPct = 20;

  _Mode _mode = _Mode.unknown;
  _Purpose _purpose = _Purpose.start;
  bool _awaiting = false;
  int _failures = 0;
  int? _retryUntilMs;
  String? _retryTag;
  bool _lowBattery = false;

  /// 정지·느린 기타 움직임에서 기준으로 삼는 위치(머문 곳, 첫 확인 측위).
  Fix? _anchor;
  Fix? _previousVehicleFix;
  double _vehicleSpeedMps = 0;

  /// 지금 유효한 깨우기 예약. 상태가 바뀌면 지워서 앞 상태의 예약이 와도 무시한다(WakeAt은 취소할 수 없다).
  String? _armedTag;
  _Purpose _armedPurpose = _Purpose.budget;
  int _timerSeq = 0;

  @override
  String get id => 'step_budget';

  @override
  Map<String, Object> get params => {
        'e_m': errorBudgetM,
        'stride_m': strideM,
        'use_steps': useSteps,
        'suppress_still': suppressStill,
        'vehicle_probe': vehicleProbe,
      };

  @override
  String get stateLabel => _mode.name;

  double get _budget => errorBudgetM * (_lowBattery ? 2 : 1);

  @override
  List<PolicyAction> onStart(PolicyContext ctx) {
    // 같은 인스턴스를 다시 써도 이전 실행의 상태가 남지 않게 한다.
    _mode = _Mode.unknown;
    _awaiting = false;
    _failures = 0;
    _retryUntilMs = null;
    _retryTag = null;
    _lowBattery = false;
    _anchor = null;
    _previousVehicleFix = null;
    _vehicleSpeedMps = 0;
    _armedTag = null;
    return _request(_Purpose.start, ctx.nowMs);
  }

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    switch (event) {
      case StepUpdate(:final state, :final stepsSinceLastFix):
        return _onStep(state, stepsSinceLastFix, event.tMs, ctx);
      case FixResult(:final fix):
        return fix == null ? _onFailure(event.tMs) : _onFix(fix, ctx);
      case Wakeup(:final tag):
        return _onWakeup(tag, event.tMs);
      case BatteryLevel(:final pct):
        _lowBattery = pct < lowBatteryPct;
        return const [];
      default:
        return const [];
    }
  }

  List<PolicyAction> _onStep(StepState state, int stepsSinceLastFix, int nowMs, PolicyContext ctx) {
    final next = switch (state) {
      StepState.walking => _Mode.walking,
      StepState.still => _Mode.still,
      // 탈것으로 판단한 뒤의 흔들림은 탈것 진동이다 — 다시 확인하지 않는다.
      StepState.otherMotion => _mode == _Mode.vehicle ? _Mode.vehicle : _Mode.otherMotion,
    };
    final actions = <PolicyAction>[];
    if (next != _mode) actions.addAll(_enter(next, nowMs, ctx));
    if (_mode == _Mode.walking && useSteps) {
      final accuracy = ctx.lastFix?.accuracyM ?? 0;
      if (accuracy + stepsSinceLastFix * strideM > _budget) {
        actions.addAll(_request(_Purpose.budget, nowMs));
      }
    }
    return actions;
  }

  List<PolicyAction> _enter(_Mode mode, int nowMs, PolicyContext ctx) {
    _mode = mode;
    // 앞 상태에서 낸 요청·예약은 이제 뜻이 없다. 기다리던 응답은 그냥 위치 하나로 받는다.
    _armedTag = null;
    _purpose = _Purpose.budget;
    switch (mode) {
      case _Mode.walking:
        return useSteps ? const [] : _armWalkingTimer(nowMs, ctx);
      case _Mode.still:
        return suppressStill ? _arm(_Purpose.stay, nowMs + settleMs) : _armWalkingTimer(nowMs, ctx);
      case _Mode.otherMotion:
        return _arm(vehicleProbe ? _Purpose.probe1 : _Purpose.stay, nowMs + settleMs);
      case _Mode.vehicle:
      case _Mode.unknown:
        return const [];
    }
  }

  List<PolicyAction> _onFix(Fix fix, PolicyContext ctx) {
    _awaiting = false;
    _failures = 0;
    _retryUntilMs = null;
    _retryTag = null;
    switch (_purpose) {
      case _Purpose.start:
      case _Purpose.budget:
        // 걸음 수를 쓰지 않는 보행·정지(절제 실험)는 다음 측위 시각을 다시 잡는다.
        return _usesWalkingTimer
            ? _arm(_Purpose.budget, fix.tMs + _waitMs(fix.accuracyM, walkingSpeedMps))
            : const [];
      case _Purpose.stay:
        _anchor = fix;
        return _arm(_Purpose.check, fix.tMs + stillCheckMs);
      case _Purpose.check:
        final anchor = _anchor;
        if (anchor != null && _moved(anchor, fix)) {
          // 걸음 없이 자리를 옮겼다 — 걸음이 나오지 않는 탈것(버스·지하철)이다.
          return _becomeVehicle(_speedBetween(anchor, fix), fix, ctx);
        }
        _anchor ??= fix;
        return _arm(_Purpose.check, fix.tMs + stillCheckMs);
      case _Purpose.probe1:
        _anchor = fix;
        return _arm(_Purpose.probe2, fix.tMs + probeGapMs);
      case _Purpose.probe2:
        final anchor = _anchor;
        final speed = anchor == null ? 0.0 : _speedBetween(anchor, fix);
        if (speed >= vehicleSpeedMps) return _becomeVehicle(speed, fix, ctx);
        // 느린 흔들림(폰 만지기 등)은 정지처럼 다룬다: 이 자리를 기준으로 5분마다 확인만 한다.
        _anchor = fix;
        return _arm(_Purpose.check, fix.tMs + stillCheckMs);
      case _Purpose.vehicle:
        final previous = _previousVehicleFix;
        if (previous != null && fix.tMs > previous.tMs) {
          _vehicleSpeedMps = _speedBetween(previous, fix);
        }
        _previousVehicleFix = fix;
        return _armVehicle(fix);
    }
  }

  List<PolicyAction> _becomeVehicle(double speedMps, Fix fix, PolicyContext ctx) {
    _enter(_Mode.vehicle, fix.tMs, ctx);
    _vehicleSpeedMps = speedMps;
    _previousVehicleFix = fix;
    return _armVehicle(fix);
  }

  /// time_speed 규칙: 지금 오차 + 속도 × 경과 시간이 예산을 넘는 시각에 다시 잰다. 탈것이라 판단한 속도
  /// 하한(시속 12km)을 둬, 신호 대기로 잠깐 멈춘 속도 때문에 너무 오래 쉬지 않게 한다.
  List<PolicyAction> _armVehicle(Fix fix) => _arm(_Purpose.vehicle,
      fix.tMs + _waitMs(fix.accuracyM, math.max(_vehicleSpeedMps, vehicleSpeedMps)));

  List<PolicyAction> _onFailure(int nowMs) {
    _awaiting = false;
    final delay = retryDelaysMs[math.min(_failures, retryDelaysMs.length - 1)];
    _failures++;
    _retryUntilMs = nowMs + delay;
    _timerSeq++;
    final tag = 'retry#$_timerSeq';
    _retryTag = tag;
    return [WakeAt(tMs: nowMs + delay, tag: tag)];
  }

  List<PolicyAction> _onWakeup(String tag, int nowMs) {
    if (tag == _retryTag) {
      _retryTag = null;
      _retryUntilMs = null;
      return _request(_purpose, nowMs);
    }
    if (tag != _armedTag) return const []; // 상태가 바뀌어 무효가 된 예약
    _armedTag = null;
    return _request(_armedPurpose, nowMs);
  }

  /// 측위를 요청한다. 응답을 기다리는 중이거나 실패 뒤 다시 시도할 시각 전이면 까닭만 바꾸고 기다린다 —
  /// 걸음이 계속 들어와도 지하철 안에서 GPS를 쉬지 않고 켜지 않게 한다.
  List<PolicyAction> _request(_Purpose purpose, int nowMs) {
    _purpose = purpose;
    if (_awaiting) return const [];
    final retryUntil = _retryUntilMs;
    if (retryUntil != null && nowMs < retryUntil) return const [];
    _awaiting = true;
    return const [RequestFix()];
  }

  List<PolicyAction> _arm(_Purpose purpose, int atMs) {
    _timerSeq++;
    final tag = '${purpose.name}#$_timerSeq';
    _armedTag = tag;
    _armedPurpose = purpose;
    return [WakeAt(tMs: atMs, tag: tag)];
  }

  bool get _usesWalkingTimer =>
      (_mode == _Mode.walking && !useSteps) || (_mode == _Mode.still && !suppressStill);

  /// 걸음 수를 쓰지 않을 때: 걷기 속도로 움직인다고 보고 오차가 예산을 넘는 시각에 깨운다.
  List<PolicyAction> _armWalkingTimer(int nowMs, PolicyContext ctx) {
    final last = ctx.lastFix;
    if (last == null) return _request(_Purpose.budget, nowMs);
    return _arm(_Purpose.budget, last.tMs + _waitMs(last.accuracyM, walkingSpeedMps));
  }

  int _waitMs(double accuracyM, double speedMps) {
    final remainingM = _budget - accuracyM;
    if (remainingM <= 0) return minWaitMs;
    return (remainingM / speedMps * 1000).round().clamp(minWaitMs, maxWaitMs);
  }

  bool _moved(Fix from, Fix to) =>
      haversineMeters(from.lat, from.lng, to.lat, to.lng) >
      math.max(_budget, from.accuracyM + to.accuracyM);

  double _speedBetween(Fix from, Fix to) {
    final seconds = (to.tMs - from.tMs) / 1000;
    if (seconds <= 0) return 0;
    return haversineMeters(from.lat, from.lng, to.lat, to.lng) / seconds;
  }
}
