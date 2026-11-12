import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'trip_period.dart';

/// 여행 기록 상태(설계 2026-11-07 9-2). 화면·기록 서비스·WorkManager가 서로 다른 isolate에서 같이 읽는다.
/// 셋 다 같은 Android SharedPreferences를 보지만 Dart 쪽 값은 isolate마다 따로 들고 있으므로, 다른 isolate가 쓴 값을
/// 보려면 읽기 전에 [reload]해야 한다. 값은 모두 JSON 문자열 하나씩이고, 깨진 값은 없는 것으로 본다.
///
/// 쓰는 쪽은 화면 isolate 하나뿐이다(코디네이터가 차례로 부른다). 쓰기 메서드는 다시 읽지 않고 이 isolate의 값을
/// 고쳐 쓰므로, 기록 서비스나 WorkManager에서 쓰기를 부르면 화면이 쓴 값을 덮어 잃을 수 있다.
///
/// - 일정: 마지막으로 서버에서 받은 내 여행 목록(기록할 여행을 고르는 재료)
/// - 일시정지: 사용자가 여행 상세에서 멈춘 여행 id(여행별)
/// - 주인: 여행 기록을 남긴 계정 uid. 다른 계정이 로그인하면 이전 계정의 기록을 지우는 기준이다(PR #32의 알람 주인과 같은 방식)
/// - 출발 알림: 출발일 아침 알림을 예약해 둔 여행 id(예약을 지울 때 쓴다)
/// - 지운 여행: 사용자가 일부러 지운 여행(삭제·404·계정 전환) id. 기록 서비스가 끝나며 늦게 쓴 점을 나중에 지우는 기준이다.
///   여행 id는 전체에서 유일하고 다시 쓰이지 않으므로 계속 쌓아도 아주 작다.
class TripRecordingStore {
  TripRecordingStore(this._prefs);

  final SharedPreferences _prefs;

  static const tripsKey = 'trip_recording.trips.v1';
  static const pausedKey = 'trip_recording.paused.v1';
  static const ownerKey = 'trip_recording.owner.v1';
  static const noticesKey = 'trip_recording.notices.v1';
  static const purgedKey = 'trip_recording.purged.v1';

  /// 다른 isolate가 쓴 값을 다시 읽어 온다.
  Future<void> reload() => _prefs.reload();

  List<TripPeriod> readTrips() {
    final raw = _prefs.getString(tripsKey);
    if (raw == null) return const [];
    try {
      return [
        for (final e in jsonDecode(raw) as List) TripPeriod.fromJson((e as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 일정을 [trips]로 바꾼다. 목록에 없는 여행의 일시정지도 함께 지운다 — 일정이 곧 지금 있는 여행이다.
  Future<void> replaceTrips(List<TripPeriod> trips) async {
    await _prefs.setString(tripsKey, jsonEncode([for (final t in trips) t.toJson()]));
    final ids = {for (final t in trips) t.tripId};
    final paused = readPaused();
    if (paused.any((id) => !ids.contains(id))) {
      await _writeIds(pausedKey, paused.where(ids.contains).toSet());
    }
  }

  Set<int> readPaused() => _readIds(pausedKey);

  Future<void> setPaused(int tripId, bool paused) {
    final ids = readPaused();
    paused ? ids.add(tripId) : ids.remove(tripId);
    return _writeIds(pausedKey, ids);
  }

  /// 없어진 여행을 일정·일시정지에서 뺀다.
  Future<void> forget(Set<int> tripIds) async {
    await _prefs.setString(
      tripsKey,
      jsonEncode([for (final t in readTrips()) if (!tripIds.contains(t.tripId)) t.toJson()]),
    );
    await _writeIds(pausedKey, readPaused()..removeAll(tripIds));
  }

  /// 일정만 비운다(로그아웃·계정 전환). 일시정지·주인·출발 알림 기록은 건드리지 않는다 — 여행 id는 서버 전체에서
  /// 유일해서, 같은 계정이 다시 로그인했을 때 멈춰 둔 여행이 몰래 다시 기록되지 않으려면 일시정지가 남아 있어야 한다.
  /// (목록에 없는 여행의 일시정지는 [replaceTrips]가 어차피 지운다.)
  Future<void> clearTrips() => _prefs.remove(tripsKey);

  /// 일시정지만 비운다(다른 계정으로 바뀔 때 — 이전 계정의 여행 id가 남지 않게).
  Future<void> clearPaused() => _prefs.remove(pausedKey);

  String? readOwner() => _prefs.getString(ownerKey);

  Future<void> writeOwner(String uid) => _prefs.setString(ownerKey, uid);

  /// 사용자가 일부러 지운 여행 id. 일정·일시정지를 비워도 남는다.
  Set<int> readPurged() => _readIds(purgedKey);

  Future<void> addPurged(Set<int> tripIds) => _writeIds(purgedKey, readPurged()..addAll(tripIds));

  Set<int> readNoticeTripIds() => _readIds(noticesKey);

  Future<void> writeNoticeTripIds(Set<int> tripIds) => _writeIds(noticesKey, tripIds);

  Set<int> _readIds(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return <int>{};
    try {
      return {for (final e in jsonDecode(raw) as List) e as int};
    } catch (_) {
      return <int>{};
    }
  }

  Future<void> _writeIds(String key, Set<int> ids) =>
      ids.isEmpty ? _prefs.remove(key) : _prefs.setString(key, jsonEncode(ids.toList()..sort()));
}
