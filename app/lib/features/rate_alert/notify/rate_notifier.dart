import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/rate_alert_evaluator.dart';

/// 환율 알림을 띄우는 쪽(설계 §6.5). 백그라운드 작업 테스트가 가짜로 바꿀 수 있게 인터페이스로 둔다.
abstract interface class RateNotifier {
  Future<void> show(RateAlertMessage message);
}

/// flutter_local_notifications로 기기 알림을 띄운다. 알림을 누르면 앱이 열린다(플러그인 기본 동작).
/// 백그라운드 isolate에서도 쓰므로 처음 보낼 때 스스로 초기화한다.
class LocalRateNotifier implements RateNotifier {
  LocalRateNotifier([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  static const channelId = 'rate_alerts';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      '환율 알림',
      channelDescription: '전 영업일 대비 등락과 목표 환율 도달 알림',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  @override
  Future<void> show(RateAlertMessage message) async {
    await _ensureInitialized();
    await _plugin.show(
      id: message.notificationId,
      title: message.title,
      body: message.body,
      notificationDetails: _details,
    );
  }
}
