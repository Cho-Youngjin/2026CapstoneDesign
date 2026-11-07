import 'package:permission_handler/permission_handler.dart';

/// 권한 하나의 결과. 실험 화면에 그대로 보여 준다.
class PermissionItem {
  const PermissionItem(this.label, this.granted);

  final String label;
  final bool granted;
}

/// 정답 기록 모드에 필요한 권한을 차례로 요청한다.
///
/// 위치는 '앱 사용 중'으로 충분하다. 서비스를 화면이 떠 있을 때 시작하므로, 위치 타입 포그라운드
/// 서비스는 화면이 꺼진 뒤에도 위치를 받는다. 신체 활동은 OS 걸음 센서와 활동 인식이 함께 쓴다.
Future<List<PermissionItem>> requestRecordingPermissions() async {
  Future<bool> ask(Permission permission) async => (await permission.request()).isGranted;

  return [
    PermissionItem('위치(앱 사용 중)', await ask(Permission.locationWhenInUse)),
    PermissionItem('신체 활동(걸음·활동 인식)', await ask(Permission.activityRecognition)),
    PermissionItem('알림(기록 중 표시)', await ask(Permission.notification)),
    PermissionItem('배터리 최적화 제외', await ask(Permission.ignoreBatteryOptimizations)),
  ];
}
