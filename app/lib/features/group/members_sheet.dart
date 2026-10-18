import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'data/chat_api.dart';
import 'group_sheets.dart' show groupErrorMessage;
import 'models/room.dart';

/// 그룹 멤버 목록 시트(채팅방 상단 멤버 아이콘). 다른 멤버의 [메시지]를 누르면 1:1 DM을 열고
/// 그 방을 돌려준다(Plan D Task 5). 닫으면 null.
///
/// DM은 같은 그룹 멤버끼리만 열 수 있어(서버 규칙) 이 목록이 DM을 시작하는 곳이다.
class MembersSheet extends ConsumerStatefulWidget {
  const MembersSheet({super.key, required this.members, required this.myUid});

  final List<RoomMember> members;
  final String? myUid;

  @override
  ConsumerState<MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends ConsumerState<MembersSheet> {
  /// DM을 여는 중인 상대. 그동안 다른 버튼은 막는다.
  String? _opening;
  String? _error;

  Future<void> _openDm(RoomMember peer) async {
    setState(() {
      _opening = peer.uid;
      _error = null;
    });
    try {
      final dm = await ref.read(chatApiProvider).openDm(peer.uid);
      if (mounted) Navigator.of(context).pop(dm);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _opening = null;
        // 404는 "같은 그룹이 아님"이다(그사이 그 사람이 다른 기기에서 계정을 바꿨거나 하는 드문 경우).
        _error = e is RoomNotFoundException
            ? '같은 그룹 멤버에게만 메시지를 보낼 수 있어요.'
            : groupErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 나를 맨 위에 두고 나머지는 참여한 순서 그대로.
    final members = [
      ...widget.members.where((m) => m.uid == widget.myUid),
      ...widget.members.where((m) => m.uid != widget.myUid),
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('멤버 ${members.length}', style: AppTextStyles.screenTitle),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const Key('membersSheetError'),
                    style: AppTextStyles.caption.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: members.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.dividerFaint),
                  itemBuilder: (_, i) {
                    final m = members[i];
                    final isMe = m.uid == widget.myUid;
                    return _MemberRow(
                      key: Key('member-${m.uid}'),
                      name: isMe ? '${m.label} (나)' : m.label,
                      action: isMe
                          ? null
                          : _opening == m.uid
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : TextButton(
                                  key: Key('dm-${m.uid}'),
                                  onPressed: _opening == null ? () => _openDm(m) : null,
                                  child: const Text('메시지'),
                                ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({super.key, required this.name, required this.action});

  final String name;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
            child: Text(
              name.isEmpty ? '?' : name.characters.first,
              style: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body),
          ),
          ?action,
        ],
      ),
    );
  }
}
