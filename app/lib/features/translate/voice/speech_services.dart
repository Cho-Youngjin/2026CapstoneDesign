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

/// 한 번의 듣기(턴)가 언제·무엇으로 끝나는지를 정하는 순수 로직. speech_to_text의 콜백 순서에
/// 의존하는 부분이라 플러그인에서 분리해 단위 테스트한다.
///
/// 실기기(SM-S911N)에서 콜백은 "부분 결과 → notListening/done 상태 → (약 2초 뒤) 최종 결과" 순서로
/// 왔다. 상태 신호는 "마이크가 멈췄다"일 뿐 "결과가 없다"가 아니므로, 그 신호로 턴을 null로
/// 끝내면 뒤늦게 오는 최종 결과를 버리게 된다. 그래서 notListening/done이 오면 곧바로 끝내지 않고
/// [graceAfterStop]만큼 최종 결과를 기다린다. 끝내 안 오면 마지막 부분 결과를 쓴다.
class SpeechTurn {
  SpeechTurn({this.graceAfterStop = const Duration(seconds: 4)});

  final Duration graceAfterStop;
  final _completer = Completer<String?>();
  String _lastWords = '';
  Timer? _graceTimer;

  Future<String?> get result => _completer.future;

  void onResult(String words, {required bool isFinal}) {
    if (words.isNotEmpty) _lastWords = words;
    if (isFinal) _finish(words.isEmpty ? null : words);
  }

  void onStatus(String status) {
    // 플러그인이 "한 번도 결과를 보내지 못했다"고 확정한 경우(아무 말도 안 한 침묵)만 즉시 끝낸다.
    if (status == 'doneNoResult') {
      _finish(null);
      return;
    }
    if (status == 'done' || status == 'notListening') {
      _graceTimer ??= Timer(graceAfterStop, () => _finish(_lastWords.isEmpty ? null : _lastWords));
    }
  }

  void onError() => _finish(null);

  /// 외부(전체 타임아웃)에서 턴을 강제로 끝낼 때 쓴다.
  void cancel() => _finish(null);

  /// 먼저 도착한 신호 하나만 턴을 끝낸다(결과·상태·오류·타임아웃이 경쟁한다).
  void _finish(String? recognized) {
    if (_completer.isCompleted) return;
    _graceTimer?.cancel();
    _completer.complete(recognized);
  }
}

/// speech_to_text는 온디바이스로 동작하며 추가 과금이 없다 (스펙 §4, §6-⑤).
class DeviceSpeechRecognitionService implements SpeechRecognitionService {
  final _speech = stt.SpeechToText();

  /// 진행 중인 턴. 플러그인 콜백(상태·오류)은 initialize() 시점에 한 번만 등록되므로 여기서 공유한다.
  SpeechTurn? _turn;

  // 상태·오류 콜백은 initialize() 시점에만 등록할 수 있다. 이 둘을 달지 않으면
  // 사용자가 아무 말도 하지 않았을 때 final 결과가 오지 않아 턴이 영원히 끝나지 않는다.
  @override
  Future<bool> initialize() => _speech.initialize(
        onStatus: (status) => _turn?.onStatus(status),
        onError: (_) => _turn?.onError(),
      );

  @override
  Future<String?> listenOnce({required String localeId}) {
    final turn = SpeechTurn();
    _turn = turn;
    _speech.listen(
      // 말이 끊긴 뒤 3초, 전체 최대 30초. 플러그인이 아무 신호도 주지 않는
      // 경우까지 막으려고 아래 타임아웃을 한 겹 더 둔다.
      listenOptions: stt.SpeechListenOptions(
        localeId: localeId,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 30),
      ),
      onResult: (result) => turn.onResult(result.recognizedWords, isFinal: result.finalResult),
    );
    return turn.result.timeout(
      const Duration(seconds: 35),
      onTimeout: () {
        _speech.stop();
        turn.cancel();
        return null;
      },
    ).whenComplete(() {
      if (identical(_turn, turn)) _turn = null;
    });
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