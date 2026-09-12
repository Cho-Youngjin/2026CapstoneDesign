import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';

/// 위치 공유 화면 (와이어프레임 정적 UI, 실제 지도/위치 연동 없음).
class LocationSharePage extends StatelessWidget {
  const LocationSharePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _Header(),
        Expanded(
          child: Stack(
            children: [
              const Positioned.fill(child: MapAreaPlaceholder()),
              const Positioned(left: 14, right: 14, top: 14, child: _ShareToggleCard()),
              Align(alignment: const Alignment(-0.5, -0.1), child: _MemberPin.me()),
              Align(alignment: const Alignment(0.1, -0.4), child: _MemberPin.member('민준')),
              Align(alignment: const Alignment(-0.2, 0.4), child: _MemberPin.member('서연')),
              Align(alignment: const Alignment(0.4, 0.2), child: _MemberPin.off('지훈 OFF')),
            ],
          ),
        ),
        const _BottomSheet(),
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
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.dividerFaint)),
      ),
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.arrow_back, color: AppColors.textBody),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 12),
          Text('위치 공유', style: AppTextStyles.screenTitle),
        ],
      ),
    );
  }
}

class _ShareToggleCard extends StatelessWidget {
  const _ShareToggleCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.borderCard),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '내 위치 공유 ON',
                style: TextStyle(
                  fontFamily: 'Noto Sans KR',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.ink,
                ),
              ),
              SizedBox(height: 5),
              Text(
                '5초마다 갱신 · 기록은 저장되지 않음',
                style: TextStyle(
                  fontFamily: 'Noto Sans KR',
                  fontWeight: FontWeight.w400,
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const _TogglePill(),
        ],
      ),
    );
  }
}

class _TogglePill extends StatelessWidget {
  const _TogglePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 27,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(980),
      ),
      child: const Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 21,
          height: 21,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

/// 지도 위에 표시되는 그룹원 마커 (아바타 원 + 이름 라벨).
class _MemberPin extends StatelessWidget {
  const _MemberPin({
    required this.label,
    required this.size,
    required this.fillColor,
    required this.labelStyle,
  });

  factory _MemberPin.me() => _MemberPin(
        label: '나',
        size: 34,
        fillColor: AppColors.accent,
        labelStyle: const TextStyle(
          fontFamily: 'Noto Sans KR',
          fontWeight: FontWeight.w600,
          fontSize: 9.5,
          color: AppColors.ink,
        ),
      );

  factory _MemberPin.member(String name) => _MemberPin(
        label: name,
        size: 32,
        fillColor: AppColors.placeholderPrimary,
        labelStyle: const TextStyle(
          fontFamily: 'Noto Sans KR',
          fontWeight: FontWeight.w500,
          fontSize: 9.5,
          color: AppColors.textBody,
        ),
      );

  factory _MemberPin.off(String name) => _MemberPin(
        label: name,
        size: 32,
        fillColor: AppColors.placeholderSecondary,
        labelStyle: const TextStyle(
          fontFamily: 'Noto Sans KR',
          fontWeight: FontWeight.w400,
          fontSize: 9.5,
          color: AppColors.textTertiary,
        ),
      );

  final String label;
  final double size;
  final Color fillColor;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: fillColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(980),
            border: Border.all(color: AppColors.borderCard),
          ),
          child: Text(label, style: labelStyle),
        ),
      ],
    );
  }
}

class _BottomSheet extends StatelessWidget {
  const _BottomSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.placeholderSecondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('그룹원 4', style: AppTextStyles.cardTitle),
              GestureDetector(
                onTap: () {},
                child: Text(
                  '전체 보기',
                  style: AppTextStyles.caption.copyWith(color: AppColors.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              _MemberSummary.me(),
              SizedBox(width: 14),
              _MemberSummary.other(),
              SizedBox(width: 14),
              _MemberSummary.other(),
              SizedBox(width: 14),
              _MemberSummary.add(),
            ],
          ),
        ],
      ),
    );
  }
}

/// 하단 시트의 그룹원 아바타 요약(원 + 이름/placeholder 라벨).
class _MemberSummary extends StatelessWidget {
  const _MemberSummary.me()
      : _variant = _MemberSummaryVariant.me;

  const _MemberSummary.other()
      : _variant = _MemberSummaryVariant.other;

  const _MemberSummary.add()
      : _variant = _MemberSummaryVariant.add;

  final _MemberSummaryVariant _variant;

  @override
  Widget build(BuildContext context) {
    switch (_variant) {
      case _MemberSummaryVariant.me:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(
                    BorderSide(color: AppColors.accent, width: 2),
                  ),
                ),
              ),
            ),
            SizedBox(height: 6),
            Text(
              '나',
              style: TextStyle(
                fontFamily: 'Noto Sans KR',
                fontWeight: FontWeight.w500,
                fontSize: 10,
                color: AppColors.ink,
              ),
            ),
          ],
        );
      case _MemberSummaryVariant.other:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(
                    BorderSide(color: AppColors.borderCard),
                  ),
                ),
              ),
            ),
            SizedBox(height: 6),
            _NameBar(color: AppColors.placeholderSecondary),
          ],
        );
      case _MemberSummaryVariant.add:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(
                    BorderSide(color: AppColors.borderMedium),
                  ),
                ),
              ),
            ),
            SizedBox(height: 6),
            _NameBar(color: AppColors.dividerFaint),
          ],
        );
    }
  }
}

enum _MemberSummaryVariant { me, other, add }

class _NameBar extends StatelessWidget {
  const _NameBar({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      width: 26,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
