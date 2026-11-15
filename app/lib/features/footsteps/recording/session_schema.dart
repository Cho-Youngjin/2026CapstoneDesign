// 세션 파일 이름과 헤더는 공용 패키지(footstep_core)가 가진다 — 앱(기록)과 PC 재생기가 같은 계약을
// 쓰게 하려고. 기존 import 경로가 깨지지 않도록 여기서 다시 내보낸다.
export 'package:footstep_core/footstep_core.dart' show SessionSchema;
