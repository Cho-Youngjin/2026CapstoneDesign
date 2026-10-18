import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/trip.dart';

// 비자 준비 일정 로컬 알람(설계 §6-①). 역산 일정은 사용자 본인 일정이라 서버 푸시 없이
// 기기에 예약해 두고, 오프라인에서도 울리게 한다.

/// 알람이 울리는 시각: 마감일 오전 9시. 준비는 출국 전 국내에서 하므로 서울 시간으로 맞춘다.
const _alarmHour = 9;

/// 환율 알림 id(목표 10억 미만, 등락 10억~10억 9만대)와 겹치지 않게 11억부터 쓴다.
const _idBase = 1100000000;

bool _timeZonesLoaded = false;

/// 서울 시간대. 시간대 데이터는 처음 쓸 때 한 번만 불러온다.
tz.Location seoulLocation() {
  if (!_timeZonesLoaded) {
    tz_data.initializeTimeZones();
    _timeZonesLoaded = true;
  }
  return tz.getLocation('Asia/Seoul');
}

/// tripId, taskId 조합마다 결정적인 알림 id를 만든다. 같은 항목을 다시 예약하거나 취소할 때
/// 같은 id로 찾아야 하므로 해시가 아니라 단순 조합을 쓴다. 여행 1만 개·일정 10만 개까지 겹치지 않는다.
int notificationIdFor(int tripId, int taskId) =>
    _idBase + (tripId % 10000) * 100000 + taskId % 100000;

/// 어느 여행의 알람인지 표시한다. 다시 판정하면 일정 id가 새로 생기므로, 이 값으로 그 여행의
/// 이전 알람을 모두 찾아 지운다.
String _payloadFor(int tripId) => 'visa-trip:$tripId';

tz.TZDateTime alarmTimeFor(TripTask task) => tz.TZDateTime(
    seoulLocation(), task.dueDate.year, task.dueDate.month, task.dueDate.day, _alarmHour);

/// 완료했거나 울릴 시각이 이미 지난 항목(화면에는 "지금 바로"로 보인다)은 예약하지 않는다.
bool shouldScheduleAlarm(TripTask task, tz.TZDateTime now) =>
    !task.done && alarmTimeFor(task).isAfter(now);

class ScheduledAlarm {
  const ScheduledAlarm({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final tz.TZDateTime at;
  final String payload;
}

typedef PendingAlarm = ({int id, String? payload});

/// 플러그인 호출만 모은 얇은 경계. 테스트는 가짜로 바꿔 무엇이 예약·취소됐는지 본다.
abstract interface class AlarmBackend {
  Future<void> schedule(ScheduledAlarm alarm);
  Future<List<PendingAlarm>> pending();
  Future<void> cancel(int id);
}

/// flutter_local_notifications로 기기에 예약한다. 재부팅 후 다시 예약하는 일은 플러그인의
/// ScheduledNotificationBootReceiver(AndroidManifest.xml)가 한다.
class LocalAlarmBackend implements AlarmBackend {
  LocalAlarmBackend([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  static const channelId = 'visa_alarms';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      '비자 준비 알람',
      channelDescription: '여행 준비 일정(비자·여권·보험 등) 마감일 알림',
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
  Future<void> schedule(ScheduledAlarm alarm) async {
    await _ensureInitialized();
    await _plugin.zonedSchedule(
      id: alarm.id,
      title: alarm.title,
      body: alarm.body,
      scheduledDate: alarm.at,
      notificationDetails: _details,
      payload: alarm.payload,
      // 정확한 시각 권한(SCHEDULE_EXACT_ALARM) 없이 쓸 수 있는 방식. 몇 분 늦을 수 있지만
      // 마감일 알림에는 충분하다. matchDateTimeComponents를 주지 않아 한 번만 울린다.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<List<PendingAlarm>> pending() async {
    await _ensureInitialized();
    final requests = await _plugin.pendingNotificationRequests();
    return [for (final r in requests) (id: r.id, payload: r.payload)];
  }

  @override
  Future<void> cancel(int id) async {
    await _ensureInitialized();
    await _plugin.cancel(id: id);
  }
}

class AlarmScheduler {
  AlarmScheduler(this._backend, {tz.TZDateTime Function()? now})
      : _now = now ?? (() => tz.TZDateTime.now(seoulLocation()));

  final AlarmBackend _backend;
  final tz.TZDateTime Function() _now;

  /// 이 여행의 알람을 지금 일정에 맞춘다. 이전 알람을 모두 지운 뒤 남은 일정만 다시 예약하므로,
  /// 다시 판정해 일정 id가 바뀌어도 낡은 알람이 남지 않는다.
  Future<void> syncTrip(Trip trip) async {
    await cancelForTrip(trip.id);
    final now = _now();
    for (final task in trip.tasks) {
      if (!shouldScheduleAlarm(task, now)) continue;
      await _backend.schedule(ScheduledAlarm(
        id: notificationIdFor(trip.id, task.id),
        title: '여행 준비: ${task.title}',
        body: '${trip.countryNameKo} 여행 준비 일정의 마감일이에요.',
        at: alarmTimeFor(task),
        payload: _payloadFor(trip.id),
      ));
    }
  }

  Future<void> cancelForTask({required int tripId, required int taskId}) =>
      _backend.cancel(notificationIdFor(tripId, taskId));

  Future<void> cancelForTrip(int tripId) async {
    final payload = _payloadFor(tripId);
    for (final alarm in await _backend.pending()) {
      if (alarm.payload == payload) await _backend.cancel(alarm.id);
    }
  }
}

final alarmSchedulerProvider =
    Provider<AlarmScheduler>((ref) => AlarmScheduler(LocalAlarmBackend()));
