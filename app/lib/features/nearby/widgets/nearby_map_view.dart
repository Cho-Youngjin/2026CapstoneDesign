import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';

import '../../footsteps/map/base_google_map.dart';
import '../../footsteps/map/position_arrow_icon.dart';
import '../models/embassy.dart';
import '../models/place.dart';

/// Plan C(발걸음)가 만든 [BaseGoogleMap] 셸을 재사용해 Places/재외공관 마커를 얹는다.
/// 장소가 있으면 현재 위치와 장소 핀이 모두 보이도록 카메라를 맞춘다.
class NearbyMapView extends StatefulWidget {
  const NearbyMapView({
    super.key,
    required this.center,
    required this.places,
    required this.embassies,
    this.overseasPosition,
    this.overseasHeading = 0,
  });

  final LatLng center;
  final List<Place> places;
  final List<Embassy> embassies;

  /// 해외 매핑 중 해외에서의 현재 위치(도로 위). 있으면 실제 GPS(한국) 파란 점 대신 이 위치를
  /// 표시하고, "내 위치" 버튼도 이 위치로 이동한다. 해외 매핑 중이 아니면 null이다.
  final LatLng? overseasPosition;
  final double overseasHeading;

  @override
  State<NearbyMapView> createState() => _NearbyMapViewState();
}

class _NearbyMapViewState extends State<NearbyMapView> {
  GoogleMapController? _controller;
  BitmapDescriptor? _arrowIcon;

  @override
  void initState() {
    super.initState();
    buildPositionArrowIcon().then((icon) {
      if (mounted) setState(() => _arrowIcon = icon);
    });
  }

  @override
  void didUpdateWidget(NearbyMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.places != widget.places || oldWidget.center != widget.center) {
      _fitToPlaces();
    }
  }

  Future<void> _fitToPlaces() async {
    final controller = _controller;
    if (controller == null || widget.places.isEmpty) return;

    final points = [
      widget.center,
      for (final p in widget.places) LatLng(p.lat, p.lng),
    ];
    final lats = points.map((p) => p.latitude);
    final lngs = points.map((p) => p.longitude);
    final bounds = LatLngBounds(
      southwest: LatLng(lats.reduce(math.min), lngs.reduce(math.min)),
      northeast: LatLng(lats.reduce(math.max), lngs.reduce(math.max)),
    );
    try {
      await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
    } catch (_) {
      // 지도가 아직 크기를 갖기 전이면 던질 수 있다 — 기본 카메라 위치로 둔다.
    }
  }

  @override
  Widget build(BuildContext context) {
    final places = widget.places;
    final embassies = widget.embassies;
    final center = widget.center;
    final markers = <Marker>{
      for (final place in places)
        Marker(
          markerId: MarkerId('place-${place.id}'),
          position: LatLng(place.lat, place.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(place.category.markerHue),
          infoWindow: InfoWindow(title: place.name, snippet: place.address),
        ),
      for (final embassy in embassies)
        Marker(
          markerId: MarkerId('embassy-${embassy.id}'),
          position: LatLng(embassy.lat, embassy.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(title: embassy.name, snippet: embassy.address),
        ),
    };

    final overseas = widget.overseasPosition;
    if (overseas != null) {
      markers.add(Marker(
        markerId: const MarkerId('overseas_current'),
        position: overseas,
        // 아이콘을 만드는 동안은 기본 파란 마커로 대신한다.
        icon: _arrowIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        rotation: widget.overseasHeading,
        flat: true,
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 1,
      ));
    }

    final map = BaseGoogleMap(
      initialCamera: CameraPosition(
        target: center,
        zoom: 15,
      ),
      markers: markers,
      // 해외 매핑 중에는 기본 파란 점·"내 위치" 버튼이 한국 위치를 가리키므로 끄고 해외 위치를 직접 그린다.
      myLocationEnabled: overseas == null,
      onMapCreated: (controller) {
        _controller = controller;
        _fitToPlaces();
      },
    );
    if (overseas == null) return map;

    return Stack(
      children: [
        Positioned.fill(child: map),
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 2,
            child: IconButton(
              tooltip: '해외 현재 위치',
              icon: const Icon(Icons.my_location),
              onPressed: () => _controller?.animateCamera(CameraUpdate.newLatLngZoom(overseas, 15)),
            ),
          ),
        ),
      ],
    );
  }
}
