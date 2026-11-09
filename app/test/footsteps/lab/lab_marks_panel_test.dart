import 'package:app/features/footsteps/recording/mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_recording_controller.dart';
import 'lab_page_test.dart' show pumpLab;

Future<void> _startRecording(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('lab-start-stop')));
  await tester.pumpAndSettle();
}

Future<void> _answerDialog(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('mark-dialog-field')), text);
  await tester.tap(find.byKey(const Key('mark-dialog-ok')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('기록 중이 아니면 표시 버튼을 누를 수 없다', (tester) async {
    final controller = FakeRecordingController();
    await pumpLab(tester, controller);

    final button = tester.widget<OutlinedButton>(find.byKey(const Key('mark-board-bus')));
    expect(button.onPressed, isNull);
  });

  testWidgets('버스 탑승·하차를 누르면 board/bus, alight 표시를 보낸다', (tester) async {
    final controller = FakeRecordingController();
    await pumpLab(tester, controller);
    await _startRecording(tester);

    await tester.tap(find.byKey(const Key('mark-board-bus')));
    await tester.tap(find.byKey(const Key('mark-alight')));
    await tester.pumpAndSettle();

    expect(controller.marks.map((m) => (m.kind, m.value)), [
      (MarkKind.board, VehicleType.bus),
      (MarkKind.alight, ''),
    ]);
  });

  testWidgets('도착은 장소 이름을 받아 보내고, 비워 두어도 보낸다', (tester) async {
    final controller = FakeRecordingController();
    await pumpLab(tester, controller);
    await _startRecording(tester);

    await tester.tap(find.byKey(const Key('mark-arrive')));
    await tester.pumpAndSettle();
    await _answerDialog(tester, '시청 앞 카페');

    await tester.tap(find.byKey(const Key('mark-arrive')));
    await tester.pumpAndSettle();
    await _answerDialog(tester, '');

    expect(controller.marks.map((m) => (m.kind, m.value)), [
      (MarkKind.arrive, '시청 앞 카페'),
      (MarkKind.arrive, ''),
    ]);
  });

  testWidgets('걸음 세기 끝은 센 걸음 수를 받는다. 숫자가 아니면 보내지 않는다', (tester) async {
    final controller = FakeRecordingController();
    await pumpLab(tester, controller);
    await _startRecording(tester);

    await tester.tap(find.byKey(const Key('mark-count-start')));
    await tester.tap(find.byKey(const Key('mark-count-end')));
    await tester.pumpAndSettle();
    await _answerDialog(tester, '152');

    await tester.tap(find.byKey(const Key('mark-count-end')));
    await tester.pumpAndSettle();
    await _answerDialog(tester, '많이');

    expect(controller.marks.map((m) => (m.kind, m.value)), [
      (MarkKind.countStart, ''),
      (MarkKind.countEnd, '152'),
    ]);
  });

  testWidgets('메모는 입력한 글을 보낸다', (tester) async {
    final controller = FakeRecordingController();
    await pumpLab(tester, controller);
    await _startRecording(tester);

    await tester.tap(find.byKey(const Key('mark-note')));
    await tester.pumpAndSettle();
    await _answerDialog(tester, '비 옴');

    expect(controller.marks.single.kind, MarkKind.note);
    expect(controller.marks.single.value, '비 옴');
  });

  testWidgets('시작 전에 고른 휴대 위치를 넘기고, 기록 중에 바꾸면 carry 표시를 보낸다', (tester) async {
    final controller = FakeRecordingController();
    await pumpLab(tester, controller);

    await tester.tap(find.byKey(const Key('carry-bag')));
    await tester.pumpAndSettle();
    expect(controller.marks, isEmpty); // 시작 전에는 표시가 아니라 시작 설정이다

    await _startRecording(tester);
    expect(controller.starts.single.carry, CarryPosition.bag);

    await tester.tap(find.byKey(const Key('carry-pocket')));
    await tester.pumpAndSettle();
    expect(controller.marks.single.kind, MarkKind.carry);
    expect(controller.marks.single.value, CarryPosition.pocket);
  });
}
