import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/network/api_client.dart';
import '../data/checkin.dart';
import '../data/route_point.dart';
import '../data/route_snapping_api.dart';
import '../providers/footsteps_providers.dart';
import 'base_google_map.dart';

final _checkinsForCountryProvider =
    FutureProvider.family<List<Checkin>, String>((ref, iso) {
  return ref.watch(footstepsRepositoryProvider).checkinsForCountry(iso);
});

final _routePointsForCountryProvider =
    FutureProvider.family<List<RoutePoint>, String>((ref, iso) {
  return ref.watch(footstepsRepositoryProvider).routePointsForCountry(iso);
});

/// 하위 지도 — 특정 국가의 체크인을 날짜별로 골라 시간순 점선 경로로 보여준다.
/// 국경 이동 확정 체크인과 별개로, 걷는 동안 촘촘히 저장된 RoutePoints(영구 기록)를
/// 같은 날짜 기준으로 겹쳐 실선으로 그린다.
class CountryDetailMapPage extends ConsumerStatefulWidget {
  const CountryDetailMapPage({super.key, required this.isoAlpha2, required this.onBack});

  final String isoAlpha2;
  final VoidCallback onBack;

  @override
  ConsumerState<CountryDetailMapPage> createState() => _CountryDetailMapPageState();
}

// 지도 화면에 "반경 10km(가로 폭 약 10km)"를 보여주는 줌 레벨의 근사치.
// meters/px = 156543.034 * cos(lat) / 2^zoom 공식으로, 화면 폭 ~1080px 기준
// 10km를 담으려면 zoom ≈ 13.7이 필요하다(위도 37.5° 기준) — 처음에 11.5로
// 잡았다가 실기기 확인해보니 실제로는 약 46km 폭이 보여서(2km 경로가
// 화면에서 점처럼 보임) 다시 계산해 바로잡았다. Google Maps 줌은 위도에 따라
// 실제 축척이 달라지지만, 이 정도면 도시 단위 이동을 화면 안에 담기에 충분하다.
const _tenKmZoom = 13.7;

class _CountryDetailMapPageState extends ConsumerState<CountryDetailMapPage> {
  DateTime? _selectedDate;
  GoogleMapController? _mapController;

  // 도로 스냅 결과 캐시. 매 build마다 서버를 부르면 안 되므로, 원본 좌표
  // 개수가 바뀔 때만(새 RoutePoint가 쌓였을 때만) 다시 요청한다. 실패하거나
  // 아직 응답이 없으면 원본 좌표를 그대로 그린다.
  List<LatLng>? _snappedRouteLine;
  int _snappedForPointCount = -1;

  DateTime _dayOf(DateTime at) => DateTime.utc(at.year, at.month, at.day);

