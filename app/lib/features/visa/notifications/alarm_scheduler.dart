import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/auth/app_user.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/prefs/shared_preferences_provider.dart';
import '../models/trip.dart';

// 비자 준비 일정 로컬 알람(설계 §6-①). 역산 일정은 사용자 본인 일정이라 서버 푸시 없이
// 기기에 예약해 두고, 오프라인에서도 울리게 한다.

/// 알람이 울리는 시각: 마감일 오전 9시. 준비는 출국 전 국내에서 하므로 서울 시간으로 맞춘다.
const _alarmHour = 9;

/// 환율 알림 id(목표 10억 미만, 등락 10억~10억 9만대)와 겹치지 않게 11억부터 10억 개를 쓴다.
/// 끝(21억)이 32비트 정수 한도(약 21.47억) 안에 들어간다.
const _idBase = 1100000000;
const _idSlots = 1000000000;

bool _timeZonesLoaded = false;

/// 서울 시간대. 시간대 데이터는 처음 쓸 때 한 번만 불러온다.
tz.Location seoulLocation() {
  if (!_timeZonesLoaded) {
    tz_data.initializeTimeZones();
    _timeZonesLoaded = true;
  }
  return tz.getLocation('Asia/Seoul');
}

/// 일정 항목마다 결정적인 알림 id. 서버의 일정 id는 모든 여행에 걸쳐 하나씩 늘어나는 번호라
/// 이것만으로 겹치지 않는다(10억 개까지). 어느 여행의 알람인지는 [AlarmRegistry]가 기억한다.
int notificationIdFor(int taskId) => _idBase + taskId % _idSlots;

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
  });

  final int id;
  final String title;
  final String body;
  final tz.TZDateTime at;
}

/// 플러그인 호출만 모은 얇은 경계. 테스트는 가짜로 바꿔 무엇이 예약·취소됐는지 본다.
abstract interface class AlarmBackend {
  Future<void> schedule(ScheduledAlarm alarm);

  /// 예약을 취소하고, 이미 울려 알림창에 남아 있으면 그것도 지운다.
  Future<void> cancel(int id);
}

/// flutter_local_notifications로 기기에 예약한다. 재부팅 후 다시 예약하는 일은 플러그인의
/// ScheduledNotificationBootReceiver(AndroidManifest.xml)가 한다.
class LocalAlarmBackend implements AlarmBackend {
  LocalAlarmBackend([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  /// Plan B 전역 제약에서 정한 채널 id. Android는 채널 id를 영구 식별자로 다뤄 나중에 바꾸면
  /// 사용자가 설정한 이전 채널이 기기에 남는다.
  static const channelId = 'com.travelfootsteps.visa_alarms';

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
      // 정확한 시각 권한(SCHEDULE_EXACT_ALARM) 없이 쓸 수 있는 방식. 몇 분 늦을 수 있지만
      // 마감일 알림에는 충분하다. matchDateTimeComponents를 주지 않아 한 번만 울린다.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int id) async {
    await _ensureInitialized();
    await _plugin.cancel(id: id);
  }
}

/// 예약한 알림 id → 여행 id. 여행 단위로 지울 때(다시 판정, 삭제, 계정 전환) 이 표로 대상을 찾는다.
///
/// 플러그인에 묻지 않는 이유: Android는 이미 울려 알림창에 남은 알림에 대해 payload를 돌려주지 않고,
/// 예약 알림을 띄울 때 tag도 붙이지 않아, 알림만 보고는 어느 여행 것인지 알 수 없다.
/// 그래서 예약할 때 적어 두고 취소할 때 지운다. 울린 뒤에도 남아 있으므로 알림창의 알림도 지울 수 있다.
///
/// 알람의 주인(계정 uid)도 함께 적는다. 계정이 바뀐 직후 정리가 끝나기 전에 앱이 꺼져도, 다음 실행에서
/// 로그인한 계정과 주인을 비교해 이전 계정의 알람을 지울 수 있게 하려는 것이다.
abstract interface class AlarmRegistry {
  Map<int, int> read();
  Future<void> write(Map<int, int> entries);

