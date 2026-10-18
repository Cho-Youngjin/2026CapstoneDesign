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
  test('예약 대기 중인 비자 알람과 이미 울려 알림창에 남은 비자 알림의 id를 돌려준다', () async {
    final waiting = notificationIdFor(7, 101);
    final fired = notificationIdFor(7, 102);
    final backend = LocalAlarmBackend(_FakePlugin(
      pendingList: [
        PendingNotificationRequest(waiting, '여행 준비', '', 'visa-trip:7'),
        const PendingNotificationRequest(5, '환율', '', null), // 환율 목표 알림
      ],
      activeList: [
        // Android는 알림창 목록에 payload를 주지 않는다 — 채널로 가려낸다.
        ActiveNotification(id: fired, channelId: LocalAlarmBackend.channelId),
        ActiveNotification(id: waiting, channelId: LocalAlarmBackend.channelId), // 겹치면 한 번만
        const ActiveNotification(id: 1000000123, channelId: 'rate_alerts'), // 환율 등락 알림
      ],
    ));

    expect(await backend.existing(), unorderedEquals([waiting, fired]));
  });

  test('비자 알람 id 구간에 있어도 다른 채널의 알림은 건드리지 않는다', () async {
    final backend = LocalAlarmBackend(_FakePlugin(
      pendingList: const [],
      activeList: [ActiveNotification(id: notificationIdFor(7, 101), channelId: 'chat')],
    ));

    expect(await backend.existing(), isEmpty);
  });
}
