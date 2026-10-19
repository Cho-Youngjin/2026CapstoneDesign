import 'dart:async';

import 'package:app/core/auth/app_user.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/visa/models/trip.dart';
import 'package:app/features/visa/notifications/alarm_scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_alarm_backend.dart';
import 'fake_trip_api.dart';

TripTask _task(int id, DateTime due, {bool done = false, String title = '항공권·숙소 확정'}) =>
    TripTask(id: id, title: title, dueDate: due, done: done);

void main() {
  group('notificationIdFor', () {
    test('일정 id가 다르면 다른 id를 낸다 (일정 id는 모든 여행에 걸쳐 하나씩 늘어난다)', () {
      expect(notificationIdFor(101), isNot(notificationIdFor(102)));
    });

    test('같은 입력이면 항상 같은 id를 낸다 (재예약/취소 시 필요)', () {
      expect(notificationIdFor(101), notificationIdFor(101));
    });

    test('환율 알림 id(10억 9만대까지)와 겹치지 않고 32비트 정수 범위 안에 있다', () {
      for (final taskId in [0, 1, 99999, 123456789, 999999999, 1000000000]) {
        final id = notificationIdFor(taskId);
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

      expect(backend.scheduled.keys, [notificationIdFor(101)]);
      final alarm = backend.scheduled[notificationIdFor(101)]!;
      expect(alarm.at, seoulTime(2026, 9, 21, 9));
      expect(alarm.at.location.name, 'Asia/Seoul');
      expect(alarm.title, contains('항공권·숙소 확정'));
      expect(alarm.body, contains('베트남'));
    });

    test('다시 판정해 일정 id가 바뀌면 이 여행의 이전 알람을 지우고 새로 예약한다', () async {
      await scheduler.syncTrip(sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21))]));
      await scheduler.syncTrip(sampleTrip(id: 8, tasks: [_task(201, DateTime(2026, 9, 21))]));

      await scheduler.syncTrip(sampleTrip(id: 7, tasks: [_task(301, DateTime(2026, 9, 30))]));

      expect(backend.scheduled.keys, unorderedEquals([notificationIdFor(201), notificationIdFor(301)]));
    });

    test('id가 1만 차이 나는 두 여행도 서로의 알람을 지우지 않는다', () async {
      await scheduler.syncTrip(sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21))]));
      await scheduler.syncTrip(sampleTrip(id: 10007, tasks: [_task(50101, DateTime(2026, 9, 21))]));

      await scheduler.cancelForTrip(7);

      expect(backend.scheduled.keys, [notificationIdFor(50101)]);
    });

    test('일정 하나를 완료하면 그 알람만 취소한다', () async {
      await scheduler.syncTrip(sampleTrip(id: 7, tasks: [
        _task(101, DateTime(2026, 9, 21)),
        _task(102, DateTime(2026, 9, 22)),
      ]));

      await scheduler.cancelForTask(101);

      expect(backend.scheduled.keys, [notificationIdFor(102)]);
    });

    test('여행을 지우면 그 여행의 알람만 모두 취소한다', () async {
      await scheduler.syncTrip(sampleTrip(id: 7, tasks: [
        _task(101, DateTime(2026, 9, 21)),
        _task(102, DateTime(2026, 9, 22)),
      ]));
      await scheduler.syncTrip(sampleTrip(id: 8, tasks: [_task(201, DateTime(2026, 9, 21))]));

      await scheduler.cancelForTrip(7);

      expect(backend.scheduled.keys, [notificationIdFor(201)]);
    });

    test('열 때 시작한 예약이 늦게 끝나도 그 사이 완료한 일정의 알람은 되살아나지 않는다', () async {
      final trip = sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21))]);
      backend.holdSchedule = Completer<void>();

      final opening = scheduler.syncTrip(trip); // 예약 도중에 멈춰 있다
      final completing = scheduler.cancelForTask(101);
      backend.holdSchedule!.complete();
      await Future.wait([opening, completing]);

      expect(backend.scheduled, isEmpty);
    });

    test('한 작업이 실패해도 다음 작업은 처리한다', () async {
      backend.holdSchedule = Completer<void>();
      final failed = scheduler.syncTrip(sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21))]));
      await pumpEventQueue(); // 예약 도중에 멈출 때까지
      backend.holdSchedule!.completeError(Exception('boom'));
      await expectLater(failed, throwsException);
      backend.holdSchedule = null;

      await scheduler.syncTrip(sampleTrip(id: 8, tasks: [_task(201, DateTime(2026, 9, 21))]));

      expect(backend.scheduled.keys, [notificationIdFor(201)]);
    });

    test('서버 목록에 없는 여행의 알람만 지운다', () async {
      await scheduler.syncTrip(sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21))]));
      await scheduler.syncTrip(sampleTrip(id: 9, tasks: [_task(901, DateTime(2026, 9, 21))]));

      await scheduler.keepOnlyTrips({7, 8});

      expect(backend.scheduled.keys, [notificationIdFor(101)]);
    });

    test('모두 지워도 비자 알람이 아닌 알림은 건드리지 않는다', () async {
      await scheduler.syncTrip(sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21))]));
      backend.scheduled[42] = ScheduledAlarm(id: 42, title: '환율', body: '', at: seoulTime(2026, 9, 8));

      await scheduler.cancelAll();

      expect(backend.scheduled.keys, [42]);
    });

    group('응답을 기다린 뒤의 예약 (계정 확인)', () {
      late AlarmScheduler owned;

      setUp(() {
        owned = AlarmScheduler(backend,
            registry: MemoryAlarmRegistry('uid-a'), now: () => seoulTime(2026, 9, 7, 12));
      });

      test('일정 하나만 예약하고 이 여행의 다른 알람은 건드리지 않는다', () async {
        final trip = sampleTrip(id: 7, tasks: [
          _task(101, DateTime(2026, 9, 21)),
          _task(102, DateTime(2026, 9, 22)),
        ]);
        await owned.syncTrip(trip);
        await owned.cancelForTask(102); // 그 사이 다른 화면에서 완료했다

        // 옛 화면이 들고 있던 trip에는 102가 아직 미완료지만, 101만 다시 맞춘다
        await owned.scheduleTaskFor('uid-a', trip, _task(101, DateTime(2026, 9, 21)));

        expect(backend.scheduled.keys, [notificationIdFor(101)]);
      });

      test('지났거나 완료된 일정은 예약하지 않는다', () async {
        final trip = sampleTrip(id: 7);
        await owned.scheduleTaskFor('uid-a', trip, _task(101, DateTime(2026, 9, 1)));
        await owned.scheduleTaskFor('uid-a', trip, _task(102, DateTime(2026, 9, 21), done: true));

        expect(backend.scheduled, isEmpty);
      });

      test('예약했는지 알려준다 (예약하지 않았으면 알림 권한을 물을 이유도 없다)', () async {
        final trip = sampleTrip(id: 7);
        expect(await owned.scheduleTaskFor('uid-a', trip, _task(101, DateTime(2026, 9, 21))), isTrue);
        expect(await owned.scheduleTaskFor('uid-a', trip, _task(102, DateTime(2026, 9, 1))), isFalse);
        expect(await owned.scheduleTaskFor('uid-b', trip, _task(103, DateTime(2026, 9, 21))), isFalse);
      });

      test('그 사이 로그아웃했으면 예약하지 않는다', () async {
        await owned.claimFor(null);

        await owned.scheduleTaskFor('uid-a', sampleTrip(id: 7), _task(101, DateTime(2026, 9, 21)));
        await owned.syncTripFor('uid-a', sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21))]));

        expect(backend.scheduled, isEmpty);
      });

      test('그 사이 다른 계정으로 바뀌었으면 예약하지 않는다', () async {
        await owned.claimFor('uid-b');

        await owned.scheduleTaskFor('uid-a', sampleTrip(id: 7), _task(101, DateTime(2026, 9, 21)));
        await owned.syncTripFor('uid-a', sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21))]));

        expect(backend.scheduled, isEmpty);
      });

      test('그 사이 지운 여행이면 예약하지 않는다', () async {
        final trip = sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21))]);
        await owned.cancelForTrip(7); // 여행 삭제(또는 다른 기기에서 지워져 404)

        expect(await owned.scheduleTaskFor('uid-a', trip, _task(101, DateTime(2026, 9, 21))), isFalse);
        await owned.syncTripFor('uid-a', trip);

        expect(backend.scheduled, isEmpty);
      });

      test('그 사이 다시 판정해 일정이 바뀌었으면 옛 일정은 예약하지 않는다', () async {
        await owned.syncTrip(sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21))]));
        await owned.syncTripFor('uid-a', sampleTrip(id: 7, tasks: [_task(201, DateTime(2026, 9, 25))]));

        final restored = await owned.scheduleTaskFor(
            'uid-a', sampleTrip(id: 7), _task(101, DateTime(2026, 9, 21)));

        expect(restored, isFalse);
        expect(backend.scheduled.keys, [notificationIdFor(201)]);
      });

      test('목록 갱신으로 정리된 여행(다른 기기에서 삭제)이면 예약하지 않는다', () async {
        final trip = sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21), done: true)]);
        await owned.syncTrip(trip); // 화면을 열었다(울릴 알람은 없다)
        await owned.keepOnlyTrips({8});

        expect(await owned.scheduleTaskFor('uid-a', trip, _task(101, DateTime(2026, 9, 21))), isFalse);
        await owned.syncTripFor('uid-a', sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21))]));

        expect(backend.scheduled, isEmpty);
      });

      test('정리됐던 여행도 서버에서 다시 받아 열면 다시 예약한다 (다른 계정일 때 목록에 없었을 뿐)', () async {
        final trip = sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21), done: true)]);
        await owned.syncTrip(trip);
        await owned.keepOnlyTrips({8}); // 다른 계정의 목록에는 7번이 없다

        await owned.syncTrip(trip); // 원래 계정으로 돌아와 7번을 다시 열었다

        expect(await owned.scheduleTaskFor('uid-a', trip, _task(101, DateTime(2026, 9, 21))), isTrue);
      });

      test('계정이 바뀌면 정리 기록도 처음부터 다시 쓴다', () async {
        final trip = sampleTrip(id: 7);
        await owned.cancelForTrip(7); // uid-a로 있을 때 404
        await owned.claimFor('uid-b');
        await owned.claimFor('uid-a');

        expect(await owned.scheduleTaskFor('uid-a', trip, _task(101, DateTime(2026, 9, 21))), isTrue);
      });

      test('같은 계정이면 여행 전체를 다시 맞춘다', () async {
        await owned.syncTripFor('uid-a', sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21))]));

        expect(backend.scheduled.keys, [notificationIdFor(101)]);
      });
    });

    test('울릴 일정이 하나라도 남았는지 알려준다 (없으면 권한을 묻지 않는다)', () {
      expect(scheduler.hasUpcoming(sampleTrip(tasks: [_task(1, DateTime(2026, 9, 21))])), isTrue);
      expect(
          scheduler.hasUpcoming(sampleTrip(tasks: [
            _task(1, DateTime(2026, 9, 1)),
            _task(2, DateTime(2026, 9, 21), done: true),
          ])),
          isFalse);
    });
  });

  group('PrefsAlarmRegistry', () {
    test('앱을 다시 켜도(새 스케줄러) 이전에 예약한 여행의 알람을 지울 수 있다', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final backend = FakeAlarmBackend();
      AlarmScheduler start() => AlarmScheduler(backend,
          registry: PrefsAlarmRegistry(prefs), now: () => seoulTime(2026, 9, 7, 12));

      await start().syncTrip(sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21))]));
      await start().cancelForTrip(7);

      expect(backend.scheduled, isEmpty);
    });

    test('저장값이 깨졌으면 빈 표로 본다', () async {
      SharedPreferences.setMockInitialValues({'visa_alarms.v1': 'not json'});
      final prefs = await SharedPreferences.getInstance();

      expect(PrefsAlarmRegistry(prefs).read(), isEmpty);
    });
  });

  group('visaAlarmAccountGuardProvider', () {
    late StreamController<AppUser?> auth;
    late FakeAlarmBackend backend;
    late AlarmScheduler scheduler;

    /// 이전 실행에서 예약해 둔 알람이 남아 있는 상태로 앱을 켠다(인증 상태는 아직 모른다).
    /// [owner]는 이전 실행에서 저장해 둔 알람 주인.
    Future<void> launch({String? owner}) async {
      auth = StreamController<AppUser?>();
      addTearDown(auth.close);
      backend = FakeAlarmBackend();
      scheduler = AlarmScheduler(backend,
          registry: MemoryAlarmRegistry(owner), now: () => seoulTime(2026, 9, 7, 12));
      await scheduler.syncTrip(sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21))]));
      final container = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => auth.stream),
        alarmSchedulerProvider.overrideWithValue(scheduler),
      ]);
      addTearDown(container.dispose);
      container.listen(visaAlarmAccountGuardProvider, (_, _) {});
    }

    /// 앞서 줄 선 정리가 끝날 때까지 기다린다(스케줄러는 부른 순서대로 처리한다).
    Future<void> settle() async {
      await pumpEventQueue();
      await scheduler.keepOnlyTrips({7});
    }

    test('로그인 상태로 켜면 알람을 그대로 둔다', () async {
      await launch();
      await settle();
      expect(backend.scheduled, isNotEmpty, reason: '인증 상태를 아직 모를 때는 지우지 않는다');

      auth.add(const AppUser(uid: 'uid-a'));
      await settle();

      expect(backend.scheduled.keys, [notificationIdFor(101)]);
    });

    test('로그아웃하면 이전 계정의 비자 알람을 지운다', () async {
      await launch();
      auth.add(const AppUser(uid: 'uid-a'));
      await settle();

      auth.add(null);
      await settle();

      expect(backend.cancelled, contains(notificationIdFor(101)));
      expect(backend.scheduled, isEmpty);
    });

    test('다른 계정으로 바로 바뀌어도 이전 계정의 알람을 지운다', () async {
      await launch();
      auth.add(const AppUser(uid: 'uid-a'));
      await settle();

      auth.add(const AppUser(uid: 'uid-b'));
      await settle();

      expect(backend.scheduled, isEmpty);
    });

    test('같은 계정으로 다시 켜면 알람을 그대로 둔다', () async {
      await launch(owner: 'uid-a');

      auth.add(const AppUser(uid: 'uid-a'));
      await settle();

      expect(backend.scheduled.keys, [notificationIdFor(101)]);
    });

    test('계정이 바뀐 뒤 정리 전에 앱이 꺼졌어도 다음 실행에서 이전 계정의 알람을 지운다', () async {
      // Firebase에는 B가 저장됐지만 A의 알람·주인 기록이 남은 채로 다시 켜진 상황.
      await launch(owner: 'uid-a');

      auth.add(const AppUser(uid: 'uid-b'));
      await settle();

      expect(backend.scheduled, isEmpty);
    });

    test('정리가 실패하면 주인을 바꾸지 않아 다음에 다시 지운다', () async {
      final registry = MemoryAlarmRegistry('uid-a');
      await AlarmScheduler(FakeAlarmBackend(), registry: registry, now: () => seoulTime(2026, 9, 7, 12))
          .syncTrip(sampleTrip(id: 7, tasks: [_task(101, DateTime(2026, 9, 21))]));

      await expectLater(
          AlarmScheduler(FakeAlarmBackend(failing: true), registry: registry).claimFor('uid-b'),
          throwsException);

      expect(registry.readOwner(), 'uid-a');
      expect(registry.read(), isNotEmpty);
    });

    test('로그아웃 때 정리하지 못했어도 로그아웃 상태로 다시 켜면 지운다', () async {
      await launch();

      auth.add(null);
      await settle();

      expect(backend.scheduled, isEmpty);
    });
  });
}
