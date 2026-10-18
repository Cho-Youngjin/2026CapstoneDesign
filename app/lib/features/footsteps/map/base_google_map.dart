import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Plan F(주변 여행 정보)가 Places 마커를 얹어 재사용할 수 있도록
/// 지도 초기화·오버레이 렌더링만 책임지는 셸.
class BaseGoogleMap extends StatelessWidget {
  const BaseGoogleMap({
    super.key,
    required this.initialCamera,
    this.polygons = const {},
    this.markers = const {},
    this.polylines = const {},
    this.circles = const {},
    this.onMapCreated,
    this.onTap,
    this.myLocationEnabled = true,
    this.myLocationButtonEnabled,
  });

  final CameraPosition initialCamera;
  final Set<Polygon> polygons;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final Set<Circle> circles;
  final void Function(GoogleMapController controller)? onMapCreated;
  final void Function(LatLng position)? onTap;
  final bool myLocationEnabled;

  /// 지정하지 않으면 [myLocationEnabled]를 따른다. 조작할 수 없는 미니맵처럼 기본 "내 위치"
  /// 버튼이 눌리지도 않으면서 자리만 차지할 때 끄는 용도다.
  final bool? myLocationButtonEnabled;

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: initialCamera,
      polygons: polygons,
      markers: markers,
      polylines: polylines,
      circles: circles,
      onMapCreated: onMapCreated,
      onTap: onTap,
      // GPS가 갱신되는 대로 지도에 파란 점으로 실시간 반영된다 (별도 새로고침 불필요).
      myLocationEnabled: myLocationEnabled,
      myLocationButtonEnabled: myLocationButtonEnabled ?? myLocationEnabled,
      zoomControlsEnabled: false,
    );
  }
}
