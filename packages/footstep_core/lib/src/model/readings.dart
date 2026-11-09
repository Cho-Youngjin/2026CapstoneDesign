/// 가속도 표본 하나(m/s², 중력 포함).
class AccelReading {
  const AccelReading({required this.tMs, required this.x, required this.y, required this.z});

  final int tMs;
  final double x;
  final double y;
  final double z;
}

/// os_steps.csv의 행 하나. [kind]가 [count]면 value는 부팅 후 누적 걸음 수, [status]면 OS 보행 상태다.
class OsStepReading {
  const OsStepReading({required this.tMs, required this.kind, required this.value});

  static const count = 'count';
  static const status = 'status';

  final int tMs;
  final String kind;
  final String value;
}

/// 구글 활동 인식 결과 하나. type은 IN_VEHICLE·ON_BICYCLE·RUNNING·STILL·WALKING·UNKNOWN,
/// confidence는 HIGH·MEDIUM·LOW다.
class ActivityReading {
  const ActivityReading({required this.tMs, required this.type, required this.confidence});

  final int tMs;
  final String type;
  final String confidence;
}

/// 배터리 잔량(%) 하나. 정책은 잔량만 쓴다(배터리 20% 미만 대응, 설계 5-3).
class BatteryLevelReading {
  const BatteryLevelReading({required this.tMs, required this.levelPct});

  final int tMs;
  final int levelPct;
}
