import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

void main() {
  test('위도 1도는 약 111,195m이고, 같은 점은 0m다', () {
    expect(haversineMeters(37.0, 127.0, 38.0, 127.0), closeTo(111195, 1));
    expect(haversineMeters(37.5, 127.0, 37.5, 127.0), 0);
  });

  test('할 일은 값으로 비교하고, actions.csv용 이름과 인자를 낸다', () {
    expect(const RequestFix(), const RequestFix());
    expect(const RequestFix(timeoutMs: 5000), isNot(const RequestFix()));
    expect(const WakeAt(tMs: 61000, tag: 'tick'), const WakeAt(tMs: 61000, tag: 'tick'));

    expect(const RequestFix().logName, 'request_fix');
    expect(const RequestFix().logArgs, 'timeout_ms=15000');
    expect(const StartContinuous(intervalMs: 1000, distanceFilterM: 10).logName, 'start_continuous');
    expect(const StartContinuous(intervalMs: 1000, distanceFilterM: 10).logArgs,
        'interval_ms=1000 distance_filter_m=10.0');
    expect(const StopContinuous().logName, 'stop_continuous');
    expect(const StopContinuous().logArgs, '');
    expect(const WakeAt(tMs: 61000, tag: 'tick').logName, 'wake_at');
    expect(const WakeAt(tMs: 61000, tag: 'tick').logArgs, 't_ms=61000 tag=tick');
  });

  test('FixResult는 위치가 없으면 실패다', () {
    const fix = Fix(tMs: 1000, lat: 37.5, lng: 127.0, accuracyM: 5);
    expect(const FixResult(tMs: 1000, fix: fix).failed, isFalse);
    expect(const FixResult(tMs: 16000).failed, isTrue);
  });

  test('OS 걸음 읽기의 kind 상수는 os_steps.csv 계약과 같다', () {
    expect(OsStepReading.count, 'count');
    expect(OsStepReading.status, 'status');
  });
}