  void _showTimestamp(DateTime recordedAt) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('기록 시각: ${recordedAt.toLocal()}')),
    );
  }

  LatLng? _lastOrNull(List<LatLng> points) => points.isEmpty ? null : points.last;

  void _snapRouteLineIfNeeded(List<LatLng> rawLine) {
    if (rawLine.length < 2 || rawLine.length == _snappedForPointCount) return;
    _snappedForPointCount = rawLine.length;

    snapToRoads(ref.read(apiClientProvider), rawLine).then((snapped) {
      if (!mounted) return;
      setState(() => _snappedRouteLine = snapped);
    }).catchError((_) {
      // 오프라인이거나 서버가 죽었으면 원본 좌표(점선 없는 실선)로 계속 그린다.
    });
  }

  @override
  Widget build(BuildContext context) {
    // 새 RoutePoint가 저장될 때마다(걷는 동안 계속) 방금 읽은 DB 스냅샷을 다시
    // 읽어와 실선이 실시간으로 이어지게 하고, 지도 카메라도 그 위치로 옮겨
    // "현재 위치가 항상 화면 가운데"를 유지한다.
    ref.listen(liveRouteProvider, (_, next) {
      ref.invalidate(_routePointsForCountryProvider(widget.isoAlpha2));
      final last = _lastOrNull(next.asData?.value ?? const []);
      if (last != null) {
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(last, _tenKmZoom));
      }
    });

    final checkinsAsync = ref.watch(_checkinsForCountryProvider(widget.isoAlpha2));
    final routePoints =
        ref.watch(_routePointsForCountryProvider(widget.isoAlpha2)).asData?.value ??
            const <RoutePoint>[];

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.isoAlpha2} 이동 경로'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
      ),
      body: checkinsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('경로를 불러오지 못했습니다\n$e')),
        data: (checkins) {
          if (checkins.isEmpty) {
            return const Center(child: Text('이 나라의 체크인 기록이 없습니다'));
          }

          final checkinsByDate = <DateTime, List<Checkin>>{};
          for (final c in checkins) {
            checkinsByDate.putIfAbsent(_dayOf(c.recordedAt), () => []).add(c);
          }
          final routePointsByDate = <DateTime, List<RoutePoint>>{};
          for (final r in routePoints) {
            routePointsByDate.putIfAbsent(_dayOf(r.recordedAt), () => []).add(r);
          }

          // 체크인만 있는 날(오래된 기록)과 RoutePoint만 있는 날(국경을 넘지 않고
          // 같은 나라 안에서만 걸은 날)이 둘 다 날짜 선택지에 나와야 한다.
          final dates = {...checkinsByDate.keys, ...routePointsByDate.keys}.toList()..sort();
          final selected = _selectedDate ?? dates.last;
          final dayCheckins = checkinsByDate[selected] ?? const <Checkin>[];
          final dayRoutePoints = routePointsByDate[selected] ?? const <RoutePoint>[];

          final checkinPoints = [for (final c in dayCheckins) LatLng(c.lat, c.lng)];
          final rawRouteLine = [for (final r in dayRoutePoints) LatLng(r.lat, r.lng)];
          _snapRouteLineIfNeeded(rawRouteLine);
          // 스냅 응답이 아직 없거나 실패했으면 원본 GPS 좌표를 그대로 쓴다.
          final routeLine = _snappedRouteLine ?? rawRouteLine;

          // 지금 실시간으로 들어오고 있는 위치가 있으면 그걸 최우선으로 화면
          // 가운데에 놓는다 — "발걸음 상세 지도는 언제나 현재 위치 중심"이라는
          // 요구사항. 아직 GPS fix가 없으면(화면 진입 직후) 과거 기록으로 대체한다.
          final livePosition = _lastOrNull(ref.watch(liveRouteProvider).asData?.value ?? const []);
          final initialCameraTarget = livePosition ??
              (checkinPoints.isNotEmpty
                  ? checkinPoints.first
                  : (routeLine.isNotEmpty
                      ? routeLine.first
                      : LatLng(checkins.first.lat, checkins.first.lng)));

          return Column(
            children: [
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final date in dates)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text('${date.month}/${date.day}'),
                          selected: date == selected,
                          onSelected: (_) => setState(() => _selectedDate = date),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: BaseGoogleMap(
                  initialCamera: CameraPosition(target: initialCameraTarget, zoom: _tenKmZoom),
                  onMapCreated: (controller) => _mapController = controller,
                  circles: {
                    // 실선 위에 각 기록 갱신 시점을 작은 점으로 구분 표시한다.
                    // 탭하면 그 지점이 언제 기록됐는지 스낵바로 보여준다. 도로 스냅
                    // 결과(routeLine)는 보간되며 개수·순서가 원본과 달라질 수 있어
                    // 구분점은 항상 원본 좌표(rawRouteLine)에 찍는다.
                    for (var i = 0; i < dayRoutePoints.length; i++)
                      Circle(
                        circleId: CircleId('route_point_$i'),
                        center: rawRouteLine[i],
                        // 10km 뷰(_tenKmZoom) 기준으로 화면에서 알아볼 수 있는 크기.
                        // Circle 반경은 실제 미터 단위라 다른 줌에서는 커 보이거나
                        // 작아 보일 수 있다 — 기본 줌에 맞춘 근사치다.
                        // 실선과 같은 주황 계열로 채우면 선 위에서 묻혀 안 보이므로
                        // 흰 배경 + 진한 테두리로 확실히 도드라지게 한다.
                        radius: 80,
                        fillColor: Colors.white,
                        strokeWidth: 3,
                        strokeColor: const Color(0xFF9A3412),
                        consumeTapEvents: true,
                        onTap: () => _showTimestamp(dayRoutePoints[i].recordedAt),
                      ),
                  },
                  markers: {
                    for (var i = 0; i < dayCheckins.length; i++)
                      Marker(
                        markerId: MarkerId('checkin_$i'),
                        position: checkinPoints[i],
                        infoWindow: InfoWindow(
                          title: '${dayCheckins[i].recordedAt.toLocal()}',
                          snippet: dayCheckins[i].source.name,
                        ),
                      ),
                  },
                  polylines: {
                    Polyline(
                      polylineId: const PolylineId('day_route'),
                      points: checkinPoints,
                      color: const Color(0xFF2563EB),
                      width: 3,
                      patterns: [PatternItem.dot, PatternItem.gap(8)], // 시간순 점선 연결
                    ),
                    // 확정된 체크인과 별개로, 그날 실제로 걸은 경로를 실선으로 겹쳐
                    // 그린다 — 국경을 넘기 전까지는 체크인이 저장되지 않으므로
                    // 이 실선이 없으면 "그날 걸은 길"이 지도에 전혀 반영되지 않는다.
                    if (routeLine.length > 1)
                      Polyline(
                        polylineId: const PolylineId('day_walking_route'),
                        points: routeLine,
                        color: const Color(0xFFEA580C),
                        width: 4,
                      ),
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