  String? readOwner();
  Future<void> writeOwner(String? uid);
}

class PrefsAlarmRegistry implements AlarmRegistry {
  PrefsAlarmRegistry(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'visa_alarms.v1';
  static const _ownerKey = 'visa_alarms.owner.v1';

  @override
  String? readOwner() => _prefs.getString(_ownerKey);

  @override
  Future<void> writeOwner(String? uid) =>
      uid == null ? _prefs.remove(_ownerKey) : _prefs.setString(_ownerKey, uid);

  @override
  Map<int, int> read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
          int.parse(e.key): e.value as int,
      };
    } catch (_) {
      return {}; // 깨진 값이면 없는 것으로 본다. 그 알람은 그 날 한 번 울리고 끝난다.
    }
  }

  @override
  Future<void> write(Map<int, int> entries) =>
      _prefs.setString(_key, jsonEncode({for (final e in entries.entries) '${e.key}': e.value}));
}

/// 테스트용으로 메모리에만 두는 표.
class MemoryAlarmRegistry implements AlarmRegistry {
  /// [_owner]는 이전 실행에서 저장해 둔 알람 주인(테스트에서 흉내 낼 때).
  MemoryAlarmRegistry([this._owner]);

  Map<int, int> _entries = {};
  String? _owner;

  @override
  Map<int, int> read() => {..._entries};

  @override
  Future<void> write(Map<int, int> entries) async => _entries = {...entries};

  @override
  String? readOwner() => _owner;

  @override
  Future<void> writeOwner(String? uid) async => _owner = uid;
}

class AlarmScheduler {
  AlarmScheduler(this._backend, {AlarmRegistry? registry, tz.TZDateTime Function()? now})
      : _registry = registry ?? MemoryAlarmRegistry(),
        _now = now ?? (() => tz.TZDateTime.now(seoulLocation()));

  final AlarmBackend _backend;
  final AlarmRegistry _registry;
  final tz.TZDateTime Function() _now;

