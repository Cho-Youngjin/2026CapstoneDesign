import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'data/chat_api.dart';
import 'data/profile_sync.dart';
import 'data/room_providers.dart';
import 'models/room.dart';

/// 그룹 화면에서 쓰는 오류 안내 문구.
String groupErrorMessage(Object error) {
  if (error is RoomNotFoundException) return '코드를 찾을 수 없어요. 다시 확인해 주세요.';
  if (error is DioException) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return '서버에 연결할 수 없어요. 네트워크를 확인해 주세요.';
    }
    if (error.response?.statusCode == 400) return '입력값을 다시 확인해 주세요.';
  }
  return '잠시 후 다시 시도해 주세요.';
}

/// 그룹 만들기 시트를 열고, 만든 방을 돌려준다(취소하면 null).
Future<RoomDetail?> showCreateGroupSheet(BuildContext context) {
  return showModalBottomSheet<RoomDetail>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CreateGroupSheet(),
  );
}

/// 초대 코드로 참여 시트를 열고, 참여한 방을 돌려준다(취소하면 null).
Future<RoomDetail?> showJoinGroupSheet(BuildContext context) {
  return showModalBottomSheet<RoomDetail>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _JoinGroupSheet(),
  );
}

/// 키보드가 올라와도 시트 내용이 가려지지 않게 아래 여백을 키보드 높이만큼 준다.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTextStyles.screenTitle),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        message,
        style: AppTextStyles.caption.copyWith(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

// ───────────────────────── 그룹 만들기 ─────────────────────────

class _CreateGroupSheet extends ConsumerStatefulWidget {
  const _CreateGroupSheet();

  @override
  ConsumerState<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends ConsumerState<_CreateGroupSheet> {
  /// 서버 제한(chat_room.name 50자)과 같다.
  static const _maxNameLength = 50;

  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  String get _name => _controller.text.trim();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // 방을 만들면 다른 멤버가 내 이름을 보게 되므로 그 전에 프로필을 맞춘다.
      await ref.read(profileSyncProvider).ensureUploaded();
      final room = await ref.read(chatApiProvider).createRoom(_name);
      ref.invalidate(myRoomsProvider);
      if (mounted) Navigator.of(context).pop(room);
    } catch (e) {
      if (mounted) setState(() => _error = groupErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _name.isNotEmpty && !_submitting;
    return _SheetFrame(
      title: '그룹 만들기',
      children: [
        TextField(
          key: const Key('createGroupName'),
          controller: _controller,
          autofocus: true,
          maxLength: _maxNameLength,
          decoration: const InputDecoration(
            labelText: '그룹 이름',
            hintText: '예: 다낭 4인방',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => canSubmit ? _submit() : null,
        ),
        if (_error != null) _ErrorText(_error!),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('createGroupSubmit'),
          onPressed: canSubmit ? _submit : null,
          child: Text(_submitting ? '만드는 중…' : '만들기'),
        ),
      ],
    );
  }
}

// ───────────────────────── 코드로 참여 ─────────────────────────

/// 입력을 대문자로 바꾼다 — 서버도 대문자로 맞추지만, 화면에서 바로 보여야 덜 헷갈린다.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

class _JoinGroupSheet extends ConsumerStatefulWidget {
  const _JoinGroupSheet();

  @override
  ConsumerState<_JoinGroupSheet> createState() => _JoinGroupSheetState();
}

class _JoinGroupSheetState extends ConsumerState<_JoinGroupSheet> {
  static const _codeLength = 6;

  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(profileSyncProvider).ensureUploaded();
      final room = await ref.read(chatApiProvider).joinRoom(_controller.text.toUpperCase());
      ref.invalidate(myRoomsProvider);
      if (mounted) Navigator.of(context).pop(room);
    } catch (e) {
      if (mounted) setState(() => _error = groupErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _controller.text.length == _codeLength && !_submitting;
    return _SheetFrame(
      title: '초대 코드로 참여',
      children: [
        TextField(
          key: const Key('joinCodeField'),
          controller: _controller,
          autofocus: true,
          maxLength: _codeLength,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
            _UpperCaseFormatter(),
          ],
          style: AppTextStyles.screenTitle.copyWith(letterSpacing: 6),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            hintText: '6자리 코드',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => canSubmit ? _submit() : null,
        ),
        if (_error != null) _ErrorText(_error!),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('joinSubmit'),
          onPressed: canSubmit ? _submit : null,
          child: Text(_submitting ? '참여하는 중…' : '참여하기'),
        ),
      ],
    );
  }
}

// ───────────────────────── 만든 뒤 초대 코드 안내 ─────────────────────────

/// 방을 만든 직후 초대 코드를 보여준다. 결과로 "채팅방으로 갈지"를 돌려준다.
Future<bool> showInviteCodeDialog(BuildContext context, RoomDetail room) async {
  final goToRoom = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('inviteCodeDialog'),
      title: Text('${room.name ?? '그룹'} 만들었어요'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('일행에게 이 코드를 알려 주세요', style: AppTextStyles.caption),
          const SizedBox(height: 12),
          SelectableText(
            room.inviteCode ?? '',
            style: AppTextStyles.screenTitle.copyWith(
              fontSize: 28,
              letterSpacing: 6,
              color: AppColors.accent,
            ),
          ),
          TextButton.icon(
            key: const Key('inviteCodeCopy'),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('복사'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: room.inviteCode ?? ''));
              if (dialogContext.mounted) {
                ScaffoldMessenger.maybeOf(dialogContext)
                    ?.showSnackBar(const SnackBar(content: Text('초대 코드를 복사했어요')));
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('inviteCodeClose'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('닫기'),
        ),
        FilledButton(
          key: const Key('inviteCodeOpenRoom'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('채팅방 열기'),
        ),
      ],
    ),
  );
  return goToRoom ?? false;
}
