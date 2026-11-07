import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:device_probe/device_probe.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as p;

import 'ground_truth_recorder.dart';
import 'mark.dart';
import 'plugin_sensor_sources.dart';
import 'recording_config.dart';
import 'recording_messages.dart';
import 'session_files.dart';
import 'session_meta.dart';

const placeButtonId = 'mark_place';
const vehicleButtonId = 'mark_vehicle';

/// 알림 버튼 두 개(도착/출발, 탑승/하차 토글). Android는 알림 버튼을 최대 3개까지만 보여 준다.
List<NotificationButton> recordingNotificationButtons(FieldState field) => [
      NotificationButton(id: placeButtonId, text: field.placeButtonLabel),
      NotificationButton(id: vehicleButtonId, text: field.vehicleButtonLabel),
    ];

/// 기록 서비스 isolate의 진입점. startService(callback:)로 넘기므로 top-level이어야 한다.
@pragma('vm:entry-point')
void recordingStartCallback() {
  FlutterForegroundTask.setTaskHandler(RecordingTaskHandler());
}

/// 기록 서비스 본체. 화면과 다른 isolate에서 돌므로 Riverpod 등 화면 쪽 상태를 쓰지 않는다.
/// R1은 정답 기록 모드만 있다. R4·R7이 [RecordingConfig.mode]로 갈라 다른 기록기를 붙인다.
class RecordingTaskHandler extends TaskHandler {
  GroundTruthRecorder? _recorder;
  SessionMetaStore? _metaStore;
  SessionMeta? _meta;

  DateTime _now() => DateTime.now().toUtc();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 이 isolate에서 Dart 쪽 등록이 필요한 플러그인(geolocator_android 등)을 쓰려면 먼저 불러야 한다.
    DartPluginRegistrant.ensureInitialized();

    final raw = await FlutterForegroundTask.getData<String>(key: RecordingConfig.storageKey);
    if (raw == null) {
      await FlutterForegroundTask.stopService();
      return;
    }
    final config = RecordingConfig.fromJson(jsonDecode(raw) as Map<String, Object?>);
    final files = await SessionFiles.open(Directory(config.sessionDir));
    _metaStore = files.meta;
    _meta = await files.meta.read() ?? await _newMeta(config);
    if (starter == TaskStarter.system) {
      // 시스템이 서비스를 죽였다 다시 띄웠다. 같은 세션 폴더에 이어 쓰되, 공백 구간을 분석에서 알 수 있게 남긴다.
      _meta = _meta!.withError(
        SessionError(at: _now(), source: 'service', message: 'restarted by system'),
      );
    }
    await files.meta.write(_meta!);

    final recorder = GroundTruthRecorder(
      sources: PluginSensorSources(),
      files: files,
      clock: _now,
      onError: _addError,
    );
    _recorder = recorder;
    await recorder.start();
  }

  Future<SessionMeta> _newMeta(RecordingConfig config) async {
    // 기기 정보는 부가 정보다. 읽지 못해도 기록 자체는 시작한다.
    DeviceInfo device;
    try {
      device = await const DeviceProbe().readDevice();
    } catch (_) {
      device = const DeviceInfo(model: 'unknown', sdkInt: 0, appVersion: 'unknown');
    }
    return SessionMeta(
      sessionId: p.basename(config.sessionDir),
      mode: config.mode,
      deviceModel: device.model,
      androidSdk: device.sdkInt,
      appVersion: device.appVersion,
      startedAt: _now(),
      carryInitial: config.carryInitial,
      note: config.note,
    );
  }

  void _addError(SessionError error) {
    final meta = _meta;
    final store = _metaStore;
    if (meta == null || store == null) return;
    _meta = meta.withError(error);
    // 메타 쓰기 실패는 달리 보고할 곳이 없다. 기다리지 않는 Future의 오류가 서비스 isolate에서
    // 잡히지 않은 예외로 새지 않도록 삼킨다.
    unawaited(store.write(_meta!).catchError((Object _) {}));
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    final recorder = _recorder;
    if (recorder == null) return;
    unawaited(_tickAndReport(recorder));
  }

  Future<void> _tickAndReport(GroundTruthRecorder recorder) async {
    // tick을 기다리지 않고 부르므로, 실패하면 오류가 잡히지 않은 채 서비스 isolate 밖으로 샌다.
    // 세션 오류로 남기고, 화면 상태는 tick 성공 여부와 상관없이 계속 보낸다.
    try {
      await recorder.tick();
    } catch (e) {
      _addError(SessionError(at: _now(), source: 'flush', message: '$e'));
    }
    FlutterForegroundTask.sendDataToMain(encodeStatusMessage(recorder.status));
  }

  @override
  void onReceiveData(Object data) {
    final mark = decodeMarkMessage(data);
    if (mark != null) _applyMark(mark);
  }

  @override
  void onNotificationButtonPressed(String id) {
    final recorder = _recorder;
    if (recorder == null) return;
    final mark = switch (id) {
      placeButtonId => recorder.field.nextPlaceMark(_now()),
      vehicleButtonId => recorder.field.nextVehicleMark(_now()),
      _ => null,
    };
    if (mark != null) _applyMark(mark);
  }

  void _applyMark(Mark mark) {
    final recorder = _recorder;
    if (recorder == null) return;
    recorder.mark(mark);
    unawaited(FlutterForegroundTask.updateService(
      notificationButtons: recordingNotificationButtons(recorder.field),
    ));
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _recorder?.stop();
    final meta = _meta;
    final store = _metaStore;
    if (meta != null && store != null) {
      _meta = meta.copyWith(endedAt: _now());
      await store.write(_meta!);
    }
  }
}
