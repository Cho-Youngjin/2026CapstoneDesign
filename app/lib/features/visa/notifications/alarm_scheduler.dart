import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/auth/auth_providers.dart';
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

const _tripSlots = 10000;
const _taskSlots = 100000;

/// tripId, taskId 조합마다 결정적인 알림 id를 만든다. 같은 항목을 다시 예약하거나 취소할 때
/// 같은 id로 찾아야 하므로 해시가 아니라 단순 조합을 쓴다. 여행 1만 개·일정 10만 개까지 겹치지 않는다.
int notificationIdFor(int tripId, int taskId) =>
    _idBase + _tripKey(tripId) * _taskSlots + taskId % _taskSlots;

/// 비자 알람 id 구간([_idBase]부터 10억 개)인가.
bool isVisaAlarmId(int id) => id >= _idBase && id < _idBase + _tripSlots * _taskSlots;

/// 알림 id에 담긴 여행 자리. 다시 판정하면 일정 id가 새로 생기므로, 이 값으로 그 여행의 이전
/// 알람을 모두 찾아 지운다. Android는 이미 울린 알림의 payload를 돌려주지 않아 id에서 읽는다.
int _tripKey(int tripId) => tripId % _tripSlots;
int _tripKeyOf(int alarmId) => (alarmId - _idBase) ~/ _taskSlots;

/// 예약 대기 목록에서 비자 알람을 가려내는 표시. 다른 알림이 같은 id 구간을 쓰더라도 섞이지 않게 한다.
String _payloadFor(int tripId) => '$visaAlarmPayloadPrefix$tripId';
const visaAlarmPayloadPrefix = 'visa-trip:';

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

/// 플러그인 호출만 모은 얇은 경계. 테스트는 가짜로 바꿔 무엇이 예약·취소됐는지 본다.
abstract interface class AlarmBackend {
  Future<void> schedule(ScheduledAlarm alarm);

  /// 예약 대기 중이거나 이미 울려 알림창에 남은 비자 알람의 id. 둘 다 [cancel]로 지운다.
  Future<List<int>> existing();

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
  Future<List<int>> existing() async {
    await _ensureInitialized();
    final ids = <int>{
      for (final r in await _plugin.pendingNotificationRequests())
        if (isVisaAlarmId(r.id) && (r.payload?.startsWith(visaAlarmPayloadPrefix) ?? false)) r.id,
    };
    // 이미 울린 알람은 예약 목록에서 빠지지만 알림창에는 남아 이전 계정의 일정이 보일 수 있다.
    // Android는 이 목록에 payload를 주지 않으므로 채널로 가려낸다(채널이 없는 Android 7 이하는 id 구간만).
    for (final a in await _plugin.getActiveNotifications()) {
      final id = a.id;
      if (id == null || !isVisaAlarmId(id)) continue;
      if (a.channelId == null || a.channelId == channelId) ids.add(id);
    }
    return ids.toList();
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

  /// 예약·취소를 부른 순서대로 하나씩 처리한다. 화면을 열자마자 일정을 완료하면 열 때 시작한
  /// 예약이 완료 처리의 취소보다 늦게 끝나 완료한 일정의 알람이 되살아날 수 있어서다.
  Future<void> _tail = Future.value();

  Future<void> _serial(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.catchError((Object _) {}); // 한 작업이 실패해도 다음 작업은 이어간다.
    return result;
  }

  /// 예약할 알람이 하나라도 있는가. 없으면 알림 권한을 물을 이유도 없다.
  bool hasUpcoming(Trip trip) {
    final now = _now();
    return trip.tasks.any((t) => shouldScheduleAlarm(t, now));
  }

  /// 이 여행의 알람을 지금 일정에 맞춘다. 이전 알람을 모두 지운 뒤 남은 일정만 다시 예약하므로,
  /// 다시 판정해 일정 id가 바뀌어도 낡은 알람이 남지 않는다.
  Future<void> syncTrip(Trip trip) => _serial(() async {
        await _cancelWhere((key) => key == _tripKey(trip.id));
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
      });

  Future<void> cancelForTask({required int tripId, required int taskId}) =>
      _serial(() => _backend.cancel(notificationIdFor(tripId, taskId)));

  Future<void> cancelForTrip(int tripId) =>
      _serial(() => _cancelWhere((key) => key == _tripKey(tripId)));

  /// 서버 목록에 없는 여행(다른 기기에서 지웠거나 다른 계정의 여행)의 알람을 지운다.
  Future<void> keepOnlyTrips(Set<int> tripIds) {
    final keep = {for (final id in tripIds) _tripKey(id)};
    return _serial(() => _cancelWhere((key) => !keep.contains(key)));
  }

  /// 비자 알람을 모두 지운다(로그아웃·계정 전환). 환율 알림 같은 다른 알림은 건드리지 않는다.
  Future<void> cancelAll() => _serial(() => _cancelWhere((_) => true));

  /// [test]는 알림 id에 담긴 여행 자리([_tripKey])를 받는다.
  Future<void> _cancelWhere(bool Function(int tripKey) test) async {
    for (final id in await _backend.existing()) {
      if (isVisaAlarmId(id) && test(_tripKeyOf(id))) await _backend.cancel(id);
    }
  }
}

final alarmSchedulerProvider =
    Provider<AlarmScheduler>((ref) => AlarmScheduler(LocalAlarmBackend()));

/// 로그아웃하거나 다른 계정으로 바뀌면 이전 계정의 알람을 모두 지운다 — 알림에 이전 계정의
/// 국가·일정이 뜨면 안 된다. 새 계정의 알람은 그 계정의 여행 상세를 열 때 다시 예약된다.
/// 앱 최상단(main.dart의 _Root)이 watch해서 앱이 떠 있는 동안 계속 지켜본다.
final visaAlarmAccountGuardProvider = Provider<void>((ref) {
  ref.listen<String?>(currentUidProvider, (previous, next) {
    if (previous == null || previous == next) return;
    unawaited(ref.read(alarmSchedulerProvider).cancelAll().catchError((Object e) {
      debugPrint('이전 계정의 비자 준비 알람 정리 실패: $e');
    }));
  });
});
