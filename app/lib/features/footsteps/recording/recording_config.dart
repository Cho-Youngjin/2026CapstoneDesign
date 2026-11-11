import 'policy_choice.dart';
import 'recording_mode.dart';

/// 기록 서비스 시작 설정. 화면이 [storageKey]로 저장하고, 서비스 isolate가 시작하면서 읽는다
/// (flutter_foreground_task의 saveData 저장소는 두 isolate가 함께 본다).
class RecordingConfig {
  const RecordingConfig({
    required this.mode,
    required this.sessionDir,
    required this.carryInitial,
    this.note,
    this.policy,
  });

  static const storageKey = 'recording_config';

  final RecordingMode mode;
  final String sessionDir;
  final String carryInitial;
  final String? note;

  /// 정책 실행 모드에서 고른 정책·감지기. 정답 기록 모드에서는 null이다.
  final PolicyChoice? policy;

  Map<String, Object?> toJson() => {
        'mode': mode.name,
        'sessionDir': sessionDir,
        'carryInitial': carryInitial,
        'note': note,
        'policy': policy?.toJson(),
      };

  factory RecordingConfig.fromJson(Map<String, Object?> json) => RecordingConfig(
        mode: RecordingMode.values.byName(json['mode'] as String),
        sessionDir: json['sessionDir'] as String,
        carryInitial: json['carryInitial'] as String,
        note: json['note'] as String?,
        policy: json['policy'] == null
            ? null
            : PolicyChoice.fromJson((json['policy'] as Map).cast<String, Object?>()),
      );
}
