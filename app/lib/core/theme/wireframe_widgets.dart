import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

/// 채워진(파란) pill 버튼. 와이어프레임의 주요 액션 버튼 스타일(radius 980, 그림자 없음).
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.height = 50,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: const StadiumBorder(),
        ),
        child: Text(label, style: AppTextStyles.buttonLarge),
      ),
    );
  }
}

/// 테두리만 있는(outline) pill 버튼.
class PillOutlineButton extends StatelessWidget {
  const PillOutlineButton({
    super.key,
    required this.label,
    this.onPressed,
    this.height = 48,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: const BorderSide(color: AppColors.accent),
          shape: const StadiumBorder(),
        ),
        child: Text(
          label,
          style: AppTextStyles.buttonLarge.copyWith(color: AppColors.accent),
        ),
      ),
    );
  }
}

/// 선택 가능한 필터/카테고리 pill(칩). [selected]면 검정 채움, 아니면 테두리만.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : Colors.white,
          borderRadius: BorderRadius.circular(980),
          border: selected ? null : Border.all(color: AppColors.borderMedium),
        ),
        child: Text(
          label,
          style: AppTextStyles.chip.copyWith(
            color: selected ? Colors.white : AppColors.textBody,
          ),
        ),
      ),
    );
  }
}

/// 사진/지도 등 아직 실제 콘텐츠가 없는 자리를 나타내는 대각선 줄무늬 박스.
/// 지도(Google Maps 등)처럼 팀원이 나중에 실제 구현을 채워 넣을 자리는
/// 이 위젯을 그대로 남겨두고 TODO만 표시한다.
class WireframePlaceholder extends StatelessWidget {
  const WireframePlaceholder({
    super.key,
    this.label,
    this.borderRadius = 0,
  });

  final String? label;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        color: AppColors.stripeB,
        child: CustomPaint(
          painter: _StripePainter(),
          child: label == null
              ? null
              : Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      label!,
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.stripeA
      ..strokeWidth = 6;
    const gap = 12.0;
    for (double x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 지도 자리 전용 placeholder. 실제 지도(Google Maps SDK 연동)는
/// Plan C/D/F에서 팀원이 이 위젯을 교체하면 된다.
class MapAreaPlaceholder extends StatelessWidget {
  const MapAreaPlaceholder({super.key, this.height = 300, this.child});

  final double height;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        children: [
          const WireframePlaceholder(label: '지도 자리 (TODO: 실제 지도 연동)'),
          ?child,
        ],
      ),
    );
  }
}

/// 하드라인 보더 카드(그림자 없음, radius 8).
class WireframeCard extends StatelessWidget {
  const WireframeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = Colors.white,
    this.borderColor = AppColors.borderCard,
    this.borderRadius = 8,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color borderColor;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: child,
    );
  }
}

/// "서류" · "전자기기" 같은 섹션 라벨(간격 넓은 대문자 느낌의 작은 캡션).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.label.copyWith(letterSpacing: 0.6),
    );
  }
}
