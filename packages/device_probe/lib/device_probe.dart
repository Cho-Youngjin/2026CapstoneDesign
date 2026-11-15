import 'package:flutter/services.dart';

/// 배터리 한 번 읽은 값. 기기가 지원하지 않는 값은 null이다(설계 문서 10장 위험 2).
class BatteryReading {
  const BatteryReading({
    required this.plugged,
    this.chargeUah,
    this.currentUa,
    this.levelPct,
    this.tempC,
  });

  static int? _positiveOrNull(int? v) => (v != null && v > 0) ? v : null;

  factory BatteryReading.fromMap(Map<String, Object?> map) => BatteryReading(
        // 일부 기기는 미지원 전하량을 MIN_VALUE 대신 0으로 돌려준다. 0μAh는 실제 값일 수 없으므로 '모름'으로 둔다.
        chargeUah: _positiveOrNull(map['chargeUah'] as int?),
        currentUa: map['currentUa'] as int?,
        levelPct: map['levelPct'] as int?,
        tempC: (map['tempC'] as num?)?.toDouble(),
        plugged: map['plugged'] as bool? ?? false,
      );

  /// BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER (μAh).
  final int? chargeUah;

  /// BatteryManager.BATTERY_PROPERTY_CURRENT_NOW (μA, 방전이면 음수인 기기가 많다).
  final int? currentUa;
  final int? levelPct;
  final double? tempC;
  final bool plugged;
}

class DeviceInfo {
  const DeviceInfo({required this.model, required this.sdkInt, required this.appVersion});

  factory DeviceInfo.fromMap(Map<String, Object?> map) => DeviceInfo(
        model: map['model'] as String,
        sdkInt: map['sdkInt'] as int,
        appVersion: map['appVersion'] as String? ?? 'unknown',
      );

  final String model;
  final int sdkInt;
  final String appVersion;
}

/// 배터리·기기 정보를 읽는다. 플러그인으로 등록되므로 기록 서비스 isolate에서도 같은 채널이 보인다.
class DeviceProbe {
  const DeviceProbe([this._channel = const MethodChannel('device_probe')]);

  final MethodChannel _channel;

  Future<BatteryReading> readBattery() async {
    final map = await _channel.invokeMapMethod<String, Object?>('readBattery');
    return BatteryReading.fromMap(map!);
  }

  Future<DeviceInfo> readDevice() async {
    final map = await _channel.invokeMapMethod<String, Object?>('readDevice');
    return DeviceInfo.fromMap(map!);
  }
}
