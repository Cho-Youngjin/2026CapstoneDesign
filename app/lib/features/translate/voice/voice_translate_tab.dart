import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/network/translate_api.dart';
import '../language/target_language.dart';
import 'speech_services.dart';

final _speechServiceProvider =
Provider<SpeechRecognitionService>((ref) => DeviceSpeechRecognitionService());
final _ttsServiceProvider = Provider<TextToSpeechService>((ref) => DeviceTextToSpeechService());

final _voiceOrchestratorProvider = Provider<VoiceTurnOrchestrator>((ref) {
  return VoiceTurnOrchestrator(
    speech: ref.watch(_speechServiceProvider),
    tts: ref.watch(_ttsServiceProvider),
    api: ref.watch(translateApiProvider),
  );
});

/// BCP-47 언어 코드 → 음성 엔진용 로케일 ID. speech_to_text/flutter_tts는
/// `ko`가 아니라 `ko-KR` 형태의 로케일을 요구한다.
const Map<String, String> _localeIdByLanguageCode = {
  'ko': 'ko-KR', 'en': 'en-US', 'ja': 'ja-JP', 'vi': 'vi-VN', 'th': 'th-TH',
  'zh-CN': 'zh-CN', 'zh-TW': 'zh-TW', 'fr': 'fr-FR', 'it': 'it-IT', 'es': 'es-ES',
  'de': 'de-DE', 'tr': 'tr-TR', 'cs': 'cs-CZ', 'id': 'id-ID',
};

enum _Speaker { me, counterpart }

class _ConversationEntry {
  const _ConversationEntry({required this.speaker, required this.original, required this.translated});

  final _Speaker speaker;
  final String original;
  final String translated;
}

class VoiceTranslateTab extends ConsumerStatefulWidget {
  const VoiceTranslateTab({super.key});

  @override
  ConsumerState<VoiceTranslateTab> createState() => _VoiceTranslateTabState();
}

class _VoiceTranslateTabState extends ConsumerState<VoiceTranslateTab> {
  final _history = <_ConversationEntry>[];
  bool _listening = false;
  String? _error;

  Future<void> _runTurn(_Speaker speaker) async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      setState(() => _error = '마이크 권한이 필요합니다.');
      return;
    }

    final target = ref.read(targetLanguageProvider);
    final koreanLocale = _localeIdByLanguageCode['ko']!;
    final targetLocale = _localeIdByLanguageCode[target.code] ?? 'en-US';

    setState(() {
      _listening = true;
      _error = null;
    });

    try {
      final orchestrator = ref.read(_voiceOrchestratorProvider);
      final result = await orchestrator.runTurn(
        sourceLocaleId: speaker == _Speaker.me ? koreanLocale : targetLocale,
        targetLanguageCode: speaker == _Speaker.me ? target.code : 'ko',
        targetLocaleId: speaker == _Speaker.me ? targetLocale : koreanLocale,
      );
      if (result != null) {
        setState(() {
          _history.add(_ConversationEntry(
            speaker: speaker,
            original: result.recognizedText,
            translated: result.translatedText,
          ));
        });
      }
    } catch (e) {
      setState(() => _error = '음성 번역에 실패했습니다: $e');
    } finally {
      setState(() => _listening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _history.length,
              itemBuilder: (context, i) {
                final entry = _history[i];
                final isMe = entry.speaker == _Speaker.me;
                return Align(
                  alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
                  child: Card(
                    color: isMe ? null : Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.original, style: const TextStyle(fontSize: 14)),
                          Text(entry.translated,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _listening ? null : () => _runTurn(_Speaker.me),
                  icon: const Icon(Icons.mic),
                  label: const Text('내 차례 (한국어)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _listening ? null : () => _runTurn(_Speaker.counterpart),
                  icon: const Icon(Icons.mic),
                  label: const Text('상대 차례'),
                ),
              ),
            ],
          ),
          if (_listening)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}