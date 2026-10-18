import 'package:app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import 'data/room_providers.dart';
import 'group_sheets.dart';
import 'models/room.dart';

/// 목록에 보이는 마지막 메시지 시각. 오늘이면 "오후 2:14", 어제면 "어제",
/// 올해 그 전이면 "04/09", 작년 이전이면 "2025/12/31".
String formatRoomTime(DateTime at, DateTime now) {
  final local = at.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  String two(int n) => n.toString().padLeft(2, '0');

  if (day == today) {
    final period = local.hour < 12 ? '오전' : '오후';
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '$period $hour12:${two(local.minute)}';
  }
  if (day == today.subtract(const Duration(days: 1))) return '어제';
  if (local.year == now.year) return '${two(local.month)}/${two(local.day)}';
  return '${local.year}/${two(local.month)}/${two(local.day)}';
}

/// 그룹 탭 — 내가 속한 채팅방 목록, 그룹 만들기, 초대 코드로 참여 (Plan D Task 3).
class GroupPage extends ConsumerWidget {
  const GroupPage({super.key});

  Future<void> _create(BuildContext context) async {
    final room = await showCreateGroupSheet(context);
    if (room == null || !context.mounted) return;
    final goToRoom = await showInviteCodeDialog(context, room);
    if (goToRoom && context.mounted) context.push(AppRoutes.groupChatOf(room.id));
  }

  Future<void> _join(BuildContext context) async {
    final room = await showJoinGroupSheet(context);
    if (room == null || !context.mounted) return;
    context.push(AppRoutes.groupChatOf(room.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(myRoomsProvider);
    return Column(
      children: [
        _Header(onJoin: () => _join(context), onCreate: () => _create(context)),
        Expanded(
          child: rooms.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _RoomsError(
              message: groupErrorMessage(e),
              onRetry: () => ref.invalidate(myRoomsProvider),
            ),
            data: (list) => RefreshIndicator(
              onRefresh: () => ref.refresh(myRoomsProvider.future),
              child: ListView(
                // 목록이 짧아도 당겨서 새로고침이 되도록 항상 스크롤 가능하게 둔다.
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
                children: [
                  if (list.isEmpty)
                    _EmptyRooms(onCreate: () => _create(context))
                  else
                    for (final room in list)
                      _ChatListRow(
                        room: room,
                        now: DateTime.now(),
                        onTap: () => context.push(AppRoutes.groupChatOf(room.id)),
                      ),
                  const SizedBox(height: 12),
                  _InviteCodeCard(onTap: () => _join(context)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onJoin, required this.onCreate});

  final VoidCallback onJoin;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.dividerFaint)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('그룹', style: AppTextStyles.screenTitle),
          Row(
            children: [
              TextButton(
                key: const Key('joinGroupButton'),
                onPressed: onJoin,
                child: Text('코드 참여', style: AppTextStyles.caption.copyWith(color: AppColors.accent)),
              ),
              TextButton(
                key: const Key('createGroupButton'),
                onPressed: onCreate,
                child: Text('+ 생성', style: AppTextStyles.caption.copyWith(color: AppColors.accent)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('emptyRooms'),
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.forum_outlined, size: 40, color: AppColors.placeholderPrimary),
          const SizedBox(height: 12),
          Text('아직 참여한 그룹이 없어요', style: AppTextStyles.body),
          const SizedBox(height: 4),
          Text(
            '그룹을 만들거나, 일행에게 받은 초대 코드로 참여해 보세요',
            style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onCreate, child: const Text('그룹 만들기')),
        ],
      ),
    );
  }
}

class _RoomsError extends StatelessWidget {
  const _RoomsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('roomsError'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('그룹 목록을 불러오지 못했어요', style: AppTextStyles.body),
            const SizedBox(height: 4),
            Text(message, style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary)),
            const SizedBox(height: 12),
            TextButton(key: const Key('roomsRetry'), onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
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
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
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

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(980)),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
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

/// 채팅 목록의 한 행 — 와이어프레임의 레이아웃(사진 자리, 제목+태그, 미리보기, 시각, 안 읽은 수)을
/// 그대로 두고 실제 방 데이터로 채운다.
class _ChatListRow extends StatelessWidget {
  const _ChatListRow({required this.room, required this.now, required this.onTap});

  final RoomSummary room;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isGroup = room.type == RoomType.group;
    final preview = room.lastMessagePreview;
    return InkWell(
      key: Key('roomRow-${room.id}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.dividerFaint)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 44, height: 44, child: WireframePlaceholder(borderRadius: 12)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          room.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Noto Sans KR',
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      isGroup
                          ? _Tag(label: '그룹 ${room.memberCount}', bg: AppColors.infoBg, color: AppColors.accent)
                          : const _Tag(label: 'DM', bg: AppColors.surface, color: AppColors.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    preview ?? '아직 메시지가 없어요',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: preview == null ? AppColors.textTertiary : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (room.lastMessageAt != null)
                  Text(
                    formatRoomTime(room.lastMessageAt!, now),
                    style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary, fontSize: 10),
                  ),
                if (room.unreadCount > 0) ...[
                  const SizedBox(height: 7),
                  _UnreadBadge(count: room.unreadCount),
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
  const _InviteCodeCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('inviteCodeCard'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
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
                  style: AppTextStyles.caption.copyWith(fontSize: 10.5, color: AppColors.textTertiary),
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
      ),
    );
  }
}
