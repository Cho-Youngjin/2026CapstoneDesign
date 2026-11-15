import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footstep_core/footstep_core.dart'
    show createDetector, createPolicy, detectorIds, parseKeyValues, policyIds;

import '../recording/mark.dart';
import '../recording/policy_choice.dart';
import '../recording/recorder_status.dart';
import '../recording/recording_config.dart';
import '../recording/recording_mode.dart';
import '../recording/recording_providers.dart';
import 'lab_marks_panel.dart';
import 'lab_mode_panel.dart';
import 'lab_permissions_panel.dart';
import 'lab_sessions_panel.dart';
import 'lab_status_card.dart';

/// 숨은 실험 화면(설계 4-3). 세계지도 아래 '방문 국가 … 총 걸음' 문구를 길게 눌러 연다.
class LabPage extends ConsumerStatefulWidget {
  const LabPage({super.key});

  @override
  ConsumerState<LabPage> createState() => _LabPageState();
}

class _LabPageState extends ConsumerState<LabPage> {
  bool _running = false;

  /// 지금 도는 것이 앱이 켠 여행 기록(R7)인가. 실험 화면에서 고를 수 있는 모드가 아니라 안내만 한다.
  bool _tripRecording = false;
  bool _busy = false;
  String? _error;
  RecorderStatus? _status;
  String _carry = CarryPosition.hand;
  RecordingMode _mode = RecordingMode.groundTruth;
  String _policyId = 'step_budget';
  String _detectorId = 'adaptive';
  final _paramsController = TextEditingController();
  int _sessionsVersion = 0;
  StreamSubscription<RecorderStatus>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(recordingControllerProvider);
    _statusSubscription = controller.statusStream().listen((status) {
      if (!mounted) return;
      setState(() {
        _status = status;
        // 서비스가 휴대 위치의 기준이다. 화면이 새로 열렸거나 알림에서 바뀐 경우에도 실제 값을 따른다.
        final carry = status.carry;
        if (carry != null) _carry = carry;
      });
    });
    controller.isRunning().then((running) async {
      if (!mounted) return;
      setState(() => _running = running);
      if (!running) return;
      // 기록 중에 화면을 다시 열면, 고르는 칸이 기본값이 아니라 지금 도는 세션의 설정을 보여 줘야 한다.
      final config = await controller.activeConfig();
      if (mounted && config != null) setState(() => _showConfig(config));
    });
  }

  void _showConfig(RecordingConfig config) {
    if (config.mode == RecordingMode.trip) {
      // 모드 선택은 기본값으로 둔다. 그대로 두면 [기록 종료] 뒤 [기록 시작]이 여행 기록 모드로 실험을 켜려 한다.
      _tripRecording = true;
      return;
    }
    _mode = config.mode;
    final policy = config.policy;
    if (policy == null) return;
    // 목록에 없는 이름(앞 버전의 설정)을 고르면 목록 상자가 그려지지 않으니 그때는 기본값을 둔다.
    if (policyIds.contains(policy.policyId)) _policyId = policy.policyId;
    if (detectorIds.contains(policy.detectorId)) _detectorId = policy.detectorId;
    _paramsController.text = [
      for (final entry in policy.policyParams.entries) '${entry.key}=${entry.value}',
    ].join(' ');
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _paramsController.dispose();
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
            _tripRecording = false;
            _status = null;
            _sessionsVersion++;
          });
        }
      } else {
        final policy = _mode == RecordingMode.policy ? _policyChoice() : null;
        await controller.start(mode: _mode, carryInitial: _carry, policy: policy);
        if (mounted) setState(() => _running = true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 화면에서 고른 정책 설정. 시작 전에 footstep_core 목록으로 한 번 만들어 보아, 파라미터 오타는 서비스를 켜기 전에
  /// 알린다(서비스 안에서 실패하면 알림만 잠깐 떴다 사라진다).
  PolicyChoice _policyChoice() {
    final params = parseKeyValues(
      _paramsController.text.split(RegExp(r'\s+')).where((pair) => pair.isNotEmpty),
    );
    createPolicy(_policyId, params);
    createDetector(_detectorId);
    return PolicyChoice(policyId: _policyId, policyParams: params, detectorId: _detectorId);
  }

  void _changeCarry(String position) {
    if (position == _carry) return;
    setState(() => _carry = position);
    // 기록 중이면 바뀐 시각을 표시로 남긴다. 시작 전이면 meta.json의 carryInitial로만 들어간다.
    if (_running) {
      ref.read(recordingControllerProvider).sendMark(
            Mark(at: DateTime.now().toUtc(), kind: MarkKind.carry, value: position),
          );
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
          Text('기록 모드', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          LabModePanel(
            mode: _mode,
            policyId: _policyId,
            detectorId: _detectorId,
            paramsController: _paramsController,
            enabled: !_running && !_busy,
            onModeChanged: (mode) => setState(() => _mode = mode),
            onPolicyChanged: (id) => setState(() => _policyId = id),
            onDetectorChanged: (id) => setState(() => _detectorId = id),
          ),
          const SizedBox(height: 8),
          const Text('휴대 위치'),
          LabCarrySelector(value: _carry, onChanged: _changeCarry),
          const SizedBox(height: 8),
          if (_running && _tripRecording)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '여행 기록 중이에요. [기록 종료]를 누르면 여행 기록을 멈추고 실험을 시작할 수 있어요. '
                '여행 기록은 다음에 앱을 열 때 다시 켜져요.',
                key: Key('lab-trip-recording'),
              ),
            ),
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
          const SizedBox(height: 16),
          LabMarksPanel(
            enabled: _running,
            atPlace: _status?.atPlace ?? false,
            onVehicle: _status?.onVehicle ?? false,
          ),
          const SizedBox(height: 16),
          LabSessionsPanel(refreshToken: _sessionsVersion),
        ],
      ),
    );
  }
}
