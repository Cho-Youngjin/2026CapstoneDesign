import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:app/router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';

/// 발걸음 — 세계지도 + 방문 국가 목록 와이어프레임 화면.
///
/// UI 전용 정적 화면이다. 실제 지도/통계 연동은 이후 마일스톤에서 다룬다.
/// 모든 카피는 와이어프레임의 placeholder 값을 그대로 옮긴 것이다.
class FootstepsPage extends StatefulWidget {
  const FootstepsPage({super.key});

  @override
  State<FootstepsPage> createState() => _FootstepsPageState();
}

class _FootstepsPageState extends State<FootstepsPage> {
  int _selectedFilter = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Header(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MapAreaPlaceholder(height: 300, child: _MapLegend()),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          FilterPill(
                            label: '누적 걸음',
                            selected: _selectedFilter == 0,
                            onTap: () => setState(() => _selectedFilter = 0),
                          ),
                          const SizedBox(width: 8),
                          FilterPill(
                            label: '방문일',
                            selected: _selectedFilter == 1,
                            onTap: () => setState(() => _selectedFilter = 1),
                          ),
                          const SizedBox(width: 8),
                          FilterPill(
                            label: '체크인',
                            selected: _selectedFilter == 2,
                            onTap: () => setState(() => _selectedFilter = 2),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const _StatsRow(),
                      const SizedBox(height: 12),
                      const _CountryRow(
                        name: '일본',
                        barWidthFactor: 0.88,
                        barOpacity: 0.5,
                        steps: '168,204',
                      ),
                      const _CountryRow(
                        name: '베트남',
                        barWidthFactor: 0.62,
                        barOpacity: 0.4,
                        steps: '104,530',
                      ),
                      const _CountryRow(
                        name: '태국',
                        barWidthFactor: 0.40,
                        barOpacity: 0.3,
                        steps: '62,117',
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('발걸음', style: AppTextStyles.screenTitle),
          GestureDetector(
            onTap: () {},
            child: Text(
              'Timeline 임포트',
              style: AppTextStyles.caption.copyWith(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// 지도 위에 얹는 방문/미방문 범례 (nice-to-have 장식).
class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.borderLight),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LegendDot(color: AppColors.accent),
              const SizedBox(width: 4),
              Text('방문', style: AppTextStyles.caption),
              const SizedBox(width: 10),
              _LegendDot(color: AppColors.placeholderSecondary),
              const SizedBox(width: 4),
              Text('미방문', style: AppTextStyles.caption),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('방문 국가 5 · 총 걸음', style: AppTextStyles.caption),
            const SizedBox(height: 5),
            const Text(
              '412,908',
              style: TextStyle(
                fontFamily: 'Noto Sans KR',
                fontWeight: FontWeight.w700,
                fontSize: 28,
                color: AppColors.ink,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        Container(
          width: 80,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ],
    );
  }
}

class _CountryRow extends StatelessWidget {
  const _CountryRow({
    required this.name,
    required this.barWidthFactor,
    required this.barOpacity,
    required this.steps,
  });

  final String name;
  final double barWidthFactor;
  final double barOpacity;
  final String steps;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.footstepsDetail),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.dividerFaint)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 30,
              height: 20,
              child: WireframePlaceholder(borderRadius: 3),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontFamily: 'Noto Sans KR',
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 7),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: barWidthFactor,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: barOpacity),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              steps,
              style: const TextStyle(
                fontFamily: 'Noto Sans KR',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.textBody,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
