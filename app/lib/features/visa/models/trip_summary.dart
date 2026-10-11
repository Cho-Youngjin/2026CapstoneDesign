import 'package:intl/intl.dart';

import 'trip.dart';

final _wireDate = DateFormat('yyyy-MM-dd');
final _shortDate = DateFormat('M/d');

/// 여행 목록(`GET /api/trips`)의 한 줄. 서버 `trip/TripSummaryResponse.java`와 필드명이 같다.
class TripSummary {
  const TripSummary({
    required this.id,
    required this.countryIso2,
    required this.countryNameKo,
    required this.departDate,
    required this.returnDate,
    required this.verdict,
  });

  final int id;
  final String countryIso2;
  final String countryNameKo;
  final DateTime departDate;
  final DateTime returnDate;
  final VisaVerdict verdict;

  /// 목록 카드·준비물 탭 상단에 쓰는 `12/20~1/9` 형식.
  String get dateRangeLabel =>
      '${_shortDate.format(departDate)}~${_shortDate.format(returnDate)}';

  factory TripSummary.fromJson(Map<String, dynamic> json) => TripSummary(
        id: json['id'] as int,
        countryIso2: json['countryIso2'] as String,
        countryNameKo: json['countryNameKo'] as String,
        departDate: DateTime.parse(json['departDate'] as String),
        returnDate: DateTime.parse(json['returnDate'] as String),
        verdict: VisaVerdict.fromWire(json['verdict'] as String),
      );

  /// 목록 캐시(SharedPreferences)에 저장할 때 쓴다. [TripSummary.fromJson]으로 그대로 되읽힌다.
  Map<String, dynamic> toJson() => {
        'id': id,
        'countryIso2': countryIso2,
        'countryNameKo': countryNameKo,
        'departDate': _wireDate.format(departDate),
        'returnDate': _wireDate.format(returnDate),
        'verdict': verdict.wireValue,
      };
}
