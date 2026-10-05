import 'package:app/features/translate/language/target_language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kSupportedLanguages', () {
    test('지원 언어는 14개다', () {
      expect(kSupportedLanguages.length, 14);
    });
  });

  group('languageCodeForCountry', () {
    test('JP -> ja', () {
      expect(languageCodeForCountry('JP'), 'ja');
    });

    test('소문자로 입력해도 매핑된다', () {
      expect(languageCodeForCountry('jp'), 'ja');
    });

    test('매핑에 없는 나라면 null', () {
      expect(languageCodeForCountry('ZZ'), isNull);
    });
  });

  group('TargetLanguageNotifier', () {
    test('초기값은 영어(en)다', () {
      final notifier = TargetLanguageNotifier();
      expect(notifier.state.code, 'en');
    });

    test('setFromCountry로 나라를 지정하면 그 나라 언어로 바뀐다', () {
      final notifier = TargetLanguageNotifier();
      notifier.setFromCountry('JP');
      expect(notifier.state.code, 'ja');
    });

    test('매핑에 없는 나라를 넣으면 기존 값을 유지한다', () {
      final notifier = TargetLanguageNotifier();
      notifier.setFromCountry('JP');
      notifier.setFromCountry('ZZ');
      expect(notifier.state.code, 'ja');
    });

    test('setManually로 지원 언어를 직접 고를 수 있다', () {
      final notifier = TargetLanguageNotifier();
      final fr = kSupportedLanguages.firstWhere((o) => o.code == 'fr');
      notifier.setManually(fr);
      expect(notifier.state.code, 'fr');
    });

    test('setManually에 지원하지 않는 언어를 넣으면 예외가 발생한다', () {
      final notifier = TargetLanguageNotifier();
      expect(
            () => notifier.setManually(const LanguageOption('xx', '없는언어')),
        throwsArgumentError,
      );
    });
  });
}