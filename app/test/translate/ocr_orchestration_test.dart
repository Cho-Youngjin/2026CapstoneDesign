import 'package:app/core/network/translate_api.dart';
import 'package:app/features/translate/ocr/text_recognizer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class _FakeTextRecognizerService implements TextRecognizerService {
  _FakeTextRecognizerService(this.textToReturn);

  final String textToReturn;
  String? lastLanguageCode;

  @override
  Future<String> recognizeText(String imagePath, {required String languageCode}) async {
    lastLanguageCode = languageCode;
    return textToReturn;
  }
}

class _FakeTranslateApi implements TranslateApi {
  _FakeTranslateApi(this.result);

  final TranslationResult result;
  String? lastText;
  String? lastTarget;

  @override
  Future<TranslationResult> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    lastText = text;
    lastTarget = targetLanguage;
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
        sourceLanguageCode: () => 'en',
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
        sourceLanguageCode: () => 'en',
      );

      expect(
            () => orchestrator.process('/tmp/photo.jpg'),
        throwsA(isA<NoTextRecognizedException>()),
      );
      expect(api.lastText, isNull);
    });

    test('목적국 언어로 인식하고 한국어로 번역한다', () async {
      // 해외 메뉴판은 현지어로 적혀 있고, 사용자는 그것을 한국어로 읽고 싶다.
      final recognizer = _FakeTextRecognizerService('ラーメン 800円');
      final api = _FakeTranslateApi(const TranslationResult(translatedText: '라멘 800엔'));
      final orchestrator = OcrTranslateOrchestrator(
        recognizer: recognizer,
        api: api,
        sourceLanguageCode: () => 'ja',
      );

      final outcome = await orchestrator.process('/tmp/menu.jpg');

      expect(recognizer.lastLanguageCode, 'ja');
      expect(api.lastTarget, 'ko');
      expect(outcome.translation.translatedText, '라멘 800엔');
    });
  });

  group('scriptForLanguage', () {
    test('일본어는 일본어 스크립트 모델을 쓴다', () {
      expect(scriptForLanguage('ja'), TextRecognitionScript.japanese);
    });

    test('간체·번체 모두 중국어 스크립트 모델을 쓴다', () {
      expect(scriptForLanguage('zh'), TextRecognitionScript.chinese);
      expect(scriptForLanguage('zh-TW'), TextRecognitionScript.chinese);
    });

    test('한국어는 한국어 스크립트 모델을 쓴다', () {
      expect(scriptForLanguage('ko'), TextRecognitionScript.korean);
    });

    test('라틴 문자권 언어는 라틴 모델로 떨어진다', () {
      expect(scriptForLanguage('en'), TextRecognitionScript.latin);
      expect(scriptForLanguage('vi'), TextRecognitionScript.latin);
      expect(scriptForLanguage('fr'), TextRecognitionScript.latin);
    });
  });
}