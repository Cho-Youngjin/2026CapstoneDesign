import 'package:flutter/material.dart';
import 'package:footstep_core/footstep_core.dart' show detectorIds, policyIds;

import '../recording/recording_mode.dart';

/// 기록 모드 선택(설계 4-1). 정책 실행 모드(배터리 실험)는 정책·걸음 감지기·파라미터를 고른다. 기록 중에는 바꿀 수
/// 없다 — 한 세션은 한 설정으로만 돈다.
class LabModePanel extends StatelessWidget {
  const LabModePanel({
    super.key,
    required this.mode,
    required this.policyId,
    required this.detectorId,
    required this.paramsController,
    required this.enabled,
    required this.onModeChanged,
    required this.onPolicyChanged,
    required this.onDetectorChanged,
  });

  final RecordingMode mode;
  final String policyId;
  final String detectorId;
  final TextEditingController paramsController;
  final bool enabled;
  final ValueChanged<RecordingMode> onModeChanged;
  final ValueChanged<String> onPolicyChanged;
  final ValueChanged<String> onDetectorChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<RecordingMode>(
          key: const Key('lab-mode'),
          segments: const [
            ButtonSegment(value: RecordingMode.groundTruth, label: Text('정답 기록')),
            ButtonSegment(value: RecordingMode.policy, label: Text('정책 실행')),
          ],
          selected: {mode},
          onSelectionChanged: enabled ? (selection) => onModeChanged(selection.single) : null,
        ),
        if (mode == RecordingMode.policy) ...[
          const SizedBox(height: 8),
          // 좁은 폰·큰 글꼴에서도 넘치지 않게 목록 상자가 남은 폭을 채운다.
          Row(
            children: [
              const Text('정책 '),
              Expanded(
                child: DropdownButton<String>(
                  key: const Key('lab-policy'),
                  isExpanded: true,
                  value: policyId,
                  items: [
                    for (final id in policyIds) DropdownMenuItem(value: id, child: Text(id)),
                  ],
                  onChanged: enabled ? (id) => onPolicyChanged(id!) : null,
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('걸음 감지기 '),
              Expanded(
                child: DropdownButton<String>(
                  key: const Key('lab-detector'),
                  isExpanded: true,
                  value: detectorId,
                  items: [
                    for (final id in detectorIds) DropdownMenuItem(value: id, child: Text(id)),
                  ],
                  onChanged: enabled ? (id) => onDetectorChanged(id!) : null,
                ),
              ),
            ],
          ),
          TextField(
            key: const Key('lab-policy-params'),
            controller: paramsController,
            enabled: enabled,
            // 폰 키보드가 e_m 같은 이름을 고치거나 띄어 쓰면, 모르는 사이 다른 설정으로 실험이 돈다.
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '정책 파라미터',
              helperText: '빈칸으로 구분, 예: e_m=50 use_steps=false',
              helperMaxLines: 2,
            ),
          ),
        ],
      ],
    );
  }
}
