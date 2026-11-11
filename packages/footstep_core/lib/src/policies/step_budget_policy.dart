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
///   마지막 측위 뒤 5초 안에는 다시 재지 않는다.
/// - 정지: 정지가 30초 이어지면 한 번 재어 머문 곳을 남기고, 그 뒤로는 5분마다 확인만 한다. 확인한 위치가 머문
///   곳에서 벗어났으면 걸음 없이 움직이는 것(버스·지하철)으로 보고 탈것 상태로 바꾼다.
/// - 기타 움직임: 30초 이어지면 30초 간격 확인 측위 두 번으로 속도를 보고, 두 위치가 오차보다 멀고 시속 12km
///   이상이면 탈것이다. 아니면 정지처럼 다룬다.
/// - 탈것: time_speed 규칙('오차 + 속도 × 경과 시간 > E'가 되는 시각에 잰다)으로 잰다. 걸음이 다시 나오면 보행이다.
///   감지기 정지와 측위상 한 자리가 둘 다 2분 넘게 이어질 때만 정지로 본다(빨간불·정류장 정차는 탈것 그대로).
///   GPS가 크게 흔들려 한 자리로 보이지 않아도, E 안에 5분 넘게 머물면 정지로 본다(잘못 본 탈것이 오래 남지 않게).
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

  /// 절제 실험 스위치. false면 정지해도, 정지처럼 다루는 기타 움직임에서도 측위를 줄이지 않는다(걷기 속도로
  /// 움직인다고 보고 계속 잰다).
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

  /// 탈것에서 정지로 바꾸려면 감지기 정지와 측위상 한 자리가 둘 다 이만큼 이어져야 한다. 빨간불·정류장 정차(보통
  /// 40초~2분)마다 탈것을 놓으면, 다시 찾는 동안(제안판 감지기 약 1분, OS판 최대 5분) 버스가 수백 m~수 km를 간다.
  static const vehicleStopMs = 120000;

  /// 정지 중 확인 측위 간격.
  static const stillCheckMs = 300000;

  /// 기타 움직임에서 확인 측위 두 번 사이 간격.
  static const probeGapMs = 30000;

  /// 측위와 측위 사이 최소·최대 간격(time_speed와 같은 값).
  static const minWaitMs = 5000;
  static const maxWaitMs = 600000;

  /// 측위가 거듭 실패할 때 다시 시도하기까지 기다리는 시간. 마지막 값을 계속 쓴다.
  static const retryDelaysMs = [30000, 60000, 120000, 300000];

  /// 배터리가 이 값(%) 미만이면 E를 2배로 키운다.
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

  /// 탈것에서 마지막으로 움직인 것이 확인된 측위. 뒤따르는 측위가 이 위치의 두 오차 안에 머물면 멈춰 있는 것이다.
  Fix? _stopFix;

  /// 탈것에서 E 넘게 움직인 것이 마지막으로 확인된 측위. [_stopFix]보다 느슨한 멈춤 기준이다.
  Fix? _longStopFix;

  /// 걸음 감지기가 마지막으로 알린 상태와, 정지가 시작된 시각(정지가 아니면 null). 탈것에서 벗어날지 판단할 때 쓴다.
  StepState? _detectorState;
  int? _stillSinceMs;

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
    _stopFix = null;
    _longStopFix = null;
    _detectorState = null;
    _stillSinceMs = null;
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
    if (state != _detectorState) {
      _detectorState = state;
      _stillSinceMs = state == StepState.still ? nowMs : null;
    }
    final next = switch (state) {
      StepState.walking => _Mode.walking,
      // 탈것 안의 정지(신호 대기)와 흔들림(진동)은 탈것 그대로다. 탈것에서 벗어나는 것은 걸음이 나오거나, 감지기
      // 정지와 측위상 한 자리가 둘 다 2분 넘게 이어졌을 때다(_onFix의 탈것 처리).
      StepState.still => _mode == _Mode.vehicle ? _Mode.vehicle : _Mode.still,
      StepState.otherMotion => _mode == _Mode.vehicle ? _Mode.vehicle : _Mode.otherMotion,
    };
    final actions = <PolicyAction>[];
    if (next != _mode) actions.addAll(_enter(next, nowMs, ctx));
    if (_mode == _Mode.walking && useSteps) {
      final last = ctx.lastFix;
      final accuracy = last?.accuracyM ?? 0;
      // 마지막 측위 뒤 최소 간격(5초)은 지킨다. 측위 오차만으로 예산을 넘는 곳(빌딩 숲·실내)에서 걸음 사건마다
      // 다시 재면 연속 측위와 다르지 않다(time_speed도 같은 최소 간격을 둔다).
      final tooSoon = last != null && nowMs - last.tMs < minWaitMs;
      if (!tooSoon && accuracy + stepsSinceLastFix * strideM > _budget) {
        actions.addAll(_request(_Purpose.budget, nowMs));
      }
    }
    return actions;
  }

  List<PolicyAction> _enter(_Mode mode, int nowMs, PolicyContext ctx) {
    _setMode(mode);
    switch (mode) {
      case _Mode.walking:
        return useSteps ? const [] : _armWalkingTimer(nowMs, ctx);
      case _Mode.still:
        return _settleAsStill(nowMs, ctx);
      case _Mode.otherMotion:
        return vehicleProbe ? _arm(_Purpose.probe1, nowMs + settleMs) : _settleAsStill(nowMs, ctx);
      case _Mode.vehicle:
      case _Mode.unknown:
        return const [];
    }
  }

  /// 앞 상태에서 낸 요청·예약은 이제 뜻이 없다. 기다리던 응답은 그냥 위치 하나로 받는다.
  void _setMode(_Mode mode) {
    _mode = mode;
    _armedTag = null;
    _purpose = _Purpose.budget;
  }

  /// 정지(또는 정지처럼 다루는 기타 움직임)로 들어간다: 30초 이어지면 머문 곳을 잰다. 정지 억제를 끈 절제
  /// 실험에서는 걷기 속도로 움직인다고 보고 계속 잰다.
  List<PolicyAction> _settleAsStill(int nowMs, PolicyContext ctx) =>
      suppressStill ? _arm(_Purpose.stay, nowMs + settleMs) : _armWalkingTimer(nowMs, ctx);

  /// [fix]를 머문 곳으로 삼아 정지처럼 지낸다: 5분마다 확인만 한다. 정지 억제를 끈 절제 실험에서는 계속 잰다 —
  /// 정지와 '정지처럼 다루는' 경로 모두에 같은 스위치가 걸려야 억제의 효과를 온전히 잴 수 있다.
  List<PolicyAction> _holdAt(Fix fix) {
    if (!suppressStill) {
      return _arm(_Purpose.budget, fix.tMs + _waitMs(fix.accuracyM, walkingSpeedMps));
    }
    _anchor = fix;
    return _arm(_Purpose.check, fix.tMs + stillCheckMs);
  }

  List<PolicyAction> _onFix(Fix fix, PolicyContext ctx) {
    _awaiting = false;
    _failures = 0;
    _retryUntilMs = null;
    _retryTag = null;
    switch (_purpose) {
      case _Purpose.start:
      case _Purpose.budget:
        // 걸음 수를 쓰지 않는 보행, 정지 억제를 끈 정지·기타 움직임(절제 실험)은 다음 측위 시각을 이 위치 기준으로
        // 다시 잡는다. 기타 움직임의 확인 측위 예약이 걸려 있으면 덮어쓰지 않는다.
        final probing = _armedTag != null && _armedPurpose != _Purpose.budget;
        return _usesWalkingTimer && !probing
            ? _arm(_Purpose.budget, fix.tMs + _waitMs(fix.accuracyM, walkingSpeedMps))
            : const [];
      case _Purpose.stay:
        return _holdAt(fix);
      case _Purpose.check:
        final anchor = _anchor;
        if (anchor != null && _moved(anchor, fix)) {
          // 걸음 없이 자리를 옮겼다 — 걸음이 나오지 않는 탈것(버스·지하철)이다.
          return _becomeVehicle(_speedBetween(anchor, fix), fix);
        }
        _anchor ??= fix;
        return _arm(_Purpose.check, fix.tMs + stillCheckMs);
      case _Purpose.probe1:
        _anchor = fix;
        return _arm(_Purpose.probe2, fix.tMs + probeGapMs);
      case _Purpose.probe2:
        final anchor = _anchor;
        // 두 위치가 서로의 오차보다 멀어야 움직인 것이다. 오차가 큰 두 위치(예: 각 60m)는 가만히 있어도 30초 만에
        // 100m 넘게 떨어져 보여, 속도만 보면 탈것으로 잘못 본다. 탈것 기준은 속도(시속 12km)라 E와 묶지 않는다.
        if (anchor != null && !_within(anchor, fix)) {
          final speed = _speedBetween(anchor, fix);
          if (speed >= vehicleSpeedMps) return _becomeVehicle(speed, fix);
        }
        // 느린 흔들림(폰 만지기 등)은 정지처럼 다룬다.
        return _holdAt(fix);
      case _Purpose.vehicle:
        final previous = _previousVehicleFix;
        final stillSince = _stillSinceMs;
        // 멈춤은 예산(E)이 아니라 오차로 본다: 시속 10km로 기어가는 버스도 13.5초면 E 안이지만 서 있는 것은 아니다.
        final stop = _stopFix;
        final inPlace = stop != null && _within(stop, fix);
        if (!inPlace) _stopFix = fix; // 움직였다: 여기서부터 멈춘 시간을 다시 잰다.
        // GPS가 알린 오차보다 크게 흔들리면 위 기준이 계속 다시 시작된다. 그래서 E 안에 5분 넘게 머무는 것도 멈춘
        // 것으로 본다 — 잘못 본 탈것(실내 GPS 튐)이 13.5초마다 재며 오래 남지 않게 한다.
        final longStop = _longStopFix;
        final nearby = longStop != null && !_moved(longStop, fix);
        if (!nearby) _longStopFix = fix;
        // 감지기 시계만 보면 안 된다: OS 걸음 센서판은 달리는 버스 안에서도 늘 정지라 첫 정류장에서 놓친다.
        final stopped =
            stillSince != null &&
            ((stop != null && inPlace && fix.tMs - math.max(stillSince, stop.tMs) >= vehicleStopMs) ||
                (longStop != null && nearby && fix.tMs - math.max(stillSince, longStop.tMs) >= stillCheckMs));
        if (stopped) {
          // 감지기 정지와 측위상 머묾이 이어졌다 — 탈것에서 내려 멈췄거나 잘못 본 탈것이다.
          _setMode(_Mode.still);
          return _holdAt(fix);
        }
        if (previous != null && fix.tMs > previous.tMs) {
          _vehicleSpeedMps = _speedBetween(previous, fix);
        }
        _previousVehicleFix = fix;
        return _armVehicle(fix);
    }
  }

  List<PolicyAction> _becomeVehicle(double speedMps, Fix fix) {
    _setMode(_Mode.vehicle);
    _vehicleSpeedMps = speedMps;
    _previousVehicleFix = fix;
    _stopFix = fix;
    _longStopFix = fix;
    return _armVehicle(fix);
  }

  /// time_speed 규칙: 지금 오차 + 속도 × 경과 시간이 예산을 넘는 시각에 다시 잰다. 탈것이라 판단한 속도
  /// 하한(시속 12km)을 둬, 신호 대기로 잠깐 멈춘 속도 때문에 너무 오래 쉬지 않게 한다.
  List<PolicyAction> _armVehicle(Fix fix) =>
      _arm(_Purpose.vehicle, fix.tMs + _waitMs(fix.accuracyM, math.max(_vehicleSpeedMps, vehicleSpeedMps)));

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
      (_mode == _Mode.walking && !useSteps) || (!suppressStill && (_mode == _Mode.still || _mode == _Mode.otherMotion));

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

  /// 두 위치가 서로의 오차 안에 있다 — 움직였다고 말할 수 없다.
  bool _within(Fix a, Fix b) => haversineMeters(a.lat, a.lng, b.lat, b.lng) <= a.accuracyM + b.accuracyM;

  /// 머문 곳에서 벗어났다: 예산(E)과 두 오차의 합 중 큰 것보다 멀다.
  bool _moved(Fix from, Fix to) =>
      haversineMeters(from.lat, from.lng, to.lat, to.lng) > math.max(_budget, from.accuracyM + to.accuracyM);

  double _speedBetween(Fix from, Fix to) {
    final seconds = (to.tMs - from.tMs) / 1000;
    if (seconds <= 0) return 0;
    return haversineMeters(from.lat, from.lng, to.lat, to.lng) / seconds;
  }
}
