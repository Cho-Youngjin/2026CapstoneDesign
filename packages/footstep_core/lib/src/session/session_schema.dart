/// 세션 폴더의 파일 이름과 CSV 헤더(설계 문서 4-2). 앱의 기록기와 PC 재생기·분석이 같은 이름과 열
/// 순서를 쓰도록 이 패키지 한곳에 둔다. 바꾸면 설계 문서도 함께 바꿔야 한다.
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
