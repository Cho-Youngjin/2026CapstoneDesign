import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../recording/mark.dart';
import '../recording/recording_providers.dart';

/// 관찰 표시 버튼(설계 4-2 `marks.csv`). 시각은 버튼을 누른 순간이다 — 이름을 입력하는 동안
/// 걸어도 도착 시각이 밀리지 않게 대화상자를 띄우기 전에 잡는다.
class LabMarksPanel extends ConsumerWidget {
  const LabMarksPanel({
    super.key,
    required this.enabled,
    required this.atPlace,
    required this.onVehicle,
  });

  final bool enabled;
  final bool atPlace;
  final bool onVehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 대화상자를 기다린 뒤에도 쓰므로 미리 잡아 둔다(await 뒤에 context를 쓰지 않는다).
    final controller = ref.read(recordingControllerProvider);
    final messenger = ScaffoldMessenger.of(context);

    void send(Mark mark) {
      controller.sendMark(mark);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('표시함: ${mark.kind.csvName} ${mark.value}')));
    }

    VoidCallback? simple(MarkKind kind, [String value = '']) => enabled
        ? () => send(Mark(at: DateTime.now().toUtc(), kind: kind, value: value))
        : null;

    VoidCallback? asking(
      MarkKind kind,
      String title, {
      bool numeric = false,
      bool allowEmpty = true,
    }) {
      if (!enabled) return null;
      return () async {
        final at = DateTime.now().toUtc();
        // 빈 값·숫자 아님은 대화상자가 닫히기 전에 걸러 낸다. 여기서 null은 취소뿐이다.
        final text = await _askText(context, title, numeric: numeric, allowEmpty: allowEmpty);
        if (text == null) return;
        send(Mark(at: at, kind: kind, value: text));
      };
    }

    Widget button(String key, String label, VoidCallback? onPressed) => OutlinedButton(
          key: Key(key),
          onPressed: onPressed,
          child: Text(label),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('관찰 표시', style: Theme.of(context).textTheme.titleMedium),
        Text('지금: ${atPlace ? '장소 안' : '이동 중'} · ${onVehicle ? '탈것 탑승 중' : '도보'}'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            button('mark-arrive', '도착', asking(MarkKind.arrive, '장소 이름(선택)')),
            button('mark-depart', '출발', simple(MarkKind.depart)),
            button('mark-board-bus', '버스 탑승', simple(MarkKind.board, VehicleType.bus)),
            button('mark-board-subway', '지하철 탑승', simple(MarkKind.board, VehicleType.subway)),
            button('mark-alight', '하차', simple(MarkKind.alight)),
            button('mark-count-start', '걸음 세기 시작', simple(MarkKind.countStart)),
            button(
              'mark-count-end',
              '걸음 세기 끝',
              asking(MarkKind.countEnd, '센 걸음 수', numeric: true, allowEmpty: false),
            ),
            button('mark-note', '메모', asking(MarkKind.note, '메모', allowEmpty: false)),
          ],
        ),
      ],
    );
  }
}

Future<String?> _askText(
  BuildContext context,
  String title, {
  required bool numeric,
  required bool allowEmpty,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(title: title, numeric: numeric, allowEmpty: allowEmpty),
    );

/// 글 한 줄을 받는 대화상자. 입력 컨트롤러를 대화상자 State가 들고 dispose한다 — pop 직후에 바로
/// 해제하면 닫히는 애니메이션 동안 TextField가 해제된 컨트롤러를 써서 오류가 난다.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.numeric,
    required this.allowEmpty,
  });

  final String title;
  final bool numeric;
  final bool allowEmpty;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 잘못된 입력이면 닫지 않고 이유를 보여 준다 — 조용히 버려지면 기록한 줄 착각하게 된다.
  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty && !widget.allowEmpty) {
      setState(() => _errorText = '내용을 입력하세요');
      return;
    }
    if (widget.numeric && !RegExp(r'^\d+$').hasMatch(text)) {
      setState(() => _errorText = '숫자만 입력하세요');
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('mark-dialog-field'),
        controller: _controller,
        autofocus: true,
        keyboardType: widget.numeric ? TextInputType.number : TextInputType.text,
        inputFormatters: widget.numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(errorText: _errorText),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
        TextButton(
          key: const Key('mark-dialog-ok'),
          onPressed: _submit,
          child: const Text('확인'),
        ),
      ],
    );
  }
}

/// 휴대 위치 선택. 위치에 따라 걸음 감지 결과가 달라 분석 때 나눠 본다.
class LabCarrySelector extends StatelessWidget {
  const LabCarrySelector({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _labels = {
    CarryPosition.hand: '손',
    CarryPosition.pocket: '주머니',
    CarryPosition.bag: '가방',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final position in CarryPosition.all)
          ChoiceChip(
            key: Key('carry-$position'),
            label: Text(_labels[position]!),
            selected: value == position,
            onSelected: (_) => onChanged(position),
          ),
      ],
    );
  }
}
