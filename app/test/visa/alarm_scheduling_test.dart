import 'package:app/features/visa/models/trip.dart';
import 'package:app/features/visa/notifications/alarm_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_alarm_backend.dart';
import 'fake_trip_api.dart';

TripTask _task(int id, DateTime due, {bool done = false, String title = '항공권·숙소 확정'}) =>
    TripTask(id: id, title: title, dueDate: due, done: done);

void main() {
  group('notificationIdFor', () {
    test('tripId와 taskId가 다르면 다른 id를 낸다', () {
      expect(notificationIdFor(1, 101), isNot(notificationIdFor(1, 102)));
      expect(notificationIdFor(1, 101), isNot(notificationIdFor(2, 101)));
    });

    test('같은 입력이면 항상 같은 id를 낸다 (재예약/취소 시 필요)', () {
      expect(notificationIdFor(7, 101), notificationIdFor(7, 101));
    });

    test('환율 알림 id(10억 9만대까지)와 겹치지 않고 32비트 정수 범위 안에 있다', () {
      for (final (tripId, taskId) in [(0, 0), (1, 1), (9999, 99999), (123456, 7654321)]) {
        final id = notificationIdFor(tripId, taskId);
        expect(id, greaterThanOrEqualTo(1100000000));
        expect(id, lessThan(1 << 31));
      }
    });
  });

  group('shouldScheduleAlarm', () {
    test('마감일 오전 9시(서울)가 아직 안 왔고 미완료면 예약한다', () {
      expect(shouldScheduleAlarm(_task(1, DateTime(2026, 9, 21)), seoulTime(2026, 9, 7)), isTrue);
    });

    test('마감일이 오늘이어도 오전 9시 전이면 예약한다', () {
      expect(shouldScheduleAlarm(_task(1, DateTime(2026, 9, 7)), seoulTime(2026, 9, 7, 8, 59)), isTrue);
    });

    test('마감일 오전 9시가 지났으면 예약하지 않는다 (화면에는 지금 바로로 보인다)', () {
      expect(shouldScheduleAlarm(_task(1, DateTime(2026, 9, 7)), seoulTime(2026, 9, 7, 9)), isFalse);
      expect(shouldScheduleAlarm(_task(1, DateTime(2026, 9, 1)), seoulTime(2026, 9, 7)), isFalse);
    });

    test('완료된 항목은 예약하지 않는다', () {
      expect(shouldScheduleAlarm(_task(1, DateTime(2026, 9, 21), done: true), seoulTime(2026, 9, 7)),
          isFalse);
    });
  });

  group('AlarmScheduler', () {
    late FakeAlarmBackend backend;
    late AlarmScheduler scheduler;

    setUp(() {
      backend = FakeAlarmBackend();
      scheduler = AlarmScheduler(backend, now: () => seoulTime(2026, 9, 7, 12));
    });

    test('남은 일정마다 마감일 오전 9시(서울)에 한 번 울리게 예약한다', () async {
      final trip = sampleTrip(id: 7, nameKo: '베트남', tasks: [
        _task(101, DateTime(2026, 9, 21), title: '항공권·숙소 확정'),
        _task(102, DateTime(2026, 9, 1), title: '여권 재발급'), // 이미 지남
        _task(103, DateTime(2026, 10, 1), done: true, title: '여행자보험'), // 완료
      ]);

      await scheduler.syncTrip(trip);

      expect(backend.scheduled.keys, [notificationIdFor(7, 101)]);
      final alarm = backend.scheduled[notificationIdFor(7, 101)]!;
      expect(alarm.at, seoulTime(2026, 9, 21, 9));
      expect(alarm.at.location.name, 'Asia/Seoul');
      expect(alarm.title, contains('항공권·숙소 확정'));
      expect(alarm.body, contains('베트남'));
    });

    test('다시 판정해 일정 id가 바뀌면 이 여행의 이전 알람을 지우고 새로 예약한다', () async {
      await scheduler.syncTrip(sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21))]));
      await scheduler.syncTrip(sampleTrip(id: 8, tasks: [_task(201, DateTime(2026, 9, 21))]));

      await scheduler.syncTrip(sampleTrip(id: 7, tasks: [_task(301, DateTime(2026, 9, 30))]));

      expect(backend.scheduled.keys,
          unorderedEquals([notificationIdFor(8, 201), notificationIdFor(7, 301)]));
    });

    test('일정 하나를 완료하면 그 알람만 취소한다', () async {
      await scheduler.syncTrip(sampleTrip(id: 7, tasks: [
        _task(101, DateTime(2026, 9, 21)),
        _task(102, DateTime(2026, 9, 22)),
      ]));

      await scheduler.cancelForTask(tripId: 7, taskId: 101);

      expect(backend.scheduled.keys, [notificationIdFor(7, 102)]);
    });

    test('여행을 지우면 그 여행의 알람만 모두 취소한다', () async {
      await scheduler.syncTrip(sampleTrip(id: 7, tasks: [
        _task(101, DateTime(2026, 9, 21)),
        _task(102, DateTime(2026, 9, 22)),
      ]));
      await scheduler.syncTrip(sampleTrip(id: 8, tasks: [_task(201, DateTime(2026, 9, 21))]));

      await scheduler.cancelForTrip(7);

      expect(backend.scheduled.keys, [notificationIdFor(8, 201)]);
    });
  });
}
