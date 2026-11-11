/// 폰에서 정책을 한 번 돌린 요약(정책 실행 모드의 summary.json). 키는 재생기 요약과 맞춰 R6 분석이 두 결과를
/// 같은 코드로 읽게 한다. 재생기에 없는 깨우기 지연을 더한다.
class RunSummary {
  const RunSummary({
    required this.policyId,
    required this.policyParams,
    required this.detectorId,
    required this.detectorParams,
    required this.startMs,
    required this.endMs,
    required this.fixRequests,
    required this.fixSuccesses,
    required this.fixFailures,
    required this.continuousFixes,
    required this.gpsOnMs,
    required this.wakeDelaysMs,
  });

  final String policyId;
  final Map<String, Object> policyParams;
  final String detectorId;
  final Map<String, Object> detectorParams;
  final int startMs;
  final int endMs;
  final int fixRequests;
  final int fixSuccesses;
  final int fixFailures;
  final int continuousFixes;

  /// 추정 GPS 켜짐 시간. 단발은 요청~응답, 연속은 켠 때~끈 때. 실기기 배터리 결과와 견주는 보조 지표다.
  final int gpsOnMs;

  /// 깨우기마다 예약보다 늦게 깬 시간(ms).
  final List<int> wakeDelaysMs;

  int get durationMs => endMs - startMs;

  int get totalFixes => fixSuccesses + continuousFixes;

  Map<String, Object?> toJson() {
    final delays = [...wakeDelaysMs]..sort();
    return {
      'policy_id': policyId,
      'policy_params': policyParams,
      'detector_id': detectorId,
      'detector_params': detectorParams,
      'start_ms': startMs,
      'end_ms': endMs,
      'duration_s': durationMs / 1000,
      'fix_requests': fixRequests,
      'fix_successes': fixSuccesses,
      'fix_failures': fixFailures,
      'continuous_fixes': continuousFixes,
      'total_fixes': totalFixes,
      'gps_on_s': gpsOnMs / 1000,
      'fixes_per_hour': durationMs == 0 ? 0 : totalFixes / (durationMs / 3600000),
      'wakeups': delays.length,
      'wake_delay_median_ms': delays.isEmpty ? null : delays[delays.length ~/ 2],
      'wake_delay_max_ms': delays.isEmpty ? null : delays.last,
    };
  }
}
