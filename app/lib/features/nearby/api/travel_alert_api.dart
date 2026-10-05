import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../models/travel_alert.dart';

Future<List<TravelAlert>> fetchTravelAlerts(
  Dio dio, {
  required String iso2,
}) async {
  final response =
      await dio.get<List<dynamic>>('/api/countries/$iso2/alerts');
  return response.data!
      .map((e) => TravelAlert.fromJson(e as Map<String, dynamic>))
      .toList();
}

final travelAlertsProvider =
    FutureProvider.family<List<TravelAlert>, String>((ref, iso2) async {
  final dio = ref.watch(apiClientProvider);
  return fetchTravelAlerts(dio, iso2: iso2);
});
