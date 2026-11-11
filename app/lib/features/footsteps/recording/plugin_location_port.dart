import 'dart:async';

import 'package:footstep_core/footstep_core.dart' show Fix, LocationPort, WakeScheduler;
import 'package:geolocator/geolocator.dart';

/// [LocationPort]의 실제 구현(geolocator, 설계 5-5). 정책 실행 모드에서 기록 서비스 isolate 안에서 부른다.
class GeolocatorLocationPort implements LocationPort {
  GeolocatorLocationPort({required this.clock});

  final DateTime Function() clock;

  @override
  Future<Fix?> currentFix({required int timeoutMs}) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(milliseconds: timeoutMs),
        ),
      );
      return fixFromPosition(position, clock());
    } on TimeoutException {
      // 제한 시간 안에 못 받았다(실내·지하철). 실행기가 실패로 정책에 알린다.
      return null;
    }
  }

  @override
  Stream<Fix> continuousFixes({required int intervalMs, required double distanceFilterM}) =>
      Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilterM.round(),
          intervalDuration: Duration(milliseconds: intervalMs),
        ),
      ).map((position) => fixFromPosition(position, clock()));
}

/// geolocator의 위치를 정책이 쓰는 [Fix]로 바꾼다. 시각은 앱이 받은 시각이다 — gps.csv의 t_ms와 같은 뜻이고,
/// 재생기도 이 시각을 '그 위치를 알 수 있게 된 때'로 쓴다. 속도·방향이 음수면 기기가 모르는 것이라 null이다.
Fix fixFromPosition(Position position, DateTime receivedAt) => Fix(
      tMs: receivedAt.millisecondsSinceEpoch,
      lat: position.latitude,
      lng: position.longitude,
      accuracyM: position.accuracy,
      speedMps: position.speed < 0 ? null : position.speed,
      bearingDeg: position.heading < 0 ? null : position.heading,
    );

/// [WakeScheduler]의 실제 구현. 기록 서비스는 부분 wake lock을 잡고 돌아서(설계 4-1) Dart 타이머가 깬다. 화면이
/// 꺼져 늦게 깨면 그 지연이 wakeups.csv에 남는다.
class TimerWakeScheduler implements WakeScheduler {
  TimerWakeScheduler({required this.clock});

  final DateTime Function() clock;

  @override
  Object schedule(int atMs, void Function() callback) {
    final delayMs = atMs - clock().millisecondsSinceEpoch;
    return Timer(Duration(milliseconds: delayMs < 0 ? 0 : delayMs), callback);
  }

  @override
  void cancel(Object handle) => (handle as Timer).cancel();
}
