import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';

/// 번역 탭의 기본 화면 — 한/현지어 번역, 상황별 문구, 최근 문구 기록.
/// 와이어프레임: "해외여행 발걸음 - 와이어프레임", 번역 화면.
class TranslatePage extends StatelessWidget {
  const TranslatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.borderLight)),
          ),
          child: Text('번역', style: AppTextStyles.screenTitle),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LanguagePairSelector(),
                const SizedBox(height: 14),
                _InputTextArea(),
                const SizedBox(height: 14),
                PillButton(label: '번역', height: 46, onPressed: () {}),
                const SizedBox(height: 14),
                _ResultCard(),
                const SizedBox(height: 14),
                const SizedBox(height: 4),
                const SectionLabel('상황별 문구'),
                const SizedBox(height: 8),
                _PresetPhraseRow(),
                const SizedBox(height: 14),
                _PhraseHistoryList(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "한국어 ⇄ 베트남어" 언어쌍 선택 pill과 "현지어 자동" 배지.
class _LanguagePairSelector extends StatelessWidget {
  const _LanguagePairSelector();

  static const _langStyle = TextStyle(
    fontFamily: 'Noto Sans KR',
    fontWeight: FontWeight.w500,
    fontSize: 13,
    color: AppColors.ink,
  );

  static const _arrowStyle = TextStyle(
    fontFamily: 'Noto Sans KR',
    fontWeight: FontWeight.w400,
    fontSize: 13,
    color: AppColors.textTertiary,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderMedium),
        borderRadius: BorderRadius.circular(980),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('한국어', style: _langStyle),
          const SizedBox(width: 10),
          const Text('⇄', style: _arrowStyle),
          const SizedBox(width: 10),
          const Text('베트남어', style: _langStyle),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.infoBg,
              borderRadius: BorderRadius.circular(980),
            ),
            child: const Text(
              '현지어 자동',
              style: TextStyle(
                fontFamily: 'Noto Sans KR',
                fontWeight: FontWeight.w500,
                fontSize: 9.5,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 번역 입력창 — placeholder 텍스트 막대, 글자 수, 카메라/음성 입력 자리.
class _InputTextArea extends StatelessWidget {
  const _InputTextArea();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 128,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderMedium),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FractionallySizedBox(
            widthFactor: 0.72,
            alignment: Alignment.centerLeft,
            child: Container(height: 11, color: AppColors.placeholderPrimary),
          ),
          const SizedBox(height: 8),
          FractionallySizedBox(
            widthFactor: 0.54,
            alignment: Alignment.centerLeft,
            child: Container(height: 11, color: AppColors.placeholderPrimary),
          ),
          const Expanded(child: SizedBox()),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '0 / 500',
                style: TextStyle(
                  fontFamily: 'Noto Sans KR',
                  fontWeight: FontWeight.w400,
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CaptureIconButton(
                    icon: Container(
                      width: 12,
                      height: 10,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.placeholderPrimary,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CaptureIconButton(
                    icon: Container(
                      width: 8,
                      height: 12,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.placeholderPrimary,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 카메라/음성 입력을 나타내는 30x30 장식용 아이콘 버튼(로직 없음).
class _CaptureIconButton extends StatelessWidget {
  const _CaptureIconButton({required this.icon});

  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.placeholderPrimary, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: icon,
      ),
    );
  }
}

/// 번역 결과 카드 — "번역 결과 · NMT" 헤더와 placeholder 결과 텍스트.
class _ResultCard extends StatelessWidget {
  const _ResultCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '번역 결과 · NMT',
                style: TextStyle(
                  fontFamily: 'Noto Sans KR',
                  fontWeight: FontWeight.w500,
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const Text(
                '듣기 · 복사',
                style: TextStyle(
                  fontFamily: 'Noto Sans KR',
                  fontWeight: FontWeight.w400,
                  fontSize: 10.5,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          FractionallySizedBox(
            widthFactor: 0.84,
            alignment: Alignment.centerLeft,
            child: Container(height: 11, color: AppColors.placeholderPrimary),
          ),
          const SizedBox(height: 9),
          FractionallySizedBox(
            widthFactor: 0.48,
            alignment: Alignment.centerLeft,
            child: Container(height: 11, color: AppColors.placeholderPrimary),
          ),
        ],
      ),
    );
  }
}

/// 상황별 문구 프리셋 pill 목록 — "입국심사"(선택됨), "식당", "교통", "응급"(경고색).
class _PresetPhraseRow extends StatelessWidget {
  const _PresetPhraseRow();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        const FilterPill(label: '입국심사', selected: true),
        const FilterPill(label: '식당'),
        const FilterPill(label: '교통'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.warn),
            borderRadius: BorderRadius.circular(980),
          ),
          child: Text('응급', style: AppTextStyles.chip.copyWith(color: AppColors.warn)),
        ),
      ],
    );
  }
}

/// 최근 사용한 문구 3건 목록 — 번역 원문/역문 placeholder와 "듣기" 액션.
class _PhraseHistoryList extends StatelessWidget {
  const _PhraseHistoryList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        _PhraseHistoryRow(primaryWidthFactor: 0.66, secondaryWidthFactor: 0.80),
        _PhraseHistoryRow(primaryWidthFactor: 0.52, secondaryWidthFactor: 0.62),
        _PhraseHistoryRow(primaryWidthFactor: 0.58),
      ],
    );
  }
}

class _PhraseHistoryRow extends StatelessWidget {
  const _PhraseHistoryRow({
    required this.primaryWidthFactor,
    this.secondaryWidthFactor,
  });

  final double primaryWidthFactor;
  final double? secondaryWidthFactor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.dividerFaint)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: primaryWidthFactor,
                  alignment: Alignment.centerLeft,
                  child: Container(height: 10, color: AppColors.placeholderPrimary),
                ),
                if (secondaryWidthFactor != null) ...[
                  const SizedBox(height: 6),
                  FractionallySizedBox(
                    widthFactor: secondaryWidthFactor!,
                    alignment: Alignment.centerLeft,
                    child: Container(height: 6, color: AppColors.placeholderSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            '듣기',
            style: TextStyle(
              fontFamily: 'Noto Sans KR',
              fontWeight: FontWeight.w400,
              fontSize: 11,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
