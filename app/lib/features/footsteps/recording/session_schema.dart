/// 세션 폴더의 파일 이름과 CSV 헤더(설계 문서 4-2). R2 재생기(footstep_core)와 R6 분석이 같은
/// 이름·열 순서로 읽으므로, 바꾸면 설계 문서와 재생기도 함께 바꿔야 한다.
abstract final class SessionSchema {
  static const gpsFile = 'gps.csv';
  static const gpsHeader = [
    't_ms', 'fix_t_ms', 'lat', 'lng', 'accuracy_m', 'speed_mps', 'bearing_deg', 'altitude_m',
  ];

  static const accelFile = 'accel.csv';
  static const accelHeader = ['t_ms', 'x', 'y', 'z'];

  static const osStepsFile = 'os_steps.csv';
  static const osStepsHeader = ['t_ms', 'kind', 'value'];

  static const activityFile = 'activity.csv';
  static const activityHeader = ['t_ms', 'type', 'confidence'];

  static const batteryFile = 'battery.csv';
  static const batteryHeader = ['t_ms', 'charge_uah', 'current_ua', 'level_pct', 'temp_c', 'plugged'];

  static const marksFile = 'marks.csv';
  static const marksHeader = ['t_ms', 'kind', 'value'];

  static const metaFile = 'meta.json';
}
