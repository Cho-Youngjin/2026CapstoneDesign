import 'package:app/router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';

/// 그룹 탭 — 채팅/그룹 목록 화면 (와이어프레임 정적 UI, 실제 데이터 연동 없음).
class GroupPage extends StatelessWidget {
  const GroupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Header(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SearchBar(),
                const SizedBox(height: 12),
                const _ChatListRow(
                  title: '다낭 4인방',
                  tagLabel: '그룹 4',
                  tagBg: AppColors.infoBg,
                  tagColor: AppColors.accent,
                  previewWidthFraction: 0.74,
                  time: '오후 2:14',
                  unreadCount: '12',
                ),
                const _ChatListRow(
                  titlePlaceholderWidth: 82,
                  tagLabel: 'DM',
                  tagBg: AppColors.surface,
                  tagColor: AppColors.textSecondary,
                  previewWidthFraction: 0.60,
                  time: '오전 11:02',
                  unreadCount: '3',
                ),
                const _ChatListRow(
                  titlePlaceholderWidth: 104,
                  tagLabel: '그룹 6',
                  tagBg: AppColors.surface,
                  tagColor: AppColors.textSecondary,
                  isImagePreview: true,
                  time: '어제',
                ),
                const _ChatListRow(
                  titlePlaceholderWidth: 70,
                  previewWidthFraction: 0.52,
                  time: '04/09',
                ),
                const _ChatListRow(
                  titlePlaceholderWidth: 92,
                  previewWidthFraction: 0.36,
                  time: '04/02',
                ),
                const SizedBox(height: 12),
                const _InviteCodeCard(),
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
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.dividerFaint)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('그룹', style: AppTextStyles.screenTitle),
          Row(
            children: [
              GestureDetector(
                onTap: () {},
                child: Text(
                  '코드 참여',
                  style: AppTextStyles.caption.copyWith(color: AppColors.accent),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {},
                child: Text(
                  '+ 생성',
                  style: AppTextStyles.caption.copyWith(color: AppColors.accent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(980),
      ),
      child: Row(
        children: [
          Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFAEAEB2), width: 1.5),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            height: 6,
            width: 96,
            decoration: BoxDecoration(
              color: AppColors.placeholderSecondary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.bg, required this.color});

  final String label;
  final Color bg;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Noto Sans KR',
          fontWeight: FontWeight.w500,
          fontSize: 9,
          color: color,
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final String count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(980),
      ),
      alignment: Alignment.center,
      child: Text(
        count,
        style: const TextStyle(
          fontFamily: 'Noto Sans KR',
          fontWeight: FontWeight.w700,
          fontSize: 10,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// 채팅 목록의 한 행. [title]이 주어지면 실제 텍스트, 아니면 [titlePlaceholderWidth]로
/// placeholder 막대를 그린다.
class _ChatListRow extends StatelessWidget {
  const _ChatListRow({
    this.title,
    this.titlePlaceholderWidth,
    this.tagLabel,
    this.tagBg,
    this.tagColor,
    this.previewWidthFraction,
    this.isImagePreview = false,
    required this.time,
    this.unreadCount,
  });

  final String? title;
  final double? titlePlaceholderWidth;
  final String? tagLabel;
  final Color? tagBg;
  final Color? tagColor;
  final double? previewWidthFraction;
  final bool isImagePreview;
  final String time;
  final String? unreadCount;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.groupChat),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.dividerFaint)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 44,
              height: 44,
              child: WireframePlaceholder(borderRadius: 12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (title != null)
                        Text(
                          title!,
                          style: const TextStyle(
                            fontFamily: 'Noto Sans KR',
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.ink,
                          ),
                        )
                      else
                        Container(
                          height: 11,
                          width: titlePlaceholderWidth,
                          decoration: BoxDecoration(
                            color: AppColors.placeholderPrimary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      if (tagLabel != null) ...[
                        const SizedBox(width: 7),
                        _Tag(label: tagLabel!, bg: tagBg!, color: tagColor!),
                      ],
                    ],
                  ),
                  const SizedBox(height: 7),
                  if (isImagePreview)
                    Row(
                      children: [
                        Container(
                          width: 11,
                          height: 11,
                          color: AppColors.placeholderSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: 0.44,
                            child: Container(
                              height: 7,
                              decoration: BoxDecoration(
                                color: AppColors.placeholderSecondary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (previewWidthFraction != null)
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: previewWidthFraction,
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
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  time,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
                if (unreadCount != null) ...[
                  const SizedBox(height: 7),
                  _UnreadBadge(count: unreadCount!),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteCodeCard extends StatelessWidget {
  const _InviteCodeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderMedium),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('초대 코드로 참여', style: AppTextStyles.chip),
              const SizedBox(height: 5),
              Text(
                '6자리 코드 입력',
                style: AppTextStyles.caption.copyWith(
                  fontSize: 10.5,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          Row(
            children: List.generate(
              6,
              (i) => Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                child: Container(
                  width: 20,
                  height: 26,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.borderMedium),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
