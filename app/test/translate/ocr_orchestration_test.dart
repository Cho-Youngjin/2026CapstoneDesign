import 'package:app/core/network/translate_api.dart';
import 'package:app/features/translate/ocr/text_recognizer_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTextRecognizerService implements TextRecognizerService {
  _FakeTextRecognizerService(this.textToReturn);

  final String textToReturn;

  @override
  Future<String> recognizeText(String imagePath) async => textToReturn;
}

class _FakeTranslateApi implements TranslateApi {
  _FakeTranslateApi(this.result);

  final TranslationResult result;
  String? lastText;

  @override
  Future<TranslationResult> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    lastText = text;
    return result;
  }
}

void main() {
  group('OcrTranslateOrchestrator', () {
    test('인식된 텍스트를 그대로 번역 API에 넘긴다', () async {
      final recognizer = _FakeTextRecognizerService('Menu: Pho 50000');
      final api = _FakeTranslateApi(const TranslationResult(translatedText: '메뉴: 쌀국수 50000'));
      final orchestrator = OcrTranslateOrchestrator(
        recognizer: recognizer,
        api: api,
        targetLanguageCode: () => 'ko',
      );

      final outcome = await orchestrator.process('/tmp/photo.jpg');

      expect(outcome.recognizedText, 'Menu: Pho 50000');
      expect(outcome.translation.translatedText, '메뉴: 쌀국수 50000');
      expect(api.lastText, 'Menu: Pho 50000');
    });

    test('인식된 텍스트가 없으면 번역을 호출하지 않고 예외를 던진다', () async {
      final recognizer = _FakeTextRecognizerService('   ');
      final api = _FakeTranslateApi(const TranslationResult(translatedText: 'unused'));
      final orchestrator = OcrTranslateOrchestrator(
        recognizer: recognizer,
        api: api,
        targetLanguageCode: () => 'ko',
      );

      expect(
            () => orchestrator.process('/tmp/photo.jpg'),
        throwsA(isA<NoTextRecognizedException>()),
      );
      expect(api.lastText, isNull);
    });
  });
}