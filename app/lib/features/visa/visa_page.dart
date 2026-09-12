import 'package:app/router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';

/// 비자 탭의 기본 화면 — 여행 계획(목적지/일정) 입력 폼.
/// 와이어프레임: "해외여행 발걸음 - 와이어프레임" Plan B, 여행 계획 화면.
class VisaPage extends StatelessWidget {
  const VisaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.borderLight),
            ),
          ),
          child: Text('여행 계획', style: AppTextStyles.screenTitle),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FieldGroup(
                  label: '목적지 국가',
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.borderMedium),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 26,
                          height: 18,
                          child: WireframePlaceholder(borderRadius: 3),
                        ),
                        const SizedBox(width: 10),
                        Text('베트남', style: AppTextStyles.body),
                        const SizedBox(width: 10),
                        Text('VN · Tier A', style: AppTextStyles.caption),
                        const Spacer(),
                        Text(
                          '▾',
                          style: AppTextStyles.caption.copyWith(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _FieldGroup(
                        label: '출발일',
                        child: _DateBox(text: '2026-12-20'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FieldGroup(
                        label: '귀국일',
                        child: _DateBox(text: '2027-01-09'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _FieldGroup(
                  label: '여권 만료일',
                  child: _DateBox(text: '2027-03-15'),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '체류 20일',
                        style: AppTextStyles.chip.copyWith(
                          color: AppColors.textBody,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 1,
                        height: 12,
                        color: AppColors.borderMedium,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: 7,
                          decoration: BoxDecoration(
                            color: AppColors.placeholderSecondary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text('최근 검색', style: AppTextStyles.label),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterPill(label: '일본', selected: false, onTap: () {}),
                    FilterPill(label: '태국', selected: false, onTap: () {}),
                    FilterPill(label: '프랑스', selected: false, onTap: () {}),
                  ],
                ),
                const SizedBox(height: 32),
                PillButton(
                  label: '비자 판정하기',
                  height: 50,
                  onPressed: () => context.push(AppRoutes.visaResult),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldGroup extends StatelessWidget {
  const _FieldGroup({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.label),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderMedium),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: AppTextStyles.body),
    );
  }
}
