import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footstep_core/footstep_core.dart' show Stay, TimeSpan;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/db/app_database.dart';
import '../../../core/network/api_client.dart';
import '../data/route_point.dart';
import '../health/distance_step_estimator.dart' show totalDistanceMeters;
import 'route_reconstruct_api.dart';
import 'trip_day.dart';
import 'trip_recording_permissions.dart';
import 'trip_recording_providers.dart';

/// 한 여행의 기록(점·정지 구간). 기록 서비스는 다른 isolate의 DB 연결로 쓰므로 drift의 watch로는 바뀐 것을 알 수 없다 —
/// 화면을 다시 열거나 새로고침할 때 다시 읽는다(autoDispose).
final tripRecordsProvider =
    FutureProvider.autoDispose.family<({List<RoutePoint> points, List<TimeSpan> spans}), int>((ref, tripId) async {
  final db = ref.watch(appDatabaseProvider);
  return (points: await db.routePointsForTrip(tripId), spans: await db.stillSpansForTrip(tripId));
});

final routeReconstructApiProvider =
    Provider<RouteReconstructApi>((ref) => RouteReconstructApi(ref.watch(apiClientProvider)));

/// 복원 결과의 캐시 키(설계 9-4): 여행, 날짜, 그날 마지막 점 시각, 머문 곳. 점이 새로 쌓이면 마지막 점 시각이 바뀌어 다시
/// 복원한다. 일시정지로 정지 구간이 닫히면 점은 그대로여도 머문 곳이 바뀌므로(서버에 같이 보낸다) 머문 곳의 도착·출발
/// 시각도 키에 넣는다. [day]는 키가 아니라 서버에 보낼 재료다 — 같은 키면 같은 점·머문 곳이다.
class DayRouteRequest {
  const DayRouteRequest({required this.tripId, required this.day, this.countryIso2 = snapCountryIso2});

  /// 서버가 도로에 맞춰 줄 수 있는 나라(서버 `RouteReconstructionService.COUNTRY`). 해외 이동은 연구 범위 밖이다.
  static const snapCountryIso2 = 'KR';

  final int tripId;
  final TripDay day;

  /// 여행 국가. 한 여행의 국가는 변하지 않으므로 캐시 키에는 넣지 않는다.
  final String countryIso2;

  @override
  bool operator ==(Object other) =>
      other is DayRouteRequest &&
      other.tripId == tripId &&
      other.day.date == day.date &&
      other.day.lastPointMs == day.lastPointMs &&
      _sameStays(other.day.stays, day.stays);

  @override
  int get hashCode => Object.hash(
        tripId,
        day.date,
        day.lastPointMs,
        Object.hashAll([for (final s in day.stays) Object.hash(s.arriveMs, s.leaveMs)]),
      );

  static bool _sameStays(List<Stay> a, List<Stay> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].arriveMs != b[i].arriveMs || a[i].leaveMs != b[i].leaveMs) return false;
    }
    return true;
  }
}

/// 고른 날의 지도에 그릴 경로.
class DayRoute {
  const DayRoute({required this.segments, required this.roadMatched});

  /// 점을 순서대로 이은 직선. 서버·네트워크가 실패했을 때 쓴다.
  factory DayRoute.straight(List<RoutePoint> points, {required bool roadMatched}) => DayRoute(
        segments: [
          if (points.isNotEmpty)
            RouteSegmentView(
              kind: RouteSegmentView.walk,
              coords: [for (final p in points) LatLng(p.lat, p.lng)],
              fallback: !roadMatched,
            ),
        ],
        roadMatched: roadMatched,
      );

  final List<RouteSegmentView> segments;

  /// false면 서버·네트워크 실패나 OSRM 대체로 직선이 섞였다 — "도로 맞춤을 못 했어요"라고 안내한다.
  final bool roadMatched;

  /// 그린 경로의 길이(탈것·추정 구간 포함). 도로에 맞췄으면 도로 거리, 아니면 직선거리다.
  double get distanceMeters => segments.fold(0.0, (sum, s) => sum + totalDistanceMeters(s.coords));
}

/// 날짜별 복원 경로. autoDispose가 아니라 앱이 떠 있는 동안 메모리에 남는다(설계 9-4의 캐시). 실패는 직선으로 바꿔 돌려주므로
/// 같은 키로는 다시 부르지 않는다 — 화면의 [다시 시도]가 이 항목만 invalidate한다. Riverpod의 자동 재시도는 끈다.
final dayRouteProvider = FutureProvider.family<DayRoute, DayRouteRequest>((ref, request) async {
  final points = request.day.points;
  // 점이 둘보다 적으면 이을 길이 없다 — 서버를 부르지 않는다.
  if (points.length < 2) return DayRoute.straight(points, roadMatched: true);
  // 서버는 국내(KR)만 복원한다. 국내가 아닌 여행은 호출하지 않고 직선으로 그리며, 실패 안내도 띄우지 않는다.
  if (request.countryIso2 != DayRouteRequest.snapCountryIso2) return DayRoute.straight(points, roadMatched: true);
  try {
    final segments = await ref.watch(routeReconstructApiProvider).reconstruct(points, request.day.stays);
    return DayRoute(segments: segments, roadMatched: !segments.any((s) => s.fallback));
  } catch (_) {
    return DayRoute.straight(points, roadMatched: false);
  }
}, retry: (_, _) => null);

/// 여행 기록에 필요한데 없는 권한(설계 9-4 배너). 설정에서 돌아오면 화면이 다시 묻는다.
final missingTripPermissionsProvider = FutureProvider.autoDispose<Set<TripRecordingPermission>>(
  (ref) => ref.watch(tripRecordingPermissionsProvider).missing(),
);
