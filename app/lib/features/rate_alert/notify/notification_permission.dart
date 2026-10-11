import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// 알림 권한 요청(설계 §6.5). 화면 테스트에서 허용/거부를 흉내 낼 수 있게 인터페이스로 둔다.
abstract interface class NotificationPermission {
  /// 허용돼 있거나 이번에 허용하면 true. Android 12 이하는 런타임 권한이 없어 항상 true다.
  Future<bool> request();
}

class PermissionHandlerNotificationPermission implements NotificationPermission {
  const PermissionHandlerNotificationPermission();

  @override
  Future<bool> request() async => (await Permission.notification.request()).isGranted;
}

final notificationPermissionProvider = Provider<NotificationPermission>((ref) {
  return const PermissionHandlerNotificationPermission();
});
