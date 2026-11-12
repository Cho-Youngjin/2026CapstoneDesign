import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../recording/recording_config.dart';
import '../recording/recording_controller.dart';
import '../recording/recording_mode.dart';
import 'trip_period.dart';
import 'trip_recorder.dart';
import 'trip_recording_task_handler.dart';

/// 화면 isolate가 여행 기록 서비스를 다루는 창구. 테스트는 가짜로 바꿔 무엇을 켜고 껐는지 본다.
abstract interface class TripRecordingService {
  /// 기록 서비스가 돌고 있는가(실험 세션 포함).
  Future<bool> isRunning();

  /// 여행 기록 모드로 도는 중이면 그 여행 id. 실험 세션이거나 꺼져 있으면 null이다.
  Future<int?> recordingTripId();

  Future<void> start(TripPeriod trip);

  Future<void> stop();
}

/// flutter_foreground_task로 기록 서비스를 여행 기록 모드로 켠다. 실험 화면과 같은 서비스·알림 채널을 쓴다(설계 4-1 D4).
/// Android 14부터 위치 포그라운드 서비스는 앱이 화면에 있을 때만 켤 수 있어, 앱이 포그라운드로 올 때만 부른다(설계 9-2).
class ForegroundTripRecordingService implements TripRecordingService {
  const ForegroundTripRecordingService();

  @override
  Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  @override
  Future<int?> recordingTripId() async {
    if (!await FlutterForegroundTask.isRunningService) return null;
    final raw = await FlutterForegroundTask.getData<String>(key: RecordingConfig.storageKey);
    if (raw == null) return null;
    try {
      final config = RecordingConfig.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
      return config.mode == RecordingMode.trip ? config.trip?.tripId : null;
    } catch (_) {
      return null; // 읽을 수 없는 설정이면 실험 세션으로 보고 건드리지 않는다
    }
  }

  @override
  Future<void> start(TripPeriod trip) async {
    final config = RecordingConfig(mode: RecordingMode.trip, policy: tripPolicyChoice, trip: trip);
    await FlutterForegroundTask.saveData(key: RecordingConfig.storageKey, value: jsonEncode(config.toJson()));
    initRecordingService();
    final result = await FlutterForegroundTask.startService(
      serviceId: recordingServiceId,
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: '${trip.countryNameKo} 여행 발걸음 기록 중',
      notificationText: '귀국 다음 날 0시에 스스로 꺼져요 · 여행 상세에서 일시정지할 수 있어요',
      callback: tripRecordingStartCallback,
    );
    if (result is ServiceRequestFailure) {
      throw StateError('여행 기록을 시작하지 못했습니다: ${result.error}');
    }
  }

  @override
  Future<void> stop() async {
    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestFailure) {
      throw StateError('여행 기록을 멈추지 못했습니다: ${result.error}');
    }
  }
}
