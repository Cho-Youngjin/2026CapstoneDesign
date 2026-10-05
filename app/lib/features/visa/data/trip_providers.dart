import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip.dart';
import 'trip_api.dart';

const _activeTripIdKey = 'active_trip_id';

/// 앱 시작 시 `SharedPreferences.getInstance()` 결과로 override한다
/// (main.dart, main_dev.dart, 테스트). override 없이 읽으면 바로 알 수 있게 예외를 던진다.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider는 ProviderScope에서 override해야 합니다',
  );
});

/// 현재 화면에 표시 중인 여행의 서버 id. 앱을 재시작해도 유지된다.
///
/// 이 앱은 데모 범위상 "활성 여행 1개"만 다룬다 — 사용자의 여행 목록을 조회하는
/// API가 스펙에 없기 때문이다 (Plan B 상단 "서버 계약 가정" 참고).
class ActiveTripIdNotifier extends Notifier<int?> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  int? build() => ref.watch(sharedPreferencesProvider).getInt(_activeTripIdKey);

  Future<void> set(int tripId) async {
    state = tripId;
    await _prefs.setInt(_activeTripIdKey, tripId);
  }

  Future<void> clear() async {
    state = null;
    await _prefs.remove(_activeTripIdKey);
  }
}

final activeTripIdProvider =
    NotifierProvider<ActiveTripIdNotifier, int?>(ActiveTripIdNotifier.new);

/// 활성 여행. 없으면 null, 있으면 서버에서 최신 상태(판정·일정·stale 여부)를 가져온다.
///
/// 저장된 id의 여행이 서버에 없으면(404 — 로컬 DB 초기화, 다른 계정 로그인 등)
/// 활성 id를 지우고 null을 돌려준다. 그대로 두면 앱을 켤 때마다 같은 오류에 갇힌다.
final activeTripProvider = FutureProvider<Trip?>((ref) async {
  final tripId = ref.watch(activeTripIdProvider);
  if (tripId == null) return null;

  try {
    return await ref.watch(tripApiProvider).getTrip(tripId);
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) {
      await ref.read(activeTripIdProvider.notifier).clear();
      return null;
    }
    rethrow;
  }
});
