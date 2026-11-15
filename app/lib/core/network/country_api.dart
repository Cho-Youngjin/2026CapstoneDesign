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

/// 사용자의 본국(한국). 서버 국가 목록(여행 목적지 20개국)에는 없어서 앱이 따로 들고 있는다.
/// 서버 목록에는 넣지 않고, 한국이 필요한 화면(여행 목적지 선택의 국내 여행, 주변 정보, 세계지도)이
/// [countriesWithHomeProvider]로 앞에 붙여 쓴다.
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

/// 서버 국가 목록 앞에 본국(한국)을 붙인 목록. 여행 목적지 선택(대한민국 = 국내 여행, 설계 9-1)과
/// 주변 정보·세계지도처럼 "지금 어느 나라에 있는가"를 보여주는 곳에서 쓴다.
final countriesWithHomeProvider = FutureProvider<List<Country>>((ref) async {
  final list = await ref.watch(countryListProvider.future);
  return [homeCountry, ...list.where((c) => c.isoAlpha2 != homeCountryIso2)];
});
