import 'package:app/features/translate/presets/phrase_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('문구는 총 16개다', () {
    expect(kPhrasePresets.length, 16);
  });

  test('카테고리마다 정확히 4개씩 있다', () {
    for (final category in PresetCategory.values) {
      final count =
          kPhrasePresets.where((p) => p.category == category).length;
      expect(count, 4, reason: '${category.labelKo}는 4개여야 한다');
    }
  });

  test('모든 문구는 빈 텍스트가 아니다', () {
    for (final preset in kPhrasePresets) {
      expect(preset.textKo.trim().isNotEmpty, isTrue);
    }
  });
}