import '../trip/trip_period.dart';
import 'policy_choice.dart';
import 'recording_mode.dart';

/// 기록 서비스 시작 설정. 화면이 [storageKey]로 저장하고, 서비스 isolate가 시작하면서 읽는다
/// (flutter_foreground_task의 saveData 저장소는 두 isolate가 함께 본다).
class RecordingConfig {
  const RecordingConfig({
    required this.mode,
    this.sessionDir,
    this.carryInitial,
    this.note,
    this.policy,
    this.trip,
  });

  static const storageKey = 'recording_config';

  final RecordingMode mode;

  /// 실험 모드(정답 기록·정책 실행)의 세션 폴더와 처음 휴대 위치. 여행 기록 모드는 세션 파일을 쓰지 않아 null이다.
  final String? sessionDir;
  final String? carryInitial;
  final String? note;

  /// 정책 실행·여행 기록 모드에서 돌리는 정책·감지기. 정답 기록 모드에서는 null이다.
  final PolicyChoice? policy;

  /// 여행 기록 모드에서 기록하는 여행. 실험 모드에서는 null이다.
  final TripPeriod? trip;

  Map<String, Object?> toJson() => {
        'mode': mode.name,
        'sessionDir': sessionDir,
        'carryInitial': carryInitial,
        'note': note,
        'policy': policy?.toJson(),
        'trip': trip?.toJson(),
      };

  factory RecordingConfig.fromJson(Map<String, Object?> json) => RecordingConfig(
        mode: RecordingMode.values.byName(json['mode'] as String),
        sessionDir: json['sessionDir'] as String?,
        carryInitial: json['carryInitial'] as String?,
        note: json['note'] as String?,
        policy: json['policy'] == null
            ? null
            : PolicyChoice.fromJson((json['policy'] as Map).cast<String, Object?>()),
        trip: json['trip'] == null
            ? null
            : TripPeriod.fromJson((json['trip'] as Map).cast<String, Object?>()),
      );
}
