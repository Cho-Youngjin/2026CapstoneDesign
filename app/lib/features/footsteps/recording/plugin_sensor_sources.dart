import 'dart:async';

import 'package:device_probe/device_probe.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'sensor_samples.dart';

/// [SensorSources]의 실제 구현. 기록 서비스 isolate 안에서 플러그인을 직접 부른다.
class PluginSensorSources implements SensorSources {
  PluginSensorSources({DateTime Function()? clock, this._probe = const DeviceProbe()})
      : _clock = clock ?? (() => DateTime.now().toUtc());

  final DateTime Function() _clock;
  final DeviceProbe _probe;

  /// 1초 간격, 거리 필터 없음 — 정답 경로라 움직이지 않아도 매초 남긴다(설계 4-2).
  @override
  Stream<GpsSample> gps() => Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 1),
        ),
      ).map((position) => gpsSampleFromPosition(position, _clock()));

  /// 약 50Hz(20ms). 걸음은 초당 2회 안팎이라 이 정도면 피크를 놓치지 않는다.
  @override
  Stream<AccelSample> accel() =>
      accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 20)).map(
        (e) => AccelSample(at: accelTimestamp(e.timestamp, _clock()), x: e.x, y: e.y, z: e.z),
      );

  @override
  Stream<OsStepSample> osSteps() => mergeStreams([
        Pedometer.stepCountStream.map(
          (s) => OsStepSample(at: _clock(), kind: OsStepKind.count, value: '${s.steps}'),
        ),
        Pedometer.pedestrianStatusStream.map(
          (s) => OsStepSample(at: _clock(), kind: OsStepKind.status, value: s.status),
        ),
      ]);

  @override
  Stream<ActivitySample> activity() => FlutterActivityRecognition.instance.activityStream.map(
        (a) => ActivitySample(at: _clock(), type: a.type.name, confidence: a.confidence.name),
      );

  @override
  Future<BatterySample> readBattery() async {
    final reading = await _probe.readBattery();
    return BatterySample(
      at: _clock(),
      chargeUah: reading.chargeUah,
      currentUa: reading.currentUa,
      levelPct: reading.levelPct,
      tempC: reading.tempC,
      plugged: reading.plugged,
    );
  }
}

GpsSample gpsSampleFromPosition(Position position, DateTime recordedAt) => GpsSample(
      at: recordedAt,
      fixTime: position.timestamp.toUtc(),
      lat: position.latitude,
      lng: position.longitude,
      accuracyM: position.accuracy,
      speedMps: position.speed,
      bearingDeg: position.heading,
      altitudeM: position.altitude,
    );

/// 가속도 이벤트는 OS가 묶어서 늦게 전달할 수 있어 받은 시각보다 센서 이벤트 시각이 정확하다.
/// 다만 기기에 따라 이벤트 시각의 기준이 다를 수 있어(부팅 후 경과 시간 등) 기록 시각과
/// 10초 넘게 차이 나면 기록 시각을 쓴다 — 같은 시계 규칙(설계 4-2)을 깨지 않기 위해서다.
DateTime accelTimestamp(DateTime eventTime, DateTime recordedAt) {
  final event = eventTime.toUtc();
  return event.difference(recordedAt).abs() > const Duration(seconds: 10) ? recordedAt : event;
}

/// 여러 스트림을 하나로 합친다(package:async의 StreamGroup.merge와 같은 동작). 의존성을 늘리지 않으려고
/// 직접 둔다.
Stream<T> mergeStreams<T>(List<Stream<T>> streams) {
  final subscriptions = <StreamSubscription<T>>[];
  late final StreamController<T> controller;
  controller = StreamController<T>(
    onListen: () {
      for (final stream in streams) {
        subscriptions.add(stream.listen(controller.add, onError: controller.addError));
      }
    },
    onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    },
  );
  return controller.stream;
}
