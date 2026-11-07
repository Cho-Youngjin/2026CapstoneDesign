import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../recording/mark.dart';
import '../recording/recorder_status.dart';
import '../recording/recording_mode.dart';
import '../recording/recording_providers.dart';
import 'lab_permissions_panel.dart';
import 'lab_status_card.dart';

/// 숨은 실험 화면(설계 4-3). 세계지도 아래 '방문 국가 … 총 걸음' 문구를 길게 눌러 연다.
class LabPage extends ConsumerStatefulWidget {
  const LabPage({super.key});

  @override
  ConsumerState<LabPage> createState() => _LabPageState();
}

class _LabPageState extends ConsumerState<LabPage> {
  bool _running = false;
  bool _busy = false;
  String? _error;
  RecorderStatus? _status;
  String _carry = CarryPosition.hand;
  StreamSubscription<RecorderStatus>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(recordingControllerProvider);
    _statusSubscription = controller.statusStream().listen((status) {
      if (mounted) setState(() => _status = status);
    });
    controller.isRunning().then((running) {
      if (mounted) setState(() => _running = running);
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    final controller = ref.read(recordingControllerProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_running) {
        await controller.stop();
        if (mounted) {
          setState(() {
            _running = false;
            _status = null;
          });
        }
      } else {
        await controller.start(mode: RecordingMode.groundTruth, carryInitial: _carry);
        if (mounted) setState(() => _running = true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('발걸음 실험')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const LabPermissionsPanel(),
          const SizedBox(height: 16),
          Text('정답 기록 모드', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('lab-start-stop'),
            onPressed: _busy ? null : _toggle,
            child: Text(_running ? '기록 종료' : '기록 시작'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          LabStatusCard(status: _status, running: _running),
        ],
      ),
    );
  }
}
