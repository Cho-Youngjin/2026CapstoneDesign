import 'package:app/features/footsteps/recording/mark.dart';
import 'package:app/features/footsteps/recording/recorder_status.dart';
import 'package:app/features/footsteps/recording/recording_config.dart';
import 'package:app/features/footsteps/recording/recording_messages.dart';
import 'package:app/features/footsteps/recording/recording_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('관찰 표시 메시지는 문자열로 보내고 그대로 되살린다', () {
    final mark = Mark(at: DateTime.utc(2026, 11, 9, 1), kind: MarkKind.countEnd, value: '152');
    final raw = encodeMarkMessage(mark);

    expect(raw, isA<String>());
    final back = decodeMarkMessage(raw)!;
    expect(back.at, mark.at);
    expect(back.kind, MarkKind.countEnd);
    expect(back.value, '152');
  });

  test('표시가 아닌 메시지나 깨진 문자열은 null이다', () {
    expect(decodeMarkMessage(42), isNull);
    expect(decodeMarkMessage('not json'), isNull);
    expect(decodeMarkMessage('{"type":"status"}'), isNull);
    expect(decodeMarkMessage('{"type":"mark","at":1,"kind":"nope"}'), isNull);
  });

  test('상태 메시지는 문자열로 보내고 그대로 되살린다', () {
    final status = RecorderStatus(
      startedAt: DateTime.utc(2026, 11, 9),
      rowCounts: const {'gps.csv': 600, 'accel.csv': 30000},
      errorCount: 0,
      atPlace: true,
      onVehicle: false,
      lastGpsAccuracyM: 7.5,
    );

    final back = decodeStatusMessage(encodeStatusMessage(status))!;
    expect(back.toJson(), status.toJson());
    expect(decodeStatusMessage(encodeMarkMessage(Mark(at: DateTime.utc(2026), kind: MarkKind.note))), isNull);
  });

  test('기록 설정은 json으로 오간다', () {
    const config = RecordingConfig(
      mode: RecordingMode.groundTruth,
      sessionDir: '/sdcard/Android/data/com.travelfootsteps.app/files/sessions/20261109-080503-groundTruth',
      carryInitial: 'pocket',
      note: '시청 코스',
    );

    final back = RecordingConfig.fromJson(config.toJson());
    expect(back.mode, RecordingMode.groundTruth);
    expect(back.sessionDir, config.sessionDir);
    expect(back.carryInitial, 'pocket');
    expect(back.note, '시청 코스');
  });
}
