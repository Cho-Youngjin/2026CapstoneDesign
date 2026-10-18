import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/prefs/shared_preferences_provider.dart';
import '../models/trip.dart';
import '../models/trip_summary.dart';
import '../notifications/alarm_scheduler.dart';
import 'trip_api.dart';

const _cacheKeyPrefix = 'trips.cache.v1';
const _selectedTripIdKeyPrefix = 'selected_trip_id';

/// 마지막으로 서버에서 받은 여행 목록. 해외에서 데이터가 끊겨도 준비물 탭 상단과 지갑까지는
/// 들어갈 수 있게 하려는 용도다(여행계획 중심 설계 §4.2). 깨진 값이면 없는 것으로 본다.
///
/// 계정이 바뀌면 이전 계정의 목록이 보이면 안 되므로 키에 uid를 붙인다.
/// uid가 없으면(로그아웃) 읽기는 null이고 쓰기·삭제는 아무것도 하지 않는다.
class TripListCache {
  TripListCache(this._prefs, this._uid);

  final SharedPreferences _prefs;
  final String? _uid;

  String? get _key => _uid == null ? null : '$_cacheKeyPrefix.$_uid';

  List<TripSummary>? read() {
    final key = _key;
    if (key == null) return null;
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List)
          .map((e) => TripSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> write(List<TripSummary> trips) async {
    final key = _key;
    if (key == null) return;
    await _prefs.setString(key, jsonEncode([for (final t in trips) t.toJson()]));
  }

  /// 서버에서 사라진 여행(상세 404)을 캐시에서도 뺀다. 캐시가 없으면 할 일이 없다.
  Future<void> remove(int tripId) async {
    final cached = read();
    if (cached == null) return;
    await write([for (final t in cached) if (t.id != tripId) t]);
  }
}

final tripListCacheProvider = Provider<TripListCache>(
  (ref) => TripListCache(
    ref.watch(sharedPreferencesProvider),
    ref.watch(currentUidProvider),
  ),
);

class TripListState {
  const TripListState({required this.trips, this.offline = false});

  final List<TripSummary> trips;

  /// 서버 조회에 실패해 캐시된 목록을 보여주는 중이다.
  final bool offline;
}

/// 내 여행 목록. 서버 조회에 성공하면 캐시를 갱신하고, 실패하면 캐시를 오프라인 표시와 함께 돌려준다.
/// 캐시도 없으면 오류를 그대로 낸다. 여행을 만들거나 지운 뒤에는 invalidate한다.
///
/// `retry`를 끈다: Riverpod 기본값은 실패한 provider를 최대 10번(수십 초) 자동 재시도해서
/// 오프라인 폴백과 오류 표시가 한참 뒤에야 나온다. 재시도는 사용자가 새로고침할 때 한다.
final tripListProvider = FutureProvider<TripListState>(
  (ref) async {
    // 캐시 provider가 uid를 watch하므로 계정이 바뀌면 이 목록도 새로 만들어진다.
    final cache = ref.watch(tripListCacheProvider);
    try {
      final trips = await ref.watch(tripApiProvider).listTrips();
      await cache.write(trips);
      // 서버 목록에 없는 여행(다른 기기에서 지웠거나 다른 계정의 여행)의 알람을 지운다.
      // 오프라인으로 캐시를 보여줄 때는 목록이 낡았을 수 있어 하지 않는다.
      unawaited(ref
          .read(alarmSchedulerProvider)
          .keepOnlyTrips({for (final t in trips) t.id}).catchError((Object e) {
        debugPrint('목록에 없는 여행의 비자 준비 알람 정리 실패: $e');
      }));
      return TripListState(trips: trips);
    } catch (_) {
      final cached = cache.read();
      if (cached == null) rethrow;
      return TripListState(trips: cached, offline: true);
    }
  },
  retry: (_, _) => null,
);

/// 준비물 탭이 보여줄 여행의 id. 앱을 재시작해도 유지되며, 계정(uid)별로 따로 저장한다.
/// uid가 없으면(로그아웃) 선택은 null이고 저장소는 건드리지 않는다.
class SelectedTripIdNotifier extends Notifier<int?> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  String? get _key {
    final uid = ref.read(currentUidProvider);
    return uid == null ? null : '$_selectedTripIdKeyPrefix.$uid';
  }

  @override
  int? build() {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) return null;
    return ref.watch(sharedPreferencesProvider).getInt('$_selectedTripIdKeyPrefix.$uid');
  }

  Future<void> set(int tripId) async {
    final key = _key;
    if (key == null) return;
    state = tripId;
    await _prefs.setInt(key, tripId);
  }

  Future<void> clear() async {
    final key = _key;
    if (key == null) return;
    state = null;
    await _prefs.remove(key);
  }
}

final selectedTripIdProvider =
    NotifierProvider<SelectedTripIdNotifier, int?>(SelectedTripIdNotifier.new);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 다가오는 여행(귀국일이 오늘 이후, 출발일 오름차순)과 지난 여행(출발일 내림차순)으로 나눈다.
({List<TripSummary> upcoming, List<TripSummary> past}) splitTrips(
  List<TripSummary> trips,
  DateTime now,
) {
  final today = _dateOnly(now);
  bool isPast(TripSummary t) => _dateOnly(t.returnDate).isBefore(today);
  final upcoming = trips.where((t) => !isPast(t)).toList()
    ..sort((a, b) => a.departDate.compareTo(b.departDate));
  final past = trips.where(isPast).toList()
    ..sort((a, b) => b.departDate.compareTo(a.departDate));
  return (upcoming: upcoming, past: past);
}

/// 준비물 탭이 보여줄 여행(설계 §3.3): 저장된 선택 여행 → 가장 가까운 다가오는 여행
/// → 가장 최근 지난 여행 → 없으면 null.
TripSummary? resolveSelectedTrip(List<TripSummary> trips, int? selectedId, DateTime now) {
  for (final t in trips) {
    if (t.id == selectedId) return t;
  }
  final split = splitTrips(trips, now);
  if (split.upcoming.isNotEmpty) return split.upcoming.first;
  if (split.past.isNotEmpty) return split.past.first;
  return null;
}

/// 여행 상세(판정·준비 일정). 화면을 떠나면 버리고, 다시 들어오면 서버에서 새로 읽는다.
///
/// `retry`를 끈다: 404나 서버 오류는 바로 보여주고, 재시도는 사용자가 [다시 시도]로 한다.
final tripProvider = FutureProvider.autoDispose.family<Trip, int>(
  (ref, id) => ref.watch(tripApiProvider).getTrip(id),
  retry: (_, _) => null,
);
