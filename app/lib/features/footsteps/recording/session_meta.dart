import 'dart:convert';
import 'dart:io';

import 'recording_mode.dart';

/// 기록 중 생긴 문제 하나(센서 실패, 서비스 재시작 등). 분석 때 그 구간을 따로 볼 수 있게
/// 시각과 출처를 남긴다.
class SessionError {
  const SessionError({required this.at, required this.source, required this.message});

  final DateTime at;
  final String source;
  final String message;

  Map<String, Object?> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'source': source,
        'message': message,
      };

  factory SessionError.fromJson(Map<String, Object?> json) => SessionError(
        at: DateTime.parse(json['at'] as String),
        source: json['source'] as String,
        message: json['message'] as String,
      );
}

/// 세션 폴더의 meta.json(설계 4-2). 키 이름은 재생기·분석이 읽는 계약이다.
class SessionMeta {
  const SessionMeta({
    required this.sessionId,
    required this.mode,
    required this.deviceModel,
    required this.androidSdk,
    required this.appVersion,
    required this.startedAt,
    required this.carryInitial,
    this.endedAt,
    this.note,
    this.errors = const [],
  });

  final String sessionId;
  final RecordingMode mode;
  final String deviceModel;
  final int androidSdk;
  final String appVersion;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String carryInitial;
  final String? note;
  final List<SessionError> errors;

  SessionMeta copyWith({DateTime? endedAt, List<SessionError>? errors}) => SessionMeta(
        sessionId: sessionId,
        mode: mode,
        deviceModel: deviceModel,
        androidSdk: androidSdk,
        appVersion: appVersion,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        carryInitial: carryInitial,
        note: note,
        errors: errors ?? this.errors,
      );

  SessionMeta withError(SessionError error) => copyWith(errors: [...errors, error]);

  Map<String, Object?> toJson() => {
        'sessionId': sessionId,
        'mode': mode.name,
        'deviceModel': deviceModel,
        'androidSdk': androidSdk,
        'appVersion': appVersion,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': endedAt?.toUtc().toIso8601String(),
        'carryInitial': carryInitial,
        'note': note,
        'errors': [for (final e in errors) e.toJson()],
      };

  factory SessionMeta.fromJson(Map<String, Object?> json) => SessionMeta(
        sessionId: json['sessionId'] as String,
        mode: RecordingMode.values.byName(json['mode'] as String),
        deviceModel: json['deviceModel'] as String,
        androidSdk: json['androidSdk'] as int,
        appVersion: json['appVersion'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        endedAt: json['endedAt'] == null ? null : DateTime.parse(json['endedAt'] as String),
        carryInitial: json['carryInitial'] as String,
        note: json['note'] as String?,
        errors: [
          for (final e in (json['errors'] as List? ?? const []))
            SessionError.fromJson((e as Map).cast<String, Object?>()),
        ],
      );
}

/// meta.json 읽기·쓰기. 쓰기를 한 줄로 세운다 — 센서 오류가 연달아 나면 같은 파일을 동시에 쓰려다
/// 내용이 섞일 수 있다. 앞의 쓰기가 실패해도 뒤의 쓰기는 계속 시도한다.
class SessionMetaStore {
  SessionMetaStore(this.file);

  final File file;
  Future<void> _queue = Future.value();

  Future<void> write(SessionMeta meta) {
    return _queue = _queue.catchError((Object _) {}).then((_) async {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(meta.toJson()),
        flush: true,
      );
    });
  }

  Future<SessionMeta?> read() async {
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    return SessionMeta.fromJson(json);
  }
}
