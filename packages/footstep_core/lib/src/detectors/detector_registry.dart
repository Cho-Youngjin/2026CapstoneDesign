import 'os_step_detector.dart';
import 'step_detector.dart';

/// 재생기 CLI가 받는 걸음 감지기 id. R3이 논문 기준판(brajdic)과 제안판(adaptive)을 더한다.
const detectorIds = ['os'];

StepDetector createDetector(String id) => switch (id) {
      'os' => OsStepDetector(),
      _ => throw ArgumentError('알 수 없는 걸음 감지기: $id (가능: ${detectorIds.join(', ')})'),
    };
