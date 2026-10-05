import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
final countryDetailProvider =
    FutureProvider.family<CountryDetail, String>((ref, isoAlpha2) async {
  final api = ref.watch(countryDetailApiProvider);
  return api.fetchDetail(isoAlpha2);
});
