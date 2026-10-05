import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../core/network/translate_api.dart';

abstract class TextRecognizerService {
  Future<String> recognizeText(String imagePath);
}

/// google_mlkit_text_recognition은 온디바이스로 동작하며 추가 과금이 없다 (스펙 §4, §6-⑤).
class MlkitTextRecognizerService implements TextRecognizerService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<String> recognizeText(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(inputImage);
    return result.text;
  }

  void dispose() => _recognizer.close();
}

class NoTextRecognizedException implements Exception {
  @override
  String toString() => '사진에서 텍스트를 찾지 못했습니다';
}

class OcrOutcome {
  const OcrOutcome({required this.recognizedText, required this.translation});

  final String recognizedText;
  final TranslationResult translation;
}

/// "사진 경로 → 인식 → 번역"을 순서대로 수행한다. 화면은 이 클래스만 알면 되고,
/// ML Kit·dio를 직접 다루지 않는다.
class OcrTranslateOrchestrator {
  OcrTranslateOrchestrator({
    required TextRecognizerService recognizer,
    required TranslateApi api,
    required String Function() targetLanguageCode,
  })  : _recognizer = recognizer,
        _api = api,
        _targetLanguageCode = targetLanguageCode;

  final TextRecognizerService _recognizer;
  final TranslateApi _api;
  final String Function() _targetLanguageCode;

  Future<OcrOutcome> process(String imagePath) async {
    final recognizedText = (await _recognizer.recognizeText(imagePath)).trim();
    if (recognizedText.isEmpty) {
      throw NoTextRecognizedException();
    }
    final translation = await _api.translate(
      text: recognizedText,
      targetLanguage: _targetLanguageCode(),
    );
    return OcrOutcome(recognizedText: recognizedText, translation: translation);
  }
}