import 'dart:math';
import 'dart:typed_data';

import 'package:app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import 'data/chat_api.dart';
import 'data/chat_images.dart';
import 'data/chat_room_controller.dart';
import 'data/room_providers.dart';
import 'members_sheet.dart';
import 'models/chat_message.dart';
import 'models/room.dart';

/// 말풍선 옆에 붙는 시각. "오후 2:05".
String formatClock(DateTime at) {
  final local = at.toLocal();
  final period = local.hour < 12 ? '오전' : '오후';
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  return '$period $hour12:${local.minute.toString().padLeft(2, '0')}';
}

String _formatDate(DateTime at) {
  final local = at.toLocal();
  return '${local.year}년 ${local.month}월 ${local.day}일';
}

bool _sameDay(DateTime a, DateTime b) {
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// 채팅방 화면 (Plan D Task 4). 와이어프레임의 말풍선 모양·색은 그대로 두고 실제 메시지로 채운다.
///
/// 메시지 목록·실시간 수신·전송 규칙은 [ChatRoomController]에 있고, 이 화면은 그리기만 한다.
/// 사진은 입력창 왼쪽 버튼으로 보낸다(Task 6). 읽음 표시(Task 7)는 아직 없다.
class ChatRoomPage extends ConsumerStatefulWidget {
  const ChatRoomPage({super.key, required this.roomId});

  final int roomId;

  @override
  ConsumerState<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends ConsumerState<ChatRoomPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// 멤버 목록에 없는 사람의 메시지가 오면 상세를 한 번 다시 불러온다(그사이 새로 참여한 멤버).
  /// 같은 사람 때문에 반복해서 부르지 않도록 기억한다.
  final Set<String> _refreshedForUnknown = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 목록이 reverse라 "맨 위(오래된 쪽)"가 maxScrollExtent 쪽이다. 거기에 가까워지면 이전 페이지를 부른다.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      ref.read(chatRoomControllerProvider(widget.roomId).notifier).loadOlder();
    }
  }

  Future<void> _send() async {
    final ok = await ref.read(chatRoomControllerProvider(widget.roomId).notifier).send(_input.text);
    if (!mounted) return;
    if (ok) {
      _input.clear();
      setState(() {});
      if (_scroll.hasClients) _scroll.jumpTo(0); // 맨 아래(최신)로
    } else {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('전송하지 못했어요. 다시 시도해 주세요.')));
    }
  }

  /// 사진을 골라 보낸다. 고르기를 취소하면 아무것도 하지 않는다.
  Future<void> _attachImage() async {
    final Uint8List? bytes;
    try {
      bytes = await ref.read(chatImagePickerProvider)();
    } catch (e) {
      // 갤러리 권한을 거부했거나 기기에서 고르기가 실패한 경우.
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('사진을 불러오지 못했어요.')));
      }
      return;
    }
    if (bytes == null || !mounted) return;
    if (_scroll.hasClients) _scroll.jumpTo(0); // 맨 아래(올리는 사진 자리)로
    await ref.read(chatRoomControllerProvider(widget.roomId).notifier).sendImage(bytes);
  }

  void _refreshIfUnknownSenders(List<ChatMessage> messages, Map<String, RoomMember> members) {
    for (final m in messages) {
      if (!members.containsKey(m.senderUid) && _refreshedForUnknown.add(m.senderUid)) {
        // build 중에는 provider를 무효화할 수 없으므로 프레임이 끝난 뒤에 한다.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.invalidate(roomDetailProvider(widget.roomId));
        });
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(roomDetailProvider(widget.roomId));
    final chat = ref.watch(chatRoomControllerProvider(widget.roomId));
    final myUid = ref.watch(currentUidProvider);

    final room = detail.value;
    if (detail.error is RoomNotFoundException) {
      return Column(children: [
        const _Header(title: '채팅방', subtitle: null),
        const Expanded(child: _RoomNotFound()),
      ]);
    }

    final members = {for (final m in room?.members ?? const <RoomMember>[]) m.uid: m};
    if (room != null) _refreshIfUnknownSenders(chat.messages, members);

    return Column(
      children: [
        _Header(
          title: room == null ? '' : _titleOf(room, myUid),
          subtitle: room == null ? null : '${room.members.length}명',
          // 위치공유는 그룹 방 기능이라 DM에서는 버튼을 두지 않는다.
          onOpenLocation: room == null || room.type != RoomType.group
              ? null
              : () => context.push(AppRoutes.groupLocationOf(widget.roomId)),
          // DM은 같은 그룹 멤버끼리 연다(Plan D Task 5) — 그룹 방의 멤버 목록에서 시작한다.
          onOpenMembers: room == null || room.type != RoomType.group ? null : () => _openMembers(room, myUid),
        ),
        Expanded(
          child: Container(
            color: AppColors.chatBg,
            child: _body(chat, members, myUid),
          ),
        ),
        _InputBar(
          controller: _input,
          sending: chat.sending,
          onChanged: () => setState(() {}),
          onSend: _send,
          onAttach: room == null ? null : _attachImage,
        ),
      ],
    );
  }

  /// 멤버 목록을 띄우고, 거기서 DM을 열었으면 그 방으로 간다. 방 목록에 새 DM이 보이도록 목록도 새로 받는다.
  Future<void> _openMembers(RoomDetail room, String? myUid) async {
    final dm = await showModalBottomSheet<RoomDetail>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MembersSheet(members: room.members, myUid: myUid),
    );
    if (dm == null || !mounted) return;
    ref.invalidate(myRoomsProvider);
    context.push(AppRoutes.groupChatOf(dm.id));
  }

  String _titleOf(RoomDetail room, String? myUid) {
    if (room.type == RoomType.group) return room.name ?? '그룹';
    final peer = room.members.where((m) => m.uid != myUid).firstOrNull;
    return peer?.label ?? '알 수 없음';
  }

  Widget _body(ChatRoomState chat, Map<String, RoomMember> members, String? myUid) {
    if (chat.loading) return const Center(child: CircularProgressIndicator());
    if (chat.loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('메시지를 불러오지 못했어요', style: AppTextStyles.body),
            TextButton(
              key: const Key('chatRetry'),
              onPressed: () => ref.read(chatRoomControllerProvider(widget.roomId).notifier).retry(),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }
    final messages = chat.messages;
    final pending = chat.pendingImages;
    if (messages.isEmpty && pending.isEmpty) {
      return Center(
        key: const Key('emptyChat'),
        child: Text(
          '첫 메시지를 보내 보세요',
          style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
        ),
      );
    }

    // reverse 목록이라 index 0이 맨 아래(가장 최신)다. 맨 아래에는 아직 올리는 중인 내 사진을 두고(가장 최근에
    // 보낸 것이 맨 아래), 그 위로 메시지를 둔다. 각 메시지 "위"에 날짜가 바뀌면 날짜 구분선을 둔다 —
    // 즉 바로 다음(더 오래된) 메시지와 날짜가 다르거나 더 오래된 메시지가 없을 때.
    final controller = ref.read(chatRoomControllerProvider(widget.roomId).notifier);
    // 멤버별 읽음 위치(Task 7): 들어올 때 받은 값과 그 뒤 실시간으로 받은 값 중 큰 쪽.
    final readPositions = {
      for (final member in members.values)
        member.uid: max(member.lastReadMessageId ?? 0, chat.readPositions[member.uid] ?? 0),
    };
    // 이 메시지를 아직 안 읽은 멤버 수 — 보낸 사람은 빼고 센다. 0이면 표시하지 않는다.
    int unreadOf(ChatMessage m) =>
        readPositions.entries.where((e) => e.key != m.senderUid && e.value < m.id).length;
    final itemCount = pending.length + messages.length + (chat.loadingMore ? 1 : 0);
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index < pending.length) {
          final p = pending[pending.length - 1 - index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _PendingImageBubble(
              key: Key('pending-${p.localId}'),
              pending: p,
              onRetry: () => controller.retryImage(p.localId),
              onDiscard: () => controller.discardImage(p.localId),
            ),
          );
        }
        final i = index - pending.length;
        if (i == messages.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final m = messages[i];
        final older = i + 1 < messages.length ? messages[i + 1] : null;
        final showDate = older == null || !_sameDay(older.createdAt, m.createdAt);
        final mine = m.senderUid == myUid;
        return Column(
          children: [
            if (showDate) ...[
              const SizedBox(height: 6),
              Center(child: _DatePill(label: _formatDate(m.createdAt))),
              const SizedBox(height: 14),
            ],
            mine
                ? _OutgoingTextMessage(key: Key('outgoing-${m.id}'), message: m, unread: unreadOf(m))
                : _IncomingTextMessage(
                    key: Key('incoming-${m.id}'),
                    message: m,
                    senderName: members[m.senderUid]?.label ?? '알 수 없음',
                    unread: unreadOf(m),
                  ),
            const SizedBox(height: 14),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle, this.onOpenLocation, this.onOpenMembers});

  final String title;
  final String? subtitle;

  /// 있으면 오른쪽에 멤버 목록 버튼을 둔다(그룹 방만). 멤버 목록에서 1:1 DM을 연다.
  final VoidCallback? onOpenMembers;

  /// 있으면 오른쪽에 위치공유 버튼을 둔다. 방 정보를 받아 멤버임이 확인된 뒤에만 준다 — 위치공유 화면은
  /// 같은 소켓 연결로 그 방의 위치를 구독하므로, 멤버가 아닌 방으로는 들어가지 않게 한다.
  final VoidCallback? onOpenLocation;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.dividerFaint)),
      ),
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.arrow_back, color: AppColors.textBody),
            onPressed: () => context.canPop() ? context.pop() : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Noto Sans KR',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontFamily: 'Noto Sans KR',
                      fontWeight: FontWeight.w400,
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onOpenMembers != null) ...[
            IconButton(
              key: const Key('openMembers'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.people_outline, color: AppColors.textSecondary),
              onPressed: onOpenMembers,
            ),
            const SizedBox(width: 14),
          ],
          if (onOpenLocation != null)
            IconButton(
              key: const Key('openLocationShare'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.location_on_outlined, color: AppColors.textSecondary),
              onPressed: onOpenLocation,
            ),
        ],
      ),
    );
  }
}