  /// 예약·취소를 부른 순서대로 하나씩 처리한다. 화면을 열자마자 일정을 완료하면 열 때 시작한
  /// 예약이 완료 처리의 취소보다 늦게 끝나 완료한 일정의 알람이 되살아날 수 있어서다.
  /// 표([_registry])를 읽고 고쳐 쓰는 일도 이 순서 안에서만 하므로 서로 덮어쓰지 않는다.
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (Object _) {}); // 한 작업이 실패해도 다음 작업은 이어간다.
    return result;
  }

  /// 예약할 알람이 하나라도 있는가. 없으면 알림 권한을 물을 이유도 없다.
  bool hasUpcoming(Trip trip) {
    final now = _now();
    return trip.tasks.any((t) => shouldScheduleAlarm(t, now));
  }

  /// 이 일정이 지금 예약 대상인가(미완료이고 울릴 시각이 남았다).
  bool isUpcoming(TripTask task) => shouldScheduleAlarm(task, _now());

  /// 이 여행의 알람을 지금 일정에 맞춘다. 이전 알람을 모두 지운 뒤 남은 일정만 다시 예약하므로,
  /// 다시 판정해 일정 id가 바뀌어도 낡은 알람이 남지 않는다.
  ///
  /// [trip]은 방금 서버에서 받은 여행이므로, 이전에 없어진 것으로 적어 둔 여행이어도(다른 계정일 때 목록에
  /// 없었다든가) 지금은 있는 것으로 되돌린다.
  Future<void> syncTrip(Trip trip) => _serial(() {
        _removedTrips.remove(trip.id);
        return _sync(trip);
      });

  /// 서버 응답을 기다린 뒤에 여행 전체를 맞출 때(다시 판정). 요청을 보낸 계정([owner])이 그 사이
  /// 로그아웃했거나 다른 계정으로 바뀌었으면 아무것도 하지 않는다 — 계정 가드가 이미 정리한 이전 계정의
  /// 알람을 되살리면 다른 사람 기기에 그 사람의 여행 일정이 뜬다.
  Future<void> syncTripFor(String? owner, Trip trip) => _serial(() async {
        if (_ownedBy(owner) && !_removedTrips.contains(trip.id)) await _sync(trip);
      });

  /// 서버 응답을 기다린 뒤에 일정 하나만 다시 예약할 때(완료 취소). 여행 전체를 다시 맞추지 않는 이유:
  /// 응답이 늦게 오면 화면이 들고 있던 [trip]이 낡았을 수 있다(그 사이 다른 일정을 완료했으면 그 알람이
  /// 되살아난다). [trip]은 알림 문구(국가 이름)와 여행 단위 정리용 표에만 쓴다. 계정 확인은 [syncTripFor]와 같다.
  ///
  /// 실제로 예약했으면 true. false면(계정이 바뀌었거나 울릴 일정이 아님) 알림 권한도 묻지 않는다.
  Future<bool> scheduleTaskFor(String? owner, Trip trip, TripTask task) => _serial(() async {
        final known = _tasksByTrip[trip.id];
        if (!_ownedBy(owner) ||
            _removedTrips.contains(trip.id) ||
            (known != null && !known.contains(task.id)) ||
            !shouldScheduleAlarm(task, _now())) {
          return false;
        }
        await _schedule(trip, task);
        return true;
      });

  bool _ownedBy(String? owner) => owner != null && _registry.readOwner() == owner;

  /// 없어진 여행([cancelForTrip], [keepOnlyTrips]로 정리). 응답을 기다리던 예약([scheduleTaskFor],
  /// [syncTripFor])이 정리보다 늦게 와도 그 여행의 알람을 되살리지 않게 기억한다. 여행 id는 다시 쓰이지
  /// 않으므로 앱이 떠 있는 동안 둔다.
  final Set<int> _removedTrips = {};

  /// 여행마다 마지막으로 맞춘([_sync]) 일정 id. 다시 판정하면 서버가 일정을 새 id로 다시 만들므로, 그 뒤에
  /// 늦게 온 완료 취소 응답의 옛 일정은 예약하지 않는다. 완료 취소는 그 여행 화면을 연 뒤에만 할 수 있고,
  /// 화면을 열 때 [syncTrip]이 돌아 여기 적히므로 응답을 기다리는 여행은 항상 여기 있다.
  final Map<int, Set<int>> _tasksByTrip = {};

  Future<void> _sync(Trip trip) async {
    _tasksByTrip[trip.id] = {for (final t in trip.tasks) t.id};
    await _cancelWhere((tripId) => tripId == trip.id);
    final now = _now();
    for (final task in trip.tasks) {
      if (!shouldScheduleAlarm(task, now)) continue;
      await _schedule(trip, task);
    }
  }

  Future<void> _schedule(Trip trip, TripTask task) async {
    final id = notificationIdFor(task.id);
    // 표에 먼저 적는다 — 예약 도중 실패해도 나중에 지울 수 있게.
    await _registry.write({..._registry.read(), id: trip.id});
    await _backend.schedule(ScheduledAlarm(
      id: id,
      title: '여행 준비: ${task.title}',
      body: '${trip.countryNameKo} 여행 준비 일정의 마감일이에요.',
      at: alarmTimeFor(task),
    ));
  }

  Future<void> cancelForTask(int taskId) => _serial(() async {
        final id = notificationIdFor(taskId);
        await _backend.cancel(id);
        await _registry.write(_registry.read()..remove(id));
      });

  /// 여행이 없어졌을 때(삭제, 다른 기기에서 지워져 404) 그 여행의 알람을 모두 지운다.
  Future<void> cancelForTrip(int tripId) => _serial(() {
        _retire([tripId]);
        return _cancelWhere((id) => id == tripId);
      });

  /// 서버 목록에 없는 여행(다른 기기에서 지웠거나 다른 계정의 여행)의 알람을 지운다.
  Future<void> keepOnlyTrips(Set<int> tripIds) => _serial(() {
        // 표에 알람이 없는 여행(울릴 일정이 없던 여행)도 이 세션에서 연 적이 있으면 없어진 것으로 적는다.
        _retire([
          for (final id in {..._tasksByTrip.keys, ..._registry.read().values})
            if (!tripIds.contains(id)) id,
        ]);
        return _cancelWhere((id) => !tripIds.contains(id));
      });

  void _retire(Iterable<int> tripIds) {
    for (final id in tripIds) {
      _removedTrips.add(id);
      _tasksByTrip.remove(id);
    }
  }

  /// 비자 알람을 모두 지운다(로그아웃·계정 전환). 환율 알림 같은 다른 알림은 건드리지 않는다.
  Future<void> cancelAll() => _serial(() => _cancelWhere((_) => true));

  /// 지금 로그인한 계정([uid], 로그아웃이면 null)을 알람의 주인으로 정한다. 로그아웃이거나 적어 둔
  /// 주인과 다른 계정이면 먼저 알람을 모두 지운다. 다 지운 뒤에만 주인을 바꾸므로, 도중에 실패하거나
  /// 앱이 꺼지면 다음에 다시 비교해 지운다. 주인이 적혀 있지 않으면(이 기능 이전 예약) 그대로 둔다.
  Future<void> claimFor(String? uid) => _serial(() async {
        final owner = _registry.readOwner();
        if (uid == null || (owner != null && owner != uid)) {
          await _cancelWhere((_) => true);
        }
        // 없어진 여행·일정 기록은 그 계정의 목록과 화면을 기준으로 쓴 것이라 계정이 바뀌면 버린다.
        if (owner != uid) {
          _removedTrips.clear();
          _tasksByTrip.clear();
        }
        if (owner != uid) await _registry.writeOwner(uid);
      });

  /// [test]는 표에 적힌 여행 id를 받는다. 취소에 성공한 것만 표에서 뺀다.
  Future<void> _cancelWhere(bool Function(int tripId) test) async {
    final entries = _registry.read();
    final targets = [for (final e in entries.entries) if (test(e.value)) e.key];
    try {
      for (final id in targets) {
        await _backend.cancel(id);
        entries.remove(id);
      }
    } finally {
      await _registry.write(entries);
    }
  }
}

