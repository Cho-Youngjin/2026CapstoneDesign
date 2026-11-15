import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

List<PolicyAction> activity(CollectionPolicy policy, int tMs, String type, String confidence) =>
    policy.onEvent(ActivityUpdate(tMs: tMs, type: type, confidence: confidence),
        PolicyContext(nowMs: tMs));

void main() {
  test('시작하면 연속 측위를 켜고, 확실한 정지면 끄고, 확실한 움직임이면 다시 켠다', () {
    final policy = ActivityGatedPolicy();

    expect(policy.onStart(const PolicyContext(nowMs: 0)),
        [const StartContinuous(intervalMs: 1000, distanceFilterM: 10)]);
    expect(activity(policy, 1000, 'STILL', 'HIGH'), [const StopContinuous()]);
    expect(activity(policy, 2000, 'STILL', 'HIGH'), isEmpty); // 이미 꺼짐
    expect(activity(policy, 3000, 'WALKING', 'MEDIUM'),
        [const StartContinuous(intervalMs: 1000, distanceFilterM: 10)]);
    expect(activity(policy, 4000, 'IN_VEHICLE', 'HIGH'), isEmpty); // 이미 켜짐
    expect(policy.id, 'activity_gated');
  });

  test('신뢰도가 낮거나 모르는 활동은 무시한다', () {
    final policy = ActivityGatedPolicy()..onStart(const PolicyContext(nowMs: 0));

    expect(activity(policy, 1000, 'STILL', 'LOW'), isEmpty);
    expect(activity(policy, 2000, 'UNKNOWN', 'HIGH'), isEmpty);
  });
}
