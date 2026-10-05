import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../models/embassy.dart';

Future<List<Embassy>> fetchEmbassies(
  Dio dio, {
  required String iso2,
}) async {
  final response =
      await dio.get<List<dynamic>>('/api/countries/$iso2/embassies');
  return response.data!
      .map((e) => Embassy.fromJson(e as Map<String, dynamic>))
      .toList();
}

final embassiesProvider =
    FutureProvider.family<List<Embassy>, String>((ref, iso2) async {
  final dio = ref.watch(apiClientProvider);
  return fetchEmbassies(dio, iso2: iso2);
});
