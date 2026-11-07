import 'dart:async';

import 'package:app/features/footsteps/recording/plugin_sensor_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  test('Position을 GpsSample로 옮긴다: 받은 시각과 측위 시각을 따로 남긴다', () {
    final fixTime = DateTime.utc(2026, 11, 9, 1, 0, 0);
    final recordedAt = DateTime.utc(2026, 11, 9, 1, 0, 1);
    final position = Position(
      latitude: 37.5665,
      longitude: 126.978,
      timestamp: fixTime,
      accuracy: 6.5,
      altitude: 38.0,
      altitudeAccuracy: 3,
      heading: 270.0,
      headingAccuracy: 10,
      speed: 1.3,
      speedAccuracy: 0.5,
    );

    final sample = gpsSampleFromPosition(position, recordedAt);
    expect(sample.at, recordedAt);
    expect(sample.fixTime, fixTime);
    expect(sample.lat, 37.5665);
    expect(sample.lng, 126.978);
    expect(sample.accuracyM, 6.5);
    expect(sample.speedMps, 1.3);
    expect(sample.bearingDeg, 270.0);
    expect(sample.altitudeM, 38.0);
  });

  test('가속도는 센서 이벤트 시각을 쓰되, 기록 시각과 10초 넘게 다르면 기록 시각을 쓴다', () {
    final recordedAt = DateTime.utc(2026, 11, 9, 1);
    final close = recordedAt.subtract(const Duration(milliseconds: 40));
    expect(accelTimestamp(close, recordedAt), close);

    final bootClock = DateTime.utc(1970, 1, 3); // 부팅 후 경과 시간이 그대로 들어온 경우
    expect(accelTimestamp(bootClock, recordedAt), recordedAt);
  });

  test('mergeStreams는 두 스트림의 값과 오류를 하나로 내보내고, 취소하면 둘 다 끊는다', () async {
    final a = StreamController<int>();
    final b = StreamController<int>();
    final values = <int>[];
    final errors = <Object>[];

    final subscription = mergeStreams([a.stream, b.stream]).listen(values.add, onError: errors.add);
    a.add(1);
    b.add(2);
    b.addError(StateError('x'));
    await Future<void>.delayed(Duration.zero);

    expect(values, [1, 2]);
    expect(errors.single, isA<StateError>());

    await subscription.cancel();
    expect(a.hasListener, isFalse);
    expect(b.hasListener, isFalse);
  });
}
