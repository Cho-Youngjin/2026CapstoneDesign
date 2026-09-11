import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';

/// 발걸음 상세(일본) — 국가별 방문 상세 와이어프레임 화면.
///
/// UI 전용 정적 화면이다. 실제 지도/체크인 연동은 이후 마일스톤에서 다룬다.
/// 모든 카피는 와이어프레임의 placeholder 값을 그대로 옮긴 것이다.
class FootstepsDetailPage extends StatelessWidget {
  const FootstepsDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _Header(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MapAreaPlaceholder(height: 360),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _StatsCardsRow(),
                      const SizedBox(height: 12),
                      const _DateRow(
                        date: '04/02',
                        barWidthFactor1: 0.62,
                        barWidthFactor2: 0.38,
                        steps: '18,402',
                      ),
                      const _DateRow(
                        date: '04/03',
                        barWidthFactor1: 0.50,
                        barWidthFactor2: 0.56,
                        steps: '22,118',
                      ),
                      const _DateRow(
                        date: '04/04',
                        barWidthFactor1: 0.44,
                        barWidthFactor2: null,
                        steps: '9,860',
                      ),
                      const SizedBox(height: 12),
                      PillButton(
                        label: '여기 저장 (수동 체크인)',
                        height: 46,
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textBody),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 4),
          const Text('일본', style: AppTextStyles.screenTitle),
          const SizedBox(width: 8),
          const Flexible(
            child: Text(
              '2026.04.02 – 04.09',
              style: AppTextStyles.caption,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsCardsRow extends StatelessWidget {
  const _StatsCardsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: _StatCard(label: '누적 걸음', value: '168,204')),
        SizedBox(width: 10),
        Expanded(child: _StatCard(label: '체크인', value: '142')),
        SizedBox(width: 10),
        Expanded(child: _StatCard(label: '도시', value: '4')),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return WireframeCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Noto Sans KR',
              fontWeight: FontWeight.w400,
              fontSize: 10.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Noto Sans KR',
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.date,
    required this.barWidthFactor1,
    required this.barWidthFactor2,
    required this.steps,
  });

  final String date;
  final double barWidthFactor1;
  final double? barWidthFactor2;
  final String steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.dividerFaint)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              date,
              style: const TextStyle(
                fontFamily: 'Noto Sans KR',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColors.accent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: barWidthFactor1,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.placeholderPrimary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                if (barWidthFactor2 != null) ...[
                  const SizedBox(height: 6),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: barWidthFactor2,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.placeholderSecondary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(steps, style: AppTextStyles.caption.copyWith(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
