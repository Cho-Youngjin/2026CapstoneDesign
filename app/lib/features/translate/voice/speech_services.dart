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

  /// 진행 중인 턴. onResult 말고 onStatus/onError로도 끝날 수 있어 여기서 공유한다.
  Completer<String?>? _turn;

  // 상태·오류 콜백은 initialize() 시점에만 등록할 수 있다. 이 둘을 달지 않으면
  // 사용자가 아무 말도 하지 않았을 때 final 결과가 오지 않아 턴이 영원히 끝나지 않는다.
  @override
  Future<bool> initialize() => _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') _finish(null);
        },
        onError: (_) => _finish(null),
      );

  /// 먼저 도착한 신호 하나만 턴을 끝낸다(결과·상태·오류·타임아웃이 경쟁한다).
  void _finish(String? recognized) {
    final turn = _turn;
    if (turn == null || turn.isCompleted) return;
    _turn = null;
    turn.complete(recognized);
  }

  @override
  Future<String?> listenOnce({required String localeId}) {
    final completer = Completer<String?>();
    _turn = completer;
    _speech.listen(
      // 말이 끊긴 뒤 3초, 전체 최대 30초. 플러그인이 아무 신호도 주지 않는
      // 경우까지 막으려고 아래 타임아웃을 한 겹 더 둔다.
      listenOptions: stt.SpeechListenOptions(
        localeId: localeId,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 30),
      ),
      onResult: (result) {
        if (result.finalResult) {
          _finish(result.recognizedWords.isEmpty ? null : result.recognizedWords);
        }
      },
    );
    return completer.future.timeout(
      const Duration(seconds: 35),
      onTimeout: () {
        _speech.stop();
        _turn = null;
        return null;
      },
    );
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
    required this.speech,
    required this.tts,
    required this.api,
  });

  final SpeechRecognitionService speech;
  final TextToSpeechService tts;
  final TranslateApi api;

  /// initialize()는 기기 권한·인식 엔진을 한 번 확인하는 작업이라 턴마다 반복하지 않는다.
  Future<bool>? _initialization;

  Future<VoiceTurnResult?> runTurn({
    required String sourceLocaleId,
    required String targetLanguageCode,
    required String targetLocaleId,
  }) async {
    // speech_to_text는 initialize()가 성공하기 전에는 listen()을 받지 않는다.
    // 실패하면(권한 거부, 인식 서비스 없음) 듣기를 시도하지 않고 끝낸다.
    final ready = await (_initialization ??= speech.initialize());
    if (!ready) {
      _initialization = null;
      return null;
    }

    final recognized = await speech.listenOnce(localeId: sourceLocaleId);
    if (recognized == null || recognized.trim().isEmpty) {
      return null;
    }

    final translation = await api.translate(
      text: recognized,
      targetLanguage: targetLanguageCode,
    );

    await tts.speak(translation.translatedText, localeId: targetLocaleId);

    return VoiceTurnResult(
      recognizedText: recognized,
      translatedText: translation.translatedText,
    );
  }
}