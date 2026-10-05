import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../language/target_language.dart';
import '../presets/phrase_presets.dart';
import 'text_translate_controller.dart';

class TextTranslateTab extends ConsumerStatefulWidget {
  const TextTranslateTab({super.key});

  @override
  ConsumerState<TextTranslateTab> createState() => _TextTranslateTabState();
}

class _TextTranslateTabState extends ConsumerState<TextTranslateTab> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _translate() {
    ref.read(textTranslateControllerProvider.notifier).translate(_controller.text);
  }

  void _usePreset(PhrasePreset preset) {
    _controller.text = preset.textKo;
    _translate();
  }

  @override
  Widget build(BuildContext context) {
    final target = ref.watch(targetLanguageProvider);
    final state = ref.watch(textTranslateControllerProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<LanguageOption>(
            initialValue: target,
            decoration: const InputDecoration(labelText: '대상 언어'),
            items: [
              for (final option in kSupportedLanguages)
                DropdownMenuItem(value: option, child: Text(option.labelKo)),
            ],
            onChanged: (value) {
              if (value != null) {
                ref.read(targetLanguageProvider.notifier).setManually(value);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '한국어로 입력',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _translate, child: const Text('번역하기')),
          const SizedBox(height: 16),
          _buildResult(state),
          const SizedBox(height: 16),
          const Text('상황별 문구', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(child: _buildPresetList()),
        ],
      ),
    );
  }

  Widget _buildResult(TextTranslateState state) {
    return switch (state) {
      TextTranslateIdle() => const SizedBox.shrink(),
      TextTranslateLoading() => const Center(child: CircularProgressIndicator()),
      TextTranslateSuccess(:final result) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(result.translatedText, style: const TextStyle(fontSize: 18)),
        ),
      ),
      TextTranslateFailure(:final message) =>
          Text(message, style: const TextStyle(color: Colors.red)),
    };
  }

  Widget _buildPresetList() {
    return ListView(
      children: [
        for (final category in PresetCategory.values) ...[
          Text(category.labelKo, style: const TextStyle(fontWeight: FontWeight.w600)),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final preset in kPhrasePresets.where((p) => p.category == category))
                ActionChip(
                  label: Text(preset.textKo),
                  onPressed: () => _usePreset(preset),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}