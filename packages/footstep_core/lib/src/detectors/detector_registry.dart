import '../params.dart';
import 'adaptive_step_detector.dart';
import 'brajdic_detector.dart';
import 'os_step_detector.dart';
import 'step_detector.dart';

/// 재생기·걸음 CLI가 받는 걸음 감지기 id(설계 5-4 `--detector os|brajdic|adaptive`).
const detectorIds = ['os', 'brajdic', 'adaptive'];

/// id와 파라미터(문자열 k=v)로 걸음 감지기를 만든다. 파라미터 이름은 결과 파일의 detector_params와 같다.
/// 최종 파라미터는 예비용 세션으로만 정한다(설계 5-2) — 그 조정을 코드 수정 없이 하려고 받는다.
StepDetector createDetector(String id, [Map<String, String> params = const {}]) {
  final reader = ParamReader('걸음 감지기 $id', params);
  switch (id) {
    case 'os':
      reader.allowOnly(const {});
      return OsStepDetector();
    case 'brajdic':
      reader.allowOnly(const {'std_th', 'smooth_s', 'peak_win_s'});
      return BrajdicDetector(
        stdThreshold: reader.positive('std_th', 0.6),
        smoothMs: (reader.positive('smooth_s', 0.31) * 1000).round(),
        peakWindowMs: (reader.positive('peak_win_s', 0.59) * 1000).round(),
      );
    case 'adaptive':
      reader.allowOnly(const {'std_th', 'band_std_th', 'ac_th', 'n_confirm', 'max_gap_s'});
      return AdaptiveStepDetector(
        shakeThreshold: reader.positive('std_th', 0.6),
        bandShakeThreshold: reader.positive('band_std_th', 0.3),
        rhythmThreshold: reader.positive('ac_th', 0.4),
        confirmSteps: reader.positiveInt('n_confirm', 5),
        maxStepGapMs: (reader.positive('max_gap_s', 1.5) * 1000).round(),
      );
    default:
      throw ArgumentError('알 수 없는 걸음 감지기: $id (가능: ${detectorIds.join(', ')})');
  }
}
