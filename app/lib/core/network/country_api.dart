import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class Country {
  const Country({
    required this.isoAlpha2,
    required this.nameKo,
    this.nameEn,
    this.continent,
    required this.tier,
  });

  final String isoAlpha2;
  final String nameKo;
  final String? nameEn;
  final String? continent;
  final String tier;

  factory Country.fromJson(Map<String, dynamic> json) => Country(
        isoAlpha2: json['isoAlpha2'] as String,
        nameKo: json['nameKo'] as String,
        nameEn: json['nameEn'] as String?,
        continent: json['continent'] as String?,
        tier: json['tier'] as String,
      );
}

final countryListProvider = FutureProvider<List<Country>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final Response<List<dynamic>> response = await dio.get('/api/countries');
  return response.data!
      .map((e) => Country.fromJson(e as Map<String, dynamic>))
      .toList();
});