final alarmSchedulerProvider = Provider<AlarmScheduler>((ref) => AlarmScheduler(
      LocalAlarmBackend(),
      registry: PrefsAlarmRegistry(ref.watch(sharedPreferencesProvider)),
    ));

/// 로그아웃 상태이거나 다른 계정으로 바뀌면 이전 계정의 알람을 모두 지운다 — 알림에 이전 계정의
/// 국가·일정이 뜨면 안 된다. 새 계정의 알람은 그 계정의 여행 상세를 열 때 다시 예약된다.
/// 앱 최상단(main.dart의 _Root)이 watch해서 앱이 떠 있는 동안 계속 지켜본다.
///
/// 바뀌는 "순간"만이 아니라 인증 상태를 알 때마다 저장해 둔 주인과 비교한다([AlarmScheduler.claimFor]).
/// 그래서 정리 도중 앱이 꺼졌어도 다음 실행에서 다시 지운다. 지울 게 없으면 플러그인을 부르지 않는다.
/// 인증 상태를 아직 모를 때(로딩)는 아무것도 하지 않는다 — 로그인한 사용자의 알람을 지우면 안 된다.
final visaAlarmAccountGuardProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<AppUser?>>(authStateProvider, (previous, next) {
    if (!next.hasValue) return;
    unawaited(ref.read(alarmSchedulerProvider).claimFor(next.value?.uid).catchError((Object e) {
      debugPrint('이전 계정의 비자 준비 알람 정리 실패: $e');
    }));
  }, fireImmediately: true);
});
