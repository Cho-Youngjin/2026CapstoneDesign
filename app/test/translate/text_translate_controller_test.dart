import 'package:app/core/network/translate_api.dart';
import 'package:app/features/translate/text/text_translate_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTranslateApi implements TranslateApi {
  _FakeTranslateApi({this.result, this.error});

  final TranslationResult? result;
  final Object? error;
  String? lastText;
  String? lastTargetLanguage;

  @override
  Future<TranslationResult> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    lastText = text;
    lastTargetLanguage = targetLanguage;
    if (error != null) throw error!;
    return result!;
  }
}

void main() {
  group('TextTranslateController', () {
    test('초기 상태는 Idle이다', () {
      final controller = TextTranslateController(
        api: _FakeTranslateApi(result: const TranslationResult(translatedText: '')),
        targetLanguageCode: () => 'en',
      );
      expect(controller.state, isA<TextTranslateIdle>());
    });

    test('성공하면 Success 상태로 번역 결과를 담는다', () async {
      final fakeApi = _FakeTranslateApi(
        result: const TranslationResult(translatedText: 'Hello'),
      );
      final controller = TextTranslateController(
        api: fakeApi,
        targetLanguageCode: () => 'en',
      );

      await controller.translate('안녕하세요');

      final state = controller.state;
      expect(state, isA<TextTranslateSuccess>());
      state as TextTranslateSuccess;
      expect(state.result.translatedText, 'Hello');
      expect(state.sourceText, '안녕하세요');
      expect(fakeApi.lastText, '안녕하세요');
      expect(fakeApi.lastTargetLanguage, 'en');
    });

    test('빈 문자열이면 API를 호출하지 않고 Idle을 유지한다', () async {
      final fakeApi = _FakeTranslateApi(
        result: const TranslationResult(translatedText: 'unused'),
      );
      final controller = TextTranslateController(
        api: fakeApi,
        targetLanguageCode: () => 'en',
      );

      await controller.translate('   ');

      expect(controller.state, isA<TextTranslateIdle>());
      expect(fakeApi.lastText, isNull);
    });

    test('실패하면 Failure 상태가 된다', () async {
      final fakeApi = _FakeTranslateApi(error: Exception('network down'));
      final controller = TextTranslateController(
        api: fakeApi,
        targetLanguageCode: () => 'en',
      );

      await controller.translate('안녕');

      expect(controller.state, isA<TextTranslateFailure>());
    });

    test('호출 중에는 Loading 상태를 거친다', () async {
      final fakeApi = _FakeTranslateApi(
        result: const TranslationResult(translatedText: 'Hi'),
      );
      final controller = TextTranslateController(
        api: fakeApi,
        targetLanguageCode: () => 'en',
      );

      final future = controller.translate('안녕');
      expect(controller.state, isA<TextTranslateLoading>());
      await future;
      expect(controller.state, isA<TextTranslateSuccess>());
    });
  });
}