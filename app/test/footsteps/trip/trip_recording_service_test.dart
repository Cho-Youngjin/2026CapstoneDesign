import 'dart:convert';
import 'dart:io';

import 'package:app/features/footsteps/recording/recording_config.dart';
import 'package:app/features/footsteps/recording/recording_controller.dart';
import 'package:app/features/footsteps/recording/recording_mode.dart';
import 'package:app/features/footsteps/trip/trip_recording_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';

import 'trip_fakes.dart';

/// 기록 서비스 플러그인 대역. 저장한 설정·켜고 끈 횟수를 남기고, 이미 돌고 있으면 실제처럼 시작을 거절한다.
class FakeServiceGateway implements RecordingServiceGateway {
  bool running = false;
  String? config;
  int saves = 0;
  int starts = 0;
  int stops = 0;

  @override
  Future<bool> isRunning() async => running;

  @override
  Future<String?> readConfig() async => config;

  @override
  Future<void> saveConfig(String json) async {
    saves++;
    config = json;
  }

  @override
  Future<ServiceRequestResult> start({
    required String notificationTitle,
    required String notificationText,
    required Function callback,
    List<NotificationButton>? notificationButtons,
  }) async {
    if (running) return ServiceRequestFailure(error: ServiceAlreadyStartedException());
    starts++;
    running = true;
    return const ServiceRequestSuccess();
  }

  @override
  Future<ServiceRequestResult> stop() async {
    if (!running) return ServiceRequestFailure(error: ServiceNotStartedException());
    stops++;
    running = false;
    return const ServiceRequestSuccess();
  }
}

void main() {
  late FakeServiceGateway gateway;
  late Directory sessions;
  final trip = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));
  final other = period(8, DateTime(2026, 12, 1), DateTime(2026, 12, 5), iso2: 'JP', nameKo: '일본');

  setUp(() async {
    gateway = FakeServiceGateway();
    sessions = await Directory.systemTemp.createTemp('trip_recording_service_test');
  });

  tearDown(() => sessions.delete(recursive: true));

  ForegroundTripRecordingService tripService() => ForegroundTripRecordingService(gateway);
  ForegroundRecordingController lab() =>
      ForegroundRecordingController(sessionsRoot: () async => sessions, service: gateway);

  test('여행 기록을 켜면 여행 기록 설정을 저장하고, 그 여행 id를 돌려준다', () async {
    await tripService().start(trip);

    expect(gateway.starts, 1);
    expect(await tripService().recordingTripId(), 7);
    final saved = RecordingConfig.fromJson((jsonDecode(gateway.config!) as Map).cast<String, Object?>());
    expect(saved.mode, RecordingMode.trip);
  });

  test('실험 화면의 낡은 [기록 시작]이 거절돼도 돌고 있는 여행 기록의 설정은 그대로다', () async {
    await tripService().start(trip);
    final before = gateway.config;

    await expectLater(
      lab().start(mode: RecordingMode.groundTruth, carryInitial: 'hand'),
      throwsStateError,
    );

    expect(gateway.config, before);
    expect(gateway.saves, 1);
    expect(await tripService().recordingTripId(), 7); // 코디네이터가 계속 끌 수 있다
    expect(sessions.listSync(), isEmpty); // 세션 폴더도 만들지 않는다
  });

  test('실험 세션이 도는 중에 여행 기록을 켜려 해도 거절되고 실험 세션의 설정은 그대로다', () async {
    await lab().start(mode: RecordingMode.groundTruth, carryInitial: 'hand');
    final before = gateway.config;

    await expectLater(tripService().start(other), throwsStateError);

    expect(gateway.config, before);
    expect(gateway.saves, 1);
    expect(await tripService().recordingTripId(), isNull);
  });

  test('여행 기록 시작이 거절돼도 이미 도는 다른 여행의 설정을 덮어쓰지 않는다', () async {
    await tripService().start(trip);

    await expectLater(tripService().start(other), throwsStateError);

    expect(await tripService().recordingTripId(), 7);
    expect(gateway.saves, 1);
  });

  test('여행 기록 서비스는 실험 세션을 끄지 않는다', () async {
    await lab().start(mode: RecordingMode.groundTruth, carryInitial: 'hand');

    await tripService().stop();

    expect(gateway.stops, 0);
    expect(gateway.running, isTrue);
  });

  test('여행 기록 서비스는 여행 기록을 끈다', () async {
    await tripService().start(trip);

    await tripService().stop();

    expect(gateway.stops, 1);
    expect(gateway.running, isFalse);
  });

  test('아무것도 돌지 않을 때 끄라고 해도 오류 없이 넘어간다', () async {
    await tripService().stop();

    expect(gateway.stops, 0);
  });
}
