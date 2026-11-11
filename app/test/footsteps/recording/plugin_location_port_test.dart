import 'package:app/features/footsteps/recording/plugin_location_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

Position _position({double speed = 1.3, double heading = 270}) => Position(
      latitude: 37.5665,
      longitude: 126.978,
      timestamp: DateTime.utc(2026, 11, 11, 0, 59, 59),
      accuracy: 6.5,
      altitude: 38,
      altitudeAccuracy: 3,
      heading: heading,
      headingAccuracy: 10,
      speed: speed,
      speedAccuracy: 0.5,
    );

void main() {
  test('위치는 받은 시각으로 Fix가 되고, 음수 속도·방향은 모르는 값(null)이다', () {
    final receivedAt = DateTime.utc(2026, 11, 11, 1);
    final fix = fixFromPosition(_position(), receivedAt);
    expect(fix.tMs, receivedAt.millisecondsSinceEpoch);
    expect((fix.lat, fix.lng, fix.accuracyM), (37.5665, 126.978, 6.5));
    expect((fix.speedMps, fix.bearingDeg), (1.3, 270.0));

    final unknown = fixFromPosition(_position(speed: -1, heading: -1), receivedAt);
    expect((unknown.speedMps, unknown.bearingDeg), (null, null));
  });

  test('타이머 예약기는 예약한 시각에 부르고, 지난 시각이면 바로 부르며, 취소하면 부르지 않는다', () async {
    final scheduler = TimerWakeScheduler(clock: DateTime.now);
    final calls = <String>[];
    final now = DateTime.now().millisecondsSinceEpoch;

    scheduler.schedule(now + 30, () => calls.add('soon'));
    scheduler.schedule(now - 1000, () => calls.add('past'));
    final cancelled = scheduler.schedule(now + 30, () => calls.add('cancelled'));
    scheduler.cancel(cancelled);
    expect(calls, isEmpty); // schedule 안에서 바로 부르지 않는다

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(calls, ['past', 'soon']);
  });
}
