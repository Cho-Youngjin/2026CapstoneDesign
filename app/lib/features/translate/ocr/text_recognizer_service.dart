import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../core/network/translate_api.dart';

abstract class TextRecognizerService {
  Future<String> recognizeText(String imagePath, {required String languageCode});
}

/// 촬영한 글자가 어느 문자 체계인지에 따라 ML Kit 모델이 달라진다.
/// 라틴 모델로는 일본어·중국어·한글을 아예 읽지 못해 빈 문자열이 나온다.
TextRecognitionScript scriptForLanguage(String languageCode) {
  final code = languageCode.toLowerCase();
  if (code == 'ja') return TextRecognitionScript.japanese;
  if (code == 'ko') return TextRecognitionScript.korean;
  if (code.startsWith('zh')) return TextRecognitionScript.chinese;
  return TextRecognitionScript.latin;
}

/// google_mlkit_text_recognition은 온디바이스로 동작하며 추가 과금이 없다 (스펙 §4, §6-⑤).
///
/// 스크립트별로 모델이 따로라 TextRecognizer도 스크립트당 하나씩 만들어 재사용한다.
/// 라틴 외 모델은 플러그인이 compileOnly로만 선언하므로
/// `android/app/build.gradle.kts`에서 implementation으로 추가해야 APK에 포함된다.
class MlkitTextRecognizerService implements TextRecognizerService {
  final _recognizers = <TextRecognitionScript, TextRecognizer>{};

  @override
  Future<String> recognizeText(String imagePath, {required String languageCode}) async {
    final script = scriptForLanguage(languageCode);
    final recognizer =
        _recognizers.putIfAbsent(script, () => TextRecognizer(script: script));
    final inputImage = InputImage.fromFilePath(imagePath);
    final result = await recognizer.processImage(inputImage);
    return result.text;
  }

  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.close();
    }
    _recognizers.clear();
  }
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
    required this.recognizer,
    required this.api,
    required this.sourceLanguageCode,
  });

  /// 메뉴판·간판은 현지어로 적혀 있고, 사용자는 그것을 한국어로 읽고 싶다.
  /// 다른 번역 모드(한국어 → 현지어)와 방향이 반대다.
  static const _readerLanguage = 'ko';

  final TextRecognizerService recognizer;
  final TranslateApi api;
  final String Function() sourceLanguageCode;

  Future<OcrOutcome> process(String imagePath) async {
    final sourceLanguage = sourceLanguageCode();
    final recognizedText = (await recognizer.recognizeText(
      imagePath,
      languageCode: sourceLanguage,
    ))
        .trim();
    if (recognizedText.isEmpty) {
      throw NoTextRecognizedException();
    }
    final translation = await api.translate(
      text: recognizedText,
      targetLanguage: _readerLanguage,
      sourceLanguage: sourceLanguage,
    );
    return OcrOutcome(recognizedText: recognizedText, translation: translation);
  }
}