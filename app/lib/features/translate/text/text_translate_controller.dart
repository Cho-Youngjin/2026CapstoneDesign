import 'package:flutter_riverpod/legacy.dart';

import '../../../core/network/translate_api.dart';
import '../language/target_language.dart';

/// 텍스트 번역 화면이 지금 어떤 상태인지 (4가지 중 하나).
sealed class TextTranslateState {
  const TextTranslateState();
}

class TextTranslateIdle extends TextTranslateState {
  const TextTranslateIdle();
}

class TextTranslateLoading extends TextTranslateState {
  const TextTranslateLoading();
}

class TextTranslateSuccess extends TextTranslateState {
  const TextTranslateSuccess(this.sourceText, this.result);

  final String sourceText;
  final TranslationResult result;
}

class TextTranslateFailure extends TextTranslateState {
  const TextTranslateFailure(this.message);

  final String message;
}

/// "번역하기" 버튼을 눌렀을 때의 흐름을 담당한다.
class TextTranslateController extends StateNotifier<TextTranslateState> {
  TextTranslateController({
    required this.api,
    required this.targetLanguageCode,
  }) : super(const TextTranslateIdle());

  final TranslateApi api;
  final String Function() targetLanguageCode;

  Future<void> translate(String sourceText) async {
    final trimmed = sourceText.trim();
    if (trimmed.isEmpty) {
      state = const TextTranslateIdle();
      return;
    }

    state = const TextTranslateLoading();
    try {
      final result = await api.translate(
        text: trimmed,
        targetLanguage: targetLanguageCode(),
      );
      state = TextTranslateSuccess(trimmed, result);
    } catch (e) {
      state = TextTranslateFailure('번역에 실패했습니다: $e');
    }
  }
}

final textTranslateControllerProvider =
StateNotifierProvider<TextTranslateController, TextTranslateState>((ref) {
  return TextTranslateController(
    api: ref.watch(translateApiProvider),
    targetLanguageCode: () => ref.read(targetLanguageProvider).code,
  );
});