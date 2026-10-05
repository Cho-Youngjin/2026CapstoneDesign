import 'package:permission_handler/permission_handler.dart';

/// 1시간 주기 자동 체크인은 앱이 꺼진 동안 WorkManager 콜백에서 위치를 읽는다.
/// Android 10부터는 매니페스트에 `ACCESS_BACKGROUND_LOCATION`을 선언해도 권한이
/// 자동으로 주어지지 않고, 포그라운드에서 "항상 허용"을 따로 받아야 한다.
///
/// 이것이 없으면 수동 체크인은 되지만 백그라운드 콜백은 위치 요청이 거부되고,
/// 그 실패가 조용히 삼켜져 "1시간마다 자동 기록"이 아무것도 남기지 않는다.
///
/// 사용자가 거부해도 앱은 정상 동작해야 한다 — 포그라운드 수동 체크인과
/// Timeline 임포트가 백업 경로다.
Future<bool> requestBackgroundLocation() async {
  // Android는 "앱 사용 중 허용"이 먼저 있어야 "항상 허용"을 요청할 수 있다.
  if (!await Permission.locationWhenInUse.isGranted) {
    final whenInUse = await Permission.locationWhenInUse.request();
    if (!whenInUse.isGranted) return false;
  }

  if (await Permission.locationAlways.isGranted) return true;

  final always = await Permission.locationAlways.request();
  return always.isGranted;
}
