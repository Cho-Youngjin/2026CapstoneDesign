import 'package:app/features/visa/notifications/alarm_scheduler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// 예약 대기 목록과 알림창 목록만 흉내 내는 가짜 플러그인. 나머지 호출은 쓰지 않는다.
class _FakePlugin implements FlutterLocalNotificationsPlugin {
  _FakePlugin({required this.pendingList, required this.activeList});

  final List<PendingNotificationRequest> pendingList;
  final List<ActiveNotification> activeList;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback? onDidReceiveBackgroundNotificationResponse,
  }) async =>
      true;

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async => pendingList;

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async => activeList;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('예약 대기 중인 알람과 이미 울려 알림창에 남은 알림을 함께 돌려준다', () async {
    final backend = LocalAlarmBackend(_FakePlugin(
      pendingList: const [PendingNotificationRequest(1, '여행 준비', '', 'visa-trip:7')],
      activeList: const [
        ActiveNotification(id: 2, payload: 'visa-trip:7'), // 이미 울린 알람
        ActiveNotification(id: 1, payload: 'visa-trip:7'), // 예약 목록과 겹치면 한 번만
      ],
    ));

    final existing = await backend.existing();

    expect(existing, unorderedEquals([(id: 1, payload: 'visa-trip:7'), (id: 2, payload: 'visa-trip:7')]));
  });
}
