import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// 번역 대상 언어 하나(코드 + 화면에 보여줄 한글 이름).
class LanguageOption {
  const LanguageOption(this.code, this.labelKo);

  final String code;
  final String labelKo;
}

/// 사용자가 직접 고를 수 있는 번역 대상 언어 14개.
const kSupportedLanguages = <LanguageOption>[
  LanguageOption('en', '영어'),
  LanguageOption('ja', '일본어'),
  LanguageOption('zh', '중국어(간체)'),
  LanguageOption('zh-TW', '중국어(번체)'),
  LanguageOption('vi', '베트남어'),
  LanguageOption('th', '태국어'),
  LanguageOption('tl', '필리핀어(타갈로그)'),
  LanguageOption('fr', '프랑스어'),
  LanguageOption('it', '이탈리아어'),
  LanguageOption('es', '스페인어'),
  LanguageOption('de', '독일어'),
  LanguageOption('tr', '튀르키예어'),
  LanguageOption('cs', '체코어'),
  LanguageOption('id', '인도네시아어'),
];

/// Tier A 20개국(iso_alpha2) -> 그 나라에서 주로 쓰는 언어 코드.
const Map<String, String> _countryToLanguage = {
  'JP': 'ja',
  'VN': 'vi',
  'TH': 'th',
  'US': 'en',
  'PH': 'tl',
  'CN': 'zh',
  'TW': 'zh-TW',
  'SG': 'en',
  'HK': 'zh-TW',
  'FR': 'fr',
  'IT': 'it',
  'ES': 'es',
  'DE': 'de',
  'GB': 'en',
  'AU': 'en',
  'TR': 'tr',
  'CH': 'de',
  'CZ': 'cs',
  'ID': 'id',
  'CA': 'en',
};

/// 국가 코드(iso_alpha2)로 그 나라의 언어 코드를 찾는다.
String? languageCodeForCountry(String isoAlpha2) {
  return _countryToLanguage[isoAlpha2.toUpperCase()];
}

LanguageOption _findByCode(String code) {
  return kSupportedLanguages.firstWhere((o) => o.code == code);
}

/// 현재 선택된 번역 대상 언어(LanguageOption 전체)를 들고 있는 상태 관리자.
class TargetLanguageNotifier extends StateNotifier<LanguageOption> {
  TargetLanguageNotifier() : super(_findByCode('en'));

  void setFromCountry(String isoAlpha2) {
    final code = languageCodeForCountry(isoAlpha2);
    if (code == null) return;
    final matches = kSupportedLanguages.where((o) => o.code == code);
    if (matches.isNotEmpty) {
      state = matches.first;
    }
  }

  void setManually(LanguageOption option) {
    final isSupported = kSupportedLanguages.any((o) => o.code == option.code);
    if (!isSupported) {
      throw ArgumentError('지원하지 않는 언어: ${option.code}');
    }
    state = option;
  }
}

final targetLanguageProvider =
StateNotifierProvider<TargetLanguageNotifier, LanguageOption>((ref) {
  return TargetLanguageNotifier();
});