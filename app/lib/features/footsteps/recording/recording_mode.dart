/// 기록 서비스 모드. 한 번에 하나만 돈다(설계 4-1) — 두 모드를 같이 돌리면 배터리 측정이 오염된다.
/// `groundTruth`는 모든 센서를 최대 빈도로 저장하고(R1), `policy`는 고른 정책 하나만 돌려 측위 결과와 배터리만
/// 저장한다(R4, 배터리 실험). R7이 `trip`을 더한다.
enum RecordingMode { groundTruth, policy }

String _two(int n) => n.toString().padLeft(2, '0');

/// 세션 폴더 이름이자 세션 id. 폴더 목록만 보고도 언제 무슨 모드였는지 알 수 있게 기기 현지 시각을 쓴다.
/// intl 대신 직접 만든다 — 서비스 isolate에서는 화면 쪽 로케일 초기화가 되어 있지 않다.
String sessionDirName(DateTime startLocal, RecordingMode mode) {
  final t = startLocal;
  return '${t.year}${_two(t.month)}${_two(t.day)}-${_two(t.hour)}${_two(t.minute)}${_two(t.second)}'
      '-${mode.name}';
}
