import 'dart:convert';

import 'package:app/features/footsteps/trip/trip_recording_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'trip_fakes.dart';

Future<(TripRecordingStore, SharedPreferences)> _store([Map<String, Object> stored = const {}]) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  return (TripRecordingStore(prefs), prefs);
}

void main() {
  final a = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));
  final b = period(8, DateTime(2026, 12, 1), DateTime(2026, 12, 5));

  test('일정을 통째로 바꾸고 되읽는다', () async {
    final (store, _) = await _store();
    expect(store.readTrips(), isEmpty);

    await store.replaceTrips([a, b]);

    expect(store.readTrips(), [a, b]);
  });

  test('깨진 값은 없는 것으로 본다', () async {
    final (store, _) = await _store({
      TripRecordingStore.tripsKey: '{oops',
      TripRecordingStore.pausedKey: '[1, "x"]',
    });

    expect(store.readTrips(), isEmpty);
    expect(store.readPaused(), isEmpty);
  });

  test('일시정지는 여행별로 켜고 끈다', () async {
    final (store, _) = await _store();

    await store.setPaused(7, true);
    await store.setPaused(8, true);
    await store.setPaused(7, false);

    expect(store.readPaused(), {8});
  });

  test('일정을 바꾸면 목록에 없는 여행의 일시정지는 지운다', () async {
    final (store, _) = await _store();
    await store.setPaused(7, true);
    await store.setPaused(8, true);

    await store.replaceTrips([b]);

    expect(store.readPaused(), {8});
  });

  test('없어진 여행은 일정과 일시정지에서 빠진다', () async {
    final (store, _) = await _store();
    await store.replaceTrips([a, b]);
    await store.setPaused(7, true);

    await store.forget({7});

    expect(store.readTrips(), [b]);
    expect(store.readPaused(), isEmpty);
  });

  test('일정을 비워도 일시정지·주인·출발 알림 기록은 남는다', () async {
    final (store, _) = await _store();
    await store.replaceTrips([a]);
    await store.setPaused(7, true);
    await store.writeOwner('uid-a');
    await store.writeNoticeTripIds({7});

    await store.clearTrips();

    expect(store.readTrips(), isEmpty);
    expect(store.readPaused(), {7});
    expect(store.readOwner(), 'uid-a');
    expect(store.readNoticeTripIds(), {7});
  });

  test('일시정지만 따로 비울 수 있다', () async {
    final (store, _) = await _store();
    await store.replaceTrips([a]);
    await store.setPaused(7, true);
    await store.writeOwner('uid-a');
    await store.writeNoticeTripIds({7});

    await store.clearPaused();

    expect(store.readTrips(), [a]);
    expect(store.readPaused(), isEmpty);
    expect(store.readOwner(), 'uid-a');
    expect(store.readNoticeTripIds(), {7});
  });

  test('일부러 지운 여행 id는 기기에 남아 누적되고, 일정·일시정지를 비워도 남는다', () async {
    final (store, _) = await _store();
    expect(store.readPurged(), isEmpty);

    await store.addPurged({7});
    await store.addPurged({8, 7});
    await store.replaceTrips([a]);
    await store.clearTrips();
    await store.clearPaused();

    expect(store.readPurged(), {7, 8});
    // 다시 만든 저장소(앱 재시작)에서도 읽힌다.
    final (reopened, _) = await _store({TripRecordingStore.purgedKey: jsonEncode([7, 8])});
    expect(reopened.readPurged(), {7, 8});
  });

  test('다른 isolate가 쓴 값은 reload한 뒤에 보인다', () async {
    final (store, _) = await _store();
    expect(store.readTrips(), isEmpty);

    // 화면 isolate가 일정을 쓴 상황을 흉내 낸다(같은 Android 저장소, 다른 Dart 캐시).
    SharedPreferences.setMockInitialValues({
      TripRecordingStore.tripsKey: jsonEncode([a.toJson()]),
    });
    expect(store.readTrips(), isEmpty);

    await store.reload();
    expect(store.readTrips(), [a]);
  });
}
