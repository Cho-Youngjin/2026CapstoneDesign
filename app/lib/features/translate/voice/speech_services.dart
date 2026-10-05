import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../core/network/translate_api.dart';

abstract class SpeechRecognitionService {
  Future<bool> initialize();

  /// 한 번 듣고 인식된 문장을 반환한다. 아무 말도 인식하지 못하면 null.
  Future<String?> listenOnce({required String localeId});
}

abstract class TextToSpeechService {
  Future<void> speak(String text, {required String localeId});
}

/// speech_to_text는 온디바이스로 동작하며 추가 과금이 없다 (스펙 §4, §6-⑤).
class DeviceSpeechRecognitionService implements SpeechRecognitionService {
  final _speech = stt.SpeechToText();

  @override
  Future<bool> initialize() => _speech.initialize();

  @override
  Future<String?> listenOnce({required String localeId}) {
    final completer = Completer<String?>();
    _speech.listen(
      localeId: localeId,
      onResult: (result) {
        if (result.finalResult) {
          completer.complete(
            result.recognizedWords.isEmpty ? null : result.recognizedWords,
          );
        }
      },
    );
    return completer.future;
  }
}

/// flutter_tts도 온디바이스로 동작하며 추가 과금이 없다.
class DeviceTextToSpeechService implements TextToSpeechService {
  final _tts = FlutterTts();

  @override
  Future<void> speak(String text, {required String localeId}) async {
    await _tts.setLanguage(localeId);
    await _tts.speak(text);
  }
}

class VoiceTurnResult {
  const VoiceTurnResult({required this.recognizedText, required this.translatedText});

  final String recognizedText;
  final String translatedText;
}

/// 한 사람의 발화 하나를 "듣기 → 번역 → 상대 언어로 읽어주기"로 완결한다.
/// 양방향 대화 모드는 이 클래스를 방향만 바꿔 두 번 호출하는 방식으로 구현된다.
class VoiceTurnOrchestrator {
  VoiceTurnOrchestrator({
    required SpeechRecognitionService speech,
    required TextToSpeechService tts,
    required TranslateApi api,
  })  : _speech = speech,
        _tts = tts,
        _api = api;

  final SpeechRecognitionService _speech;
  final TextToSpeechService _tts;
  final TranslateApi _api;

  Future<VoiceTurnResult?> runTurn({
    required String sourceLocaleId,
    required String targetLanguageCode,
    required String targetLocaleId,
  }) async {
    final recognized = await _speech.listenOnce(localeId: sourceLocaleId);
    if (recognized == null || recognized.trim().isEmpty) {
      return null;
    }

    final translation = await _api.translate(
      text: recognized,
      targetLanguage: targetLanguageCode,
    );

    await _tts.speak(translation.translatedText, localeId: targetLocaleId);

    return VoiceTurnResult(
      recognizedText: recognized,
      translatedText: translation.translatedText,
    );
  }
}