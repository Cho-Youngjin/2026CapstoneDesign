import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/network/translate_api.dart';
import '../language/target_language.dart';
import 'text_recognizer_service.dart';

final _textRecognizerServiceProvider = Provider<TextRecognizerService>((ref) {
  final service = MlkitTextRecognizerService();
  ref.onDispose(service.dispose);
  return service;
});

final _ocrOrchestratorProvider = Provider<OcrTranslateOrchestrator>((ref) {
  return OcrTranslateOrchestrator(
    recognizer: ref.watch(_textRecognizerServiceProvider),
    api: ref.watch(translateApiProvider),
    targetLanguageCode: () => ref.read(targetLanguageProvider).code,
  );
});

class OcrTranslateTab extends ConsumerStatefulWidget {
  const OcrTranslateTab({super.key});

  @override
  ConsumerState<OcrTranslateTab> createState() => _OcrTranslateTabState();
}

class _OcrTranslateTabState extends ConsumerState<OcrTranslateTab> {
  bool _loading = false;
  String? _error;
  OcrOutcome? _outcome;

  Future<void> _takePhotoAndTranslate() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _error = '카메라 권한이 필요합니다.');
      return;
    }

    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _outcome = null;
    });

    try {
      final outcome = await ref.read(_ocrOrchestratorProvider).process(picked.path);
      setState(() => _outcome = outcome);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _loading ? null : _takePhotoAndTranslate,
            icon: const Icon(Icons.camera_alt),
            label: const Text('메뉴판 촬영해서 번역'),
          ),
          const SizedBox(height: 16),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_outcome != null) ...[
            const Text('인식된 원문', style: TextStyle(fontWeight: FontWeight.bold)),
            Card(child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_outcome!.recognizedText),
            )),
            const SizedBox(height: 12),
            const Text('번역 결과', style: TextStyle(fontWeight: FontWeight.bold)),
            Card(child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_outcome!.translation.translatedText,
                  style: const TextStyle(fontSize: 18)),
            )),
          ],
        ],
      ),
    );
  }
}