import 'dart:math' as math;

import 'package:intl/intl.dart';

/// 통화 하나의 표시·계산 규칙.
///
/// 지갑의 금액은 앱 전체에서 "최소단위 정수"(엔은 1엔, 달러는 1센트)로 다루고,
/// 화면에 보일 때만 이 정보로 바꾼다 — 실수(double)로 더하면 0.1 + 0.2 같은 오차가 쌓이기 때문이다.
class CurrencyInfo {
  const CurrencyInfo({
    required this.code,
    required this.minorDigits,
    required this.symbol,
    required this.nameKo,
    required this.unitKo,
  });

  final String code;

  /// 소수 자릿수. 엔·동·루피아는 0, 달러·유로 등은 2.
  final int minorDigits;
  final String symbol;

  /// 알림 문구 등에 쓰는 통화 이름(예: "엔화", "미국 달러").
  final String nameKo;

  /// "100엔", "1달러"처럼 수량 뒤에 붙는 단위.
  final String unitKo;

  int get _scale => math.pow(10, minorDigits).toInt();

  /// "1,200" / "12.5" 같은 입력을 최소단위 정수로 바꾼다.
  /// 형식이 틀리거나, 소수 자릿수가 이 통화보다 많거나, 0 이하면 null.
  int? parseToMinor(String input) {
    final text = input.replaceAll(',', '').trim();
    final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(text);
    if (match == null) return null;
    final whole = int.parse(match.group(1)!);
    final fraction = match.group(2) ?? '';
    if (fraction.length > minorDigits) return null;
    final fractionMinor =
        fraction.isEmpty ? 0 : int.parse(fraction.padRight(minorDigits, '0'));
    final minor = whole * _scale + fractionMinor;
    return minor > 0 ? minor : null;
  }

  double toMajor(int minor) => minor / _scale;

  /// 편집 폼에 다시 채울 문자열(콤마 없음). 예: 1250센트 → "12.50", 1200엔 → "1200".
  String toInputText(int minor) => toMajor(minor).toStringAsFixed(minorDigits);

  /// "¥1,200", "$12.50", "-₫50,000"
  String format(int minor) {
    final pattern = minorDigits == 0 ? '#,##0' : '#,##0.${'0' * minorDigits}';
    final text = NumberFormat(pattern, 'en_US').format(toMajor(minor.abs()));
    return '${minor < 0 ? '-' : ''}$symbol$text';
  }

  /// 원화 환산(반올림한 정수 원). [krwPerUnit]은 1단위당 원화.
  int toKrw(int minor, double krwPerUnit) => (toMajor(minor) * krwPerUnit).round();

  /// 환율을 보여줄 단위 수량: 1, 100, 1000 중 "단위 × 1단위 환율 ≥ 10원"인 가장 작은 값.
  /// 예: USD → 1, JPY(약 8.47원) → 100, VND(약 0.052원) → 1000.
  int displayUnit(double krwPerUnit) {
    for (final unit in const [1, 100]) {
      if (unit * krwPerUnit >= 10) return unit;
    }
    return 1000;
  }

  /// "100엔", "1달러", "1,000동"
  String unitLabel(int unit) => '${NumberFormat('#,##0', 'en_US').format(unit)}$unitKo';
}

/// 원화 금액 표기: 10170 → "10,170원", -500 → "-500원"
String formatKrw(int won) => '${NumberFormat('#,##0', 'en_US').format(won)}원';

/// 환율 값 표기(소수 둘째 자리): 847.46 → "847.46원", 1339.2 → "1,339.20원"
String formatKrwRate(double won) => '${NumberFormat('#,##0.00', 'en_US').format(won)}원';

/// 우리 country 테이블에 있는 통화 17개. 소수 자릿수는 ISO 4217을 따르되, 실제로 소수 단위를
/// 쓰지 않는 엔·동·루피아는 0으로 둔다(지갑·환율 알림 설계 §5.4).
const _currencies = <String, CurrencyInfo>{
  'AUD': CurrencyInfo(code: 'AUD', minorDigits: 2, symbol: r'A$', nameKo: '호주 달러', unitKo: '호주달러'),
  'CAD': CurrencyInfo(code: 'CAD', minorDigits: 2, symbol: r'C$', nameKo: '캐나다 달러', unitKo: '캐나다달러'),
  'CHF': CurrencyInfo(code: 'CHF', minorDigits: 2, symbol: 'CHF ', nameKo: '스위스 프랑', unitKo: '프랑'),
  'CNY': CurrencyInfo(code: 'CNY', minorDigits: 2, symbol: 'CN¥', nameKo: '위안화', unitKo: '위안'),
  'CZK': CurrencyInfo(code: 'CZK', minorDigits: 2, symbol: 'Kč ', nameKo: '체코 코루나', unitKo: '코루나'),
  'EUR': CurrencyInfo(code: 'EUR', minorDigits: 2, symbol: '€', nameKo: '유로', unitKo: '유로'),
  'GBP': CurrencyInfo(code: 'GBP', minorDigits: 2, symbol: '£', nameKo: '영국 파운드', unitKo: '파운드'),
  'HKD': CurrencyInfo(code: 'HKD', minorDigits: 2, symbol: r'HK$', nameKo: '홍콩 달러', unitKo: '홍콩달러'),
  'IDR': CurrencyInfo(code: 'IDR', minorDigits: 0, symbol: 'Rp ', nameKo: '인도네시아 루피아', unitKo: '루피아'),
  'JPY': CurrencyInfo(code: 'JPY', minorDigits: 0, symbol: '¥', nameKo: '엔화', unitKo: '엔'),
  'PHP': CurrencyInfo(code: 'PHP', minorDigits: 2, symbol: '₱', nameKo: '필리핀 페소', unitKo: '페소'),
  'SGD': CurrencyInfo(code: 'SGD', minorDigits: 2, symbol: r'S$', nameKo: '싱가포르 달러', unitKo: '싱가포르달러'),
  'THB': CurrencyInfo(code: 'THB', minorDigits: 2, symbol: '฿', nameKo: '태국 바트', unitKo: '바트'),
  'TRY': CurrencyInfo(code: 'TRY', minorDigits: 2, symbol: '₺', nameKo: '튀르키예 리라', unitKo: '리라'),
  'TWD': CurrencyInfo(code: 'TWD', minorDigits: 2, symbol: r'NT$', nameKo: '대만 달러', unitKo: '대만달러'),
  'USD': CurrencyInfo(code: 'USD', minorDigits: 2, symbol: r'$', nameKo: '미국 달러', unitKo: '달러'),
  'VND': CurrencyInfo(code: 'VND', minorDigits: 0, symbol: '₫', nameKo: '베트남 동', unitKo: '동'),
};

/// 통화 코드로 표시 규칙을 찾는다. 표에 없는 통화는 코드를 기호로 쓰고 소수 2자리로 다룬다.
CurrencyInfo currencyInfoOf(String code) {
  final upper = code.trim().toUpperCase();
  return _currencies[upper] ??
      CurrencyInfo(code: upper, minorDigits: 2, symbol: '$upper ', nameKo: upper, unitKo: ' $upper');
}
