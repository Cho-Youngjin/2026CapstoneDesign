import 'dart:io';

import 'package:footstep_core/footstep_core.dart' show createDetector, createPolicy;

import 'ground_truth_recorder.dart';
import 'plugin_location_port.dart';
import 'plugin_sensor_sources.dart';
import 'policy_choice.dart';
import 'policy_recorder.dart';
import 'policy_session_files.dart';
import 'recording_config.dart';
import 'recording_mode.dart';
import 'session_files.dart';
import 'session_meta.dart';
import 'session_recorder.dart';

/// 기록 서비스가 모드에 맞는 기록기를 만든다. 플러그인을 직접 부르므로 기록 서비스 isolate 안에서만 쓴다.
/// 정책·감지기 설정이 잘못됐으면 파일을 만들기 전에 ArgumentError로 멈춘다(서비스가 시작 실패로 남긴다).
Future<SessionRecorder> openSessionRecorder(
  RecordingConfig config,
  Directory sessionDir, {
  required DateTime Function() clock,
  required void Function(SessionError error) onError,
}) async {
  switch (config.mode) {
    case RecordingMode.groundTruth:
      return GroundTruthRecorder(
        sources: PluginSensorSources(),
        files: await SessionFiles.open(sessionDir),
        clock: clock,
        onError: onError,
      );
    case RecordingMode.policy:
      final choice = config.policy;
      if (choice == null) throw StateError('정책 실행 모드인데 고른 정책이 없습니다.');
      final policy = createPolicy(choice.policyId, choice.policyParams);
      final detector = createDetector(choice.detectorId, choice.detectorParams);
      return PolicyRecorder(
        sources: PluginSensorSources(),
        files: await PolicySessionFiles.open(sessionDir),
        clock: clock,
        onError: onError,
        policy: policy,
        detector: detector,
        location: GeolocatorLocationPort(clock: clock),
        scheduler: TimerWakeScheduler(clock: clock),
        needs: PolicySensorNeeds.of(choice),
      );
    case RecordingMode.trip:
      // 여행 기록은 세션 파일 없이 앱 DB에 쓴다 — TripRecordingTaskHandler가 TripRecorder를 직접 연다.
      throw StateError('여행 기록 모드는 실험 세션 기록기로 열지 않습니다.');
  }
}
