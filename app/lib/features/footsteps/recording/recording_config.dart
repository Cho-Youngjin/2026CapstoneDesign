import 'recording_mode.dart';

/// 기록 서비스 시작 설정. 화면이 [storageKey]로 저장하고, 서비스 isolate가 시작하면서 읽는다
/// (flutter_foreground_task의 saveData 저장소는 두 isolate가 함께 본다).
class RecordingConfig {
  const RecordingConfig({
    required this.mode,
    required this.sessionDir,
    required this.carryInitial,
    this.note,
  });

  static const storageKey = 'recording_config';

  final RecordingMode mode;
  final String sessionDir;
  final String carryInitial;
  final String? note;

  Map<String, Object?> toJson() => {
        'mode': mode.name,
        'sessionDir': sessionDir,
        'carryInitial': carryInitial,
        'note': note,
      };

  factory RecordingConfig.fromJson(Map<String, Object?> json) => RecordingConfig(
        mode: RecordingMode.values.byName(json['mode'] as String),
        sessionDir: json['sessionDir'] as String,
        carryInitial: json['carryInitial'] as String,
        note: json['note'] as String?,
      );
}
