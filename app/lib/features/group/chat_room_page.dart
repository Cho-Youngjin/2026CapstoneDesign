import 'package:app/router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';

/// 채팅방 화면 (와이어프레임 정적 UI, 실제 메시지/전송 연동 없음).
class ChatRoomPage extends StatelessWidget {
  const ChatRoomPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _Header(),
        Expanded(
          child: Container(
            color: AppColors.chatBg,
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: const [
                Center(child: _DatePill()),
                SizedBox(height: 14),
                _IncomingTextMessage(),
                SizedBox(height: 14),
                _OutgoingTextMessage(),
                SizedBox(height: 14),
                _IncomingLocationMessage(),
                SizedBox(height: 14),
                _OutgoingImageMessage(),
              ],
            ),
          ),
        ),
        const _InputBar(),
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '다낭 4인방',
                  style: TextStyle(
                    fontFamily: 'Noto Sans KR',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '4명 · 위치 공유 중 2',
                  style: TextStyle(
                    fontFamily: 'Noto Sans KR',
                    fontWeight: FontWeight.w400,
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => context.push(AppRoutes.groupLocation),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.placeholderPrimary, width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.stripeA,
        borderRadius: BorderRadius.circular(980),
      ),
      child: Text(
        '2026년 4월 4일',
        style: AppTextStyles.caption.copyWith(
          fontSize: 10,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _NamePlaceholder extends StatelessWidget {
  const _NamePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      width: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFD8D8DE),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _TextBar extends StatelessWidget {
  const _TextBar({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 9,
      width: width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _IncomingTextMessage extends StatelessWidget {
  const _IncomingTextMessage();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(
          width: 30,
          height: 30,
          child: WireframePlaceholder(borderRadius: 10),
        ),
        const SizedBox(width: 9),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 230),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _NamePlaceholder(),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.borderLight),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TextBar(width: 170, color: AppColors.placeholderPrimary),
                    SizedBox(height: 6),
                    _TextBar(width: 120, color: AppColors.placeholderPrimary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OutgoingTextMessage extends StatelessWidget {
  const _OutgoingTextMessage();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '읽음 3',
          style: AppTextStyles.caption.copyWith(
            fontSize: 9,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(width: 9),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: const BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Container(
              height: 9,
              width: 140,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IncomingLocationMessage extends StatelessWidget {
  const _IncomingLocationMessage();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(
          width: 30,
          height: 30,
          child: WireframePlaceholder(borderRadius: 10),
        ),
        const SizedBox(width: 9),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _NamePlaceholder(),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomRight: Radius.circular(14),
                bottomLeft: Radius.circular(4),
              ),
              child: Container(
                width: 236,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MapAreaPlaceholder(height: 112),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '내 위치 공유',
                            style: TextStyle(
                              fontFamily: 'Noto Sans KR',
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 6),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: 0.76,
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: AppColors.placeholderSecondary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OutgoingImageMessage extends StatelessWidget {
  const _OutgoingImageMessage();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(4),
          ),
          child: const SizedBox(
            width: 150,
            height: 112,
            child: WireframePlaceholder(),
          ),
        ),
      ],
    );
  }
}

class _InputIconButton extends StatelessWidget {
  const _InputIconButton({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.placeholderPrimary, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          _InputIconButton(
            child: Container(
              width: 14,
              height: 11,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.placeholderPrimary, width: 1.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _InputIconButton(
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.placeholderPrimary, width: 1.5),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(980),
              ),
              alignment: Alignment.centerLeft,
              child: Container(
                height: 6,
                width: 80,
                decoration: BoxDecoration(
                  color: AppColors.placeholderSecondary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () {},
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text(
                '↑',
                style: TextStyle(
                  fontFamily: 'Noto Sans KR',
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
