import 'package:app/router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';

/// 비자 판정 결과 화면(비자 탭에서 push되는 상세 화면).
/// 와이어프레임: "해외여행 발걸음 - 와이어프레임" Plan B, 베트남 판정 결과.
class VisaResultPage extends StatelessWidget {
  const VisaResultPage({super.key});

  static const _badgeTitle = TextStyle(
    fontFamily: 'Noto Sans KR',
    fontWeight: FontWeight.w700,
    fontSize: 12,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.borderLight),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.textBody),
                onPressed: () => context.pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              Text('베트남 판정 결과', style: AppTextStyles.screenTitle),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: WireframeCard(
                        color: AppColors.infoBg,
                        borderColor: AppColors.infoBorder,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '무비자 45일',
                              style: _badgeTitle.copyWith(
                                color: AppColors.accent,
                              ),
                            ),
                            const SizedBox(height: 7),
                            FractionallySizedBox(
                              widthFactor: 0.7,
                              alignment: Alignment.centerLeft,
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: AppColors.infoBorder,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              '체류 20일 → 가능',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textBody,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: WireframeCard(
                        color: AppColors.warnBg,
                        borderColor: AppColors.warnBorder,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '여권 재발급 필요',
                              style: _badgeTitle.copyWith(
                                color: AppColors.warn,
                              ),
                            ),
                            const SizedBox(height: 7),
                            FractionallySizedBox(
                              widthFactor: 0.55,
                              alignment: Alignment.centerLeft,
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: AppColors.warnBorder,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              '잔여 85일 / 6개월 요건',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textBody,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                WireframeCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('근거 (외교부 입국허가요건)', style: AppTextStyles.label),
                          Text('검증 완료', style: AppTextStyles.caption),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        height: 7,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.placeholderSecondary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 6),
                      FractionallySizedBox(
                        widthFactor: 0.78,
                        alignment: Alignment.centerLeft,
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
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('역산 일정', style: AppTextStyles.cardTitle),
                    Text(
                      '알람 4건 예약',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const _TimelineStep(
                  dot: _TimelineDot.filled(color: AppColors.warn),
                  title: '여권 재발급 신청',
                  trailing: Text(
                    '지금 바로',
                    style: TextStyle(
                      fontFamily: 'Noto Sans KR',
                      fontWeight: FontWeight.w400,
                      fontSize: 11,
                      color: AppColors.warn,
                    ),
                  ),
                  barWidthFactor: 0.6,
                  date: 'D-90 · 09/21',
                ),
                const _TimelineStep(
                  dot: _TimelineDot.outline(color: AppColors.accent),
                  title: '비자 서류 준비',
                  trailing: Text('🔔', style: TextStyle(fontSize: 12)),
                  barWidthFactor: 0.72,
                  date: 'D-45 · 11/05',
                ),
                const _TimelineStep(
                  dot: _TimelineDot.outline(color: AppColors.placeholderPrimary),
                  title: '여행자보험 가입',
                  trailing: Text('🔔', style: TextStyle(fontSize: 12)),
                  barWidthFactor: 0.5,
                  date: 'D-30 · 11/20',
                ),
                const _TimelineStep(
                  dot: _TimelineDot.outline(color: AppColors.placeholderPrimary),
                  title: '최종 서류 점검',
                  trailing: Text('🔔', style: TextStyle(fontSize: 12)),
                  barWidthFactor: 0.44,
                  date: 'D-7 · 12/13',
                  isLast: true,
                ),
                const SizedBox(height: 24),
                PillOutlineButton(
                  label: '준비물 체크리스트 보기',
                  onPressed: () => context.push(AppRoutes.checklist),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 타임라인 점(dot) 스타일 — 완료/긴급은 채움, 예정은 테두리만.
class _TimelineDot extends StatelessWidget {
  const _TimelineDot.filled({required this.color}) : filled = true;

  const _TimelineDot.outline({required this.color}) : filled = false;

  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.white,
        border: filled ? null : Border.all(color: color, width: 2),
      ),
    );
  }
}

/// 역산 일정 타임라인 한 단계: 좌측 점(+연결선), 우측 제목/진행바/날짜.
class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.dot,
    required this.title,
    required this.trailing,
    required this.barWidthFactor,
    required this.date,
    this.isLast = false,
  });

  final _TimelineDot dot;
  final String title;
  final Widget trailing;
  final double barWidthFactor;
  final String date;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 16,
            child: Column(
              children: [
                dot,
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 2,
                        color: AppColors.borderLight,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(title, style: AppTextStyles.body),
                      trailing,
                    ],
                  ),
                  const SizedBox(height: 7),
                  FractionallySizedBox(
                    widthFactor: barWidthFactor,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.placeholderSecondary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(date, style: AppTextStyles.caption),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
