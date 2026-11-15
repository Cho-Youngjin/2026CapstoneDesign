import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../recording/recording_providers.dart';
import 'recording_permissions.dart';

class LabPermissionsPanel extends ConsumerStatefulWidget {
  const LabPermissionsPanel({super.key});

  @override
  ConsumerState<LabPermissionsPanel> createState() => _LabPermissionsPanelState();
}

class _LabPermissionsPanelState extends ConsumerState<LabPermissionsPanel> {
  List<PermissionItem>? _items;

  Future<void> _request() async {
    final items = await ref.read(recordingPermissionRequesterProvider)();
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('권한', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton(
              key: const Key('lab-permissions'),
              onPressed: _request,
              child: const Text('확인·요청'),
            ),
          ],
        ),
        if (items != null)
          for (final item in items) Text('${item.label}: ${item.granted ? '허용' : '거부'}'),
      ],
    );
  }
}
