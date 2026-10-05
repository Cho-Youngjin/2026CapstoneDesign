import 'package:app/core/network/translate_api.dart';
import 'package:app/features/translate/voice/speech_services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSpeechRecognitionService implements SpeechRecognitionService {
  _FakeSpeechRecognitionService(this.textToReturn);

  final String? textToReturn;
  String? lastLocaleId;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<String?> listenOnce({required String localeId}) async {
    lastLocaleId = localeId;
    return textToReturn;
  }
}

class _FakeTextToSpeechService implements TextToSpeechService {
  String? spokenText;
  String? spokenLocale;

  @override
  Future<void> speak(String text, {required String localeId}) async {
    spokenText = text;
    spokenLocale = localeId;
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
  group('VoiceTurnOrchestrator', () {
    test('인식한 말을 번역하고 대상 언어로 읽어준다', () async {
      final speech = _FakeSpeechRecognitionService('안녕하세요');
      final tts = _FakeTextToSpeechService();
      final api = _FakeTranslateApi(const TranslationResult(translatedText: 'Hello'));
      final orchestrator = VoiceTurnOrchestrator(speech: speech, tts: tts, api: api);

      final result = await orchestrator.runTurn(
        sourceLocaleId: 'ko-KR',
        targetLanguageCode: 'en',
        targetLocaleId: 'en-US',
      );

      expect(result, isNotNull);
      expect(result!.recognizedText, '안녕하세요');
      expect(result.translatedText, 'Hello');
      expect(speech.lastLocaleId, 'ko-KR');
      expect(api.lastText, '안녕하세요');
      expect(api.lastTarget, 'en');
      expect(tts.spokenText, 'Hello');
      expect(tts.spokenLocale, 'en-US');
    });

    test('아무 말도 인식하지 못하면 null을 반환하고 번역·TTS를 호출하지 않는다', () async {
      final speech = _FakeSpeechRecognitionService(null);
      final tts = _FakeTextToSpeechService();
      final api = _FakeTranslateApi(const TranslationResult(translatedText: 'unused'));
      final orchestrator = VoiceTurnOrchestrator(speech: speech, tts: tts, api: api);

      final result = await orchestrator.runTurn(
        sourceLocaleId: 'ko-KR',
        targetLanguageCode: 'en',
        targetLocaleId: 'en-US',
      );

      expect(result, isNull);
      expect(api.lastText, isNull);
      expect(tts.spokenText, isNull);
    });
  });
}