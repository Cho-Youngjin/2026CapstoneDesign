import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../providers/footsteps_providers.dart' show liveRouteProvider;
import '../providers/overseas_mapping_session.dart';
import 'base_google_map.dart';
import 'position_arrow_icon.dart';

/// 해외 매핑 화면(설계 문서 §9). 한국에서의 실제 이동을 해외 도로망에 투영·매칭한
/// 결과(해외 지도)를 메인으로 보여주고, 실제 국내 이동은 오른쪽 아래 작은 지도로 보여준다.
///
/// 이 화면은 [overseasMappingProvider]의 상태를 그리기만 한다. 매핑 자체(위치 구독, 해외 경로
/// 계산, 저장)는 앱 전체 상태가 맡아서 다른 탭으로 가도 계속되고, 발걸음 탭으로 돌아오면
/// 이 화면이 다시 나온다. 끝내려면 [멈춤]을 눌러야 한다.
class OverseasMappingPage extends ConsumerStatefulWidget {
  const OverseasMappingPage({super.key});

  @override
  ConsumerState<OverseasMappingPage> createState() => _OverseasMappingPageState();
}

class _OverseasMappingPageState extends ConsumerState<OverseasMappingPage> {
  GoogleMapController? _krMapController;
  GoogleMapController? _jpMapController;

  // 해외 지도의 현재 위치점 + 진행 방향 화살표. 실제 GPS 파란 점은 국내 좌표라
  // 해외 지도에서는 끄고, 투영된 위치를 직접 마커로 그린다.
  BitmapDescriptor? _arrowIcon;

  @override
  void initState() {
    super.initState();
    buildPositionArrowIcon().then((icon) {
      if (mounted) setState(() => _arrowIcon = icon);
    });
  }

  // 한국 미니맵의 중심으로 쓸 가장 최근 실제 위치. 앱 전체 위치 스트림이 세션 경로보다 먼저
  // 갱신되고, 세션이 시작되기 전의 위치도 가지고 있다.
  LatLng? _latestKrPosition() {
    final live = ref.read(liveRouteProvider).asData?.value;
    if (live != null && live.isNotEmpty) return live.last;
    final route = ref.read(overseasMappingProvider).krRoute;
    return route.isEmpty ? null : route.last;
  }

  // 아직 받은 위치가 하나도 없을 때(제자리에 서 있는 채로 시작) 현재 위치를 한 번 읽어 가운데로 옮긴다.
  Future<void> _centerKrOnCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      _krMapController?.moveCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );
    } catch (_) {
      // 위치를 못 읽으면 기본 위치로 둔다 — 다음 위치 업데이트가 오면 그쪽으로 따라간다.
    }
  }

  @override
  Widget build(BuildContext context) {
    // 새 위치가 들어오면 각 지도가 현재 위치를 따라간다. 한국 미니맵은 항상 내 위치가 가운데다.
    ref.listen(liveRouteProvider, (prev, next) {
      final route = next.asData?.value;
      if (route != null && route.isNotEmpty) {
        _krMapController?.animateCamera(CameraUpdate.newLatLng(route.last));
      }
    });
    ref.listen(overseasMappingProvider, (prev, next) {
      final anchor = next.anchor;
      if (anchor != null && anchor != prev?.anchor) {
        _jpMapController?.animateCamera(CameraUpdate.newLatLng(anchor));
      }
    });

    final session = ref.watch(overseasMappingProvider);
    final startAnchor = session.startAnchor;
    final anchor = session.anchor;
    if (!session.active || startAnchor == null || anchor == null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('해외 매핑'),
        actions: [
          TextButton.icon(
            onPressed: () => ref.read(overseasMappingProvider.notifier).stop(),
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('멈춤'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: BaseGoogleMap(
              initialCamera: CameraPosition(target: anchor, zoom: 16),
              onMapCreated: (controller) => _jpMapController = controller,
              myLocationEnabled: false,
              markers: {
                Marker(markerId: const MarkerId('overseas_anchor_start'), position: startAnchor),
                if (_arrowIcon != null)
                  Marker(
                    markerId: const MarkerId('overseas_current'),
                    position: anchor,
                    icon: _arrowIcon!,
                    rotation: session.jpHeading,
                    flat: true,
                    anchor: const Offset(0.5, 0.5),
                    zIndexInt: 1,
                  ),
              },
              polylines: {
                if (session.jpRoute.length > 1)
                  Polyline(
                    polylineId: const PolylineId('jp_route'),
                    points: session.jpRoute,
                    color: const Color(0xFFEA580C),
                    width: 4,
                  ),
              },
            ),
          ),
          // 한국에서의 실제 이동 — 오른쪽 아래 미니맵. 조작은 막고 현재 위치만 따라간다.
          Positioned(
            right: 12,
            bottom: 12,
            width: 132,
            height: 176,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: BaseGoogleMap(
                    initialCamera: CameraPosition(
                      target: _latestKrPosition() ?? const LatLng(37.5665, 126.9780),
                      zoom: 15,
                    ),
                    onMapCreated: (controller) {
                      _krMapController = controller;
                      final latest = _latestKrPosition();
                      if (latest != null) {
                        controller.moveCamera(CameraUpdate.newLatLng(latest));
                      } else {
                        _centerKrOnCurrentPosition();
                      }
                    },
                    // 조작을 막은 미니맵이라 눌리지도 않는 "내 위치" 버튼은 숨긴다.
                    myLocationButtonEnabled: false,
                    polylines: {
                      if (session.krRoute.length > 1)
                        Polyline(
                          polylineId: const PolylineId('kr_route'),
                          points: session.krRoute,
                          color: const Color(0xFF2563EB),
                          width: 4,
                        ),
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
