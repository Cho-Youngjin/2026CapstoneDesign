import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../visa/notifications/alarm_scheduler.dart';
import 'trip_period.dart';
import 'trip_recording_store.dart';

/// 출발일 알림 시각: 출발일 아침 8시(설계 2026-11-07 9-2의 2번). 출발은 한국에서 하므로 서울 시간으로 맞춘다
/// (비자 준비 알람과 같은 시간대 데이터를 쓴다).
const _noticeHour = 8;

/// 비자 준비 알람 id(11억~21억) 뒤에 두어 겹치지 않게 한다. 끝(21.4억)이 32비트 정수 한도(약 21.47억) 안에 들어간다.
const _noticeIdBase = 2100000000;
const _noticeIdSlots = 40000000;

int departureNoticeIdFor(int tripId) => _noticeIdBase + tripId % _noticeIdSlots;

tz.TZDateTime departureNoticeTime(TripPeriod trip) => tz.TZDateTime(
    seoulLocation(), trip.departDate.year, trip.departDate.month, trip.departDate.day, _noticeHour);

/// 출발일 알림 채널. Android는 채널 id를 영구 식별자로 다루므로 바꾸지 않는다.
const tripNoticeDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'com.travelfootsteps.trip_recording',
    '여행 기록 알림',
    channelDescription: '여행 출발일 아침, 발걸음 기록을 시작한다고 알려 줍니다.',
    importance: Importance.high,
    priority: Priority.high,
  ),
);

/// 출발일 아침 알림(설계 9-2의 2번). "오늘부터 ○○ 여행 발걸음을 기록합니다." 알림을 누르면 앱이 열리고(플러그인 기본
/// 동작), 앱 셸이 포그라운드로 온 김에 여행 기록을 켠다. 기록 서비스는 백그라운드에서 켤 수 없어서 이 알림이 사용자를
/// 앱으로 데려온다.
///
/// 예약해 둔 여행 id를 저장소에 적어 두고, 일정이 바뀌면 필요 없어진 알림을 지운다. 재부팅 뒤 다시 예약하는 일은
/// 플러그인의 ScheduledNotificationBootReceiver가 한다.
class TripDepartureNotices {
  TripDepartureNotices(this._backend, this._store, {tz.TZDateTime Function()? now})
      : _now = now ?? (() => tz.TZDateTime.now(seoulLocation()));

  final AlarmBackend _backend;
  final TripRecordingStore _store;
  final tz.TZDateTime Function() _now;

  /// 일시정지하지 않았고 아직 아침 8시 전인 여행이 있는가. 있으면 알림이 울릴 테니 앱 셸이 알림 권한을 묻는다.
  bool hasUpcoming(List<TripPeriod> trips, Set<int> paused) {
    final now = _now();
    return trips.any((t) => !paused.contains(t.tripId) && departureNoticeTime(t).isAfter(now));
  }

  /// [trips] 중 일시정지하지 않았고 아직 아침 8시 전인 여행마다 알림을 예약하고, 그 밖에 예약해 둔 알림은 지운다.
  Future<void> sync(List<TripPeriod> trips, Set<int> paused) async {
    final now = _now();
    final wanted = {
      for (final trip in trips)
        if (!paused.contains(trip.tripId) && departureNoticeTime(trip).isAfter(now)) trip.tripId: trip,
    };
    final registered = _store.readNoticeTripIds();
    try {
      for (final tripId in registered.difference(wanted.keys.toSet())) {
        await _backend.cancel(departureNoticeIdFor(tripId));
        registered.remove(tripId);
      }
      for (final trip in wanted.values) {
        // 예약 전에 적는다 — 도중에 실패해도 다음 sync가 지울 수 있게.
        registered.add(trip.tripId);
        await _store.writeNoticeTripIds(registered);
        await _backend.schedule(ScheduledAlarm(
          id: departureNoticeIdFor(trip.tripId),
          title: '여행 발걸음 기록',
          body: '오늘부터 ${trip.countryNameKo} 여행 발걸음을 기록합니다.',
          at: departureNoticeTime(trip),
        ));
      }
    } finally {
      await _store.writeNoticeTripIds(registered);
    }
  }

  /// 예약해 둔 출발일 알림을 모두 지운다(로그아웃·계정 전환).
  Future<void> cancelAll() => sync(const [], const {});
}
