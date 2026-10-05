import 'package:permission_handler/permission_handler.dart';

/// 최초 실행 시 1회 호출한다. 사용자가 거부해도 앱은 정상 동작해야 한다
/// (포그라운드 체크인 + Timeline 임포트가 백업 경로이므로).
Future<bool> requestIgnoreBatteryOptimization() async {
  final status = await Permission.ignoreBatteryOptimizations.status;
  if (status.isGranted) return true;

  final result = await Permission.ignoreBatteryOptimizations.request();
  return result.isGranted;
}
