import 'package:device_probe/device_probe.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('device_probe');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('readBattery는 네이티브 값을 옮기고, 기기가 모르는 값은 null로 둔다', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readBattery');
      return <String, Object?>{
        'chargeUah': 3012000,
        'currentUa': null,
        'levelPct': 87,
        'tempC': 31.5,
        'plugged': false,
      };
    });

    final reading = await const DeviceProbe().readBattery();
    expect(reading.chargeUah, 3012000);
    expect(reading.currentUa, isNull);
    expect(reading.levelPct, 87);
    expect(reading.tempC, 31.5);
    expect(reading.plugged, isFalse);
  });

  test('전하량 0은 지원 안 함으로 보고 null로 둔다', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{
        'chargeUah': 0,
        'currentUa': 0,
        'levelPct': 50,
        'tempC': 30.0,
        'plugged': false,
      };
    });

    final reading = await const DeviceProbe().readBattery();
    expect(reading.chargeUah, isNull);
    // 전류 0은 실제 측정값일 수 있어 그대로 둔다.
    expect(reading.currentUa, 0);
  });

  test('readDevice는 기종·SDK·앱 버전을 돌려준다', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readDevice');
      return <String, Object?>{'model': 'samsung SM-S921N', 'sdkInt': 35, 'appVersion': '1.0.0'};
    });

    final info = await const DeviceProbe().readDevice();
    expect(info.model, 'samsung SM-S921N');
    expect(info.sdkInt, 35);
    expect(info.appVersion, '1.0.0');
  });
}
