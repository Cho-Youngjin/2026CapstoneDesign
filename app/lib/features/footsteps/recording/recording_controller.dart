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

  /// 지금 도는 기록의 설정(시작할 때 저장한 것). 기록 중이 아니거나 읽을 수 없으면 null이다. 기록 중에 실험 화면을
  /// 다시 열었을 때 어떤 모드·정책으로 도는지 보여 주는 데 쓴다.
  Future<RecordingConfig?> activeConfig();
}

/// 기록 서비스의 서비스 id. 실험 모드와 여행 기록이 같은 서비스 하나를 번갈아 쓴다(설계 4-1 — 동시에 돌지 않는다).
const recordingServiceId = 7101;

/// 기록 서비스 플러그인(flutter_foreground_task)을 부르는 창구. 실험 화면과 여행 기록이 같은 서비스·같은 설정 저장소를
/// 쓰므로 둘이 한 창구를 공유한다. 테스트는 가짜로 바꿔 어떤 설정을 저장하고 무엇을 켜고 껐는지 본다.
abstract interface class RecordingServiceGateway {
  Future<bool> isRunning();

  /// 시작할 때 저장한 [RecordingConfig] JSON. 없으면 null이다.
  Future<String?> readConfig();

  Future<void> saveConfig(String json);

  /// 알림 채널을 맞춘 뒤 위치 포그라운드 서비스를 켠다. 이미 돌고 있으면 플러그인이 실패 결과를 돌려준다.
  Future<ServiceRequestResult> start({
    required String notificationTitle,
    required String notificationText,
    required Function callback,
    List<NotificationButton>? notificationButtons,
  });

  Future<ServiceRequestResult> stop();
}

/// [RecordingServiceGateway]의 실제 구현. 플러그인을 그대로 부른다.
class PluginRecordingServiceGateway implements RecordingServiceGateway {
  const PluginRecordingServiceGateway();

  @override
  Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  @override
  Future<String?> readConfig() => FlutterForegroundTask.getData<String>(key: RecordingConfig.storageKey);

  @override
  Future<void> saveConfig(String json) => FlutterForegroundTask.saveData(key: RecordingConfig.storageKey, value: json);

  @override
  Future<ServiceRequestResult> start({
    required String notificationTitle,
    required String notificationText,
    required Function callback,
    List<NotificationButton>? notificationButtons,
  }) {
    initRecordingService();
    return FlutterForegroundTask.startService(
      serviceId: recordingServiceId,
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: notificationTitle,
      notificationText: notificationText,
      notificationButtons: notificationButtons,
      callback: callback,
    );
  }

  @override
  Future<ServiceRequestResult> stop() => FlutterForegroundTask.stopService();
}

/// 서비스가 이미 돌고 있으면 던진다. 설정을 저장하기 전에 불러야 한다 — 거절될 시작이 돌고 있는 서비스의 설정(모드·여행)을
/// 덮어쓰면, 서비스는 그대로인데 화면은 다른 모드로 보게 된다(예: 실험 화면의 낡은 [기록 시작]이 여행 기록을 실험 세션으로 바꾼다).
Future<void> ensureRecordingServiceIdle(RecordingServiceGateway gateway) async {
  if (await gateway.isRunning()) {
    throw StateError('기록 서비스가 이미 돌고 있어 새로 시작하지 않습니다.');
  }
}

/// 기록 서비스의 알림 채널·반복 주기를 정한다. 실험 화면(ForegroundRecordingController)과 여행 기록
/// (ForegroundTripRecordingService)이 서비스를 켜기 전에 똑같이 부른다.
void initRecordingService() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'footstep_recording',
      channelName: '발걸음 기록',
      channelDescription: '발걸음 실험·여행 기록이 진행 중일 때 표시됩니다.',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      // 5초마다 디스크에 쓰고 화면에 상태를 보낸다(설계 4-2). 여행 기록은 이 주기에 날짜를 확인한다(설계 9-2).
      eventAction: ForegroundTaskEventAction.repeat(5000),
      // 재부팅 뒤에는 다시 켜지 않는다 — 여행 기록은 다음에 앱을 열 때 다시 켜진다(설계 9-2).
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );
}

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
    this._service = const PluginRecordingServiceGateway(),
  });

  final Future<Directory> Function() _sessionsRoot;
  final DateTime Function() _clock;
  final RecordingServiceGateway _service;

  @override
  Future<bool> isRunning() => _service.isRunning();

  @override
  Future<void> start({
    required RecordingMode mode,
    required String carryInitial,
    String? note,
    PolicyChoice? policy,
  }) async {
    if (mode == RecordingMode.trip) {
      throw ArgumentError('여행 기록은 실험 화면이 아니라 ForegroundTripRecordingService로 켭니다.');
    }
    await ensureRecordingServiceIdle(_service);
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
    await _service.saveConfig(jsonEncode(config.toJson()));

    final result = await _service.start(
      notificationTitle: '발걸음 실험 기록 중',
      notificationText: switch (mode) {
        RecordingMode.groundTruth => '정답 기록 모드 · 알림 버튼으로 도착·탑승을 표시하세요',
        RecordingMode.policy => '정책 실행 모드(${policy?.policyId}) · 알림 버튼으로 도착·탑승을 표시하세요',
        RecordingMode.trip => '', // 위에서 막았다
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
    final result = await _service.stop();
    if (result is ServiceRequestFailure) {
      throw StateError('기록 서비스를 멈추지 못했습니다: ${result.error}');
    }
  }

  @override
  void sendMark(Mark mark) => FlutterForegroundTask.sendDataToTask(encodeMarkMessage(mark));

  @override
  Future<RecordingConfig?> activeConfig() async {
    if (!await _service.isRunning()) return null;
    final raw = await _service.readConfig();
    if (raw == null) return null;
    try {
      return RecordingConfig.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      // 앞 버전이 저장한 다른 모양의 설정이면 보여 줄 수 없을 뿐, 기록은 서비스가 이어 간다.
      return null;
    }
  }

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