class _RoomNotFound extends StatelessWidget {
  const _RoomNotFound();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('roomNotFound'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '채팅방을 찾을 수 없어요.\n초대 코드로 참여한 방인지 확인해 주세요.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body,
        ),
      ),
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.stripeA,
        borderRadius: BorderRadius.circular(980),
      ),
      child: Text(label, style: AppTextStyles.caption.copyWith(fontSize: 10, color: AppColors.textSecondary)),
    );
  }
}

/// 말풍선 옆의 시각. 위에 아직 안 읽은 멤버 수를 붙인다(Task 7, 0이면 생략).
class _Time extends StatelessWidget {
  const _Time(this.at, {required this.messageId, this.unread = 0, this.alignEnd = false});

  final DateTime at;
  final int messageId;
  final int unread;

  /// 내 말풍선은 시각이 말풍선 왼쪽에 오므로 오른쪽(말풍선 쪽)에 붙인다.
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (unread > 0)
          Text(
            '$unread',
            key: Key('unread-$messageId'),
            style: AppTextStyles.caption.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        Text(
          formatClock(at),
          style: AppTextStyles.caption.copyWith(fontSize: 9, color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

const _bubbleText = TextStyle(fontFamily: 'Noto Sans KR', fontSize: 14, height: 1.4, color: AppColors.ink);

class _IncomingTextMessage extends StatelessWidget {
  const _IncomingTextMessage({
    super.key,
    required this.message,
    required this.senderName,
    required this.unread,
  });

  final ChatMessage message;
  final String senderName;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 30, height: 30, child: WireframePlaceholder(borderRadius: 10)),
        const SizedBox(width: 9),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(senderName, style: AppTextStyles.caption.copyWith(fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 5),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 240),
                      padding: message.type == MessageType.image
                          ? const EdgeInsets.all(4)
                          : const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
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
                      child: message.type == MessageType.image
                          ? _ChatImageView(key: Key('image-${message.id}'), imageUrl: message.imageUrl!)
                          : Text(message.text ?? '', style: _bubbleText),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _Time(message.createdAt, messageId: message.id, unread: unread),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OutgoingTextMessage extends StatelessWidget {
  const _OutgoingTextMessage({super.key, required this.message, required this.unread});

  final ChatMessage message;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _Time(message.createdAt, messageId: message.id, unread: unread, alignEnd: true),
        const SizedBox(width: 6),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 240),
            padding: message.type == MessageType.image
                ? const EdgeInsets.all(4)
                : const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: message.type == MessageType.image
                ? _ChatImageView(key: Key('image-${message.id}'), imageUrl: message.imageUrl!)
                : Text(message.text ?? '', style: _bubbleText.copyWith(color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

/// 말풍선 안의 사진(Plan D Task 6). 바이트는 토큰이 붙는 API로 받는다([chatImageBytesProvider]).
/// 누르면 화면 가득 크게 본다. 받지 못했으면 눌러서 다시 받는다.
class _ChatImageView extends ConsumerWidget {
  const _ChatImageView({super.key, required this.imageUrl});

  final String imageUrl;

  static const _size = Size(220, 165);

  /// 받기는 됐는데 그림으로 풀리지 않을 때(앞부분만 그림 형식이고 뒤가 잘린 파일 등). 서버는 앞부분 바이트로만
  /// 형식을 보므로 이런 파일도 올라올 수 있다 — 오류를 내는 대신 깨진 그림 표시로 대신한다.
  static Widget _broken(BuildContext context, Object error, StackTrace? stackTrace) => const _ImageSlot(
        child: Icon(Icons.broken_image_outlined, key: Key('brokenImage'), color: AppColors.textTertiary),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(chatImageBytesProvider(imageUrl));
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: bytes.when(
        loading: () => const _ImageSlot(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, _) => GestureDetector(
          onTap: () => ref.invalidate(chatImageBytesProvider(imageUrl)),
          child: const _ImageSlot(child: Icon(Icons.refresh, color: AppColors.textTertiary)),
        ),
        data: (data) => GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (dialogContext) => GestureDetector(
              onTap: () => Navigator.of(dialogContext).pop(),
              child: InteractiveViewer(
                child: Image.memory(data, key: const Key('imageFullScreen'), errorBuilder: _broken),
              ),
            ),
          ),
          child: Image.memory(
            data,
            width: _size.width,
            height: _size.height,
            fit: BoxFit.cover,
            errorBuilder: _broken,
          ),
        ),
      ),
    );
  }
}

/// 사진이 아직 없을 때(받는 중·실패) 자리를 같은 크기로 잡아 둔다 — 받고 나서 목록이 덜컹거리지 않게.
class _ImageSlot extends StatelessWidget {
  const _ImageSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _ChatImageView._size.width,
      height: _ChatImageView._size.height,
      color: AppColors.surface,
      alignment: Alignment.center,
      child: SizedBox(width: 24, height: 24, child: Center(child: child)),
    );
  }
}

/// 올리는 중이거나 올리지 못한 내 사진. 고른 사진을 바로 보여 주고, 실패하면 [다시 시도]·[지우기]를 둔다.
class _PendingImageBubble extends StatelessWidget {
  const _PendingImageBubble({
    super.key,
    required this.pending,
    required this.onRetry,
    required this.onDiscard,
  });

