import 'dart:async';

import 'package:app/features/visa/notifications/alarm_scheduler.dart';
import 'package:timezone/timezone.dart' as tz;

/// 기기 알림 대신 예약 목록을 메모리에 들고 있는 가짜. 무엇이 예약·취소됐는지 테스트가 본다.
class FakeAlarmBackend implements AlarmBackend {
  FakeAlarmBackend({this.failing = false});

  /// true면 모든 호출이 실패한다 — 알람 오류가 화면·삭제를 막지 않는지 확인할 때 쓴다.
  final bool failing;

  final Map<int, ScheduledAlarm> scheduled = {};
  final List<int> cancelled = [];

  /// 정해 두면 [pending]이 이 Completer가 끝날 때까지 기다린다 — 작업이 겹치는 순간을 만든다.
  Completer<void>? holdPending;

  void _check() {
    if (failing) throw Exception('alarm backend failed');
  }

  @override
  Future<void> schedule(ScheduledAlarm alarm) async {
    _check();
    scheduled[alarm.id] = alarm;
  }

  @override
  Future<List<PendingAlarm>> pending() async {
    _check();
    final hold = holdPending;
    if (hold != null) await hold.future;
    return [for (final a in scheduled.values) (id: a.id, payload: a.payload)];
  }

  @override
  Future<void> cancel(int id) async {
    _check();
    cancelled.add(id);
    scheduled.remove(id);
  }
}

/// 테스트에서 서울 시각을 만든다. 시간대 데이터는 [AlarmScheduler]가 처음 쓸 때 불러온다.
tz.TZDateTime seoulTime(int year, int month, int day, [int hour = 0, int minute = 0]) =>
    tz.TZDateTime(seoulLocation(), year, month, day, hour, minute);
