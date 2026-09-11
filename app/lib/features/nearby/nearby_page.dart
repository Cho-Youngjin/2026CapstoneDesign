import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';

/// 주변 탭의 기본 화면 — 지도, 카테고리 필터, 주변 장소 목록, 긴급 연락처.
/// 와이어프레임: "해외여행 발걸음 - 와이어프레임", 주변 화면.
class NearbyPage extends StatelessWidget {
  const NearbyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.borderLight)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('주변', style: AppTextStyles.screenTitle),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.warnBg,
                  border: Border.all(color: AppColors.warnBorder),
                  borderRadius: BorderRadius.circular(980),
                ),
                child: const Text(
                  '여행경보 2단계',
                  style: TextStyle(
                    fontFamily: 'Noto Sans KR',
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                    color: AppColors.warn,
                  ),
                ),
              ),
            ],
          ),
        ),
        const _NearbyMapSection(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CategoryFilterRow(),
                const SizedBox(height: 12),
                _NearbyPlaceList(),
                const SizedBox(height: 12),
                _EmergencyContactCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 지도 자리 — 현재 위치/주변 관심 지점/경보 지점 핀과 레이어 버튼(모두 장식용).
class _NearbyMapSection extends StatelessWidget {
  const _NearbyMapSection();

  @override
  Widget build(BuildContext context) {
    return MapAreaPlaceholder(
      height: 268,
      child: Stack(
        children: [
          Align(
            alignment: const Alignment(-0.55, -0.25),
            child: _dot(size: 13, color: AppColors.ink),
          ),
          Align(
            alignment: const Alignment(0.35, 0.35),
            child: _dot(size: 13, color: AppColors.ink),
          ),
          Align(
            alignment: const Alignment(-0.15, 0.6),
            child: _dot(size: 13, color: AppColors.ink),
          ),
          Align(
            alignment: const Alignment(0.6, -0.3),
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.warn,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent,
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderCard),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _dot({required double size, required Color color}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }
}

/// 카테고리 필터 pill 목록 — "관광지"(선택됨), "음식점", "약국", "ATM".
class _CategoryFilterRow extends StatelessWidget {
  const _CategoryFilterRow();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterPill(label: '관광지', selected: true),
        FilterPill(label: '음식점'),
        FilterPill(label: '약국'),
        FilterPill(label: 'ATM'),
      ],
    );
  }
}

/// 주변 장소 3건 목록 — 사진 placeholder, 이름/주소 placeholder, 거리.
class _NearbyPlaceList extends StatelessWidget {
  const _NearbyPlaceList();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _NearbyPlaceRow(primaryWidthFactor: 0.56, secondaryWidthFactor: 0.74, distance: '240m'),
        _NearbyPlaceRow(primaryWidthFactor: 0.44, secondaryWidthFactor: 0.62, distance: '610m'),
        _NearbyPlaceRow(primaryWidthFactor: 0.62, secondaryWidthFactor: 0.50, distance: '1.2km'),
      ],
    );
  }
}

class _NearbyPlaceRow extends StatelessWidget {
  const _NearbyPlaceRow({
    required this.primaryWidthFactor,
    required this.secondaryWidthFactor,
    required this.distance,
  });

  final double primaryWidthFactor;
  final double secondaryWidthFactor;
  final String distance;

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
          const SizedBox(
            width: 48,
            height: 48,
            child: WireframePlaceholder(borderRadius: 8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: primaryWidthFactor,
                  alignment: Alignment.centerLeft,
                  child: Container(height: 11, color: AppColors.placeholderPrimary),
                ),
                const SizedBox(height: 6),
                FractionallySizedBox(
                  widthFactor: secondaryWidthFactor,
                  alignment: Alignment.centerLeft,
                  child: Container(height: 6, color: AppColors.placeholderSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            distance,
            style: const TextStyle(
              fontFamily: 'Noto Sans KR',
              fontWeight: FontWeight.w400,
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 긴급/영사관 연락처 카드.
class _EmergencyContactCard extends StatelessWidget {
  const _EmergencyContactCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warnBg,
        border: Border.all(color: AppColors.warnBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '주 호치민 총영사관',
                style: TextStyle(
                  fontFamily: 'Noto Sans KR',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: AppColors.warn,
                ),
              ),
              SizedBox(height: 5),
              Text(
                '긴급전화 · 지도에서 보기',
                style: TextStyle(
                  fontFamily: 'Noto Sans KR',
                  fontWeight: FontWeight.w400,
                  fontSize: 10.5,
                  color: AppColors.textBody,
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: () {},
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.warn, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