  final PendingImage pending;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: 0.5,
                child: Image.memory(
                  pending.bytes,
                  width: _ChatImageView._size.width,
                  height: _ChatImageView._size.height,
                  fit: BoxFit.cover,
                  // 디코딩할 수 없는 바이트여도 자리는 지킨다.
                  errorBuilder: (_, _, _) => const _ImageSlot(child: SizedBox()),
                ),
              ),
              if (!pending.failed) const CircularProgressIndicator(strokeWidth: 2),
            ],
          ),
        ),
        if (pending.failed) ...[
          const SizedBox(height: 4),
          Text(
            pending.error ?? '사진을 보내지 못했어요.',
            style: AppTextStyles.caption.copyWith(color: Theme.of(context).colorScheme.error),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 다시 해도 안 되는 실패(크기·형식)면 다시 시도는 두지 않는다.
              if (pending.error == null)
                TextButton(
                  key: Key('retryImage-${pending.localId}'),
                  onPressed: onRetry,
                  child: const Text('다시 시도'),
                ),
              TextButton(
                key: Key('discardImage-${pending.localId}'),
                onPressed: onDiscard,
                child: const Text('지우기'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onChanged,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onChanged;
  final VoidCallback onSend;

  /// 사진 고르기. 방 정보를 받기 전(멤버 확인 전)에는 null이라 버튼이 꺼진다.
  final VoidCallback? onAttach;

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trim().isNotEmpty && !sending;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('attachImage'),
            onPressed: onAttach,
            icon: const Icon(Icons.image_outlined, color: AppColors.textSecondary),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
              child: TextField(
                key: const Key('chatInput'),
                controller: controller,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000, // 서버 제한과 같다
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '메시지 입력',
                  border: InputBorder.none,
                  counterText: '',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('chatSend'),
            onPressed: canSend ? onSend : null,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.accent,
              disabledBackgroundColor: AppColors.placeholderPrimary,
            ),
            icon: sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }
}
