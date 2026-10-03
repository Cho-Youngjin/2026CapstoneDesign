import 'package:app/features/visa/data/trip_api.dart';
import 'package:app/features/visa/data/trip_providers.dart';
import 'package:app/features/visa/models/trip.dart';
import 'package:dio/dio.dart';
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
  group('activeTripIdProvider', () {
    test('저장된 값이 없으면 null로 시작한다', () async {
      final container = await _container();

      expect(container.read(activeTripIdProvider), isNull);
    });

    test('앱 재시작 시 저장된 여행 id를 복원한다', () async {
      final container = await _container(stored: {'active_trip_id': 7});

      expect(container.read(activeTripIdProvider), 7);
    });

    test('set은 상태와 SharedPreferences를 함께 바꾼다', () async {
      final container = await _container();

      await container.read(activeTripIdProvider.notifier).set(42);

      expect(container.read(activeTripIdProvider), 42);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('active_trip_id'), 42);
    });

    test('clear는 상태와 저장값을 모두 지운다', () async {
      final container = await _container(stored: {'active_trip_id': 7});

      await container.read(activeTripIdProvider.notifier).clear();

      expect(container.read(activeTripIdProvider), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('active_trip_id'), isFalse);
    });
  });

  group('activeTripProvider', () {
    test('활성 여행이 없으면 서버를 호출하지 않고 null이다', () async {
      final api = FakeTripApi();
      final container = await _container(api: api);

      final trip = await container.read(activeTripProvider.future);

      expect(trip, isNull);
      expect(api.getTripCalls, isEmpty);
    });

    test('활성 여행 id로 서버에서 여행을 가져온다', () async {
      final api = FakeTripApi(tripToReturn: sampleTrip(id: 7));
      final container = await _container(stored: {'active_trip_id': 7}, api: api);

      final trip = await container.read(activeTripProvider.future);

      expect(trip!.id, 7);
      expect(api.getTripCalls, [7]);
    });

    test('활성 여행 id가 바뀌면 새 여행을 다시 가져온다', () async {
      final api = FakeTripApi(tripToReturn: sampleTrip(id: 9));
      final container = await _container(stored: {'active_trip_id': 7}, api: api);
      final sub = container.listen(activeTripProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(activeTripProvider.future);

      await container.read(activeTripIdProvider.notifier).set(9);
      await container.read(activeTripProvider.future);

      expect(api.getTripCalls, [7, 9]);
    });

    test('서버가 해당 여행을 404로 돌려주면 활성 id를 지우고 null이 된다', () async {
      final api = FakeTripApi(getTripStatusCode: 404);
      final container = await _container(stored: {'active_trip_id': 7}, api: api);
      // 실제 앱처럼 화면이 구독 중인 상태를 흉내 낸다. Riverpod 3는 구독자가 없는
      // provider의 재빌드를 멈춰 두기 때문에, 구독이 없으면 id를 지운 뒤의 재빌드가 돌지 않는다.
      final sub = container.listen(activeTripProvider, (_, _) {});
      addTearDown(sub.close);

      await container.read(activeTripProvider.future);
      final trip = await container.read(activeTripProvider.future);

      expect(trip, isNull);
      expect(container.read(activeTripIdProvider), isNull);
      expect(api.getTripCalls, [7], reason: 'id를 지운 뒤에는 다시 호출하지 않는다');
    });
  });

  test('sampleTrip 헬퍼가 판정 결과를 가진다', () {
    expect(sampleTrip(id: 1).visaResult.verdict, VisaVerdict.visaFreeOk);
  });

  test('FakeTripApi는 지정 상태 코드로 DioException을 낸다', () {
    expect(
      FakeTripApi(getTripStatusCode: 500).getTrip(1),
      throwsA(isA<DioException>()),
    );
  });
}
