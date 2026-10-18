import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/visa/data/trip_api.dart';
import 'package:app/features/visa/data/trip_list_providers.dart';
import 'package:app/features/visa/models/trip.dart';
import 'package:app/features/visa/notifications/alarm_scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_alarm_backend.dart';
import 'fake_trip_api.dart';

Future<ProviderContainer> _container({
  Map<String, Object> stored = const {},
  TripApi? api,
  String? uid = 'uid-a',
  AlarmScheduler? alarms,
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUidProvider.overrideWithValue(uid),
      if (api != null) tripApiProvider.overrideWithValue(api),
      if (alarms != null) alarmSchedulerProvider.overrideWithValue(alarms),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 계정 전환을 흉내 내려고 uid를 바꿀 수 있게 만든 테스트용 notifier.
class _UidNotifier extends Notifier<String?> {
  @override
  String? build() => 'uid-a';

  void switchTo(String? uid) => state = uid;
}

final _uidForTest = NotifierProvider<_UidNotifier, String?>(_UidNotifier.new);

Future<ProviderContainer> _switchableContainer({
  Map<String, Object> stored = const {},
  TripApi? api,
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUidProvider.overrideWith((ref) => ref.watch(_uidForTest)),
      if (api != null) tripApiProvider.overrideWithValue(api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  final now = DateTime(2026, 10, 11, 15);
  final pastOld = sampleSummary(id: 1, depart: DateTime(2026, 3, 1), ret: DateTime(2026, 3, 5));
  final pastRecent = sampleSummary(id: 2, depart: DateTime(2026, 9, 1), ret: DateTime(2026, 9, 5));
  final endsToday = sampleSummary(id: 3, depart: DateTime(2026, 10, 8), ret: DateTime(2026, 10, 11));
  final later = sampleSummary(id: 4, depart: DateTime(2027, 1, 1), ret: DateTime(2027, 1, 5));

  group('splitTrips', () {
    test('귀국일이 오늘 이후면 다가오는 여행(출발일 오름차순), 아니면 지난 여행(출발일 내림차순)', () {
      final split = splitTrips([pastOld, later, pastRecent, endsToday], now);

      expect(split.upcoming.map((t) => t.id), [3, 4]);
      expect(split.past.map((t) => t.id), [2, 1]);
    });
  });

  group('resolveSelectedTrip', () {
    test('저장된 선택 여행이 목록에 있으면 그 여행', () {
      expect(resolveSelectedTrip([pastOld, later], 1, now)?.id, 1);
    });

    test('선택 여행이 없거나 목록에 없으면 가장 가까운 다가오는 여행', () {
      expect(resolveSelectedTrip([pastRecent, later, endsToday], null, now)?.id, 3);
      expect(resolveSelectedTrip([pastRecent, later], 99, now)?.id, 4);
    });

    test('다가오는 여행이 없으면 가장 최근 지난 여행', () {
      expect(resolveSelectedTrip([pastOld, pastRecent], null, now)?.id, 2);
    });

    test('여행이 하나도 없으면 null', () {
      expect(resolveSelectedTrip(const [], 1, now), isNull);
    });
  });

  group('TripListCache', () {
    test('쓴 목록을 그대로 읽는다', () async {
      final container = await _container();
      final cache = container.read(tripListCacheProvider);

      await cache.write([pastOld, later]);

      expect(cache.read()!.map((t) => t.id), [1, 4]);
    });

    test('캐시가 없거나 깨졌으면 null', () async {
      expect((await _container()).read(tripListCacheProvider).read(), isNull);
      final broken = await _container(stored: {'trips.cache.v1.uid-a': 'not json'});
      expect(broken.read(tripListCacheProvider).read(), isNull);
    });

    test('다른 계정(uid)이 쓴 캐시는 읽지 않는다', () async {
      final a = await _container();
      await a.read(tripListCacheProvider).write([pastOld]);
      final prefs = a.read(sharedPreferencesProvider);

      final b = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUidProvider.overrideWithValue('uid-b'),
      ]);
      addTearDown(b.dispose);

      expect(b.read(tripListCacheProvider).read(), isNull);
      expect(a.read(tripListCacheProvider).read()!.single.id, 1);
    });

    test('uid가 없으면(로그아웃) 읽기는 null이고 쓰기는 아무것도 저장하지 않는다', () async {
      final container = await _container(uid: null);
      final cache = container.read(tripListCacheProvider);

      await cache.write([pastOld]);

      expect(cache.read(), isNull);
      expect(container.read(sharedPreferencesProvider).getKeys(), isEmpty);
    });

    test('remove는 그 여행만 캐시에서 뺀다', () async {
      final container = await _container();
      final cache = container.read(tripListCacheProvider);
      await cache.write([pastOld, later]);

      await cache.remove(1);

      expect(cache.read()!.map((t) => t.id), [4]);
    });

    test('remove는 캐시가 없으면 아무것도 만들지 않는다', () async {
      final container = await _container();

      await container.read(tripListCacheProvider).remove(1);

      expect(container.read(sharedPreferencesProvider).getKeys(), isEmpty);
    });
  });

  group('tripListProvider', () {
    test('서버 목록을 돌려주고 캐시에 저장한다', () async {
      final container = await _container(api: FakeTripApi(trips: [later]));

      final state = await container.read(tripListProvider.future);

      expect(state.trips.map((t) => t.id), [4]);
      expect(state.offline, isFalse);
      expect(container.read(tripListCacheProvider).read()!.single.id, 4);
    });

    test('서버 조회가 실패하면 캐시를 오프라인 표시와 함께 돌려준다', () async {
      final container = await _container(api: FakeTripApi(listTripsStatusCode: 503));
      await container.read(tripListCacheProvider).write([pastRecent]);

      final state = await container.read(tripListProvider.future);

      expect(state.trips.single.id, 2);
      expect(state.offline, isTrue);
    });

    test('서버 조회가 실패하고 캐시도 없으면 오류를 낸다', () async {
      final container = await _container(api: FakeTripApi(listTripsStatusCode: 503));

      await expectLater(container.read(tripListProvider.future), throwsA(anything));
    });

    test('계정이 바뀌면 이전 계정의 캐시를 오프라인 목록으로 보여주지 않는다', () async {
      final container = await _switchableContainer(api: FakeTripApi(listTripsStatusCode: 503));
      await container.read(tripListCacheProvider).write([pastRecent]);
      expect((await container.read(tripListProvider.future)).offline, isTrue);

      container.read(_uidForTest.notifier).switchTo('uid-b');

      await expectLater(container.read(tripListProvider.future), throwsA(anything));
    });

    group('준비 일정 알람 정리', () {
      Future<(AlarmScheduler, FakeAlarmBackend)> alarmsFor7And9() async {
        final backend = FakeAlarmBackend();
        final scheduler = AlarmScheduler(backend, now: () => seoulTime(2026, 9, 7, 12));
        for (final id in [7, 9]) {
          await scheduler.syncTrip(sampleTrip(id: id, tasks: [
            TripTask(id: id * 10, title: '여행자보험 가입', dueDate: DateTime(2026, 11, 20), done: false),
          ]));
        }
        return (scheduler, backend);
      }

      test('서버 목록에 없는 여행(다른 기기에서 지운 여행)의 알람을 지운다', () async {
        final (scheduler, backend) = await alarmsFor7And9();
        final container = await _container(
            api: FakeTripApi(trips: [sampleSummary(id: 7)]), alarms: scheduler);

        await container.read(tripListProvider.future);
        await scheduler.keepOnlyTrips({7, 9}); // 앞선 정리가 끝날 때까지 기다린다(순서대로 처리)

        expect(backend.scheduled.keys, [notificationIdFor(70)]);
      });

      test('오프라인 캐시를 보여줄 때는 알람을 건드리지 않는다', () async {
        final (scheduler, backend) = await alarmsFor7And9();
        final container = await _container(
            api: FakeTripApi(listTripsStatusCode: 503), alarms: scheduler);
        await container.read(tripListCacheProvider).write([sampleSummary(id: 7)]);

        await container.read(tripListProvider.future);
        await scheduler.keepOnlyTrips({7, 9});

        expect(backend.scheduled.keys,
            unorderedEquals([notificationIdFor(70), notificationIdFor(90)]));
      });
    });
  });

  group('selectedTripIdProvider', () {
    test('저장된 값으로 시작하고 set/clear가 저장값도 바꾼다', () async {
      final container = await _container(stored: {'selected_trip_id.uid-a': 5});
      final prefs = container.read(sharedPreferencesProvider);

      expect(container.read(selectedTripIdProvider), 5);

      await container.read(selectedTripIdProvider.notifier).set(8);
      expect(container.read(selectedTripIdProvider), 8);
      expect(prefs.getInt('selected_trip_id.uid-a'), 8);

      await container.read(selectedTripIdProvider.notifier).clear();
      expect(container.read(selectedTripIdProvider), isNull);
      expect(prefs.getInt('selected_trip_id.uid-a'), isNull);
    });

    test('선택은 계정(uid)별로 따로 저장되고 계정이 바뀌면 그 계정의 값으로 바뀐다', () async {
      final container = await _switchableContainer(stored: {'selected_trip_id.uid-a': 5});
      final prefs = container.read(sharedPreferencesProvider);
      expect(container.read(selectedTripIdProvider), 5);

      container.read(_uidForTest.notifier).switchTo('uid-b');
      expect(container.read(selectedTripIdProvider), isNull);

      await container.read(selectedTripIdProvider.notifier).set(9);
      expect(prefs.getInt('selected_trip_id.uid-b'), 9);
      expect(prefs.getInt('selected_trip_id.uid-a'), 5);

      container.read(_uidForTest.notifier).switchTo('uid-a');
      expect(container.read(selectedTripIdProvider), 5);
    });

    test('uid가 없으면 선택은 null이고 set/clear는 저장소를 건드리지 않는다', () async {
      final container = await _container(stored: {'selected_trip_id.uid-a': 5}, uid: null);
      final prefs = container.read(sharedPreferencesProvider);

      expect(container.read(selectedTripIdProvider), isNull);

      await container.read(selectedTripIdProvider.notifier).set(8);
      await container.read(selectedTripIdProvider.notifier).clear();

      expect(container.read(selectedTripIdProvider), isNull);
      expect(prefs.getKeys(), {'selected_trip_id.uid-a'});
    });
  });

  test('tripProvider는 id로 서버에서 여행을 가져온다', () async {
    final api = FakeTripApi(tripToReturn: sampleTrip(id: 9));
    final container = await _container(api: api);

    final trip = await container.read(tripProvider(9).future);

    expect(trip.id, 9);
    expect(api.getTripCalls, [9]);
  });
}
