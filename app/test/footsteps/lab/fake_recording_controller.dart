import 'dart:async';

import 'package:app/features/footsteps/recording/mark.dart';
import 'package:app/features/footsteps/recording/policy_choice.dart';
import 'package:app/features/footsteps/recording/recorder_status.dart';
import 'package:app/features/footsteps/recording/recording_controller.dart';
import 'package:app/features/footsteps/recording/recording_mode.dart';

/// 실험 화면 위젯 테스트용. 실제 서비스 대신 호출을 기록하고, 상태는 [statusController]로 직접 흘린다.
class FakeRecordingController implements RecordingController {
  final statusController = StreamController<RecorderStatus>.broadcast();
  bool running = false;
  Object? startError;
  final starts = <({RecordingMode mode, String carry, PolicyChoice? policy})>[];
  int stops = 0;
  final marks = <Mark>[];

  @override
  Future<bool> isRunning() async => running;

  @override
  Future<void> start({
    required RecordingMode mode,
    required String carryInitial,
    String? note,
    PolicyChoice? policy,
  }) async {
    final error = startError;
    if (error != null) throw error;
    starts.add((mode: mode, carry: carryInitial, policy: policy));
    running = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    running = false;
  }

  @override
  void sendMark(Mark mark) => marks.add(mark);

  @override
  Stream<RecorderStatus> statusStream() => statusController.stream;
}
