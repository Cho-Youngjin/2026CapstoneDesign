import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'mark.dart';
import 'policy_choice.dart';
import 'recorder_status.dart';
import 'recording_config.dart';
import 'recording_messages.dart';
import 'recording_mode.dart';
import 'recording_task_handler.dart';

/// 실험 화면이 기록 서비스를 다루는 창구. 위젯 테스트는 가짜 구현을 넣는다.
abstract interface class RecordingController {
  Future<bool> isRunning();
  /// [policy]는 정책 실행 모드에서만 준다.
  Future<void> start({
    required RecordingMode mode,
    required String carryInitial,
    String? note,
    PolicyChoice? policy,
  });
  Future<void> stop();
  void sendMark(Mark mark);
  Stream<RecorderStatus> statusStream();
}

const _recordingServiceId = 7101;

/// 세션 폴더들의 상위 폴더. adb pull로 꺼낼 수 있게 앱 전용 외부 저장소
/// (`/sdcard/Android/data/<패키지>/files/sessions`)를 쓴다.
Future<Directory> defaultSessionsRoot() async {
  final external = await getExternalStorageDirectory();
  if (external == null) throw StateError('외부 저장소를 쓸 수 없습니다.');
  return Directory(p.join(external.path, 'sessions'));
}

class ForegroundRecordingController implements RecordingController {
  ForegroundRecordingController({
    this._sessionsRoot = defaultSessionsRoot,
    this._clock = DateTime.now,
  });

  final Future<Directory> Function() _sessionsRoot;
  final DateTime Function() _clock;

  void _initService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'footstep_recording',
        channelName: '발걸음 기록',
        channelDescription: '발걸음 실험·여행 기록이 진행 중일 때 표시됩니다.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // 5초마다 디스크에 쓰고 화면에 상태를 보낸다(설계 4-2).
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  @override
  Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  @override
  Future<void> start({
    required RecordingMode mode,
    required String carryInitial,
    String? note,
    PolicyChoice? policy,
  }) async {
    final root = await _sessionsRoot();
    final dir = Directory(p.join(root.path, sessionDirName(_clock(), mode)));
    await dir.create(recursive: true);
    final config = RecordingConfig(
      mode: mode,
      sessionDir: dir.path,
      carryInitial: carryInitial,
      note: note,
      policy: policy,
    );
    await FlutterForegroundTask.saveData(
      key: RecordingConfig.storageKey,
      value: jsonEncode(config.toJson()),
    );

    _initService();
    final result = await FlutterForegroundTask.startService(
      serviceId: _recordingServiceId,
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: '발걸음 실험 기록 중',
      notificationText: switch (mode) {
        RecordingMode.groundTruth => '정답 기록 모드 · 알림 버튼으로 도착·탑승을 표시하세요',
        RecordingMode.policy => '정책 실행 모드(${policy?.policyId}) · 알림 버튼으로 도착·탑승을 표시하세요',
      },
      notificationButtons: recordingNotificationButtons(FieldState()),
      callback: recordingStartCallback,
    );
    if (result is ServiceRequestFailure) {
      throw StateError('기록 서비스를 시작하지 못했습니다: ${result.error}');
    }
  }

  @override
  Future<void> stop() async {
    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestFailure) {
      throw StateError('기록 서비스를 멈추지 못했습니다: ${result.error}');
    }
  }

  @override
  void sendMark(Mark mark) => FlutterForegroundTask.sendDataToTask(encodeMarkMessage(mark));

  @override
  Stream<RecorderStatus> statusStream() {
    late final StreamController<RecorderStatus> controller;
    void onData(Object data) {
      final status = decodeStatusMessage(data);
      if (status != null) controller.add(status);
    }

    controller = StreamController<RecorderStatus>(
      onListen: () => FlutterForegroundTask.addTaskDataCallback(onData),
      onCancel: () => FlutterForegroundTask.removeTaskDataCallback(onData),
    );
    return controller.stream;
  }
}
