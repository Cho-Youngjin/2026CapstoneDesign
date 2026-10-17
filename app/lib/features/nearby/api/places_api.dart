import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/network/api_client.dart';
import '../models/place.dart';
import '../providers/nearby_selection_providers.dart';

/// 반경(m). 현재 위치 기준 10km까지의 정보를 보여준다.
const nearbySearchRadiusMeters = 10000;

Future<List<Place>> fetchNearbyPlaces(
  Dio dio, {
  required double lat,
  required double lng,
  required PlaceCategory category,
  int radius = nearbySearchRadiusMeters,
}) async {
  final response = await dio.get<List<dynamic>>(
    '/api/places/nearby',
    queryParameters: {
      'lat': lat,
      'lng': lng,
      'radius': radius,
      'category': category.apiValue,
    },
  );
  final places = response.data!
      .map((e) => Place.fromJson(e as Map<String, dynamic>))
      .toList();

  // 서버(Google Places)는 거리순을 보장하지 않으므로 현재 위치에서 가까운 순으로 정렬한다.
  // 목록과 지도가 같은 결과를 쓰므로 여기서 한 번만 정렬한다.
  double distanceTo(Place p) => Geolocator.distanceBetween(lat, lng, p.lat, p.lng);
  places.sort((a, b) => distanceTo(a).compareTo(distanceTo(b)));
  return places;
}

final nearbyPlacesProvider = FutureProvider<List<Place>>((ref) async {
  final position = await ref.watch(nearbyPositionProvider.future);
  final category = ref.watch(nearbyCategoryProvider);
  final dio = ref.watch(apiClientProvider);

  return fetchNearbyPlaces(
    dio,
    lat: position.latitude,
    lng: position.longitude,
    category: category,
  );
});
