import 'package:flutter/material.dart';

import '../recording/recorder_status.dart';

String formatElapsed(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  final seconds = d.inSeconds % 60;
  return hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '${two(minutes)}:${two(seconds)}';
}

/// 기록 서비스가 5초마다 보내는 상태. 실기기 점검 때 "센서가 지금 값을 내고 있는가"를 눈으로 본다.
class LabStatusCard extends StatelessWidget {
  const LabStatusCard({super.key, required this.status, required this.running, this.now});

  final RecorderStatus? status;
  final bool running;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (!running) return const Text('기록 중이 아닙니다.');
    if (s == null) return const Text('상태를 기다리는 중… (5초마다 갱신)');

    final elapsed = (now ?? DateTime.now)().toUtc().difference(s.startedAt);
    final accuracy = s.lastGpsAccuracyM;
    final charge = s.lastChargeUah;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('경과 ${formatElapsed(elapsed)}'),
            for (final entry in s.rowCounts.entries) Text('${entry.key}: ${entry.value}행'),
            Text('GPS 정확도: ${accuracy == null ? '-' : '${accuracy.toStringAsFixed(1)} m'}'),
            Text('OS 누적 걸음: ${s.lastOsSteps ?? '-'}'),
            Text('배터리: ${s.lastLevelPct ?? '-'}% · 전하량 ${charge == null ? '지원 안 함' : '$charge μAh'}'),
            Text('현장 상태: ${s.atPlace ? '장소 안' : '이동 중'} · ${s.onVehicle ? '탈것 탑승 중' : '도보'}'),
            if (s.policyState != null)
              Text('정책 상태: ${s.policyState} · 측위 뒤 걸음: ${s.stepsSinceFix ?? '-'}'),
            Text('오류: ${s.errorCount}건'),
          ],
        ),
      ),
    );
  }
}
