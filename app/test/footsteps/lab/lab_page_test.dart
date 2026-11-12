import 'dart:io';

import 'package:app/features/footsteps/lab/lab_page.dart';
import 'package:app/features/footsteps/lab/lab_status_card.dart';
import 'package:app/features/footsteps/lab/recording_permissions.dart';
import 'package:app/features/footsteps/recording/mark.dart';
import 'package:app/features/footsteps/recording/policy_choice.dart';
import 'package:app/features/footsteps/recording/recorder_status.dart';
import 'package:app/features/footsteps/recording/recording_config.dart';
import 'package:app/features/footsteps/recording/recording_mode.dart';
import 'package:app/features/footsteps/recording/recording_providers.dart';
import 'package:app/features/footsteps/recording/session_library.dart';
import 'package:app/features/footsteps/trip/trip_period.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fake_recording_controller.dart';

Future<void> pumpLab(
  WidgetTester tester,
  FakeRecordingController controller, {
  List<Override> extra = const [],
}) async {
  // 화면 전체가 한 번에 그려지도록 세로로 긴 화면을 쓴다(ListView가 화면 밖 항목을 만들지 않는다).
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      recordingControllerProvider.overrideWithValue(controller),
      recordingPermissionRequesterProvider.overrideWithValue(
        () async => const [
          PermissionItem('위치(앱 사용 중)', true),
          PermissionItem('신체 활동(걸음·활동 인식)', false),
        ],
      ),
      sessionLibraryProvider.overrideWithValue(_EmptyLibrary()),
      ...extra,
    ],
    child: const MaterialApp(home: LabPage()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('시작을 누르면 정답 기록 모드로 서비스를 켜고, 종료를 누르면 끈다', (tester) async {
    final controller = FakeRecordingController();
    await pumpLab(tester, controller);

    expect(find.text('기록 중이 아닙니다.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lab-start-stop')));
    await tester.pumpAndSettle();

    expect(controller.starts.single.mode, RecordingMode.groundTruth);
    expect(controller.starts.single.carry, 'hand');
    expect(find.text('기록 종료'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lab-start-stop')));
    await tester.pumpAndSettle();
    expect(controller.stops, 1);
    expect(find.text('기록 시작'), findsOneWidget);
  });

  testWidgets('정책 실행을 고르면 정책·감지기·파라미터로 기록을 시작한다', (tester) async {
    final controller = FakeRecordingController();
    await pumpLab(tester, controller);

    expect(find.byKey(const Key('lab-policy')), findsNothing);
    await tester.tap(find.text('정책 실행'));
    await tester.pumpAndSettle();
    expect(find.text('step_budget'), findsOneWidget);
    expect(find.text('adaptive'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('lab-policy-params')), 'e_m=25  use_steps=false');
    await tester.tap(find.byKey(const Key('lab-start-stop')));
    await tester.pumpAndSettle();

    expect(controller.starts.single.mode, RecordingMode.policy);
    expect(
      controller.starts.single.policy,
      const PolicyChoice(
        policyId: 'step_budget',
        detectorId: 'adaptive',
        policyParams: {'e_m': '25', 'use_steps': 'false'},
      ),
    );
  });

  testWidgets('정책 파라미터가 잘못되면 기록을 시작하지 않고 이유를 보여 준다', (tester) async {
    final controller = FakeRecordingController();
    await pumpLab(tester, controller);
    await tester.tap(find.text('정책 실행'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('lab-policy-params')), 'e_m=abc');
    await tester.tap(find.byKey(const Key('lab-start-stop')));
    await tester.pumpAndSettle();

    expect(controller.starts, isEmpty);
    expect(find.textContaining('양수여야'), findsOneWidget);
    expect(find.text('기록 시작'), findsOneWidget);
  });

  testWidgets('기록 중에는 모드를 바꿀 수 없고, 정책 실행 상태를 보여 준다', (tester) async {
    final controller = FakeRecordingController()..running = true;
    await pumpLab(tester, controller);
    final mode = tester.widget<SegmentedButton<RecordingMode>>(find.byKey(const Key('lab-mode')));
    expect(mode.onSelectionChanged, isNull);

    controller.statusController.add(RecorderStatus(
      startedAt: DateTime.now().toUtc(),
      rowCounts: const {'fixes.csv': 3},
      errorCount: 0,
      atPlace: false,
      onVehicle: false,
      policyState: 'walking',
      stepsSinceFix: 42,
    ));
    await tester.pumpAndSettle();
    expect(find.text('정책 상태: walking · 측위 뒤 걸음: 42'), findsOneWidget);
  });

  testWidgets('이미 기록 중이면 들어오자마자 종료 버튼을 보여 준다', (tester) async {
    final controller = FakeRecordingController()..running = true;
    await pumpLab(tester, controller);

    expect(find.text('기록 종료'), findsOneWidget);
  });

  testWidgets('정책 실행 중에 화면을 다시 열면 기본값이 아니라 지금 도는 설정을 보여 준다', (tester) async {
    final controller = FakeRecordingController()
      ..running = true
      ..config = const RecordingConfig(
        mode: RecordingMode.policy,
        sessionDir: 'sessions/x-policy',
        carryInitial: 'hand',
        policy: PolicyChoice(policyId: 'still_suppress', detectorId: 'os', policyParams: {'interval_s': '120'}),
      );
    await pumpLab(tester, controller);

    final mode = tester.widget<SegmentedButton<RecordingMode>>(find.byKey(const Key('lab-mode')));
    expect(mode.selected, {RecordingMode.policy});
    expect(tester.widget<DropdownButton<String>>(find.byKey(const Key('lab-policy'))).value, 'still_suppress');
    expect(tester.widget<DropdownButton<String>>(find.byKey(const Key('lab-detector'))).value, 'os');
    expect(tester.widget<TextField>(find.byKey(const Key('lab-policy-params'))).controller!.text, 'interval_s=120');
  });

  testWidgets('여행 기록 중에 열면 안내하고, 종료한 뒤 시작하면 여행 기록이 아니라 실험 모드로 켠다', (tester) async {
    final controller = FakeRecordingController()
      ..running = true
      ..config = RecordingConfig(
        mode: RecordingMode.trip,
        policy: const PolicyChoice(policyId: 'step_budget', detectorId: 'adaptive'),
        trip: TripPeriod(
          tripId: 7,
          countryIso2: 'KR',
          countryNameKo: '대한민국',
          departDate: DateTime(2026, 11, 20),
          returnDate: DateTime(2026, 11, 22),
        ),
      );
    await pumpLab(tester, controller);

    expect(find.byKey(const Key('lab-trip-recording')), findsOneWidget);
    final mode = tester.widget<SegmentedButton<RecordingMode>>(find.byKey(const Key('lab-mode')));
    expect(mode.selected, {RecordingMode.groundTruth});

    await tester.tap(find.byKey(const Key('lab-start-stop')));
    await tester.pumpAndSettle();
    expect(controller.stops, 1);
    expect(find.byKey(const Key('lab-trip-recording')), findsNothing);

    await tester.tap(find.byKey(const Key('lab-start-stop')));
    await tester.pumpAndSettle();
    expect(controller.starts.single.mode, RecordingMode.groundTruth);
  });

  testWidgets('서비스가 보낸 상태를 보여 준다', (tester) async {
    final controller = FakeRecordingController()..running = true;
    await pumpLab(tester, controller);

    controller.statusController.add(RecorderStatus(
      startedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 3, seconds: 5)),
      rowCounts: const {'gps.csv': 185, 'accel.csv': 9200},
      errorCount: 1,
      atPlace: false,
      onVehicle: true,
      lastGpsAccuracyM: 7.26,
      lastOsSteps: 1520,
      lastLevelPct: 86,
    ));
    await tester.pumpAndSettle();

    expect(find.text('gps.csv: 185행'), findsOneWidget);
    expect(find.text('accel.csv: 9200행'), findsOneWidget);
    expect(find.text('GPS 정확도: 7.3 m'), findsOneWidget);
    expect(find.text('OS 누적 걸음: 1520'), findsOneWidget);
    expect(find.text('배터리: 86% · 전하량 지원 안 함'), findsOneWidget);
    expect(find.text('현장 상태: 이동 중 · 탈것 탑승 중'), findsOneWidget);
    expect(find.text('오류: 1건'), findsOneWidget);
    expect(find.textContaining('경과 03:0'), findsOneWidget);
  });

  testWidgets('기록 중인 서비스의 휴대 위치를 따라가서, 손을 누르면 carry 표시를 남긴다', (tester) async {
    final controller = FakeRecordingController()..running = true;
    await pumpLab(tester, controller);

    controller.statusController.add(RecorderStatus(
      startedAt: DateTime.now().toUtc(),
      rowCounts: const {},
      errorCount: 0,
      atPlace: false,
      onVehicle: false,
      carry: 'pocket',
    ));
    await tester.pumpAndSettle();

    expect(tester.widget<ChoiceChip>(find.byKey(const Key('carry-pocket'))).selected, isTrue);
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('carry-hand'))).selected, isFalse);

    await tester.tap(find.byKey(const Key('carry-hand')));
    await tester.pumpAndSettle();

    expect(controller.marks.single.kind, MarkKind.carry);
    expect(controller.marks.single.value, 'hand');
  });

  testWidgets('권한 확인을 누르면 결과를 보여 준다', (tester) async {
    await pumpLab(tester, FakeRecordingController());

    await tester.tap(find.byKey(const Key('lab-permissions')));
    await tester.pumpAndSettle();

    expect(find.text('위치(앱 사용 중): 허용'), findsOneWidget);
    expect(find.text('신체 활동(걸음·활동 인식): 거부'), findsOneWidget);
  });

  testWidgets('시작이 실패하면 오류 문구를 보여 주고 시작 버튼을 유지한다', (tester) async {
    final controller = FakeRecordingController()..startError = StateError('권한 없음');
    await pumpLab(tester, controller);

    await tester.tap(find.byKey(const Key('lab-start-stop')));
    await tester.pumpAndSettle();

    expect(find.textContaining('권한 없음'), findsOneWidget);
    expect(find.text('기록 시작'), findsOneWidget);
  });

  test('경과 시간은 1시간 미만이면 mm:ss, 넘으면 h:mm:ss로 쓴다', () {
    expect(formatElapsed(const Duration(minutes: 3, seconds: 5)), '03:05');
    expect(formatElapsed(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });
}

class _EmptyLibrary implements SessionLibrary {
  @override
  Future<List<SessionSummary>> list() async => const [];

  @override
  Future<File> zip(SessionSummary session, Directory outDir) => throw UnimplementedError();
}
