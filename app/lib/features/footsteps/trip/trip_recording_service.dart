import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart' show ServiceRequestFailure;

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

  /// 서비스가 이미 돌고 있으면(실험 세션이든 다른 여행이든) StateError로 거절하고, 돌고 있는 서비스의 설정은 건드리지 않는다.
  Future<void> start(TripPeriod trip);

  /// 여행 기록 모드로 도는 서비스만 끈다. 꺼져 있거나 실험 세션이면 아무것도 하지 않는다(실험 세션을 끄지 않는다).
  ///
  /// 한계: 서비스가 꺼지는 것과 기록 서비스 isolate가 마지막 쓰기(열려 있던 정지 구간 닫기, 대기 중인 위치 점)를 끝내는 것은
  /// 순서가 정해져 있지 않다. 플러그인은 서비스가 멈췄다고 알리는데 isolate의 onDestroy는 그 뒤에 끝날 수 있다. 그래서 이 호출이
  /// 돌아온 뒤에 그 여행의 정지 구간이나 점이 한 행 더 들어올 수 있다. 여행 기록을 지우는 호출자는 이 행이 남아도 다음
  /// updateTrips의 정리가 지운다는 점에 기댄다.
  Future<void> stop();
}

/// flutter_foreground_task로 기록 서비스를 여행 기록 모드로 켠다. 실험 화면과 같은 서비스·알림 채널을 쓴다(설계 4-1 D4).
/// Android 14부터 위치 포그라운드 서비스는 앱이 화면에 있을 때만 켤 수 있어, 앱이 포그라운드로 올 때만 부른다(설계 9-2).
class ForegroundTripRecordingService implements TripRecordingService {
  const ForegroundTripRecordingService([this._service = const PluginRecordingServiceGateway()]);

  final RecordingServiceGateway _service;

  @override
  Future<bool> isRunning() => _service.isRunning();

  @override
  Future<int?> recordingTripId() async {
    if (!await _service.isRunning()) return null;
    final raw = await _service.readConfig();
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
    // 설정은 돌고 있는 서비스도 읽는다. 거절될 시작이 먼저 덮어쓰지 않도록 저장 전에 확인한다.
    await ensureRecordingServiceIdle(_service);
    final config = RecordingConfig(mode: RecordingMode.trip, policy: tripPolicyChoice, trip: trip);
    await _service.saveConfig(jsonEncode(config.toJson()));
    final result = await _service.start(
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
    // 실험 세션이 도는 중이면 끄지 않는다(코디네이터는 recordingTripId로 먼저 확인하지만 그 사이에 바뀔 수 있다).
    if (await recordingTripId() == null) return;
    final result = await _service.stop();
    if (result is ServiceRequestFailure) {
      throw StateError('여행 기록을 멈추지 못했습니다: ${result.error}');
    }
  }
}
