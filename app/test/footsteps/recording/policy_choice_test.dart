import 'package:app/features/footsteps/recording/policy_choice.dart';
import 'package:app/features/footsteps/recording/recorder_status.dart';
import 'package:app/features/footsteps/recording/recording_messages.dart';
import 'package:flutter_test/flutter_test.dart';

const _choice = PolicyChoice(
  policyId: 'step_budget',
  policyParams: {'e_m': '25'},
  detectorId: 'adaptive',
  detectorParams: {'n_confirm': '6'},
);

void main() {
  test('고른 정책은 json으로 오가고 값으로 비교한다', () {
    final back = PolicyChoice.fromJson(_choice.toJson());
    expect(back, _choice);
    expect(back.hashCode, _choice.hashCode);
    expect(back == const PolicyChoice(policyId: 'step_budget', detectorId: 'adaptive'), isFalse);
    // 파라미터 하나만 달라도 다른 선택이다(정책 파라미터·감지기 파라미터 각각).
    const otherPolicyParams = PolicyChoice(
      policyId: 'step_budget',
      policyParams: {'e_m': '50'},
      detectorId: 'adaptive',
      detectorParams: {'n_confirm': '6'},
    );
    const otherDetectorParams = PolicyChoice(
      policyId: 'step_budget',
      policyParams: {'e_m': '25'},
      detectorId: 'adaptive',
      detectorParams: {'n_confirm': '5'},
    );
    expect(_choice == otherPolicyParams, isFalse);
    expect(_choice == otherDetectorParams, isFalse);
  });

  test('걸음 정보를 쓰는 정책만 걸음 감지기의 센서를 켜고, 활동 인식은 activity_gated만 켠다', () {
    PolicySensorNeeds needs(String policy, String detector) =>
        PolicySensorNeeds.of(PolicyChoice(policyId: policy, detectorId: detector));

    final adaptive = needs('step_budget', 'adaptive');
    expect((adaptive.accel, adaptive.osSteps, adaptive.activity), (true, false, false));
    final os = needs('still_suppress', 'os');
    expect((os.accel, os.osSteps, os.activity), (false, true, false));
    final gatedTimeSpeed = needs('time_speed_still', 'adaptive'); // EnTracked처럼 멈춤을 걸음 감지기로 본다
    expect((gatedTimeSpeed.accel, gatedTimeSpeed.osSteps, gatedTimeSpeed.activity), (true, false, false));
    final plainTimeSpeed = needs('time_speed', 'adaptive');
    expect((plainTimeSpeed.accel, plainTimeSpeed.osSteps, plainTimeSpeed.activity), (false, false, false));
    final fixed = needs('fixed_1m', 'adaptive');
    expect((fixed.accel, fixed.osSteps, fixed.activity), (false, false, false));
    final gated = needs('activity_gated', 'os');
    expect((gated.accel, gated.osSteps, gated.activity), (false, false, true));
  });

  test('상태 메시지는 정책 상태와 측위 뒤 걸음 수를 함께 오가고, 키가 없으면 null이다', () {
    final status = RecorderStatus(
      startedAt: DateTime.utc(2026, 11, 11),
      rowCounts: const {'fixes.csv': 3},
      errorCount: 0,
      atPlace: false,
      onVehicle: false,
      policyState: 'walking',
      stepsSinceFix: 42,
    );
    final back = decodeStatusMessage(encodeStatusMessage(status))!;
    expect(back.policyState, 'walking');
    expect(back.stepsSinceFix, 42);

    final old = RecorderStatus(
      startedAt: DateTime.utc(2026, 11, 11),
      rowCounts: const {},
      errorCount: 0,
      atPlace: false,
      onVehicle: false,
    );
    expect(decodeStatusMessage(encodeStatusMessage(old))!.policyState, isNull);
  });
}
