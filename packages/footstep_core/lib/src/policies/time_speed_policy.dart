import 'dart:math' as math;

import '../events/policy_action.dart';
import '../events/policy_event.dart';
import 'collection_policy.dart';

/// 시간 × 속도 오차 추정 측위(EnTracked, MobiSys 2009 · RAPS, MobiSys 2010의 원리).
/// '마지막 측위 오차 + 속도 × 경과 시간'이 오차 예산 E를 넘는 시각에 다시 측위한다.
/// 속도는 마지막 측위의 속도를 쓰되 걷기 속도 1.4m/s를 하한으로 둔다 — 서 있다가 걷기 시작해도 오차가 예산을
/// 넘기 전에 다시 재기 위해서다. 제안 정책(R4)은 이 '시간 × 속도' 대신 실제 걸음 수를 쓴다.
///
/// [stillGate]를 켜면 EnTracked(4.1절)처럼 멈춤/움직임 두 상태로 GPS를 쉰다(id `time_speed_still`).
/// - 걸음 감지기가 멈춤이라고 하면 다음 측위를 예약하지 않고, 예약해 둔 시각이 와도 건너뛴다.
/// - 다시 움직이면(보행·기타 움직임) 바로 한 번 잰다 — EnTracked는 움직임을 감지하면 GPS로 속도를 잰 뒤
///   오차 모델로 다음 측위 시각을 정한다.
/// - 걸음 정보가 아직 없으면 움직이는 것으로 본다. 측위에 실패하면 멈춰 있어도 다시 시도한다(머문 곳의 위치를
///   남기기 위해서다).
/// 원문의 기기 전력 모델(GPS 끄기 지연 등)과 동적 계획법 스케줄링은 넣지 않았다 — 기본판과 같은 '단순화판'이다.
class TimeSpeedPolicy implements CollectionPolicy {
  TimeSpeedPolicy({
    this.errorBudgetM = 50,
    this.minSpeedMps = 1.4,
    this.minWaitMs = 5000,
    this.maxWaitMs = 600000,
    this.failureRetryMs = 30000,
    this.stillGate = false,
  });

  static const _tag = 'next';

  final double errorBudgetM;
  final double minSpeedMps;
  final int minWaitMs;
  final int maxWaitMs;
  final int failureRetryMs;
  final bool stillGate;

  StepState? _state;

  /// 멈춰 있어서 다음 측위를 미뤄 둔 상태. 다시 움직이면 바로 잰다.
  bool _waitingForMove = false;

  /// 마지막 측위가 실패해 다시 시도하는 중. 멈춰 있어도 위치 하나는 얻을 때까지 잰다.
  bool _retrying = false;

  @override
  String get id => stillGate ? 'time_speed_still' : 'time_speed';

  @override
  Map<String, Object> get params => {'e_m': errorBudgetM};

  bool get _still => stillGate && _state == StepState.still;

  @override
  List<PolicyAction> onStart(PolicyContext ctx) {
    _state = null;
    _waitingForMove = false;
    _retrying = false;
    return [const RequestFix()];
  }

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    switch (event) {
      case StepUpdate(:final state):
        _state = state;
        if (_waitingForMove && !_still) {
          _waitingForMove = false;
          return [const RequestFix()];
        }
        return const [];
      case FixResult(:final fix):
        _retrying = fix == null;
        if (fix == null) return [WakeAt(tMs: event.tMs + failureRetryMs, tag: _tag)];
        if (_still) {
          _waitingForMove = true;
          return const [];
        }
        return [WakeAt(tMs: event.tMs + _waitFor(fix.accuracyM, fix.speedMps ?? 0), tag: _tag)];
      case Wakeup(:final tag) when tag == _tag:
        if (_still && !_retrying) {
          _waitingForMove = true;
          return const [];
        }
        return [const RequestFix()];
      default:
        return const [];
    }
  }

  int _waitFor(double accuracyM, double speedMps) {
    final remainingM = errorBudgetM - accuracyM;
    if (remainingM <= 0) return minWaitMs;
    final speed = math.max(speedMps, minSpeedMps);
    final waitMs = (remainingM / speed * 1000).round();
    return waitMs.clamp(minWaitMs, maxWaitMs);
  }
}
