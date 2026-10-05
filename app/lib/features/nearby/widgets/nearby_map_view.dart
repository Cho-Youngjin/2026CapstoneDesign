import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';

import '../../footsteps/map/base_google_map.dart';
import '../models/embassy.dart';
import '../models/place.dart';

/// Plan C(발걸음)가 만든 [BaseGoogleMap] 셸을 재사용해 Places/재외공관 마커를 얹는다.
class NearbyMapView extends StatelessWidget {
  const NearbyMapView({
    super.key,
    required this.center,
    required this.places,
    required this.embassies,
  });

  final Position center;
  final List<Place> places;
  final List<Embassy> embassies;

  @override
  Widget build(BuildContext context) {
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
        target: LatLng(center.latitude, center.longitude),
        zoom: 15,
      ),
      markers: markers,
    );
  }
}
