/// 서버 `GET /api/exchange-rates/{code}` 응답(지갑·환율 알림 설계 §4.5).
class ExchangeRate {
  const ExchangeRate({
    required this.currencyCode,
    required this.krwRate,
    required this.baseDate,
    this.previousKrwRate,
    this.previousBaseDate,
    this.changePercent,
    required this.source,
  });

  final String currencyCode;

  /// 통화 1단위당 원화(JPY는 1엔 기준).
  final double krwRate;

  /// 고시일(배치를 돌린 날이 아니다).
  final DateTime baseDate;
  final double? previousKrwRate;
  final DateTime? previousBaseDate;

  /// 전 영업일 대비 등락률(%). 이전값이 없으면 null.
  final double? changePercent;

  /// "EXIM"(한국수출입은행 고시환율) 또는 "ER_API"(open.er-api.com 참고환율).
  final String source;

  /// 참고환율이면 화면에 출처(Rates By Exchange Rate API)를 함께 표기해야 한다.
  bool get isReference => source == 'ER_API';

  factory ExchangeRate.fromJson(Map<String, dynamic> json) => ExchangeRate(
        currencyCode: json['currencyCode'] as String,
        krwRate: (json['krwRate'] as num).toDouble(),
        baseDate: DateTime.parse(json['baseDate'] as String),
        previousKrwRate: (json['previousKrwRate'] as num?)?.toDouble(),
        previousBaseDate: json['previousBaseDate'] == null
            ? null
            : DateTime.parse(json['previousBaseDate'] as String),
        changePercent: (json['changePercent'] as num?)?.toDouble(),
        source: json['source'] as String? ?? 'EXIM',
      );

  Map<String, dynamic> toJson() => {
        'currencyCode': currencyCode,
        'krwRate': krwRate,
        'baseDate': _isoDate(baseDate),
        'previousKrwRate': previousKrwRate,
        'previousBaseDate': previousBaseDate == null ? null : _isoDate(previousBaseDate!),
        'changePercent': changePercent,
        'source': source,
      };

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 화면이 쓰는 환율 한 벌 + 그 값을 받은 시각. 기기 캐시에도 이 모양 그대로 저장한다.
class RateSnapshot {
  const RateSnapshot({required this.rate, required this.fetchedAt});

  final ExchangeRate rate;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => {
        'rate': rate.toJson(),
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  factory RateSnapshot.fromJson(Map<String, dynamic> json) => RateSnapshot(
        rate: ExchangeRate.fromJson(json['rate'] as Map<String, dynamic>),
        fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      );
}
