import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import '../models/trip.dart';
import '../models/trip_summary.dart';
import 'trip_api.dart';

const _cacheKey = 'trips.cache.v1';
const _selectedTripIdKey = 'selected_trip_id';

/// 마지막으로 서버에서 받은 여행 목록. 해외에서 데이터가 끊겨도 준비물 탭 상단과 지갑까지는
/// 들어갈 수 있게 하려는 용도다(여행계획 중심 설계 §4.2). 깨진 값이면 없는 것으로 본다.
class TripListCache {
  TripListCache(this._prefs);

  final SharedPreferences _prefs;

  List<TripSummary>? read() {
    final raw = _prefs.getString(_cacheKey);
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
    await _prefs.setString(_cacheKey, jsonEncode([for (final t in trips) t.toJson()]));
  }
}

final tripListCacheProvider = Provider<TripListCache>(
  (ref) => TripListCache(ref.watch(sharedPreferencesProvider)),
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
    final cache = ref.watch(tripListCacheProvider);
    try {
      final trips = await ref.watch(tripApiProvider).listTrips();
      await cache.write(trips);
      return TripListState(trips: trips);
    } catch (_) {
      final cached = cache.read();
      if (cached == null) rethrow;
      return TripListState(trips: cached, offline: true);
    }
  },
  retry: (_, _) => null,
);

/// 준비물 탭이 보여줄 여행의 id. 앱을 재시작해도 유지된다.
class SelectedTripIdNotifier extends Notifier<int?> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  int? build() => ref.watch(sharedPreferencesProvider).getInt(_selectedTripIdKey);

  Future<void> set(int tripId) async {
    state = tripId;
    await _prefs.setInt(_selectedTripIdKey, tripId);
  }

  Future<void> clear() async {
    state = null;
    await _prefs.remove(_selectedTripIdKey);
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
