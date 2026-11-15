/// 기록 서비스가 받는 센서 값들. 모든 [at]은 같은 시계(UTC)다 — 설계 4-2의 '같은 시계' 규칙이라
/// 재생기가 파일들을 시각순으로 합칠 수 있다.
class GpsSample {
  const GpsSample({
    required this.at,
    required this.fixTime,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    this.speedMps,
    this.bearingDeg,
    this.altitudeM,
  });

  /// 앱이 값을 받은 시각.
  final DateTime at;

  /// GPS가 알려 준 측위 시각.
  final DateTime fixTime;
  final double lat;
  final double lng;
  final double accuracyM;
  final double? speedMps;
  final double? bearingDeg;
  final double? altitudeM;

  List<Object?> toCsvRow() => [
        at.millisecondsSinceEpoch,
        fixTime.millisecondsSinceEpoch,
        lat,
        lng,
        accuracyM,
        speedMps,
        bearingDeg,
        altitudeM,
      ];
}

class AccelSample {
  const AccelSample({required this.at, required this.x, required this.y, required this.z});

  final DateTime at;
  final double x;
  final double y;
  final double z;

  List<Object?> toCsvRow() => [at.millisecondsSinceEpoch, x, y, z];
}

/// `os_steps.csv`의 kind 값(설계 4-2).
abstract final class OsStepKind {
  /// value = 부팅 후 누적 걸음 수.
  static const count = 'count';

  /// value = OS 보행 상태(`walking`·`stopped`·`unknown`).
  static const status = 'status';
}

class OsStepSample {
  const OsStepSample({required this.at, required this.kind, required this.value});

  final DateTime at;
  final String kind;
  final String value;

  List<Object?> toCsvRow() => [at.millisecondsSinceEpoch, kind, value];
}

class ActivitySample {
  const ActivitySample({required this.at, required this.type, required this.confidence});

  final DateTime at;
  final String type;
  final String confidence;

  List<Object?> toCsvRow() => [at.millisecondsSinceEpoch, type, confidence];
}

class BatterySample {
  const BatterySample({
    required this.at,
    required this.plugged,
    this.chargeUah,
    this.currentUa,
    this.levelPct,
    this.tempC,
  });

  final DateTime at;

  /// 남은 전하량(μAh). 기기가 지원하지 않으면 null.
  final int? chargeUah;
  final int? currentUa;
  final int? levelPct;
  final double? tempC;
  final bool plugged;

  List<Object?> toCsvRow() =>
      [at.millisecondsSinceEpoch, chargeUah, currentUa, levelPct, tempC, plugged];
}

/// 기록에 쓰는 센서 묶음. 실제 구현은 플러그인(plugin_sensor_sources.dart)이고, 테스트는 가짜를 넣는다.
abstract interface class SensorSources {
  Stream<GpsSample> gps();
  Stream<AccelSample> accel();
  Stream<OsStepSample> osSteps();
  Stream<ActivitySample> activity();
  Future<BatterySample> readBattery();
}
