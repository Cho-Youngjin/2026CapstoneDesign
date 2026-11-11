import '../events/policy_action.dart';
import '../model/fix.dart';

/// 정책에 알린 위치 하나(fixes.csv의 행).
class FixRecord {
  const FixRecord({
    required this.fix,
    required this.stepsSincePrev,
    required this.state,
    required this.kind,
  });

  final Fix fix;

  /// 직전에 알린 위치 이후 걸음 수.
  final int stepsSincePrev;

  /// 정책 상태(ReportsState) 또는 걸음 감지기 상태 이름.
  final String state;

  /// `single`(RequestFix 응답) 또는 `continuous`(연속 측위).
  final String kind;

  int get tMs => fix.tMs;
}

/// 정책이 낸 할 일 하나(actions.csv의 행).
class ActionRecord {
  const ActionRecord({required this.tMs, required this.action});

  final int tMs;
  final PolicyAction action;
}

/// 재생 한 번의 요약(summary.json). 키는 R6 분석(Python)이 읽기 쉬운 snake_case다.
class ReplaySummary {
  const ReplaySummary({
    required this.sessionId,
    required this.policyId,
    required this.policyParams,
    required this.detectorId,
    this.detectorParams = const {},
    required this.ttffMs,
    required this.startMs,
    required this.endMs,
    required this.fixRequests,
    required this.fixSuccesses,
    required this.fixFailures,
    required this.continuousFixes,
    required this.gpsOnMs,
  });

  final String sessionId;
  final String policyId;
  final Map<String, Object> policyParams;
  final String detectorId;

  /// 걸음 감지기 파라미터. 감지기 파라미터를 바꿔 가며 재생한 결과를 구분하려고 남긴다.
  final Map<String, Object> detectorParams;
  final int ttffMs;
  final int startMs;
  final int endMs;
  final int fixRequests;
  final int fixSuccesses;
  final int fixFailures;
  final int continuousFixes;

  /// 추정 GPS 켜짐 시간. 단발은 요청~응답, 연속은 켠 때~끈 때.
  final int gpsOnMs;

  int get durationMs => endMs - startMs;

  int get totalFixes => fixSuccesses + continuousFixes;

  double get fixesPerHour => durationMs == 0 ? 0 : totalFixes / (durationMs / 3600000);

  Map<String, Object?> toJson() => {
        'session_id': sessionId,
        'policy_id': policyId,
        'policy_params': policyParams,
        'detector_id': detectorId,
        'detector_params': detectorParams,
        'ttff_ms': ttffMs,
        'start_ms': startMs,
        'end_ms': endMs,
        'duration_s': durationMs / 1000,
        'fix_requests': fixRequests,
        'fix_successes': fixSuccesses,
        'fix_failures': fixFailures,
        'continuous_fixes': continuousFixes,
        'total_fixes': totalFixes,
        'gps_on_s': gpsOnMs / 1000,
        'fixes_per_hour': fixesPerHour,
      };
}

class ReplayResult {
  const ReplayResult({required this.fixes, required this.actions, required this.summary});

  final List<FixRecord> fixes;
  final List<ActionRecord> actions;
  final ReplaySummary summary;
}
