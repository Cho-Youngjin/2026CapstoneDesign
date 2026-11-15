import 'dart:io';

import 'package:app/features/footsteps/recording/policy_choice.dart';
import 'package:app/features/footsteps/recording/recording_config.dart';
import 'package:app/features/footsteps/recording/recording_mode.dart';
import 'package:app/features/footsteps/recording/session_meta.dart';
import 'package:app/features/footsteps/recording/session_recorder_factory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('session_recorder_factory_test'));
  tearDown(() => dir.delete(recursive: true));

  Future<void> open(PolicyChoice? policy) => openSessionRecorder(
        RecordingConfig(
          mode: RecordingMode.policy,
          sessionDir: dir.path,
          carryInitial: 'hand',
          policy: policy,
        ),
        dir,
        clock: DateTime.now,
        onError: (SessionError _) {},
      );

  // 잘못된 설정은 세션 파일을 만들기 전에 멈춰야 한다 — 빈 CSV만 남은 세션이 분석에 섞이지 않게.
  test('정책 실행 모드인데 고른 정책이 없으면 파일을 만들기 전에 멈춘다', () async {
    await expectLater(open(null), throwsStateError);
    expect(dir.listSync(), isEmpty);
  });

  test('여행 기록 모드는 실험 세션 기록기로 열지 않고 파일도 만들지 않는다', () async {
    await expectLater(
      openSessionRecorder(
        const RecordingConfig(mode: RecordingMode.trip),
        dir,
        clock: DateTime.now,
        onError: (SessionError _) {},
      ),
      throwsStateError,
    );
    expect(dir.listSync(), isEmpty);
  });

  test('모르는 정책·감지기나 잘못된 파라미터면 파일을 만들기 전에 멈춘다', () async {
    await expectLater(open(const PolicyChoice(policyId: 'nope', detectorId: 'os')), throwsArgumentError);
    await expectLater(open(const PolicyChoice(policyId: 'step_budget', detectorId: 'nope')), throwsArgumentError);
    await expectLater(
      open(const PolicyChoice(policyId: 'step_budget', detectorId: 'os', policyParams: {'e_m': 'abc'})),
      throwsArgumentError,
    );
    expect(dir.listSync(), isEmpty);
  });
}
