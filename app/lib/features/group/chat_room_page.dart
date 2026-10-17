import 'package:app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import 'data/chat_api.dart';
import 'data/chat_room_controller.dart';
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
/// 사진 첨부(Task 6)와 읽음 표시(Task 7)는 아직 없다.
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
        ),
      ],
    );
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
    if (messages.isEmpty) {
      return Center(
        key: const Key('emptyChat'),
        child: Text(
          '첫 메시지를 보내 보세요',
          style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
        ),
      );
    }

    // reverse 목록이라 index 0이 맨 아래(가장 최신)다. 각 메시지 "위"에 날짜가 바뀌면 날짜 구분선을 둔다 —
    // 즉 바로 다음(더 오래된) 메시지와 날짜가 다르거나 더 오래된 메시지가 없을 때.
    final itemCount = messages.length + (chat.loadingMore ? 1 : 0);
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      itemBuilder: (context, i) {
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
                ? _OutgoingTextMessage(key: Key('outgoing-${m.id}'), message: m)
                : _IncomingTextMessage(
                    key: Key('incoming-${m.id}'),
                    message: m,
                    senderName: members[m.senderUid]?.label ?? '알 수 없음',
                  ),
            const SizedBox(height: 14),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle});

  final String title;
  final String? subtitle;

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
          // 위치공유 화면(R3 담당, Plan D Task 9에서 방 id와 연결)
          IconButton(
            key: const Key('openLocationShare'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.location_on_outlined, color: AppColors.textSecondary),
            onPressed: () => context.push(AppRoutes.groupLocation),
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

class _Time extends StatelessWidget {
  const _Time(this.at);

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatClock(at),
      style: AppTextStyles.caption.copyWith(fontSize: 9, color: AppColors.textTertiary),
    );
  }
}

const _bubbleText = TextStyle(fontFamily: 'Noto Sans KR', fontSize: 14, height: 1.4, color: AppColors.ink);

class _IncomingTextMessage extends StatelessWidget {
  const _IncomingTextMessage({super.key, required this.message, required this.senderName});

  final ChatMessage message;
  final String senderName;

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
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
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
                      child: Text(message.text ?? '', style: _bubbleText),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _Time(message.createdAt),
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
  const _OutgoingTextMessage({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _Time(message.createdAt),
        const SizedBox(width: 6),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 240),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(message.text ?? '', style: _bubbleText.copyWith(color: Colors.white)),
          ),
        ),
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
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onChanged;
  final VoidCallback onSend;

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
