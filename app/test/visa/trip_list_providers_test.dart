import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/visa/data/trip_api.dart';
import 'package:app/features/visa/data/trip_list_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_trip_api.dart';

Future<ProviderContainer> _container({
  Map<String, Object> stored = const {},
  TripApi? api,
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
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
      final broken = await _container(stored: {'trips.cache.v1': 'not json'});
      expect(broken.read(tripListCacheProvider).read(), isNull);
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
  });

  group('selectedTripIdProvider', () {
    test('저장된 값으로 시작하고 set/clear가 저장값도 바꾼다', () async {
      final container = await _container(stored: {'selected_trip_id': 5});
      final prefs = container.read(sharedPreferencesProvider);

      expect(container.read(selectedTripIdProvider), 5);

      await container.read(selectedTripIdProvider.notifier).set(8);
      expect(container.read(selectedTripIdProvider), 8);
      expect(prefs.getInt('selected_trip_id'), 8);

      await container.read(selectedTripIdProvider.notifier).clear();
      expect(container.read(selectedTripIdProvider), isNull);
      expect(prefs.getInt('selected_trip_id'), isNull);
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
