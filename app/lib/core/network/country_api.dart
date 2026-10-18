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

/// 사용자의 본국(한국). 서버 국가 목록(여행 목적지 20개국)에는 없어서 앱이 따로 들고 있는다 —
/// 서버 목록에 넣으면 비자 화면의 목적지 선택에 한국이 나타난다.
const homeCountryIso2 = 'KR';
const homeCountry = Country(
  isoAlpha2: homeCountryIso2,
  nameKo: '대한민국',
  nameEn: 'South Korea',
  continent: '아시아',
  tier: 'A',
);

final countryListProvider = FutureProvider<List<Country>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final Response<List<dynamic>> response = await dio.get('/api/countries');
  return response.data!
      .map((e) => Country.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// 서버 국가 목록 앞에 본국(한국)을 붙인 목록. 주변 정보처럼 "지금 어느 나라에 있는가"를
/// 보여주는 곳에서 쓴다(여행 목적지를 고르는 곳은 [countryListProvider]를 그대로 쓴다).
final countriesWithHomeProvider = FutureProvider<List<Country>>((ref) async {
  final list = await ref.watch(countryListProvider.future);
  return [homeCountry, ...list.where((c) => c.isoAlpha2 != homeCountryIso2)];
});
