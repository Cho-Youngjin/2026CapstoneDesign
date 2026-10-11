import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../prefs/shared_preferences_provider.dart';
import 'api_client.dart';

/// 서버 country 테이블의 card_acceptance 값을 화면에 보여줄 한글 3단계로 바꾼다.
enum PaymentTier {
  cashRecommended, // LOW
  cashPrepare, // MEDIUM
  cardFriendly; // HIGH

  static PaymentTier fromCardAcceptance(String value) {
    switch (value.toUpperCase()) {
      case 'HIGH':
        return PaymentTier.cardFriendly;
      case 'MEDIUM':
        return PaymentTier.cashPrepare;
      case 'LOW':
        return PaymentTier.cashRecommended;
      default:
        throw ArgumentError('알 수 없는 card_acceptance 값: $value');
    }
  }
}

extension PaymentTierLabel on PaymentTier {
  String get labelKo {
    switch (this) {
      case PaymentTier.cardFriendly:
        return '카드 결제 용이';
      case PaymentTier.cashPrepare:
        return '현금 구비';
      case PaymentTier.cashRecommended:
        return '현금 권장';
    }
  }
}

/// `GET /api/countries/{iso2}` 응답 (서버 CountryDetailResponse와 1:1 대응).
class CountryDetail {
  const CountryDetail({
    required this.isoAlpha2,
    this.isoAlpha3,
    required this.nameKo,
    this.nameEn,
    this.continent,
    this.tier,
    this.plugTypes,
    this.voltageV,
    this.frequencyHz,
    this.currencyCode,
    required this.cardAcceptance,
    this.powerBankWhLimit,
  });

  final String isoAlpha2;
  final String? isoAlpha3;
  final String nameKo;
  final String? nameEn;
  final String? continent;
  final String? tier;
  final String? plugTypes;
  final int? voltageV;
  final int? frequencyHz;
  final String? currencyCode;
  final String cardAcceptance;
  final int? powerBankWhLimit;

  bool get hasDetail => cardAcceptance.isNotEmpty;

  /// 화면에 표시할 한글 3단계 등급. cardAcceptance가 아직 채워지지 않았을 수도 있어
  /// null을 반환할 수 있다.
  PaymentTier? get paymentTier {
    if (cardAcceptance.isEmpty) return null;
    return PaymentTier.fromCardAcceptance(cardAcceptance);
  }

  factory CountryDetail.fromJson(Map<String, dynamic> json) => CountryDetail(
        isoAlpha2: json['isoAlpha2'] as String,
        isoAlpha3: json['isoAlpha3'] as String?,
        nameKo: json['nameKo'] as String,
        nameEn: json['nameEn'] as String?,
        continent: json['continent'] as String?,
        tier: json['tier'] as String?,
        plugTypes: json['plugTypes'] as String?,
        voltageV: json['voltageV'] as int?,
        frequencyHz: json['frequencyHz'] as int?,
        currencyCode: json['currencyCode'] as String?,
        cardAcceptance: json['cardAcceptance'] as String? ?? '',
        powerBankWhLimit: json['powerBankWhLimit'] as int?,
      );

  /// 기기 캐시에 저장할 때 쓴다. [CountryDetail.fromJson]으로 그대로 되읽힌다.
  Map<String, dynamic> toJson() => {
        'isoAlpha2': isoAlpha2,
        'isoAlpha3': isoAlpha3,
        'nameKo': nameKo,
        'nameEn': nameEn,
        'continent': continent,
        'tier': tier,
        'plugTypes': plugTypes,
        'voltageV': voltageV,
        'frequencyHz': frequencyHz,
        'currencyCode': currencyCode,
        'cardAcceptance': cardAcceptance,
        'powerBankWhLimit': powerBankWhLimit,
      };
}

/// 서버 국가 상세 조회(`GET /api/countries/{iso2}`)를 소비한다.
class CountryDetailApi {
  CountryDetailApi(this._dio);

  final Dio _dio;

  Future<CountryDetail> fetchDetail(String isoAlpha2) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/api/countries/$isoAlpha2');
    return CountryDetail.fromJson(response.data!);
  }
}

final countryDetailApiProvider = Provider<CountryDetailApi>((ref) {
  return CountryDetailApi(ref.watch(apiClientProvider));
});

/// iso2 코드 하나를 받아서 그 나라의 상세 정보(+결제 등급)를 가져오는 provider.
///
/// 받은 정보는 기기에 저장해 두고, 서버 조회가 실패하면(해외에서 데이터가 끊긴 경우 등) 저장해 둔
/// 것을 쓴다 — 준비물 탭의 지갑 카드와 지갑 화면이 통화 정보를 여기서 얻기 때문에, 이게 없으면
/// 오프라인에서 지갑에 들어갈 수 없다(여행계획 중심 설계 §4.2). 저장된 것도 없으면 오류를 그대로
/// 내고, 자동 재시도는 끈다(오류 안내가 수십 초 늦어지지 않게).
final countryDetailProvider = FutureProvider.family<CountryDetail, String>(
  (ref, isoAlpha2) async {
    final prefs = ref.watch(sharedPreferencesProvider);
    final key = 'country_detail.v1.$isoAlpha2';
    try {
      final detail = await ref.watch(countryDetailApiProvider).fetchDetail(isoAlpha2);
      await prefs.setString(key, jsonEncode(detail.toJson()));
      return detail;
    } catch (_) {
      final raw = prefs.getString(key);
      if (raw == null) rethrow;
      return CountryDetail.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
  },
  retry: (_, _) => null,
);
