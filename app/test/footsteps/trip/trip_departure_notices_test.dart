import 'package:app/features/footsteps/trip/trip_departure_notices.dart';
import 'package:app/features/footsteps/trip/trip_recording_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../visa/fake_alarm_backend.dart';
import 'trip_fakes.dart';

void main() {
  late FakeAlarmBackend backend;
  late TripRecordingStore store;
  late TripDepartureNotices notices;

  final domestic = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));
  final japan = period(8, DateTime(2026, 12, 1), DateTime(2026, 12, 5), iso2: 'JP', nameKo: '일본');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = TripRecordingStore(await SharedPreferences.getInstance());
    backend = FakeAlarmBackend();
    notices = TripDepartureNotices(backend, store, now: () => seoulTime(2026, 11, 12, 15));
  });

  test('출발일 아침 8시(서울)에 "오늘부터 ○○ 여행 발걸음을 기록합니다." 알림을 예약한다', () async {
    await notices.sync([domestic, japan], const {});

    final alarm = backend.scheduled[departureNoticeIdFor(7)]!;
    expect(alarm.at, seoulTime(2026, 11, 20, 8));
    expect(alarm.body, '오늘부터 대한민국 여행 발걸음을 기록합니다.');
    expect(backend.scheduled[departureNoticeIdFor(8)]!.body, '오늘부터 일본 여행 발걸음을 기록합니다.');
    expect(store.readNoticeTripIds(), {7, 8});
  });

  test('일시정지했거나 이미 아침 8시가 지난 여행은 예약하지 않는다', () async {
    final today = TripDepartureNotices(backend, store, now: () => seoulTime(2026, 11, 20, 8, 1));

    await today.sync([domestic, japan], {8});

    expect(backend.scheduled, isEmpty);
    expect(store.readNoticeTripIds(), isEmpty);
  });

  test('일정에서 빠지거나 일시정지한 여행의 알림은 지운다', () async {
    await notices.sync([domestic, japan], const {});

    await notices.sync([japan], {8});

    expect(backend.cancelled, unorderedEquals([departureNoticeIdFor(7), departureNoticeIdFor(8)]));
    expect(backend.scheduled, isEmpty);
    expect(store.readNoticeTripIds(), isEmpty);
  });

  test('모두 지우면(로그아웃) 예약해 둔 알림이 남지 않는다', () async {
    await notices.sync([domestic, japan], const {});

    await notices.cancelAll();

    expect(backend.scheduled, isEmpty);
    expect(store.readNoticeTripIds(), isEmpty);
  });

  test('비자 준비 알람·환율 알림 id와 겹치지 않고 32비트 안에 든다', () {
    expect(departureNoticeIdFor(1), greaterThanOrEqualTo(2100000000));
    expect(departureNoticeIdFor(39999999), lessThan(2147483647));
  });
}
