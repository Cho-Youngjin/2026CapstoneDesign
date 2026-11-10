import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../recording/recording_providers.dart';
import '../recording/session_library.dart';

/// 기기에 저장된 세션 목록과 zip 공유(설계 4-3). [refreshToken]이 바뀌면 다시 읽는다 —
/// 기록을 끝낸 직후 새 세션이 목록에 바로 나타나게 하려고 실험 화면이 값을 올린다.
class LabSessionsPanel extends ConsumerStatefulWidget {
  const LabSessionsPanel({super.key, required this.refreshToken});

  final int refreshToken;

  @override
  ConsumerState<LabSessionsPanel> createState() => _LabSessionsPanelState();
}

class _LabSessionsPanelState extends ConsumerState<LabSessionsPanel> {
  late Future<List<SessionSummary>> _sessions;

  @override
  void initState() {
    super.initState();
    _sessions = ref.read(sessionLibraryProvider).list();
  }

  @override
  void didUpdateWidget(LabSessionsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _sessions = ref.read(sessionLibraryProvider).list();
    }
  }

  String _subtitle(SessionSummary s) {
    final size = (s.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
    final duration = s.duration;
    final time = duration == null ? '기록 중이거나 비정상 종료' : '${duration.inMinutes}분';
    return '${size}MB · $time · 오류 ${s.meta?.errors.length ?? 0}건';
  }

  Future<void> _share(SessionSummary session) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(sessionSharerProvider)(session);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('공유하지 못했습니다: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('세션', style: Theme.of(context).textTheme.titleMedium),
        const Text('PC: adb pull /sdcard/Android/data/com.travelfootsteps.app/files/sessions/'),
        FutureBuilder<List<SessionSummary>>(
          future: _sessions,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('목록을 읽지 못했습니다: ${snapshot.error}');
            final sessions = snapshot.data;
            if (sessions == null) return const LinearProgressIndicator();
            if (sessions.isEmpty) return const Text('저장된 세션이 없습니다.');
            return Column(
              children: [
                for (final session in sessions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(session.id),
                    subtitle: Text(_subtitle(session)),
                    trailing: IconButton(
                      key: Key('share-${session.id}'),
                      icon: const Icon(Icons.share),
                      tooltip: 'zip으로 공유',
                      onPressed: () => _share(session),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
