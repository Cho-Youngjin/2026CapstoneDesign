import 'package:flutter/material.dart';

import 'ocr/ocr_translate_tab.dart';
import 'text/text_translate_tab.dart';
import 'voice/voice_translate_tab.dart';

class TranslatePage extends StatelessWidget {
  const TranslatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.translate), text: '텍스트'),
              Tab(icon: Icon(Icons.camera_alt_outlined), text: '카메라'),
              Tab(icon: Icon(Icons.mic_none), text: '음성'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                TextTranslateTab(),
                OcrTranslateTab(),
                VoiceTranslateTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}