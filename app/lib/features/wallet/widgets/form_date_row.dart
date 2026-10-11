import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../domain/month_day.dart';

/// 기록 폼의 날짜 행. 누르면 날짜 선택기를 연다(선택기는 부모가 띄운다).
class FormDateRow extends StatelessWidget {
  const FormDateRow({super.key, required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('dateRow'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('날짜', style: AppTextStyles.label),
            Text(
              '${formatMonthDay(date)} · 변경',
              style: AppTextStyles.chip.copyWith(color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// 시각을 떼고 날짜만 남긴다(지갑 기록은 날짜 단위).
DateTime dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
