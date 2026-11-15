import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:device_probe/device_probe.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as p;

import 'mark.dart';
import 'recording_config.dart';
import 'recording_messages.dart';
import 'recording_mode.dart';
import 'session_marks.dart';
import 'session_meta.dart';
import 'session_recorder.dart';
import 'session_recorder_factory.dart';
import 'session_schema.dart';

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
/// [RecordingConfig.mode]에 맞는 기록기(정답 기록·정책 실행)를 붙이고, 모드와 상관없는 일(meta.json, 알림 버튼,
/// 5초 tick, 화면 상태 전달)만 맡는다.
class RecordingTaskHandler extends TaskHandler {
  SessionRecorder? _recorder;
  SessionMetaStore? _metaStore;
  SessionMeta? _meta;

  DateTime _now() => DateTime.now().toUtc();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 이 isolate에서 Dart 쪽 등록이 필요한 플러그인(geolocator_android 등)을 쓰려면 먼저 불러야 한다.
    DartPluginRegistrant.ensureInitialized();

    try {
      final raw = await FlutterForegroundTask.getData<String>(key: RecordingConfig.storageKey);
      if (raw == null) {
        await FlutterForegroundTask.stopService();
        return;
      }
      final config = RecordingConfig.fromJson(jsonDecode(raw) as Map<String, Object?>);
      final sessionPath = config.sessionDir;
      if (config.mode == RecordingMode.trip || sessionPath == null) {
        // 여행 기록 설정이다(TripRecordingTaskHandler가 맡는다). 실험 세션으로 열지 않는다.
        await FlutterForegroundTask.stopService();
        return;
      }
      final sessionDir = Directory(sessionPath);
      // 열기 전에 읽는다. 시스템이 서비스를 다시 띄운 경우 marks.csv에 이전 표시가 남아 있다.
      final previousMarks = await readSessionMarks(sessionDir);
      final metaStore = SessionMetaStore(File(p.join(sessionDir.path, SessionSchema.metaFile)));
      _metaStore = metaStore;
      _meta = await metaStore.read() ?? await _newMeta(config);
      if (starter == TaskStarter.system) {
        // 시스템이 서비스를 죽였다 다시 띄웠다. 같은 세션 폴더에 이어 쓰되, 공백 구간을 분석에서 알 수 있게 남긴다.
        _meta = _meta!.withError(
          SessionError(at: _now(), source: 'service', message: 'restarted by system'),
        );
      }
      await metaStore.write(_meta!);

      final recorder = await openSessionRecorder(config, sessionDir, clock: _now, onError: _addError);
      _recorder = recorder;
      // 새 기록기의 토글 상태는 비어 있다. 이어 쓰는 세션이면 이미 남은 표시를 다시 흘려 넣어(marks.csv에는
      // 다시 쓰지 않는다) 도착/출발·탑승/하차 버튼과 휴대 위치가 끊기기 전 상태에서 이어지게 한다.
      recorder.field.carry = config.carryInitial ?? CarryPosition.hand;
      for (final mark in previousMarks) {
        recorder.field.observe(mark);
      }
      if (previousMarks.isNotEmpty) {
        unawaited(FlutterForegroundTask.updateService(
          notificationButtons: recordingNotificationButtons(recorder.field),
        ));
      }
      await recorder.start();
    } catch (e) {
      // 시작에 실패했는데 알림만 남아 있으면 테스터가 기록되는 줄 알고 걷는다. 이유를 남기고 서비스를 끈다.
      await _recordStartFailure(e);
      await FlutterForegroundTask.stopService();
    }
  }

  /// 시작 실패를 meta.json에 남긴다. 메타 저장소가 아직 없거나 쓰기마저 실패하면 포기한다.
  Future<void> _recordStartFailure(Object error) async {
    final store = _metaStore;
    if (store == null) return;
    try {
      final meta = _meta ?? await store.read();
      if (meta == null) return;
      _meta = meta.withError(
        SessionError(at: _now(), source: 'service', message: 'start failed: $error'),
      );
      await store.write(_meta!);
    } catch (_) {
      // 달리 보고할 곳이 없다.
    }
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
      sessionId: p.basename(config.sessionDir!),
      mode: config.mode,
      deviceModel: device.model,
      androidSdk: device.sdkInt,
      appVersion: device.appVersion,
      startedAt: _now(),
      carryInitial: config.carryInitial ?? CarryPosition.hand,
      note: config.note,
      policy: config.policy,
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

  Future<void> _tickAndReport(SessionRecorder recorder) async {
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
    try {
      await _recorder?.stop();
    } finally {
      // 기록기를 닫다 실패해도 종료 시각은 남긴다. 분석이 세션 길이를 이 값으로 잰다.
      final meta = _meta;
      final store = _metaStore;
      if (meta != null && store != null) {
        _meta = meta.copyWith(endedAt: _now());
        await store.write(_meta!);
      }
    }
  }
}
