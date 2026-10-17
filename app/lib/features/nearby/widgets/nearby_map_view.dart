import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';

import '../../footsteps/map/base_google_map.dart';
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
  });

  final LatLng center;
  final List<Place> places;
  final List<Embassy> embassies;

  @override
  State<NearbyMapView> createState() => _NearbyMapViewState();
}

class _NearbyMapViewState extends State<NearbyMapView> {
  GoogleMapController? _controller;

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

    return BaseGoogleMap(
      initialCamera: CameraPosition(
        target: center,
        zoom: 15,
      ),
      markers: markers,
      onMapCreated: (controller) {
        _controller = controller;
        _fitToPlaces();
      },
    );
  }
}
