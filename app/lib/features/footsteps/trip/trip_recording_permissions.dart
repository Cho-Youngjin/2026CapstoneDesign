import 'package:permission_handler/permission_handler.dart';

/// 여행 기록이 제대로 돌려면 있어야 하는 권한 중, 없으면 날짜별 보기 위에 "기록이 꺼져 있어요" 배너를 띄우는 것(설계 9-4).
enum TripRecordingPermission {
  /// 위치 '항상 허용'. 기록 서비스는 앱이 화면에 있을 때 켜 '앱 사용 중' 권한으로도 돌지만, 시스템이 서비스를 다시
  /// 띄우거나 WorkManager 체크인이 위치를 읽으려면 필요하다.
  backgroundLocation('백그라운드 위치'),

  /// 걸음 감지(OS 걸음 센서)에 쓴다.
  activityRecognition('활동 인식'),

  /// 기록 중 알림과 출발일 아침 알림을 보이게 한다.
  notification('알림');

  const TripRecordingPermission(this.label);

  final String label;
}

/// 여행 기록 권한 확인. 플러그인을 부르므로 화면·코디네이터 테스트는 가짜로 바꾼다.
abstract interface class TripRecordingPermissions {
  /// 위치(앱 사용 중) 권한이 있어 기록 서비스를 켤 수 있는가. 없으면 켜지 않는다(위치 서비스가 바로 죽는다).
  Future<bool> canRecord();

  /// 없는 권한들.
  Future<Set<TripRecordingPermission>> missing();

  /// 앱 설정 화면을 연다(권한은 사용자가 직접 켠다).
  Future<void> openSettings();
}

class PermissionHandlerTripRecordingPermissions implements TripRecordingPermissions {
  const PermissionHandlerTripRecordingPermissions();

  @override
  Future<bool> canRecord() => Permission.locationWhenInUse.isGranted;

  @override
  Future<Set<TripRecordingPermission>> missing() async => {
        if (!await Permission.locationAlways.isGranted) TripRecordingPermission.backgroundLocation,
        if (!await Permission.activityRecognition.isGranted) TripRecordingPermission.activityRecognition,
        if (!await Permission.notification.isGranted) TripRecordingPermission.notification,
      };

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }
}
