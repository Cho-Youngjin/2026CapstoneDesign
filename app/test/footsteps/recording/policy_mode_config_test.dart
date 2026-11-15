import 'dart:convert';

import 'package:app/features/footsteps/recording/policy_choice.dart';
import 'package:app/features/footsteps/recording/recording_config.dart';
import 'package:app/features/footsteps/recording/recording_mode.dart';
import 'package:app/features/footsteps/recording/session_meta.dart';
import 'package:app/features/footsteps/trip/trip_period.dart';
import 'package:flutter_test/flutter_test.dart';

const _choice = PolicyChoice(
  policyId: 'step_budget',
  policyParams: {'e_m': '25'},
  detectorId: 'adaptive',
  detectorParams: {'n_confirm': '6'},
);

void main() {
  test('정책 실행 모드의 기록 설정과 meta.json은 고른 정책을 함께 오가고, 정답 기록 모드는 null이다', () {
    const config = RecordingConfig(
      mode: RecordingMode.policy,
      sessionDir: '/s/20261111-090000-policy',
      carryInitial: 'pocket',
      policy: _choice,
    );
    final back = RecordingConfig.fromJson(config.toJson());
    expect(back.mode, RecordingMode.policy);
    expect(back.policy, _choice);

    final meta = SessionMeta(
      sessionId: '20261111-090000-policy',
      mode: RecordingMode.policy,
      deviceModel: 'samsung SM-S911N',
      androidSdk: 36,
      appVersion: '1.0.0',
      startedAt: DateTime.utc(2026, 11, 11),
      carryInitial: 'pocket',
      policy: _choice,
    );
    final metaBack = SessionMeta.fromJson(meta.toJson());
    expect(metaBack.policy, _choice);
    expect(meta.toJson()['policy'], {
      'policyId': 'step_budget',
      'policyParams': {'e_m': '25'},
      'detectorId': 'adaptive',
      'detectorParams': {'n_confirm': '6'},
    });
    expect(metaBack.copyWith(endedAt: DateTime.utc(2026, 11, 11, 1)).policy, _choice);

    const truth = RecordingConfig(mode: RecordingMode.groundTruth, sessionDir: '/s', carryInitial: 'hand');
    expect(RecordingConfig.fromJson(truth.toJson()).policy, isNull);
    expect(sessionDirName(DateTime(2026, 11, 11, 9), RecordingMode.policy), '20261111-090000-policy');
  });

  test('여행 기록 모드의 기록 설정은 여행과 정책을 JSON 문자열을 거쳐도 그대로 오가고, 실험 모드에서는 trip이 null이다', () {
    final trip = TripPeriod(
      tripId: 7,
      countryIso2: 'JP',
      countryNameKo: '일본',
      departDate: DateTime(2026, 11, 20),
      returnDate: DateTime(2026, 11, 25),
    );
    final config = RecordingConfig(mode: RecordingMode.trip, policy: _choice, trip: trip);

    // 서비스 isolate는 saveData에 넣은 문자열을 읽는다 — 문자열을 거친 값으로 확인한다.
    final back = RecordingConfig.fromJson((jsonDecode(jsonEncode(config.toJson())) as Map).cast<String, Object?>());
    expect(back.mode, RecordingMode.trip);
    expect(back.policy, _choice);
    expect(back.trip?.tripId, 7);
    expect(back.trip?.countryIso2, 'JP');
    expect(back.trip?.countryNameKo, '일본');
    expect(back.trip?.departDate, DateTime(2026, 11, 20));
    expect(back.trip?.returnDate, DateTime(2026, 11, 25));
    expect(back.sessionDir, isNull);

    const lab = RecordingConfig(mode: RecordingMode.groundTruth, sessionDir: '/s', carryInitial: 'hand');
    expect(RecordingConfig.fromJson(lab.toJson()).trip, isNull);
  });
}
