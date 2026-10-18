import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/network/api_client.dart';
import '../models/place.dart';
import '../providers/nearby_selection_providers.dart';

/// 반경(m). 현재 위치 기준 8km까지의 정보를 보여준다.
const nearbySearchRadiusMeters = 8000;

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

  // 서버(Google Places)는 거리순도, 요청한 반경 안만 준다는 것도 보장하지 않는다 — 현재 위치에서
  // 직접 거리를 재서 반경 밖은 버리고 가까운 순으로 정렬한다. 목록과 지도가 같은 결과를 쓰므로
  // 여기서 한 번만 처리하고, 계산한 거리는 목록에 그대로 보여준다.
  final measured = [
    for (final p in places) p.withDistance(Geolocator.distanceBetween(lat, lng, p.lat, p.lng)),
  ].where((p) => p.distanceMeters! <= radius).toList()
    ..sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));
  return measured;
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
