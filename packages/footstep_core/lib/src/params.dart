/// 실험 설정의 문자열 파라미터(k=v)를 읽는다. 모르는 키·잘못된 숫자는 ArgumentError다 — 실험 설정 오타로
/// 엉뚱한 기본값이 조용히 쓰이는 것을 막는다. 정책 목록과 걸음 감지기 목록이 같이 쓴다.
class ParamReader {
  ParamReader(this.owner, this.params);

  /// 오류 문구에 쓰는 이름. 예: '정책 time_speed', '걸음 감지기 adaptive'.
  final String owner;
  final Map<String, String> params;

  void allowOnly(Set<String> keys) {
    final unknown = params.keys.where((k) => !keys.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw ArgumentError('$owner에 없는 파라미터: ${unknown.join(', ')}');
    }
  }

  double positive(String key, double fallback) {
    final raw = params[key];
    if (raw == null) return fallback;
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite || value <= 0) {
      throw ArgumentError('$key는 양수여야 합니다: $raw');
    }
    return value;
  }

  int positiveInt(String key, int fallback) {
    final raw = params[key];
    if (raw == null) return fallback;
    final value = int.tryParse(raw);
    if (value == null || value <= 0) throw ArgumentError('$key는 양의 정수여야 합니다: $raw');
    return value;
  }

  /// 켜고 끄는 스위치(절제 실험). true·false 또는 1·0만 받는다.
  bool flag(String key, bool fallback) {
    final raw = params[key];
    if (raw == null) return fallback;
    switch (raw.toLowerCase()) {
      case 'true' || '1':
        return true;
      case 'false' || '0':
        return false;
    }
    throw ArgumentError('$key는 true 또는 false여야 합니다: $raw');
  }
}
