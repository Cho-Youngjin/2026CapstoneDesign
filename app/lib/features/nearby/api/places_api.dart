import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  return response.data!
      .map((e) => Place.fromJson(e as Map<String, dynamic>))
      .toList();
}

final nearbyPlacesProvider = FutureProvider<List<Place>>((ref) async {
  final position = await ref.watch(currentPositionProvider.future);
  final category = ref.watch(nearbyCategoryProvider);
  final dio = ref.watch(apiClientProvider);

  return fetchNearbyPlaces(
    dio,
    lat: position.latitude,
    lng: position.longitude,
    category: category,
  );
});
