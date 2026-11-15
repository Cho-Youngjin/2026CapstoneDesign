# R1 기록 서비스와 로거 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 화면이 꺼져도 1초 GPS·50Hz 가속도·OS 걸음·활동 인식·배터리를 같은 시계로 세션 폴더에 기록하고, 관찰 표시를 남기고, PC로 꺼낼 수 있는 '정답 기록 모드'를 앱의 숨은 실험 화면에 만든다.

**Architecture:**
- `flutter_foreground_task`로 위치 타입 포그라운드 서비스를 띄우고, 그 안의 `TaskHandler`(별도 isolate)가 기록을 맡는다.
- 기록 로직(`GroundTruthRecorder`)은 센서 인터페이스(`SensorSources`)와 CSV 쓰기(`CsvWriter`)만 알도록 해서 가짜 센서로 단위 테스트한다.
- 화면과 서비스는 JSON 문자열 메시지로 대화한다. 화면 → 서비스는 관찰 표시, 서비스 → 화면은 5초마다 상태를 보낸다.
- 배터리 전하량과 기기 정보는 서비스 isolate에서도 동작하도록 작은 로컬 플러그인(`packages/device_probe`)으로 읽는다.

**Tech Stack:** Flutter 3.47.2 / Dart 3.13.2, flutter_foreground_task 11.x, geolocator 14(기존), sensors_plus 7.x, pedometer 4.x, flutter_activity_recognition 4.x, permission_handler 13(기존), share_plus 13.x, archive 4.x, Kotlin(로컬 플러그인).

**설계 문서:** `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md` 4장(R1). CSV 열 이름·파일 이름은 4-2절이 계약이며, R2 재생기가 같은 이름으로 읽는다.

## Global Constraints

- 작업 브랜치는 `research`다. 커밋에 `Co-Authored-By`, `Claude-Session` 같은 AI 트레일러를 넣지 않는다. push 전에 `git log --format=%B origin/master..HEAD | grep -iE "co-authored|claude"`가 빈 결과인지 확인한다.
- 로컬 정적 분석은 `app/`에서 `dart analyze`로 한다. 이 PC는 한글 경로 때문에 `flutter analyze`가 죽는다(코드 문제가 아님).
- 테스트는 `app/`에서 `flutter test`, `packages/device_probe/`에서 `flutter test`로 돌린다.
- 이 계획은 debug 빌드만 쓴다. profile/release 빌드(R4 배터리 실험)는 `C:\tfbuild` 복사본에서 해야 한다.
- 빌드가 `Failed to find target with hash string 'android-37'`로 실패하면 `compileSdk`를 바꾸지 않는다. 대신 PowerShell에서 `New-Item -ItemType Junction -Path "C:\Android\SDK\platforms\android-37" -Target "C:\Android\SDK\platforms\android-37.0"`을 실행한다.
- 앱 코드 주석은 기존 스타일대로 한국어로 '왜'를 적는다. Spring 학습용 주석 규칙은 서버 코드에만 적용되므로 이 계획에는 해당하지 않는다.
- applicationId는 `com.travelfootsteps.app`이다. 세션 폴더는 `/sdcard/Android/data/com.travelfootsteps.app/files/sessions/<yyyyMMdd-HHmmss>-<mode>/`다.
- CSV의 모든 시각 열(`t_ms`, `fix_t_ms`)은 UTC epoch 밀리초다. 헤더 행을 포함하고 줄바꿈은 `\n`이다.
- 수집한 세션 데이터(실제 이동 경로)는 절대 커밋하지 않는다. `research/data/`는 `.gitignore` 대상이다.
- 정답 기록 모드는 배터리 실험에 쓰지 않는다. 배터리 실험은 R4의 정책 실행 모드로 한다.

## 파일 구조

```
packages/device_probe/                         새 로컬 Flutter 플러그인 (Android 전용)
  pubspec.yaml
  lib/device_probe.dart                        DeviceProbe.readBattery()/readDevice()
  android/src/main/kotlin/com/travelfootsteps/device_probe/DeviceProbePlugin.kt
  test/device_probe_test.dart

app/lib/features/footsteps/recording/          기록 서비스 (R4·R7이 모드를 더한다)
  csv_writer.dart                              버퍼링 CSV 쓰기
  session_schema.dart                          파일 이름·헤더 (설계 4-2 계약)
  recording_mode.dart                          RecordingMode, sessionDirName()
  session_meta.dart                            SessionMeta, SessionError, SessionMetaStore
  session_files.dart                           한 세션의 CSV 여섯 개 + meta 묶음
  mark.dart                                    MarkKind, Mark, FieldState, CarryPosition, VehicleType
  sensor_samples.dart                          센서 값 타입 + SensorSources 인터페이스
  recorder_status.dart                         서비스 → 화면 상태
  ground_truth_recorder.dart                   정답 기록 모드 본체
  plugin_sensor_sources.dart                   SensorSources의 실제 플러그인 구현
  recording_config.dart                        서비스 시작 설정
  recording_messages.dart                      화면 ↔ 서비스 메시지 인코딩
  recording_task_handler.dart                  TaskHandler (서비스 isolate 진입점)
  recording_controller.dart                    화면 쪽 서비스 제어
  recording_providers.dart                     Riverpod provider
  session_check.dart                           세션 점검 통계 (실기기 점검·tool에서 사용)
  session_library.dart                         세션 목록·zip
app/lib/features/footsteps/lab/                숨은 실험 화면
  lab_page.dart
  lab_status_card.dart
  lab_permissions_panel.dart
  lab_marks_panel.dart
  lab_sessions_panel.dart
  recording_permissions.dart
app/tool/check_session.dart                    PC에서 세션 폴더 점검
app/test/footsteps/recording/*_test.dart
app/test/footsteps/lab/*_test.dart
docs/research/device-check.md                  실기기 점검 결과 기록
docs/research/recording-guide.md               팀원용 기록 안내
```

수정하는 기존 파일은 다음과 같다.
- `app/pubspec.yaml`
- `app/android/app/src/main/AndroidManifest.xml`
- `app/lib/main.dart`
- `app/lib/router.dart`
- `app/lib/features/footsteps/footsteps_page.dart`
- `app/lib/features/footsteps/map/world_map_page.dart`
- `app/test/router_test.dart`
- `.gitignore`

---

### Task 1: 버퍼링 CSV 쓰기 (`CsvWriter`)

**Files:**
- Create: `app/lib/features/footsteps/recording/csv_writer.dart`
- Test: `app/test/footsteps/recording/csv_writer_test.dart`

**Interfaces:**
- Produces:
  - `class CsvWriter`
    - `static Future<CsvWriter> open(File file, List<String> header)`
    - `void add(List<Object?> row)`
    - `Future<void> flush()`
    - `Future<void> close()`
    - `int get pendingRows`, `int get totalRows`, `final File file`
  - `String formatCsvField(Object? value)`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/footsteps/recording/csv_writer_test.dart`:

```dart
import 'dart:io';

import 'package:app/features/footsteps/recording/csv_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('csv_writer_test'));
  tearDown(() async => dir.delete(recursive: true));

  test('새 파일에는 헤더를 쓰고, close 때 모아 둔 행을 쓴다', () async {
    final file = File(p.join(dir.path, 'gps.csv'));
    final writer = await CsvWriter.open(file, ['t_ms', 'lat']);
    writer.add([1, 37.5]);
    writer.add([2, 37.6]);
    await writer.close();

    expect(await file.readAsLines(), ['t_ms,lat', '1,37.5', '2,37.6']);
    expect(writer.totalRows, 2);
  });

  test('flush 전에는 행을 디스크에 쓰지 않는다', () async {
    final file = File(p.join(dir.path, 'a.csv'));
    final writer = await CsvWriter.open(file, ['t_ms']);
    writer.add([123]);

    expect(writer.pendingRows, 1);
    expect(await file.readAsString(), isNot(contains('123')));

    await writer.flush();
    expect(writer.pendingRows, 0);
    expect(await file.readAsString(), contains('123'));
    await writer.close();
  });

  test('동시에 여러 번 flush해도 오류 없이 순서대로 쓴다', () async {
    final file = File(p.join(dir.path, 'c.csv'));
    final writer = await CsvWriter.open(file, ['t_ms']);
    writer.add([1]);
    final first = writer.flush();
    writer.add([2]);
    final second = writer.flush();
    await Future.wait([first, second]);
    await writer.close();

    expect(await file.readAsLines(), ['t_ms', '1', '2']);
  });

  test('이미 내용이 있는 파일을 다시 열면 헤더 없이 이어 쓴다', () async {
    final file = File(p.join(dir.path, 'b.csv'));
    final first = await CsvWriter.open(file, ['t_ms']);
    first.add([1]);
    await first.close();

    final second = await CsvWriter.open(file, ['t_ms']);
    second.add([2]);
    await second.close();

    expect(await file.readAsLines(), ['t_ms', '1', '2']);
  });

  test('close를 두 번 불러도 오류 없이 한 번만 닫는다', () async {
    final file = File(p.join(dir.path, 'd.csv'));
    final writer = await CsvWriter.open(file, ['t_ms']);
    writer.add([1]);
    await writer.close();
    await writer.close();

    expect(await file.readAsLines(), ['t_ms', '1']);
  });

  test('필드 서식: null·NaN은 빈칸, bool은 1/0, 쉼표·따옴표·줄바꿈은 따옴표로 감싼다', () {
    expect(formatCsvField(null), '');
    expect(formatCsvField(double.nan), '');
    expect(formatCsvField(double.infinity), '');
    expect(formatCsvField(true), '1');
    expect(formatCsvField(false), '0');
    expect(formatCsvField('카페, 2층'), '"카페, 2층"');
    expect(formatCsvField('그가 "여기"'), '"그가 ""여기"""');
    expect(formatCsvField('a\nb'), '"a\nb"');
    expect(formatCsvField(37.56651), '37.56651');
    expect(formatCsvField(1762650000000), '1762650000000');
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run (`app/`에서): `flutter test test/footsteps/recording/csv_writer_test.dart`
Expected: FAIL. 컴파일 오류 `Target of URI doesn't exist: 'package:app/features/footsteps/recording/csv_writer.dart'`

- [ ] **Step 3: 구현**

`app/lib/features/footsteps/recording/csv_writer.dart`:

```dart
import 'dart:io';

/// 기록 세션의 CSV 파일 하나. 행을 메모리에 모았다가 [flush] 때 한 번에 쓴다 —
/// 50Hz 가속도를 행마다 디스크에 쓰면 쓰기 자체가 배터리를 써서 측정을 오염시킨다.
class CsvWriter {
  CsvWriter._(this.file, this._sink);

  final File file;
  final IOSink _sink;
  final StringBuffer _buffer = StringBuffer();
  int _pendingRows = 0;
  int _totalRows = 0;

  // IOSink는 flush가 끝나기 전에 다시 write/flush하면 StateError를 던진다. 서비스의 5초 tick과
  // 종료가 겹칠 수 있어 쓰기를 한 줄로 세운다.
  Future<void> _queue = Future.value();
  bool _closed = false;

  /// 파일이 없거나 비어 있으면 헤더를 쓴다. 내용이 있으면 이어 쓴다 — 시스템이 기록 서비스를
  /// 다시 띄워 같은 세션 폴더를 다시 열 때 헤더가 중간에 끼면 재생기가 읽지 못한다.
  static Future<CsvWriter> open(File file, List<String> header) async {
    await file.parent.create(recursive: true);
    final hasContent = await file.exists() && await file.length() > 0;
    final sink = file.openWrite(mode: FileMode.append);
    if (!hasContent) {
      sink.writeln(header.join(','));
      await sink.flush();
    }
    return CsvWriter._(file, sink);
  }

  /// 아직 디스크에 쓰지 않은 행 수.
  int get pendingRows => _pendingRows;

  /// 이 writer로 추가한 행 수(헤더 제외). 다시 열기 전에 쓴 행은 세지 않는다.
  int get totalRows => _totalRows;

  void add(List<Object?> row) {
    _buffer.writeln(row.map(formatCsvField).join(','));
    _pendingRows++;
    _totalRows++;
  }

  Future<void> flush() {
    if (_closed) return _queue;
    final chunk = _buffer.toString();
    _buffer.clear();
    _pendingRows = 0;
    return _queue = _queue.then((_) async {
      if (chunk.isNotEmpty) _sink.write(chunk);
      await _sink.flush();
    });
  }

  /// 여러 번 불러도 된다 — 기록 종료와 테스트 정리가 같은 파일을 두 번 닫을 수 있다.
  /// (Windows는 열린 파일이 있으면 폴더를 지우지 못해서 테스트가 항상 닫는다.)
  Future<void> close() async {
    if (_closed) return;
    final pending = flush();
    _closed = true;
    await pending;
    await _sink.close();
  }
}

/// CSV 필드 하나의 문자열. 값이 없거나 유한한 숫자가 아니면(NaN 등) 빈칸으로 둔다 —
/// 분석 쪽(pandas)이 빈칸을 결측치로 읽는다.
String formatCsvField(Object? value) {
  if (value == null) return '';
  if (value is double && !value.isFinite) return '';
  if (value is bool) return value ? '1' : '0';
  final text = value.toString();
  final needsQuote =
      text.contains(',') || text.contains('"') || text.contains('\n') || text.contains('\r');
  return needsQuote ? '"${text.replaceAll('"', '""')}"' : text;
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/footsteps/recording/csv_writer_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/footsteps/recording/csv_writer.dart app/test/footsteps/recording/csv_writer_test.dart
git commit -m "feat(app): 기록 세션용 버퍼링 CSV 쓰기를 추가한다"
```

---

### Task 2: 세션 폴더 구조 (스키마·이름·메타·파일 묶음)

**Files:**
- Create: `app/lib/features/footsteps/recording/session_schema.dart`
- Create: `app/lib/features/footsteps/recording/recording_mode.dart`
- Create: `app/lib/features/footsteps/recording/session_meta.dart`
- Create: `app/lib/features/footsteps/recording/session_files.dart`
- Test: `app/test/footsteps/recording/session_files_test.dart`

**Interfaces:**
- Consumes: `CsvWriter.open`, `CsvWriter.flush/close` (Task 1)
- Produces:
  - `abstract final class SessionSchema` — 상수 `gpsFile`, `gpsHeader`, `accelFile`, `accelHeader`, `osStepsFile`, `osStepsHeader`, `activityFile`, `activityHeader`, `batteryFile`, `batteryHeader`, `marksFile`, `marksHeader`, `metaFile`
  - `enum RecordingMode { groundTruth }`
  - `String sessionDirName(DateTime startLocal, RecordingMode mode)`
  - `class SessionError({required DateTime at, required String source, required String message})` + `toJson()` / `fromJson`
  - `class SessionMeta(...)` + `toJson()` / `fromJson` / `copyWith({DateTime? endedAt, List<SessionError>? errors})` / `withError(SessionError)`
  - `class SessionMetaStore(File file)` — `Future<void> write(SessionMeta)`, `Future<SessionMeta?> read()`
  - `class SessionFiles` — `static Future<SessionFiles> open(Directory)`, 필드 `directory, gps, accel, osSteps, activity, battery, marks, meta`, `List<CsvWriter> get all`, `Future<void> flushAll()`, `Future<void> closeAll()`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/footsteps/recording/session_files_test.dart`:

```dart
import 'dart:io';

import 'package:app/features/footsteps/recording/recording_mode.dart';
import 'package:app/features/footsteps/recording/session_files.dart';
import 'package:app/features/footsteps/recording/session_meta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

SessionMeta _meta({DateTime? endedAt, List<SessionError> errors = const []}) => SessionMeta(
      sessionId: '20261109-080503-groundTruth',
      mode: RecordingMode.groundTruth,
      deviceModel: 'samsung SM-S921N',
      androidSdk: 35,
      appVersion: '1.0.0',
      startedAt: DateTime.utc(2026, 11, 8, 23, 5, 3),
      endedAt: endedAt,
      carryInitial: 'pocket',
      note: '시청 코스',
      errors: errors,
    );

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('session_files_test'));
  tearDown(() async => dir.delete(recursive: true));

  test('세션 폴더 이름은 현지 시각과 모드로 만든다', () {
    expect(
      sessionDirName(DateTime(2026, 11, 9, 8, 5, 3), RecordingMode.groundTruth),
      '20261109-080503-groundTruth',
    );
  });

  test('open은 여섯 CSV를 설계 문서 4-2의 헤더로 만든다', () async {
    final sessionDir = Directory(p.join(dir.path, 's1'));
    final files = await SessionFiles.open(sessionDir);
    await files.closeAll();

    String header(String name) => File(p.join(sessionDir.path, name)).readAsLinesSync().first;
    expect(header('gps.csv'), 't_ms,fix_t_ms,lat,lng,accuracy_m,speed_mps,bearing_deg,altitude_m');
    expect(header('accel.csv'), 't_ms,x,y,z');
    expect(header('os_steps.csv'), 't_ms,kind,value');
    expect(header('activity.csv'), 't_ms,type,confidence');
    expect(header('battery.csv'), 't_ms,charge_uah,current_ua,level_pct,temp_c,plugged');
    expect(header('marks.csv'), 't_ms,kind,value');
  });

  test('meta.json을 쓰고 다시 읽는다', () async {
    final files = await SessionFiles.open(Directory(p.join(dir.path, 's2')));
    final meta = _meta(
      endedAt: DateTime.utc(2026, 11, 9, 1),
      errors: [SessionError(at: DateTime.utc(2026, 11, 9), source: 'os_steps', message: 'no sensor')],
    );
    await files.meta.write(meta);
    await files.closeAll();

    final read = await files.meta.read();
    expect(read!.toJson(), meta.toJson());
    expect(read.errors.single.source, 'os_steps');
  });

  test('meta.json이 없으면 read는 null을 돌려준다', () async {
    final store = SessionMetaStore(File(p.join(dir.path, 'none', 'meta.json')));
    expect(await store.read(), isNull);
  });

  test('연달아 쓴 meta는 마지막 내용으로 남는다', () async {
    final store = SessionMetaStore(File(p.join(dir.path, 'm', 'meta.json')));
    final base = _meta();
    store.write(base);
    store.write(base.withError(SessionError(at: DateTime.utc(2026), source: 'gps', message: 'a')));
    await store.write(base.copyWith(endedAt: DateTime.utc(2026, 11, 9, 2)));

    final read = await store.read();
    expect(read!.endedAt, DateTime.utc(2026, 11, 9, 2));
    expect(read.errors, isEmpty);
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `flutter test test/footsteps/recording/session_files_test.dart`
Expected: FAIL (URI가 없다는 컴파일 오류)

- [ ] **Step 3: 구현**

`app/lib/features/footsteps/recording/session_schema.dart`:

```dart
/// 세션 폴더의 파일 이름과 CSV 헤더(설계 문서 4-2). R2 재생기(footstep_core)와 R6 분석이 같은
/// 이름·열 순서로 읽으므로, 바꾸면 설계 문서와 재생기도 함께 바꿔야 한다.
abstract final class SessionSchema {
  static const gpsFile = 'gps.csv';
  static const gpsHeader = [
    't_ms', 'fix_t_ms', 'lat', 'lng', 'accuracy_m', 'speed_mps', 'bearing_deg', 'altitude_m',
  ];

  static const accelFile = 'accel.csv';
  static const accelHeader = ['t_ms', 'x', 'y', 'z'];

  static const osStepsFile = 'os_steps.csv';
  static const osStepsHeader = ['t_ms', 'kind', 'value'];

  static const activityFile = 'activity.csv';
  static const activityHeader = ['t_ms', 'type', 'confidence'];

  static const batteryFile = 'battery.csv';
  static const batteryHeader = ['t_ms', 'charge_uah', 'current_ua', 'level_pct', 'temp_c', 'plugged'];

  static const marksFile = 'marks.csv';
  static const marksHeader = ['t_ms', 'kind', 'value'];

  static const metaFile = 'meta.json';
}
```

`app/lib/features/footsteps/recording/recording_mode.dart`:

```dart
/// 기록 서비스 모드. 한 번에 하나만 돈다(설계 4-1) — 두 모드를 같이 돌리면 배터리 측정이 오염된다.
/// R4가 `policy`, R7이 `trip`을 더한다.
enum RecordingMode { groundTruth }

String _two(int n) => n.toString().padLeft(2, '0');

/// 세션 폴더 이름이자 세션 id. 폴더 목록만 보고도 언제 무슨 모드였는지 알 수 있게 기기 현지 시각을 쓴다.
/// intl 대신 직접 만든다 — 서비스 isolate에서는 화면 쪽 로케일 초기화가 되어 있지 않다.
String sessionDirName(DateTime startLocal, RecordingMode mode) {
  final t = startLocal;
  return '${t.year}${_two(t.month)}${_two(t.day)}-${_two(t.hour)}${_two(t.minute)}${_two(t.second)}'
      '-${mode.name}';
}
```

`app/lib/features/footsteps/recording/session_meta.dart`:

```dart
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
```

`app/lib/features/footsteps/recording/session_files.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

import 'csv_writer.dart';
import 'session_meta.dart';
import 'session_schema.dart';

/// 한 세션 폴더의 CSV 여섯 개와 meta.json. 기록 모드는 이 묶음 하나만 받아 쓴다.
class SessionFiles {
  SessionFiles._({
    required this.directory,
    required this.gps,
    required this.accel,
    required this.osSteps,
    required this.activity,
    required this.battery,
    required this.marks,
  }) : meta = SessionMetaStore(File(p.join(directory.path, SessionSchema.metaFile)));

  static Future<SessionFiles> open(Directory directory) async {
    Future<CsvWriter> openCsv(String name, List<String> header) =>
        CsvWriter.open(File(p.join(directory.path, name)), header);

    return SessionFiles._(
      directory: directory,
      gps: await openCsv(SessionSchema.gpsFile, SessionSchema.gpsHeader),
      accel: await openCsv(SessionSchema.accelFile, SessionSchema.accelHeader),
      osSteps: await openCsv(SessionSchema.osStepsFile, SessionSchema.osStepsHeader),
      activity: await openCsv(SessionSchema.activityFile, SessionSchema.activityHeader),
      battery: await openCsv(SessionSchema.batteryFile, SessionSchema.batteryHeader),
      marks: await openCsv(SessionSchema.marksFile, SessionSchema.marksHeader),
    );
  }

  final Directory directory;
  final CsvWriter gps;
  final CsvWriter accel;
  final CsvWriter osSteps;
  final CsvWriter activity;
  final CsvWriter battery;
  final CsvWriter marks;
  final SessionMetaStore meta;

  List<CsvWriter> get all => [gps, accel, osSteps, activity, battery, marks];

  Future<void> flushAll() async {
    for (final writer in all) {
      await writer.flush();
    }
  }

  Future<void> closeAll() async {
    for (final writer in all) {
      await writer.close();
    }
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/footsteps/recording/session_files_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/footsteps/recording/session_schema.dart app/lib/features/footsteps/recording/recording_mode.dart app/lib/features/footsteps/recording/session_meta.dart app/lib/features/footsteps/recording/session_files.dart app/test/footsteps/recording/session_files_test.dart
git commit -m "feat(app): 기록 세션 폴더의 파일 구조와 meta.json을 정한다"
```

---

### Task 3: 관찰 표시와 현장 상태 (`Mark`, `FieldState`)

**Files:**
- Create: `app/lib/features/footsteps/recording/mark.dart`
- Test: `app/test/footsteps/recording/mark_test.dart`

**Interfaces:**
- Produces:
  - `enum MarkKind { arrive, depart, board, alight, countStart, countEnd, carry, note }`
    - `String csvName` (`arrive`, `depart`, `board`, `alight`, `count_start`, `count_end`, `carry`, `note`)
    - `static MarkKind fromCsvName(String)`
  - `abstract final class VehicleType { bus, subway, unspecified='vehicle' }`
  - `abstract final class CarryPosition { hand, pocket, bag, all }`
  - `class Mark({required DateTime at, required MarkKind kind, String value = ''})`
    - `List<Object?> toCsvRow()`, `Map<String, Object?> toJson()`, `factory Mark.fromJson(Map<String, Object?>)`
  - `class FieldState`
    - `bool atPlace`, `bool onVehicle`
    - `Mark nextPlaceMark(DateTime at)`, `Mark nextVehicleMark(DateTime at)` — 둘 다 상태를 바꾸지 않는다
    - `void observe(Mark)` — 상태는 여기서만 바뀐다
    - `String get placeButtonLabel`, `String get vehicleButtonLabel`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/footsteps/recording/mark_test.dart`:

```dart
import 'package:app/features/footsteps/recording/mark.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime.utc(2026, 11, 9, 1, 2, 3);

  test('kind는 설계 문서의 csv 이름으로 오간다', () {
    expect(MarkKind.countStart.csvName, 'count_start');
    expect(MarkKind.countEnd.csvName, 'count_end');
    for (final kind in MarkKind.values) {
      expect(MarkKind.fromCsvName(kind.csvName), kind);
    }
  });

  test('Mark는 csv 행과 json으로 바뀐다', () {
    final mark = Mark(at: at, kind: MarkKind.board, value: VehicleType.bus);

    expect(mark.toCsvRow(), [at.millisecondsSinceEpoch, 'board', 'bus']);
    final back = Mark.fromJson(mark.toJson());
    expect(back.at, at);
    expect(back.kind, MarkKind.board);
    expect(back.value, 'bus');
  });

  test('알림 버튼 토글: 다음 표시를 만들 뿐 상태는 observe에서만 바뀐다', () {
    final field = FieldState();
    expect(field.placeButtonLabel, '도착');

    final arrive = field.nextPlaceMark(at);
    expect(arrive.kind, MarkKind.arrive);
    expect(field.atPlace, isFalse);

    field.observe(arrive);
    expect(field.atPlace, isTrue);
    expect(field.placeButtonLabel, '출발');
    expect(field.nextPlaceMark(at).kind, MarkKind.depart);
  });

  test('탑승 토글은 종류 미지정(vehicle)으로 표시하고, 다음은 하차다', () {
    final field = FieldState();
    expect(field.vehicleButtonLabel, '탑승');

    final board = field.nextVehicleMark(at);
    expect(board.kind, MarkKind.board);
    expect(board.value, VehicleType.unspecified);

    field.observe(board);
    expect(field.vehicleButtonLabel, '하차');
    final alight = field.nextVehicleMark(at);
    expect(alight.kind, MarkKind.alight);
    expect(alight.value, '');
  });

  test('화면에서 남긴 버스 탑승·출발도 같은 상태를 바꾼다', () {
    final field = FieldState()
      ..observe(Mark(at: at, kind: MarkKind.arrive))
      ..observe(Mark(at: at, kind: MarkKind.board, value: VehicleType.bus));
    expect(field.atPlace, isTrue);
    expect(field.onVehicle, isTrue);

    field
      ..observe(Mark(at: at, kind: MarkKind.depart))
      ..observe(Mark(at: at, kind: MarkKind.alight));
    expect(field.atPlace, isFalse);
    expect(field.onVehicle, isFalse);
  });

  test('걸음 세기·휴대 위치·메모는 현장 상태를 바꾸지 않는다', () {
    final field = FieldState()
      ..observe(Mark(at: at, kind: MarkKind.countStart))
      ..observe(Mark(at: at, kind: MarkKind.carry, value: CarryPosition.bag))
      ..observe(Mark(at: at, kind: MarkKind.note, value: '비 옴'));
    expect(field.atPlace, isFalse);
    expect(field.onVehicle, isFalse);
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `flutter test test/footsteps/recording/mark_test.dart`
Expected: FAIL (URI가 없다는 컴파일 오류)

- [ ] **Step 3: 구현**

`app/lib/features/footsteps/recording/mark.dart`:

```dart
/// 관찰 표시 종류(설계 4-2 `marks.csv`). csvName은 분석이 읽는 계약이다.
enum MarkKind {
  arrive('arrive'),
  depart('depart'),
  board('board'),
  alight('alight'),
  countStart('count_start'),
  countEnd('count_end'),
  carry('carry'),
  note('note');

  const MarkKind(this.csvName);

  final String csvName;

  static MarkKind fromCsvName(String name) => values.firstWhere((k) => k.csvName == name);
}

/// `board` 표시의 값. 알림 버튼으로는 종류를 고를 수 없어 `vehicle`로 남긴다.
abstract final class VehicleType {
  static const bus = 'bus';
  static const subway = 'subway';
  static const unspecified = 'vehicle';
}

/// 휴대 위치(`carry` 표시 값, meta.json의 carryInitial). 위치에 따라 걸음 감지 결과가 달라서
/// 분석 때 나눠 본다(연구 자료 5-1).
abstract final class CarryPosition {
  static const hand = 'hand';
  static const pocket = 'pocket';
  static const bag = 'bag';
  static const all = [hand, pocket, bag];
}

class Mark {
  const Mark({required this.at, required this.kind, this.value = ''});

  final DateTime at;
  final MarkKind kind;
  final String value;

  List<Object?> toCsvRow() => [at.millisecondsSinceEpoch, kind.csvName, value];

  Map<String, Object?> toJson() => {
        'at': at.millisecondsSinceEpoch,
        'kind': kind.csvName,
        'value': value,
      };

  factory Mark.fromJson(Map<String, Object?> json) => Mark(
        at: DateTime.fromMillisecondsSinceEpoch(json['at'] as int, isUtc: true),
        kind: MarkKind.fromCsvName(json['kind'] as String),
        value: json['value'] as String? ?? '',
      );
}

/// 지금 장소 안에 있는지, 탈것에 타 있는지. Android 알림 버튼은 최대 3개라서 도착/출발,
/// 탑승/하차를 버튼 하나씩으로 토글한다 — 다음 누름이 무엇인지 정하려면 지금 상태를 알아야 한다.
///
/// 상태는 [observe]에서만 바뀐다. 알림 버튼이든 화면 버튼이든 실제로 기록된 표시를 그대로 넣어,
/// 두 입력 경로가 서로 다른 상태를 보지 않게 한다.
class FieldState {
  bool atPlace = false;
  bool onVehicle = false;

  Mark nextPlaceMark(DateTime at) =>
      Mark(at: at, kind: atPlace ? MarkKind.depart : MarkKind.arrive);

  Mark nextVehicleMark(DateTime at) => onVehicle
      ? Mark(at: at, kind: MarkKind.alight)
      : Mark(at: at, kind: MarkKind.board, value: VehicleType.unspecified);

  void observe(Mark mark) {
    switch (mark.kind) {
      case MarkKind.arrive:
        atPlace = true;
      case MarkKind.depart:
        atPlace = false;
      case MarkKind.board:
        onVehicle = true;
      case MarkKind.alight:
        onVehicle = false;
      case MarkKind.countStart || MarkKind.countEnd || MarkKind.carry || MarkKind.note:
        break;
    }
  }

  String get placeButtonLabel => atPlace ? '출발' : '도착';

  String get vehicleButtonLabel => onVehicle ? '하차' : '탑승';
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/footsteps/recording/mark_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/footsteps/recording/mark.dart app/test/footsteps/recording/mark_test.dart
git commit -m "feat(app): 관찰 표시와 알림 버튼 토글 상태를 추가한다"
```

---

### Task 4: 정답 기록 모드 본체 (`GroundTruthRecorder`)

**Files:**
- Create: `app/lib/features/footsteps/recording/sensor_samples.dart`
- Create: `app/lib/features/footsteps/recording/recorder_status.dart`
- Create: `app/lib/features/footsteps/recording/ground_truth_recorder.dart`
- Test: `app/test/footsteps/recording/ground_truth_recorder_test.dart`

**Interfaces:**
- Consumes: `SessionFiles`, `SessionError`, `SessionSchema` (Task 2), `Mark`, `FieldState` (Task 3)
- Produces:
  - 센서 값 타입 (`at`은 모두 UTC)
    - `GpsSample({at, fixTime, lat, lng, accuracyM, speedMps?, bearingDeg?, altitudeM?})`
    - `AccelSample({at, x, y, z})`
    - `OsStepSample({at, kind, value})` — `OsStepKind.count` / `OsStepKind.status`
    - `ActivitySample({at, type, confidence})`
    - `BatterySample({at, chargeUah?, currentUa?, levelPct?, tempC?, plugged})`
    - 각 타입에 `List<Object?> toCsvRow()`
  - `abstract interface class SensorSources` — `Stream<GpsSample> gps()`, `Stream<AccelSample> accel()`, `Stream<OsStepSample> osSteps()`, `Stream<ActivitySample> activity()`, `Future<BatterySample> readBattery()`
  - `class RecorderStatus({startedAt, rowCounts, errorCount, atPlace, onVehicle, lastGpsAccuracyM?, lastOsSteps?, lastChargeUah?, lastLevelPct?})` + `toJson()` / `fromJson`
  - `class GroundTruthRecorder({required SensorSources sources, required SessionFiles files, required DateTime Function() clock, required void Function(SessionError) onError, Duration batteryInterval = 30s})`
    - `Future<void> start()`, `Future<void> tick()`, `void mark(Mark)`, `Future<void> stop()`
    - `RecorderStatus get status`, `final FieldState field`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/footsteps/recording/ground_truth_recorder_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:app/features/footsteps/recording/ground_truth_recorder.dart';
import 'package:app/features/footsteps/recording/mark.dart';
import 'package:app/features/footsteps/recording/recorder_status.dart';
import 'package:app/features/footsteps/recording/sensor_samples.dart';
import 'package:app/features/footsteps/recording/session_files.dart';
import 'package:app/features/footsteps/recording/session_meta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeSources implements SensorSources {
  _FakeSources(this.clock);

  final DateTime Function() clock;
  final gpsController = StreamController<GpsSample>();
  final accelController = StreamController<AccelSample>();
  final stepsController = StreamController<OsStepSample>();
  final activityController = StreamController<ActivitySample>();
  final batteryReads = <DateTime>[];
  Object? batteryError;

  @override
  Stream<GpsSample> gps() => gpsController.stream;

  @override
  Stream<AccelSample> accel() => accelController.stream;

  @override
  Stream<OsStepSample> osSteps() => stepsController.stream;

  @override
  Stream<ActivitySample> activity() => activityController.stream;

  @override
  Future<BatterySample> readBattery() async {
    final at = clock();
    batteryReads.add(at);
    final error = batteryError;
    if (error != null) throw error;
    return BatterySample(
      at: at,
      chargeUah: 3012000,
      currentUa: -250000,
      levelPct: 87,
      tempC: 31.5,
      plugged: false,
    );
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late Directory dir;
  late DateTime now;
  late _FakeSources sources;
  late SessionFiles files;
  late List<SessionError> errors;
  late GroundTruthRecorder recorder;

  List<String> lines(String name) => File(p.join(dir.path, name)).readAsLinesSync();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('recorder_test');
    now = DateTime.utc(2026, 11, 9, 1);
    sources = _FakeSources(() => now);
    files = await SessionFiles.open(dir);
    errors = [];
    recorder = GroundTruthRecorder(
      sources: sources,
      files: files,
      clock: () => now,
      onError: errors.add,
    );
  });

  tearDown(() async {
    // Windows는 열린 파일이 있으면 폴더를 지우지 못한다. stop을 부른 테스트도 있어 close는 여러 번 불러도 된다.
    await files.closeAll();
    await dir.delete(recursive: true);
  });

  test('start하면 배터리를 한 번 읽고, 각 센서 값을 해당 CSV에 쓴다', () async {
    await recorder.start();
    final t = now.millisecondsSinceEpoch;
    sources.gpsController.add(GpsSample(
      at: now,
      fixTime: now.subtract(const Duration(seconds: 1)),
      lat: 37.5665,
      lng: 126.978,
      accuracyM: 8.0,
      speedMps: 1.2,
      bearingDeg: 90.0,
      altitudeM: 35.0,
    ));
    sources.accelController.add(AccelSample(at: now, x: 0.1, y: 9.8, z: -0.2));
    sources.stepsController.add(OsStepSample(at: now, kind: OsStepKind.count, value: '1520'));
    sources.stepsController.add(OsStepSample(at: now, kind: OsStepKind.status, value: 'walking'));
    sources.activityController.add(ActivitySample(at: now, type: 'WALKING', confidence: 'HIGH'));
    await _settle();
    await recorder.tick();

    expect(sources.batteryReads, hasLength(1));
    expect(lines('gps.csv')[1], '$t,${t - 1000},37.5665,126.978,8.0,1.2,90.0,35.0');
    expect(lines('accel.csv')[1], '$t,0.1,9.8,-0.2');
    expect(lines('os_steps.csv').sublist(1), ['$t,count,1520', '$t,status,walking']);
    expect(lines('activity.csv')[1], '$t,WALKING,HIGH');
    expect(lines('battery.csv')[1], '$t,3012000,-250000,87,31.5,0');
  });

  test('배터리는 30초가 지나야 다시 읽는다', () async {
    await recorder.start();
    now = now.add(const Duration(seconds: 5));
    await recorder.tick();
    expect(sources.batteryReads, hasLength(1));

    now = now.add(const Duration(seconds: 25));
    await recorder.tick();
    expect(sources.batteryReads, hasLength(2));
  });

  test('센서 하나가 오류를 내도 오류를 남기고 다른 센서는 계속 쓴다', () async {
    await recorder.start();
    sources.stepsController.addError(StateError('no step sensor'));
    sources.accelController.add(AccelSample(at: now, x: 0, y: 0, z: 9.8));
    await _settle();
    await recorder.tick();

    expect(errors.single.source, 'os_steps');
    expect(errors.single.message, contains('no step sensor'));
    expect(lines('accel.csv'), hasLength(2));
    expect(recorder.status.errorCount, 1);
  });

  test('배터리 읽기 실패는 오류로 남기고 행은 쓰지 않는다', () async {
    sources.batteryError = StateError('probe failed');
    await recorder.start();
    await recorder.tick();

    expect(errors.single.source, 'battery');
    expect(lines('battery.csv'), hasLength(1)); // 헤더만
  });

  test('mark는 marks.csv에 쓰고 현장 상태를 바꾼다', () async {
    await recorder.start();
    recorder.mark(Mark(at: now, kind: MarkKind.board, value: VehicleType.subway));
    await recorder.tick();

    expect(lines('marks.csv')[1], '${now.millisecondsSinceEpoch},board,subway');
    expect(recorder.field.onVehicle, isTrue);
    expect(recorder.status.onVehicle, isTrue);
  });

  test('stop하면 구독을 끊고 남은 행을 쓴다', () async {
    await recorder.start();
    sources.accelController.add(AccelSample(at: now, x: 1, y: 2, z: 3));
    await _settle();
    await recorder.stop();

    expect(lines('accel.csv'), hasLength(2));
    expect(sources.gpsController.hasListener, isFalse);
    expect(sources.accelController.hasListener, isFalse);
  });

  test('status는 행 수와 마지막 값을 담고 json으로 오간다', () async {
    await recorder.start();
    sources.gpsController.add(GpsSample(at: now, fixTime: now, lat: 37, lng: 127, accuracyM: 4.5));
    sources.stepsController.add(OsStepSample(at: now, kind: OsStepKind.count, value: '10'));
    await _settle();

    final status = recorder.status;
    expect(status.rowCounts['gps.csv'], 1);
    expect(status.rowCounts['battery.csv'], 1);
    expect(status.lastGpsAccuracyM, 4.5);
    expect(status.lastOsSteps, 10);
    expect(status.lastChargeUah, 3012000);
    expect(status.lastLevelPct, 87);

    final back = RecorderStatus.fromJson(status.toJson());
    expect(back.toJson(), status.toJson());
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `flutter test test/footsteps/recording/ground_truth_recorder_test.dart`
Expected: FAIL (URI가 없다는 컴파일 오류)

- [ ] **Step 3: 센서 값 타입 구현**

`app/lib/features/footsteps/recording/sensor_samples.dart`:

```dart
/// 기록 서비스가 받는 센서 값들. 모든 [at]은 같은 시계(UTC)다 — 설계 4-2의 '같은 시계' 규칙이라
/// 재생기가 파일들을 시각순으로 합칠 수 있다.
class GpsSample {
  const GpsSample({
    required this.at,
    required this.fixTime,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    this.speedMps,
    this.bearingDeg,
    this.altitudeM,
  });

  /// 앱이 값을 받은 시각.
  final DateTime at;

  /// GPS가 알려 준 측위 시각.
  final DateTime fixTime;
  final double lat;
  final double lng;
  final double accuracyM;
  final double? speedMps;
  final double? bearingDeg;
  final double? altitudeM;

  List<Object?> toCsvRow() => [
        at.millisecondsSinceEpoch,
        fixTime.millisecondsSinceEpoch,
        lat,
        lng,
        accuracyM,
        speedMps,
        bearingDeg,
        altitudeM,
      ];
}

class AccelSample {
  const AccelSample({required this.at, required this.x, required this.y, required this.z});

  final DateTime at;
  final double x;
  final double y;
  final double z;

  List<Object?> toCsvRow() => [at.millisecondsSinceEpoch, x, y, z];
}

/// `os_steps.csv`의 kind 값(설계 4-2).
abstract final class OsStepKind {
  /// value = 부팅 후 누적 걸음 수.
  static const count = 'count';

  /// value = OS 보행 상태(`walking`·`stopped`·`unknown`).
  static const status = 'status';
}

class OsStepSample {
  const OsStepSample({required this.at, required this.kind, required this.value});

  final DateTime at;
  final String kind;
  final String value;

  List<Object?> toCsvRow() => [at.millisecondsSinceEpoch, kind, value];
}

class ActivitySample {
  const ActivitySample({required this.at, required this.type, required this.confidence});

  final DateTime at;
  final String type;
  final String confidence;

  List<Object?> toCsvRow() => [at.millisecondsSinceEpoch, type, confidence];
}

class BatterySample {
  const BatterySample({
    required this.at,
    required this.plugged,
    this.chargeUah,
    this.currentUa,
    this.levelPct,
    this.tempC,
  });

  final DateTime at;

  /// 남은 전하량(μAh). 기기가 지원하지 않으면 null.
  final int? chargeUah;
  final int? currentUa;
  final int? levelPct;
  final double? tempC;
  final bool plugged;

  List<Object?> toCsvRow() =>
      [at.millisecondsSinceEpoch, chargeUah, currentUa, levelPct, tempC, plugged];
}

/// 기록에 쓰는 센서 묶음. 실제 구현은 플러그인(plugin_sensor_sources.dart)이고, 테스트는 가짜를 넣는다.
abstract interface class SensorSources {
  Stream<GpsSample> gps();
  Stream<AccelSample> accel();
  Stream<OsStepSample> osSteps();
  Stream<ActivitySample> activity();
  Future<BatterySample> readBattery();
}
```

- [ ] **Step 4: 상태 타입 구현**

`app/lib/features/footsteps/recording/recorder_status.dart`:

```dart
/// 기록 서비스가 5초마다 화면에 보내는 상태. 실험 화면이 "센서가 지금 값을 내고 있는가"를 보여 준다.
class RecorderStatus {
  const RecorderStatus({
    required this.startedAt,
    required this.rowCounts,
    required this.errorCount,
    required this.atPlace,
    required this.onVehicle,
    this.lastGpsAccuracyM,
    this.lastOsSteps,
    this.lastChargeUah,
    this.lastLevelPct,
  });

  final DateTime startedAt;

  /// 파일 이름 → 이번 실행에서 쓴 행 수.
  final Map<String, int> rowCounts;
  final int errorCount;
  final bool atPlace;
  final bool onVehicle;
  final double? lastGpsAccuracyM;
  final int? lastOsSteps;
  final int? lastChargeUah;
  final int? lastLevelPct;

  Map<String, Object?> toJson() => {
        'startedAt': startedAt.millisecondsSinceEpoch,
        'rowCounts': rowCounts,
        'errorCount': errorCount,
        'atPlace': atPlace,
        'onVehicle': onVehicle,
        'lastGpsAccuracyM': lastGpsAccuracyM,
        'lastOsSteps': lastOsSteps,
        'lastChargeUah': lastChargeUah,
        'lastLevelPct': lastLevelPct,
      };

  factory RecorderStatus.fromJson(Map<String, Object?> json) => RecorderStatus(
        startedAt: DateTime.fromMillisecondsSinceEpoch(json['startedAt'] as int, isUtc: true),
        rowCounts: (json['rowCounts'] as Map).map((k, v) => MapEntry(k as String, v as int)),
        errorCount: json['errorCount'] as int,
        atPlace: json['atPlace'] as bool,
        onVehicle: json['onVehicle'] as bool,
        lastGpsAccuracyM: (json['lastGpsAccuracyM'] as num?)?.toDouble(),
        lastOsSteps: json['lastOsSteps'] as int?,
        lastChargeUah: json['lastChargeUah'] as int?,
        lastLevelPct: json['lastLevelPct'] as int?,
      );
}
```

- [ ] **Step 5: 기록 본체 구현**

`app/lib/features/footsteps/recording/ground_truth_recorder.dart`:

```dart
import 'dart:async';

import 'csv_writer.dart';
import 'mark.dart';
import 'recorder_status.dart';
import 'sensor_samples.dart';
import 'session_files.dart';
import 'session_meta.dart';
import 'session_schema.dart';

/// 정답 기록 모드(설계 4-2). 모든 센서를 최대 빈도로 받아 세션 폴더의 CSV에 쓴다.
///
/// 타이머를 안에 두지 않는다. 기록 서비스가 5초마다 [tick]을 불러 배터리 읽기와 디스크 쓰기를
/// 맡기고, 테스트는 시각을 직접 넘긴다.
class GroundTruthRecorder {
  GroundTruthRecorder({
    required SensorSources sources,
    required SessionFiles files,
    required DateTime Function() clock,
    required void Function(SessionError error) onError,
    this.batteryInterval = const Duration(seconds: 30),
  })  : _sources = sources,
        _files = files,
        _clock = clock,
        _onError = onError;

  final SensorSources _sources;
  final SessionFiles _files;
  final DateTime Function() _clock;
  final void Function(SessionError error) _onError;
  final Duration batteryInterval;

  /// 지금 장소 안인지, 탈것에 탔는지. 알림 버튼 토글이 다음 표시를 정할 때 쓴다.
  final FieldState field = FieldState();

  final _subscriptions = <StreamSubscription<Object?>>[];
  DateTime? _startedAt;
  DateTime? _lastBatteryAt;
  int _errorCount = 0;
  double? _lastGpsAccuracyM;
  int? _lastOsSteps;
  int? _lastChargeUah;
  int? _lastLevelPct;

  Future<void> start() async {
    _startedAt = _clock();
    _listen(_sources.gps(), 'gps', (GpsSample s) {
      _files.gps.add(s.toCsvRow());
      _lastGpsAccuracyM = s.accuracyM;
    });
    _listen(_sources.accel(), 'accel', (AccelSample s) => _files.accel.add(s.toCsvRow()));
    _listen(_sources.osSteps(), 'os_steps', (OsStepSample s) {
      _files.osSteps.add(s.toCsvRow());
      if (s.kind == OsStepKind.count) _lastOsSteps = int.tryParse(s.value);
    });
    _listen(
      _sources.activity(),
      'activity',
      (ActivitySample s) => _files.activity.add(s.toCsvRow()),
    );
    await _readBattery();
  }

  /// 센서 하나가 실패해도 나머지는 계속 기록한다(설계 4-2). 실패는 meta.json의 errors로 남긴다.
  void _listen<T>(Stream<T> stream, String source, void Function(T sample) onSample) {
    _subscriptions.add(stream.listen(onSample, onError: (Object e) => _reportError(source, e)));
  }

  /// 서비스의 반복 이벤트(5초)마다 부른다. 배터리는 [batteryInterval]마다만 읽는다.
  Future<void> tick() async {
    final last = _lastBatteryAt;
    if (last == null || _clock().difference(last) >= batteryInterval) await _readBattery();
    await _files.flushAll();
  }

  void mark(Mark mark) {
    field.observe(mark);
    _files.marks.add(mark.toCsvRow());
  }

  RecorderStatus get status {
    final writers = <String, CsvWriter>{
      SessionSchema.gpsFile: _files.gps,
      SessionSchema.accelFile: _files.accel,
      SessionSchema.osStepsFile: _files.osSteps,
      SessionSchema.activityFile: _files.activity,
      SessionSchema.batteryFile: _files.battery,
      SessionSchema.marksFile: _files.marks,
    };
    return RecorderStatus(
      startedAt: _startedAt ?? _clock(),
      rowCounts: {for (final e in writers.entries) e.key: e.value.totalRows},
      errorCount: _errorCount,
      atPlace: field.atPlace,
      onVehicle: field.onVehicle,
      lastGpsAccuracyM: _lastGpsAccuracyM,
      lastOsSteps: _lastOsSteps,
      lastChargeUah: _lastChargeUah,
      lastLevelPct: _lastLevelPct,
    );
  }

  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _files.closeAll();
  }

  Future<void> _readBattery() async {
    _lastBatteryAt = _clock();
    try {
      final battery = await _sources.readBattery();
      _files.battery.add(battery.toCsvRow());
      _lastChargeUah = battery.chargeUah;
      _lastLevelPct = battery.levelPct;
    } catch (e) {
      _reportError('battery', e);
    }
  }

  void _reportError(String source, Object error) {
    _errorCount++;
    _onError(SessionError(at: _clock(), source: source, message: '$error'));
  }
}
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `flutter test test/footsteps/recording/ground_truth_recorder_test.dart`
Expected: PASS (7 tests)

- [ ] **Step 7: 커밋**

```bash
git add app/lib/features/footsteps/recording/sensor_samples.dart app/lib/features/footsteps/recording/recorder_status.dart app/lib/features/footsteps/recording/ground_truth_recorder.dart app/test/footsteps/recording/ground_truth_recorder_test.dart
git commit -m "feat(app): 정답 기록 모드 본체를 추가한다"
```

---

### Task 5: 배터리·기기 정보 로컬 플러그인 (`packages/device_probe`)

서비스 isolate는 `flutter_foreground_task`가 따로 띄우는 엔진이다. 그래서 `MainActivity`에 등록한 MethodChannel은 그 isolate에서 보이지 않는다. pub 플러그인처럼 `GeneratedPluginRegistrant`로 모든 엔진에 자동 등록되도록 로컬 플러그인 패키지로 만든다.

**Files:**
- Create (생성기 사용): `packages/device_probe/` 전체
- Replace: `packages/device_probe/pubspec.yaml`
- Replace: `packages/device_probe/lib/device_probe.dart`
- Replace: `packages/device_probe/android/src/main/kotlin/com/travelfootsteps/device_probe/DeviceProbePlugin.kt`
- Test: `packages/device_probe/test/device_probe_test.dart`

**Interfaces:**
- Produces:
  - `class BatteryReading({int? chargeUah, int? currentUa, int? levelPct, double? tempC, required bool plugged})`
  - `class DeviceInfo({required String model, required int sdkInt, required String appVersion})`
  - `class DeviceProbe` — `const DeviceProbe([MethodChannel channel = const MethodChannel('device_probe')])`, `Future<BatteryReading> readBattery()`, `Future<DeviceInfo> readDevice()`

- [ ] **Step 1: 플러그인 뼈대 생성**

저장소 루트에서 실행한다.

```bash
flutter create --template=plugin --platforms=android --org com.travelfootsteps --project-name device_probe packages/device_probe
```

Expected: `packages/device_probe/`에 `android/`, `lib/`, `example/`, `test/`가 생긴다. 생성된 `android/build.gradle*`은 이 Flutter 버전(3.47.2)의 템플릿이라 AGP 9와 맞으므로 **건드리지 않는다**.

- [ ] **Step 2: 쓰지 않는 생성물 지우기**

```bash
rm -rf packages/device_probe/example
rm -f packages/device_probe/lib/device_probe_platform_interface.dart packages/device_probe/lib/device_probe_method_channel.dart
rm -rf packages/device_probe/test packages/device_probe/android/src/test
```

`packages/device_probe/pubspec.yaml`을 다음 내용으로 바꾼다. `plugin_platform_interface` 의존을 빼는 것이 핵심이다.

```yaml
name: device_probe
description: 배터리 전하량·기기 정보를 읽는 앱 전용 Android 플러그인. 기록 서비스 isolate에서도 동작한다.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.13.2
  flutter: ">=3.47.0"

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  # 생성된 analysis_options.yaml이 flutter_lints를 include한다.
  flutter_lints: ^6.0.0

flutter:
  plugin:
    platforms:
      android:
        package: com.travelfootsteps.device_probe
        pluginClass: DeviceProbePlugin
```

- [ ] **Step 3: 실패하는 테스트 작성**

`packages/device_probe/test/device_probe_test.dart`:

```dart
import 'package:device_probe/device_probe.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('device_probe');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('readBattery는 네이티브 값을 옮기고, 기기가 모르는 값은 null로 둔다', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readBattery');
      return <String, Object?>{
        'chargeUah': 3012000,
        'currentUa': null,
        'levelPct': 87,
        'tempC': 31.5,
        'plugged': false,
      };
    });

    final reading = await const DeviceProbe().readBattery();
    expect(reading.chargeUah, 3012000);
    expect(reading.currentUa, isNull);
    expect(reading.levelPct, 87);
    expect(reading.tempC, 31.5);
    expect(reading.plugged, isFalse);
  });

  test('readDevice는 기종·SDK·앱 버전을 돌려준다', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readDevice');
      return <String, Object?>{'model': 'samsung SM-S921N', 'sdkInt': 35, 'appVersion': '1.0.0'};
    });

    final info = await const DeviceProbe().readDevice();
    expect(info.model, 'samsung SM-S921N');
    expect(info.sdkInt, 35);
    expect(info.appVersion, '1.0.0');
  });
}
```

- [ ] **Step 4: 테스트가 실패하는지 확인**

Run (`packages/device_probe/`에서): `flutter pub get && flutter test`
Expected: FAIL. `DeviceProbe`가 없다는 컴파일 오류(생성된 `lib/device_probe.dart`에는 다른 클래스가 있다)

- [ ] **Step 5: Dart 쪽 구현**

`packages/device_probe/lib/device_probe.dart`를 다음 내용으로 바꾼다.

```dart
import 'package:flutter/services.dart';

/// 배터리 한 번 읽은 값. 기기가 지원하지 않는 값은 null이다(설계 문서 10장 위험 2).
class BatteryReading {
  const BatteryReading({
    required this.plugged,
    this.chargeUah,
    this.currentUa,
    this.levelPct,
    this.tempC,
  });

  factory BatteryReading.fromMap(Map<String, Object?> map) => BatteryReading(
        chargeUah: map['chargeUah'] as int?,
        currentUa: map['currentUa'] as int?,
        levelPct: map['levelPct'] as int?,
        tempC: (map['tempC'] as num?)?.toDouble(),
        plugged: map['plugged'] as bool? ?? false,
      );

  /// BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER (μAh).
  final int? chargeUah;

  /// BatteryManager.BATTERY_PROPERTY_CURRENT_NOW (μA, 방전이면 음수인 기기가 많다).
  final int? currentUa;
  final int? levelPct;
  final double? tempC;
  final bool plugged;
}

class DeviceInfo {
  const DeviceInfo({required this.model, required this.sdkInt, required this.appVersion});

  factory DeviceInfo.fromMap(Map<String, Object?> map) => DeviceInfo(
        model: map['model'] as String,
        sdkInt: map['sdkInt'] as int,
        appVersion: map['appVersion'] as String? ?? 'unknown',
      );

  final String model;
  final int sdkInt;
  final String appVersion;
}

/// 배터리·기기 정보를 읽는다. 플러그인으로 등록되므로 기록 서비스 isolate에서도 같은 채널이 보인다.
class DeviceProbe {
  const DeviceProbe([this._channel = const MethodChannel('device_probe')]);

  final MethodChannel _channel;

  Future<BatteryReading> readBattery() async {
    final map = await _channel.invokeMapMethod<String, Object?>('readBattery');
    return BatteryReading.fromMap(map!);
  }

  Future<DeviceInfo> readDevice() async {
    final map = await _channel.invokeMapMethod<String, Object?>('readDevice');
    return DeviceInfo.fromMap(map!);
  }
}
```

- [ ] **Step 6: Kotlin 쪽 구현**

`packages/device_probe/android/src/main/kotlin/com/travelfootsteps/device_probe/DeviceProbePlugin.kt`를 다음 내용으로 바꾼다.

```kotlin
package com.travelfootsteps.device_probe

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** 배터리 전하량·전류와 기기 정보를 읽는다. 엔진마다 붙으므로 포그라운드 서비스 isolate에서도 동작한다. */
class DeviceProbePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "device_probe")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readBattery" -> result.success(readBattery())
            "readDevice" -> result.success(readDevice())
            else -> result.notImplemented()
        }
    }

    private fun readBattery(): Map<String, Any?> {
        val manager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        // 지원하지 않는 속성은 Integer.MIN_VALUE를 돌려준다. null로 바꿔 Dart 쪽에서 '모름'으로 다룬다.
        fun property(id: Int): Int? = manager.getIntProperty(id).takeIf { it != Int.MIN_VALUE }

        // 수신기 없이(null) 등록하면 마지막 배터리 상태(sticky intent)만 읽고 끝난다.
        val sticky: Intent? = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = sticky?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = sticky?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val temperature = sticky?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE) ?: Int.MIN_VALUE
        val plugged = sticky?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0

        return mapOf(
            "chargeUah" to property(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER),
            "currentUa" to property(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW),
            "levelPct" to if (level >= 0 && scale > 0) level * 100 / scale else null,
            "tempC" to if (temperature != Int.MIN_VALUE) temperature / 10.0 else null,
            "plugged" to (plugged != 0),
        )
    }

    private fun readDevice(): Map<String, Any?> {
        @Suppress("DEPRECATION")
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        return mapOf(
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "sdkInt" to Build.VERSION.SDK_INT,
            "appVersion" to info.versionName,
        )
    }
}
```

- [ ] **Step 7: 테스트 통과 확인**

Run (`packages/device_probe/`에서): `flutter test`
Expected: PASS (2 tests)

Run (`packages/device_probe/`에서): `dart analyze`
Expected: `No issues found!`

- [ ] **Step 8: 빌드 산출물 무시 설정 후 커밋**

루트 `.gitignore`의 `# Flutter / Dart` 묶음 아래에 다음 두 줄을 추가한다.

```
packages/*/build/
packages/*/.dart_tool/
```

```bash
git add .gitignore packages/device_probe
git status --short packages/device_probe   # build/, .dart_tool/가 없어야 한다
git commit -m "feat(device_probe): 배터리 전하량과 기기 정보를 읽는 로컬 플러그인을 추가한다"
```

---

### Task 6: 실제 센서 연결 (`PluginSensorSources`) + 의존성·권한

**Files:**
- Modify: `app/pubspec.yaml` (dependencies)
- Modify: `app/android/app/src/main/AndroidManifest.xml` (권한)
- Create: `app/lib/features/footsteps/recording/plugin_sensor_sources.dart`
- Test: `app/test/footsteps/recording/plugin_sensor_sources_test.dart`

**Interfaces:**
- Consumes: `SensorSources`와 센서 값 타입 (Task 4), `DeviceProbe` (Task 5)
- Produces:
  - `class PluginSensorSources implements SensorSources` — `PluginSensorSources({DateTime Function()? clock, DeviceProbe probe = const DeviceProbe()})`
  - `GpsSample gpsSampleFromPosition(Position position, DateTime recordedAt)`
  - `DateTime accelTimestamp(DateTime eventTime, DateTime recordedAt)`
  - `Stream<T> mergeStreams<T>(List<Stream<T>> streams)`

- [ ] **Step 1: 의존성 추가**

`app/pubspec.yaml`의 `dependencies:` 끝(`timezone: 0.11.1` 다음 줄)에 추가한다.

```yaml
  # R1 기록 서비스(설계 2026-11-07 4장): 50Hz 가속도, OS 걸음 센서, 구글 활동 인식, 배터리 전하량.
  sensors_plus: ^7.1.1
  pedometer: ^4.2.0
  flutter_activity_recognition: ^4.0.0
  device_probe:
    path: ../packages/device_probe
```

Run (`app/`에서): `flutter pub get`
Expected: `Got dependencies!`

- [ ] **Step 2: 매니페스트 권한 추가**

`app/android/app/src/main/AndroidManifest.xml`의 `POST_NOTIFICATIONS` 권한 줄 다음에 추가한다.

```xml
    <!-- R1 기록 서비스: OS 걸음 센서(pedometer)와 구글 활동 인식. Android 10+는 앞의 것, 9 이하는 뒤의 것을 쓴다. -->
    <uses-permission android:name="android.permission.ACTIVITY_RECOGNITION" />
    <uses-permission android:name="com.google.android.gms.permission.ACTIVITY_RECOGNITION" />
```

- [ ] **Step 3: 실패하는 테스트 작성**

`app/test/footsteps/recording/plugin_sensor_sources_test.dart`:

```dart
import 'dart:async';

import 'package:app/features/footsteps/recording/plugin_sensor_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  test('Position을 GpsSample로 옮긴다: 받은 시각과 측위 시각을 따로 남긴다', () {
    final fixTime = DateTime.utc(2026, 11, 9, 1, 0, 0);
    final recordedAt = DateTime.utc(2026, 11, 9, 1, 0, 1);
    final position = Position(
      latitude: 37.5665,
      longitude: 126.978,
      timestamp: fixTime,
      accuracy: 6.5,
      altitude: 38.0,
      altitudeAccuracy: 3,
      heading: 270.0,
      headingAccuracy: 10,
      speed: 1.3,
      speedAccuracy: 0.5,
    );

    final sample = gpsSampleFromPosition(position, recordedAt);
    expect(sample.at, recordedAt);
    expect(sample.fixTime, fixTime);
    expect(sample.lat, 37.5665);
    expect(sample.lng, 126.978);
    expect(sample.accuracyM, 6.5);
    expect(sample.speedMps, 1.3);
    expect(sample.bearingDeg, 270.0);
    expect(sample.altitudeM, 38.0);
  });

  test('가속도는 센서 이벤트 시각을 쓰되, 기록 시각과 10초 넘게 다르면 기록 시각을 쓴다', () {
    final recordedAt = DateTime.utc(2026, 11, 9, 1);
    final close = recordedAt.subtract(const Duration(milliseconds: 40));
    expect(accelTimestamp(close, recordedAt), close);

    final bootClock = DateTime.utc(1970, 1, 3); // 부팅 후 경과 시간이 그대로 들어온 경우
    expect(accelTimestamp(bootClock, recordedAt), recordedAt);
  });

  test('mergeStreams는 두 스트림의 값과 오류를 하나로 내보내고, 취소하면 둘 다 끊는다', () async {
    final a = StreamController<int>();
    final b = StreamController<int>();
    final values = <int>[];
    final errors = <Object>[];

    final subscription = mergeStreams([a.stream, b.stream]).listen(values.add, onError: errors.add);
    a.add(1);
    b.add(2);
    b.addError(StateError('x'));
    await Future<void>.delayed(Duration.zero);

    expect(values, [1, 2]);
    expect(errors.single, isA<StateError>());

    await subscription.cancel();
    expect(a.hasListener, isFalse);
    expect(b.hasListener, isFalse);
  });
}
```

- [ ] **Step 4: 테스트가 실패하는지 확인**

Run: `flutter test test/footsteps/recording/plugin_sensor_sources_test.dart`
Expected: FAIL (URI가 없다는 컴파일 오류)

- [ ] **Step 5: 구현**

`app/lib/features/footsteps/recording/plugin_sensor_sources.dart`:

```dart
import 'dart:async';

import 'package:device_probe/device_probe.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'sensor_samples.dart';

/// [SensorSources]의 실제 구현. 기록 서비스 isolate 안에서 플러그인을 직접 부른다.
class PluginSensorSources implements SensorSources {
  PluginSensorSources({DateTime Function()? clock, DeviceProbe probe = const DeviceProbe()})
      : _clock = clock ?? (() => DateTime.now().toUtc()),
        _probe = probe;

  final DateTime Function() _clock;
  final DeviceProbe _probe;

  /// 1초 간격, 거리 필터 없음 — 정답 경로라 움직이지 않아도 매초 남긴다(설계 4-2).
  @override
  Stream<GpsSample> gps() => Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 1),
        ),
      ).map((position) => gpsSampleFromPosition(position, _clock()));

  /// 약 50Hz(20ms). 걸음은 초당 2회 안팎이라 이 정도면 피크를 놓치지 않는다.
  @override
  Stream<AccelSample> accel() =>
      accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 20)).map(
        (e) => AccelSample(at: accelTimestamp(e.timestamp, _clock()), x: e.x, y: e.y, z: e.z),
      );

  @override
  Stream<OsStepSample> osSteps() => mergeStreams([
        Pedometer.stepCountStream.map(
          (s) => OsStepSample(at: _clock(), kind: OsStepKind.count, value: '${s.steps}'),
        ),
        Pedometer.pedestrianStatusStream.map(
          (s) => OsStepSample(at: _clock(), kind: OsStepKind.status, value: s.status),
        ),
      ]);

  @override
  Stream<ActivitySample> activity() => FlutterActivityRecognition.instance.activityStream.map(
        (a) => ActivitySample(at: _clock(), type: a.type.name, confidence: a.confidence.name),
      );

  @override
  Future<BatterySample> readBattery() async {
    final reading = await _probe.readBattery();
    return BatterySample(
      at: _clock(),
      chargeUah: reading.chargeUah,
      currentUa: reading.currentUa,
      levelPct: reading.levelPct,
      tempC: reading.tempC,
      plugged: reading.plugged,
    );
  }
}

GpsSample gpsSampleFromPosition(Position position, DateTime recordedAt) => GpsSample(
      at: recordedAt,
      fixTime: position.timestamp.toUtc(),
      lat: position.latitude,
      lng: position.longitude,
      accuracyM: position.accuracy,
      speedMps: position.speed,
      bearingDeg: position.heading,
      altitudeM: position.altitude,
    );

/// 가속도 이벤트는 OS가 묶어서 늦게 전달할 수 있어 받은 시각보다 센서 이벤트 시각이 정확하다.
/// 다만 기기에 따라 이벤트 시각의 기준이 다를 수 있어(부팅 후 경과 시간 등) 기록 시각과
/// 10초 넘게 차이 나면 기록 시각을 쓴다 — 같은 시계 규칙(설계 4-2)을 깨지 않기 위해서다.
DateTime accelTimestamp(DateTime eventTime, DateTime recordedAt) {
  final event = eventTime.toUtc();
  return event.difference(recordedAt).abs() > const Duration(seconds: 10) ? recordedAt : event;
}

/// 여러 스트림을 하나로 합친다(package:async의 StreamGroup.merge와 같은 동작). 의존성을 늘리지 않으려고
/// 직접 둔다.
Stream<T> mergeStreams<T>(List<Stream<T>> streams) {
  final subscriptions = <StreamSubscription<T>>[];
  late final StreamController<T> controller;
  controller = StreamController<T>(
    onListen: () {
      for (final stream in streams) {
        subscriptions.add(stream.listen(controller.add, onError: controller.addError));
      }
    },
    onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    },
  );
  return controller.stream;
}
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `flutter test test/footsteps/recording/plugin_sensor_sources_test.dart`
Expected: PASS (3 tests)

Run: `dart analyze lib/features/footsteps/recording test/footsteps/recording`
Expected: `No issues found!`

- [ ] **Step 7: debug 빌드로 플러그인 호환 확인**

새로 넣은 플러그인들이 AGP 9.1·compileSdk 37에서 빌드되는지 확인한다. `flutter_activity_recognition` 4.0.0은 2년 전 버전이라 가장 위험하다.

Run (`app/`에서): `flutter build apk --debug`
Expected: `✓ Built build\app\outputs\flutter-apk\app-debug.apk`

**멈춤 조건:** 빌드가 특정 플러그인(예: `flutter_activity_recognition`의 namespace·Kotlin 오류) 때문에 실패하면 여기서 멈춘다. 오류 전문과 원인 플러그인을 사용자에게 보고한다. 그 센서를 `device_probe`의 Kotlin 코드로 대신 구현할지는 사용자와 정한다. compileSdk는 바꾸지 않는다.

- [ ] **Step 8: 커밋**

```bash
git add app/pubspec.yaml app/pubspec.lock app/android/app/src/main/AndroidManifest.xml app/lib/features/footsteps/recording/plugin_sensor_sources.dart app/test/footsteps/recording/plugin_sensor_sources_test.dart
git commit -m "feat(app): 기록 서비스가 쓸 실제 센서 연결을 추가한다"
```

---

### Task 7: 기록 서비스 (포그라운드 서비스 + TaskHandler + 화면 쪽 제어)

**Files:**
- Modify: `app/pubspec.yaml` (`flutter_foreground_task`)
- Modify: `app/android/app/src/main/AndroidManifest.xml` (권한, `<service>`)
- Modify: `app/lib/main.dart` (`initCommunicationPort`)
- Create: `app/lib/features/footsteps/recording/recording_config.dart`
- Create: `app/lib/features/footsteps/recording/recording_messages.dart`
- Create: `app/lib/features/footsteps/recording/recording_task_handler.dart`
- Create: `app/lib/features/footsteps/recording/recording_controller.dart`
- Create: `app/lib/features/footsteps/recording/recording_providers.dart`
- Test: `app/test/footsteps/recording/recording_messages_test.dart`

**Interfaces:**
- Consumes:
  - `GroundTruthRecorder`, `RecorderStatus` (Task 4)
  - `SessionFiles`, `SessionMeta`, `SessionError`, `RecordingMode`, `sessionDirName` (Task 2)
  - `Mark`, `FieldState` (Task 3)
  - `PluginSensorSources` (Task 6), `DeviceProbe` (Task 5)
- Produces:
  - `class RecordingConfig({required RecordingMode mode, required String sessionDir, required String carryInitial, String? note})`
    - `static const storageKey = 'recording_config'`, `toJson`, `fromJson`
  - `String encodeMarkMessage(Mark)`, `Mark? decodeMarkMessage(Object data)`
  - `String encodeStatusMessage(RecorderStatus)`, `RecorderStatus? decodeStatusMessage(Object data)`
  - `void recordingStartCallback()` (top-level 진입점), `class RecordingTaskHandler extends TaskHandler`
  - `const placeButtonId = 'mark_place'`, `const vehicleButtonId = 'mark_vehicle'`, `List<NotificationButton> recordingNotificationButtons(FieldState)`
  - `abstract interface class RecordingController`
    - `Future<bool> isRunning()`
    - `Future<void> start({required RecordingMode mode, required String carryInitial, String? note})`
    - `Future<void> stop()`
    - `void sendMark(Mark mark)`
    - `Stream<RecorderStatus> statusStream()`
  - `class ForegroundRecordingController implements RecordingController`
  - `Future<Directory> defaultSessionsRoot()`
  - `final recordingControllerProvider = Provider<RecordingController>`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/footsteps/recording/recording_messages_test.dart`:

```dart
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
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `flutter test test/footsteps/recording/recording_messages_test.dart`
Expected: FAIL (URI가 없다는 컴파일 오류)

- [ ] **Step 3: 설정·메시지 구현**

`app/lib/features/footsteps/recording/recording_config.dart`:

```dart
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
```

`app/lib/features/footsteps/recording/recording_messages.dart`:

```dart
import 'dart:convert';

import 'mark.dart';
import 'recorder_status.dart';

// 화면(main isolate)과 기록 서비스(task isolate) 사이 메시지. 플러그인 포트로는 문자열·Map·List만
// 그대로 보낼 수 있어 JSON 문자열로 주고받고, 'type'으로 종류를 가른다.

String encodeMarkMessage(Mark mark) => jsonEncode({'type': 'mark', ...mark.toJson()});

Mark? decodeMarkMessage(Object data) {
  final json = _decode(data, 'mark');
  if (json == null) return null;
  try {
    return Mark.fromJson(json);
  } catch (_) {
    return null;
  }
}

String encodeStatusMessage(RecorderStatus status) =>
    jsonEncode({'type': 'status', ...status.toJson()});

RecorderStatus? decodeStatusMessage(Object data) {
  final json = _decode(data, 'status');
  if (json == null) return null;
  try {
    return RecorderStatus.fromJson(json);
  } catch (_) {
    return null;
  }
}

Map<String, Object?>? _decode(Object data, String type) {
  if (data is! String) return null;
  try {
    final json = jsonDecode(data);
    if (json is Map<String, Object?> && json['type'] == type) return json;
  } on FormatException {
    return null;
  }
  return null;
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/footsteps/recording/recording_messages_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: 포그라운드 서비스 의존성과 매니페스트**

`app/pubspec.yaml`에서 Task 6에 넣은 `device_probe:` 묶음 바로 위에 추가한다.

```yaml
  flutter_foreground_task: ^11.0.3
```

Run: `flutter pub get`

`AndroidManifest.xml`에서 Task 6에 넣은 활동 인식 권한 다음에 추가한다.

```xml
    <!-- R1 기록 서비스: 화면이 꺼져도 기록을 이어 가는 위치 타입 포그라운드 서비스(Android 14+는 타입별 권한 필요).
         WAKE_LOCK은 모든 방식을 같은 조건(부분 wake lock)에서 재기 위해 쓴다(설계 4-1, 10장 위험 3). -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
```

`<application>` 안, `ScheduledNotificationBootReceiver` `</receiver>` 다음에 추가한다.

```xml
        <!-- R1 기록 서비스(flutter_foreground_task). 기록 로직은 lib/features/footsteps/recording/recording_task_handler.dart. -->
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="location"
            android:exported="false" />
```

- [ ] **Step 6: TaskHandler 구현**

`app/lib/features/footsteps/recording/recording_task_handler.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:device_probe/device_probe.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as p;

import 'ground_truth_recorder.dart';
import 'mark.dart';
import 'plugin_sensor_sources.dart';
import 'recording_config.dart';
import 'recording_messages.dart';
import 'session_files.dart';
import 'session_meta.dart';

const placeButtonId = 'mark_place';
const vehicleButtonId = 'mark_vehicle';

/// 알림 버튼 두 개(도착/출발, 탑승/하차 토글). Android는 알림 버튼을 최대 3개까지만 보여 준다.
List<NotificationButton> recordingNotificationButtons(FieldState field) => [
      NotificationButton(id: placeButtonId, text: field.placeButtonLabel),
      NotificationButton(id: vehicleButtonId, text: field.vehicleButtonLabel),
    ];

/// 기록 서비스 isolate의 진입점. startService(callback:)로 넘기므로 top-level이어야 한다.
@pragma('vm:entry-point')
void recordingStartCallback() {
  FlutterForegroundTask.setTaskHandler(RecordingTaskHandler());
}

/// 기록 서비스 본체. 화면과 다른 isolate에서 돌므로 Riverpod 등 화면 쪽 상태를 쓰지 않는다.
/// R1은 정답 기록 모드만 있다. R4·R7이 [RecordingConfig.mode]로 갈라 다른 기록기를 붙인다.
class RecordingTaskHandler extends TaskHandler {
  GroundTruthRecorder? _recorder;
  SessionMetaStore? _metaStore;
  SessionMeta? _meta;

  DateTime _now() => DateTime.now().toUtc();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 이 isolate에서 Dart 쪽 등록이 필요한 플러그인(geolocator_android 등)을 쓰려면 먼저 불러야 한다.
    DartPluginRegistrant.ensureInitialized();

    final raw = await FlutterForegroundTask.getData<String>(key: RecordingConfig.storageKey);
    if (raw == null) {
      await FlutterForegroundTask.stopService();
      return;
    }
    final config = RecordingConfig.fromJson(jsonDecode(raw) as Map<String, Object?>);
    final files = await SessionFiles.open(Directory(config.sessionDir));
    _metaStore = files.meta;
    _meta = await files.meta.read() ?? await _newMeta(config);
    if (starter == TaskStarter.system) {
      // 시스템이 서비스를 죽였다 다시 띄웠다. 같은 세션 폴더에 이어 쓰되, 공백 구간을 분석에서 알 수 있게 남긴다.
      _meta = _meta!.withError(
        SessionError(at: _now(), source: 'service', message: 'restarted by system'),
      );
    }
    await files.meta.write(_meta!);

    final recorder = GroundTruthRecorder(
      sources: PluginSensorSources(),
      files: files,
      clock: _now,
      onError: _addError,
    );
    _recorder = recorder;
    await recorder.start();
  }

  Future<SessionMeta> _newMeta(RecordingConfig config) async {
    // 기기 정보는 부가 정보다. 읽지 못해도 기록 자체는 시작한다.
    DeviceInfo device;
    try {
      device = await const DeviceProbe().readDevice();
    } catch (_) {
      device = const DeviceInfo(model: 'unknown', sdkInt: 0, appVersion: 'unknown');
    }
    return SessionMeta(
      sessionId: p.basename(config.sessionDir),
      mode: config.mode,
      deviceModel: device.model,
      androidSdk: device.sdkInt,
      appVersion: device.appVersion,
      startedAt: _now(),
      carryInitial: config.carryInitial,
      note: config.note,
    );
  }

  void _addError(SessionError error) {
    final meta = _meta;
    final store = _metaStore;
    if (meta == null || store == null) return;
    _meta = meta.withError(error);
    unawaited(store.write(_meta!));
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    final recorder = _recorder;
    if (recorder == null) return;
    unawaited(recorder.tick().then((_) {
      FlutterForegroundTask.sendDataToMain(encodeStatusMessage(recorder.status));
    }));
  }

  @override
  void onReceiveData(Object data) {
    final mark = decodeMarkMessage(data);
    if (mark != null) _applyMark(mark);
  }

  @override
  void onNotificationButtonPressed(String id) {
    final recorder = _recorder;
    if (recorder == null) return;
    final mark = switch (id) {
      placeButtonId => recorder.field.nextPlaceMark(_now()),
      vehicleButtonId => recorder.field.nextVehicleMark(_now()),
      _ => null,
    };
    if (mark != null) _applyMark(mark);
  }

  void _applyMark(Mark mark) {
    final recorder = _recorder;
    if (recorder == null) return;
    recorder.mark(mark);
    unawaited(FlutterForegroundTask.updateService(
      notificationButtons: recordingNotificationButtons(recorder.field),
    ));
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _recorder?.stop();
    final meta = _meta;
    final store = _metaStore;
    if (meta != null && store != null) {
      _meta = meta.copyWith(endedAt: _now());
      await store.write(_meta!);
    }
  }
}
```

- [ ] **Step 7: 화면 쪽 제어 구현**

`app/lib/features/footsteps/recording/recording_controller.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'mark.dart';
import 'recorder_status.dart';
import 'recording_config.dart';
import 'recording_messages.dart';
import 'recording_mode.dart';
import 'recording_task_handler.dart';

/// 실험 화면이 기록 서비스를 다루는 창구. 위젯 테스트는 가짜 구현을 넣는다.
abstract interface class RecordingController {
  Future<bool> isRunning();
  Future<void> start({required RecordingMode mode, required String carryInitial, String? note});
  Future<void> stop();
  void sendMark(Mark mark);
  Stream<RecorderStatus> statusStream();
}

const _recordingServiceId = 7101;

/// 세션 폴더들의 상위 폴더. adb pull로 꺼낼 수 있게 앱 전용 외부 저장소
/// (`/sdcard/Android/data/<패키지>/files/sessions`)를 쓴다.
Future<Directory> defaultSessionsRoot() async {
  final external = await getExternalStorageDirectory();
  if (external == null) throw StateError('외부 저장소를 쓸 수 없습니다.');
  return Directory(p.join(external.path, 'sessions'));
}

class ForegroundRecordingController implements RecordingController {
  ForegroundRecordingController({
    Future<Directory> Function() sessionsRoot = defaultSessionsRoot,
    DateTime Function() clock = DateTime.now,
  })  : _sessionsRoot = sessionsRoot,
        _clock = clock;

  final Future<Directory> Function() _sessionsRoot;
  final DateTime Function() _clock;

  void _initService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'footstep_recording',
        channelName: '발걸음 기록',
        channelDescription: '발걸음 실험·여행 기록이 진행 중일 때 표시됩니다.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // 5초마다 디스크에 쓰고 화면에 상태를 보낸다(설계 4-2).
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  @override
  Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  @override
  Future<void> start({
    required RecordingMode mode,
    required String carryInitial,
    String? note,
  }) async {
    final root = await _sessionsRoot();
    final dir = Directory(p.join(root.path, sessionDirName(_clock(), mode)));
    await dir.create(recursive: true);
    final config = RecordingConfig(
      mode: mode,
      sessionDir: dir.path,
      carryInitial: carryInitial,
      note: note,
    );
    await FlutterForegroundTask.saveData(
      key: RecordingConfig.storageKey,
      value: jsonEncode(config.toJson()),
    );

    _initService();
    final result = await FlutterForegroundTask.startService(
      serviceId: _recordingServiceId,
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: '발걸음 실험 기록 중',
      notificationText: '정답 기록 모드 · 알림 버튼으로 도착·탑승을 표시하세요',
      notificationButtons: recordingNotificationButtons(FieldState()),
      callback: recordingStartCallback,
    );
    if (result is ServiceRequestFailure) {
      throw StateError('기록 서비스를 시작하지 못했습니다: ${result.error}');
    }
  }

  @override
  Future<void> stop() async {
    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestFailure) {
      throw StateError('기록 서비스를 멈추지 못했습니다: ${result.error}');
    }
  }

  @override
  void sendMark(Mark mark) => FlutterForegroundTask.sendDataToTask(encodeMarkMessage(mark));

  @override
  Stream<RecorderStatus> statusStream() {
    late final StreamController<RecorderStatus> controller;
    void onData(Object data) {
      final status = decodeStatusMessage(data);
      if (status != null) controller.add(status);
    }

    controller = StreamController<RecorderStatus>(
      onListen: () => FlutterForegroundTask.addTaskDataCallback(onData),
      onCancel: () => FlutterForegroundTask.removeTaskDataCallback(onData),
    );
    return controller.stream;
  }
}
```

`app/lib/features/footsteps/recording/recording_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recording_controller.dart';

final recordingControllerProvider =
    Provider<RecordingController>((ref) => ForegroundRecordingController());
```

- [ ] **Step 8: main.dart에 통신 포트 초기화**

`app/lib/main.dart`의 import 묶음에 추가한다.

```dart
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
```

`await Firebase.initializeApp();` 바로 다음 줄에 추가한다.

```dart
  // 기록 서비스(isolate)가 보내는 상태를 받으려면 runApp 전에 포트를 열어야 한다(flutter_foreground_task 요구).
  FlutterForegroundTask.initCommunicationPort();
```

- [ ] **Step 9: 전체 확인**

Run (`app/`에서): `dart analyze`
Expected: `No issues found!`. 이번 Task가 만든 파일에 대한 경고가 없어야 한다. 기존 경고가 있었다면 그 수가 늘지 않아야 한다.

Run: `flutter test`
Expected: 전체 PASS

Run: `flutter build apk --debug`
Expected: `✓ Built build\app\outputs\flutter-apk\app-debug.apk`

- [ ] **Step 10: 커밋**

```bash
git add app/pubspec.yaml app/pubspec.lock app/android/app/src/main/AndroidManifest.xml app/lib/main.dart app/lib/features/footsteps/recording/recording_config.dart app/lib/features/footsteps/recording/recording_messages.dart app/lib/features/footsteps/recording/recording_task_handler.dart app/lib/features/footsteps/recording/recording_controller.dart app/lib/features/footsteps/recording/recording_providers.dart app/test/footsteps/recording/recording_messages_test.dart
git commit -m "feat(app): 화면이 꺼져도 도는 기록 서비스를 추가한다"
```

---

### Task 8: 실험 화면 최소판 + 경로 + 입구

실기기 점검(Task 10)에 필요한 만큼만 만든다: 권한 요청, 시작·종료, 상태 보기. 관찰 표시와 세션 목록은 Task 11·12에서 붙인다.

**Files:**
- Create: `app/lib/features/footsteps/lab/recording_permissions.dart`
- Create: `app/lib/features/footsteps/lab/lab_permissions_panel.dart`
- Create: `app/lib/features/footsteps/lab/lab_status_card.dart`
- Create: `app/lib/features/footsteps/lab/lab_page.dart`
- Modify: `app/lib/features/footsteps/recording/recording_providers.dart`
- Modify: `app/lib/router.dart`
- Modify: `app/lib/features/footsteps/map/world_map_page.dart`
- Modify: `app/lib/features/footsteps/footsteps_page.dart`
- Test: `app/test/footsteps/lab/lab_page_test.dart`
- Test: `app/test/footsteps/lab/fake_recording_controller.dart`
- Modify (test): `app/test/router_test.dart`

**Interfaces:**
- Consumes: `RecordingController`, `recordingControllerProvider` (Task 7), `RecorderStatus` (Task 4), `RecordingMode` (Task 2), `CarryPosition` (Task 3)
- Produces:
  - `class PermissionItem(String label, bool granted)`, `Future<List<PermissionItem>> requestRecordingPermissions()`
  - `final recordingPermissionRequesterProvider = Provider<Future<List<PermissionItem>> Function()>`
  - `class LabPage extends ConsumerStatefulWidget`
  - `class LabStatusCard({required RecorderStatus? status, required bool running, DateTime Function()? now})`
  - `String formatElapsed(Duration)`
  - `AppRoutes.footstepsLab = '/footsteps/lab'`
  - `WorldMapPage({..., VoidCallback? onLabRequested})`
  - 테스트 공용: `FakeRecordingController implements RecordingController`

- [ ] **Step 1: 테스트용 가짜 컨트롤러 작성**

`app/test/footsteps/lab/fake_recording_controller.dart`:

```dart
import 'dart:async';

import 'package:app/features/footsteps/recording/mark.dart';
import 'package:app/features/footsteps/recording/recorder_status.dart';
import 'package:app/features/footsteps/recording/recording_controller.dart';
import 'package:app/features/footsteps/recording/recording_mode.dart';

/// 실험 화면 위젯 테스트용. 실제 서비스 대신 호출을 기록하고, 상태는 [statusController]로 직접 흘린다.
class FakeRecordingController implements RecordingController {
  final statusController = StreamController<RecorderStatus>.broadcast();
  bool running = false;
  Object? startError;
  final starts = <({RecordingMode mode, String carry})>[];
  int stops = 0;
  final marks = <Mark>[];

  @override
  Future<bool> isRunning() async => running;

  @override
  Future<void> start({
    required RecordingMode mode,
    required String carryInitial,
    String? note,
  }) async {
    final error = startError;
    if (error != null) throw error;
    starts.add((mode: mode, carry: carryInitial));
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
```

- [ ] **Step 2: 실패하는 위젯 테스트 작성**

`app/test/footsteps/lab/lab_page_test.dart`:

```dart
import 'package:app/features/footsteps/lab/lab_page.dart';
import 'package:app/features/footsteps/lab/lab_status_card.dart';
import 'package:app/features/footsteps/lab/recording_permissions.dart';
import 'package:app/features/footsteps/recording/recorder_status.dart';
import 'package:app/features/footsteps/recording/recording_mode.dart';
import 'package:app/features/footsteps/recording/recording_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  testWidgets('이미 기록 중이면 들어오자마자 종료 버튼을 보여 준다', (tester) async {
    final controller = FakeRecordingController()..running = true;
    await pumpLab(tester, controller);

    expect(find.text('기록 종료'), findsOneWidget);
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
```

- [ ] **Step 3: 테스트가 실패하는지 확인**

Run: `flutter test test/footsteps/lab/lab_page_test.dart`
Expected: FAIL (URI가 없다는 컴파일 오류)

- [ ] **Step 4: 권한 요청 구현**

`app/lib/features/footsteps/lab/recording_permissions.dart`:

```dart
import 'package:permission_handler/permission_handler.dart';

/// 권한 하나의 결과. 실험 화면에 그대로 보여 준다.
class PermissionItem {
  const PermissionItem(this.label, this.granted);

  final String label;
  final bool granted;
}

/// 정답 기록 모드에 필요한 권한을 차례로 요청한다.
///
/// 위치는 '앱 사용 중'으로 충분하다. 서비스를 화면이 떠 있을 때 시작하므로, 위치 타입 포그라운드
/// 서비스는 화면이 꺼진 뒤에도 위치를 받는다. 신체 활동은 OS 걸음 센서와 활동 인식이 함께 쓴다.
Future<List<PermissionItem>> requestRecordingPermissions() async {
  Future<bool> ask(Permission permission) async => (await permission.request()).isGranted;

  return [
    PermissionItem('위치(앱 사용 중)', await ask(Permission.locationWhenInUse)),
    PermissionItem('신체 활동(걸음·활동 인식)', await ask(Permission.activityRecognition)),
    PermissionItem('알림(기록 중 표시)', await ask(Permission.notification)),
    PermissionItem('배터리 최적화 제외', await ask(Permission.ignoreBatteryOptimizations)),
  ];
}
```

`app/lib/features/footsteps/recording/recording_providers.dart`를 다음 내용으로 바꾼다.

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lab/recording_permissions.dart';
import 'recording_controller.dart';

final recordingControllerProvider =
    Provider<RecordingController>((ref) => ForegroundRecordingController());

/// 권한 요청 함수. 위젯 테스트는 실제 권한 창 대신 정해 둔 결과를 넣는다.
final recordingPermissionRequesterProvider =
    Provider<Future<List<PermissionItem>> Function()>((ref) => requestRecordingPermissions);
```

- [ ] **Step 5: 패널·카드·화면 구현**

`app/lib/features/footsteps/lab/lab_permissions_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../recording/recording_providers.dart';
import 'recording_permissions.dart';

class LabPermissionsPanel extends ConsumerStatefulWidget {
  const LabPermissionsPanel({super.key});

  @override
  ConsumerState<LabPermissionsPanel> createState() => _LabPermissionsPanelState();
}

class _LabPermissionsPanelState extends ConsumerState<LabPermissionsPanel> {
  List<PermissionItem>? _items;

  Future<void> _request() async {
    final items = await ref.read(recordingPermissionRequesterProvider)();
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('권한', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton(
              key: const Key('lab-permissions'),
              onPressed: _request,
              child: const Text('확인·요청'),
            ),
          ],
        ),
        if (items != null)
          for (final item in items) Text('${item.label}: ${item.granted ? '허용' : '거부'}'),
      ],
    );
  }
}
```

`app/lib/features/footsteps/lab/lab_status_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../recording/recorder_status.dart';

String formatElapsed(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  final seconds = d.inSeconds % 60;
  return hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '${two(minutes)}:${two(seconds)}';
}

/// 기록 서비스가 5초마다 보내는 상태. 실기기 점검 때 "센서가 지금 값을 내고 있는가"를 눈으로 본다.
class LabStatusCard extends StatelessWidget {
  const LabStatusCard({super.key, required this.status, required this.running, this.now});

  final RecorderStatus? status;
  final bool running;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (!running) return const Text('기록 중이 아닙니다.');
    if (s == null) return const Text('상태를 기다리는 중… (5초마다 갱신)');

    final elapsed = (now ?? DateTime.now)().toUtc().difference(s.startedAt);
    final accuracy = s.lastGpsAccuracyM;
    final charge = s.lastChargeUah;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('경과 ${formatElapsed(elapsed)}'),
            for (final entry in s.rowCounts.entries) Text('${entry.key}: ${entry.value}행'),
            Text('GPS 정확도: ${accuracy == null ? '-' : '${accuracy.toStringAsFixed(1)} m'}'),
            Text('OS 누적 걸음: ${s.lastOsSteps ?? '-'}'),
            Text('배터리: ${s.lastLevelPct ?? '-'}% · 전하량 ${charge == null ? '지원 안 함' : '$charge μAh'}'),
            Text('현장 상태: ${s.atPlace ? '장소 안' : '이동 중'} · ${s.onVehicle ? '탈것 탑승 중' : '도보'}'),
            Text('오류: ${s.errorCount}건'),
          ],
        ),
      ),
    );
  }
}
```

`app/lib/features/footsteps/lab/lab_page.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../recording/mark.dart';
import '../recording/recorder_status.dart';
import '../recording/recording_mode.dart';
import '../recording/recording_providers.dart';
import 'lab_permissions_panel.dart';
import 'lab_status_card.dart';

/// 숨은 실험 화면(설계 4-3). 세계지도 아래 '방문 국가 … 총 걸음' 문구를 길게 눌러 연다.
class LabPage extends ConsumerStatefulWidget {
  const LabPage({super.key});

  @override
  ConsumerState<LabPage> createState() => _LabPageState();
}

class _LabPageState extends ConsumerState<LabPage> {
  bool _running = false;
  bool _busy = false;
  String? _error;
  RecorderStatus? _status;
  String _carry = CarryPosition.hand;
  StreamSubscription<RecorderStatus>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(recordingControllerProvider);
    _statusSubscription = controller.statusStream().listen((status) {
      if (mounted) setState(() => _status = status);
    });
    controller.isRunning().then((running) {
      if (mounted) setState(() => _running = running);
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    final controller = ref.read(recordingControllerProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_running) {
        await controller.stop();
        if (mounted) {
          setState(() {
            _running = false;
            _status = null;
          });
        }
      } else {
        await controller.start(mode: RecordingMode.groundTruth, carryInitial: _carry);
        if (mounted) setState(() => _running = true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('발걸음 실험')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const LabPermissionsPanel(),
          const SizedBox(height: 16),
          Text('정답 기록 모드', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('lab-start-stop'),
            onPressed: _busy ? null : _toggle,
            child: Text(_running ? '기록 종료' : '기록 시작'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          LabStatusCard(status: _status, running: _running),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: 위젯 테스트 통과 확인**

Run: `flutter test test/footsteps/lab/lab_page_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 7: 경로와 입구 연결**

`app/lib/router.dart`의 `AppRoutes`에서 `static const footstepsDetail = '/footsteps/detail';` 다음 줄에 추가한다.

```dart

  /// 숨은 실험 화면(연구 R1). 세계지도 아래 요약 문구를 길게 눌러 연다.
  static const footstepsLab = '/footsteps/lab';
```

같은 파일의 라우트 목록에서 `footstepsDetail` GoRoute 다음에 추가한다.

```dart
          GoRoute(path: AppRoutes.footstepsLab, builder: (_, _) => const LabPage()),
```

파일 위쪽 import 묶음(`features/footsteps/footsteps_page.dart` 다음)에 추가한다.

```dart
import 'features/footsteps/lab/lab_page.dart';
```

`app/lib/features/footsteps/map/world_map_page.dart`의 생성자와 필드를 바꾼다.

```dart
  const WorldMapPage({super.key, required this.onCountryTap, this.onLabRequested});

  final void Function(String iso) onCountryTap;

  /// 요약 문구를 길게 누르면 부른다(숨은 실험 화면 입구, 연구 R1). 일반 사용자에게는 보이지 않는다.
  final VoidCallback? onLabRequested;
```

같은 파일의 요약 문구 `Text('방문 국가 ...')`를 `GestureDetector`로 감싼다.

```dart
              GestureDetector(
                onLongPress: onLabRequested,
                child: Text(
                  '방문 국가 ${visitedByStepsDesc.length} · 총 걸음 ${steps.values.fold(0, (a, b) => a + b)} (이동 거리 기준)',
                  style: AppTextStyles.caption,
                ),
              ),
```

`app/lib/features/footsteps/footsteps_page.dart`의 import 묶음에 추가한다.

```dart
import 'package:go_router/go_router.dart';

import '../../router.dart';
```

같은 파일의 `WorldMapPage(` 생성 부분을 바꾼다.

```dart
      body: WorldMapPage(
        onCountryTap: (iso) => setState(() => _selectedCountryIso = iso),
        onLabRequested: () => context.push(AppRoutes.footstepsLab),
      ),
```

- [ ] **Step 8: 경로 테스트 추가**

`app/test/router_test.dart`의 import에 추가한다.

```dart
import 'package:app/features/footsteps/recording/recording_providers.dart';

import 'footsteps/lab/fake_recording_controller.dart';
```

`group('createRouter', () {` 안의 마지막 testWidgets 다음에 추가한다.

```dart
    testWidgets('실험 화면 경로(/footsteps/lab)로 가면 실험 화면이 보인다', (tester) async {
      final router = createRouter(isLoggedIn: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tripListProvider.overrideWith((ref) async => const TripListState(trips: [])),
            recordingControllerProvider.overrideWithValue(FakeRecordingController()),
          ],
          child: TravelFootstepsApp(router: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.footstepsLab);
      await tester.pumpAndSettle();

      expect(find.text('발걸음 실험'), findsOneWidget);
      expect(find.byKey(const Key('lab-start-stop')), findsOneWidget);
    });
```

- [ ] **Step 9: 전체 확인**

Run: `flutter test`
Expected: 전체 PASS

Run: `dart analyze`
Expected: 새 경고 없음

- [ ] **Step 10: 커밋**

```bash
git add app/lib/features/footsteps/lab app/lib/features/footsteps/recording/recording_providers.dart app/lib/router.dart app/lib/features/footsteps/map/world_map_page.dart app/lib/features/footsteps/footsteps_page.dart app/test/footsteps/lab app/test/router_test.dart
git commit -m "feat(app): 숨은 실험 화면에서 정답 기록을 시작·종료한다"
```

---

### Task 9: 세션 점검 도구 (`check_session`)

실기기 점검(Task 10)과 팀원 수집 후 확인에 쓴다. "파일마다 몇 행이 있고 간격이 얼마인가"를 PC에서 바로 본다.

**Files:**
- Create: `app/lib/features/footsteps/recording/session_check.dart`
- Create: `app/tool/check_session.dart`
- Modify: `.gitignore` (`research/data/`, `research/results/`)
- Test: `app/test/footsteps/recording/session_check_test.dart`

**Interfaces:**
- Consumes: `SessionSchema` (Task 2)
- Produces:
  - `class CsvFileStats({required String file, required int rows, int? firstMs, int? lastMs, int? medianGapMs, int? maxGapMs, List<String> emptyColumns})` + `Duration? get span`
  - `List<String> splitCsvLine(String line)`
  - `CsvFileStats statsFromCsvLines(String file, List<String> lines)`
  - `Future<List<CsvFileStats>> checkSession(Directory dir)`
  - `String formatSessionReport(List<CsvFileStats> stats)`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/footsteps/recording/session_check_test.dart`:

```dart
import 'dart:io';

import 'package:app/features/footsteps/recording/session_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('따옴표 안의 쉼표와 이중 따옴표를 하나의 필드로 읽는다', () {
    expect(splitCsvLine('1,arrive,"카페, 2층"'), ['1', 'arrive', '카페, 2층']);
    expect(splitCsvLine('1,note,"그가 ""여기"""'), ['1', 'note', '그가 "여기"']);
    expect(splitCsvLine('1,,3'), ['1', '', '3']);
  });

  test('행 수, 처음·마지막 시각, 간격 중앙값·최대, 빈 열을 계산한다', () {
    final stats = statsFromCsvLines('battery.csv', [
      't_ms,charge_uah,current_ua,level_pct,temp_c,plugged',
      '1000,,-250000,87,31.5,0',
      '31000,,-251000,87,31.6,0',
      '61000,,-249000,86,31.6,0',
      '151000,,-250000,86,31.7,0',
    ]);

    expect(stats.rows, 4);
    expect(stats.firstMs, 1000);
    expect(stats.lastMs, 151000);
    expect(stats.span, const Duration(seconds: 150));
    expect(stats.medianGapMs, 30000);
    expect(stats.maxGapMs, 90000);
    expect(stats.emptyColumns, ['charge_uah']);
  });

  test('헤더만 있거나 빈 파일이면 0행이다', () {
    expect(statsFromCsvLines('gps.csv', ['t_ms,lat']).rows, 0);
    expect(statsFromCsvLines('gps.csv', const []).rows, 0);
  });

  test('checkSession은 여섯 파일을 모두 보고, 없는 파일은 0행으로 둔다', () async {
    final dir = await Directory.systemTemp.createTemp('session_check_test');
    addTearDown(() => dir.delete(recursive: true));
    File(p.join(dir.path, 'gps.csv')).writeAsStringSync('t_ms,fix_t_ms,lat\n1000,900,37.5\n2000,1900,37.5\n');

    final stats = await checkSession(dir);
    expect(stats.map((s) => s.file), [
      'gps.csv', 'accel.csv', 'os_steps.csv', 'activity.csv', 'battery.csv', 'marks.csv',
    ]);
    expect(stats.first.rows, 2);
    expect(stats.first.medianGapMs, 1000);
    expect(stats[1].rows, 0);

    final report = formatSessionReport(stats);
    expect(report, contains('gps.csv'));
    expect(report, contains('rows=2'));
    expect(report, contains('median=1000ms'));
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `flutter test test/footsteps/recording/session_check_test.dart`
Expected: FAIL (URI가 없다는 컴파일 오류)

- [ ] **Step 3: 구현**

`app/lib/features/footsteps/recording/session_check.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

import 'session_schema.dart';

// 이 파일은 dart:io와 path만 쓴다. tool/check_session.dart가 Flutter 없이 `dart run`으로 불러 쓰기 때문이다.

/// 세션 파일 하나의 요약. 실기기 점검(설계 4-4)에서 "화면이 꺼진 동안에도 센서가 제 빈도로 값을 냈는가"를
/// 이 숫자로 판단한다.
class CsvFileStats {
  const CsvFileStats({
    required this.file,
    required this.rows,
    this.firstMs,
    this.lastMs,
    this.medianGapMs,
    this.maxGapMs,
    this.emptyColumns = const [],
  });

  final String file;
  final int rows;
  final int? firstMs;
  final int? lastMs;
  final int? medianGapMs;
  final int? maxGapMs;

  /// 모든 행이 빈칸인 열. 예: 기기가 전하량을 지원하지 않으면 charge_uah가 여기에 나온다.
  final List<String> emptyColumns;

  Duration? get span {
    final first = firstMs;
    final last = lastMs;
    return first == null || last == null ? null : Duration(milliseconds: last - first);
  }
}

/// 따옴표로 감싼 필드(쉼표·이중 따옴표 포함)를 처리하는 CSV 한 줄 분리. CsvWriter의 서식과 짝이다.
List<String> splitCsvLine(String line) {
  final fields = <String>[];
  final current = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        current.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      fields.add(current.toString());
      current.clear();
    } else {
      current.write(c);
    }
  }
  fields.add(current.toString());
  return fields;
}

CsvFileStats statsFromCsvLines(String file, List<String> lines) {
  if (lines.isEmpty) return CsvFileStats(file: file, rows: 0);
  final header = splitCsvLine(lines.first);
  final rows = lines.skip(1).where((l) => l.isNotEmpty).map(splitCsvLine).toList();
  if (rows.isEmpty) return CsvFileStats(file: file, rows: 0);

  // 가속도는 이벤트 시각을 쓰므로 순서가 살짝 뒤바뀔 수 있다. 간격은 정렬한 시각으로 잰다.
  final times = rows.map((r) => int.parse(r.first)).toList()..sort();
  final gaps = [for (var i = 1; i < times.length; i++) times[i] - times[i - 1]]..sort();
  final emptyColumns = [
    for (var c = 0; c < header.length; c++)
      if (rows.every((r) => c >= r.length || r[c].isEmpty)) header[c],
  ];
  return CsvFileStats(
    file: file,
    rows: rows.length,
    firstMs: times.first,
    lastMs: times.last,
    medianGapMs: gaps.isEmpty ? null : gaps[gaps.length ~/ 2],
    maxGapMs: gaps.isEmpty ? null : gaps.last,
    emptyColumns: emptyColumns,
  );
}

const _sessionCsvFiles = [
  SessionSchema.gpsFile,
  SessionSchema.accelFile,
  SessionSchema.osStepsFile,
  SessionSchema.activityFile,
  SessionSchema.batteryFile,
  SessionSchema.marksFile,
];

Future<List<CsvFileStats>> checkSession(Directory dir) async {
  return [
    for (final name in _sessionCsvFiles)
      await () async {
        final file = File(p.join(dir.path, name));
        if (!await file.exists()) return CsvFileStats(file: name, rows: 0);
        return statsFromCsvLines(name, await file.readAsLines());
      }(),
  ];
}

String formatSessionReport(List<CsvFileStats> stats) {
  String two(int n) => n.toString().padLeft(2, '0');
  String span(Duration? d) => d == null ? '-' : '${d.inMinutes}:${two(d.inSeconds % 60)}';
  return [
    for (final s in stats)
      '${s.file.padRight(13)} rows=${s.rows}  span=${span(s.span)}'
          '  median=${s.medianGapMs ?? '-'}ms  max=${s.maxGapMs ?? '-'}ms'
          '${s.emptyColumns.isEmpty ? '' : '  empty=${s.emptyColumns.join('|')}'}',
  ].join('\n');
}
```

`app/tool/check_session.dart`:

```dart
import 'dart:io';

import 'package:app/features/footsteps/recording/session_check.dart';
import 'package:path/path.dart' as p;

/// 사용법(app/에서): dart run tool/check_session.dart <세션 폴더>
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('사용법: dart run tool/check_session.dart <세션 폴더>');
    exitCode = 64;
    return;
  }
  final dir = Directory(args.single);
  if (!await dir.exists()) {
    stderr.writeln('폴더가 없습니다: ${dir.path}');
    exitCode = 66;
    return;
  }
  stdout.writeln(formatSessionReport(await checkSession(dir)));
  final meta = File(p.join(dir.path, 'meta.json'));
  if (await meta.exists()) {
    stdout
      ..writeln('--- meta.json ---')
      ..writeln(await meta.readAsString());
  }
}
```

루트 `.gitignore` 끝에 추가한다.

```
# 연구 수집 데이터(실제 이동 경로)와 분석 산출물 — 절대 커밋하지 않는다(설계 2026-11-07 3-1)
research/data/
research/results/
```

- [ ] **Step 4: 테스트 통과와 도구 실행 확인**

Run: `flutter test test/footsteps/recording/session_check_test.dart`
Expected: PASS (4 tests)

`app/`에서 임시 폴더로 도구를 한 번 돌려 본다(Bash).

```bash
CS="$(mktemp -d)" && printf 't_ms,lat\n1000,1\n2000,1\n' > "$CS/gps.csv" && dart run tool/check_session.dart "$CS"; rm -rf "$CS"
```

Expected: 첫 줄이 `gps.csv       rows=2  span=0:01  median=1000ms  max=1000ms`이고, 나머지 다섯 파일은 `rows=0`이다.

- [ ] **Step 5: 커밋**

```bash
git add .gitignore app/lib/features/footsteps/recording/session_check.dart app/tool/check_session.dart app/test/footsteps/recording/session_check_test.dart
git commit -m "feat(app): 기록 세션을 PC에서 점검하는 도구를 추가한다"
```

---

### Task 10: 실기기 점검 (게이트)

**사람이 실험 폰을 들고 하는 태스크다.** 서브에이전트는 Step 1~2(설치)와 Step 6(점검 도구 실행)을 돕는다. 화면 끄고 걷기는 사용자가 한다. 이 태스크를 통과하기 전에는 Task 11 이후로 넘어가지 않는다(설계 4-4).

**Files:**
- Create: `docs/research/device-check.md`

- [ ] **Step 1: 실험 폰 연결 확인**

Run: `adb devices`
Expected: 기기 한 대가 `device` 상태로 보인다.

- [ ] **Step 2: 앱 설치·실행**

Run (`app/`에서): `flutter run --debug`
Expected: 앱이 폰에서 열린다. 로그인 후 발걸음 탭으로 이동한다.

- [ ] **Step 3: 실험 화면 열고 권한 받기**

- 세계지도 아래 '방문 국가 … 총 걸음' 문구를 길게 누른다 → '발걸음 실험' 화면이 열려야 한다.
- '확인·요청'을 누르고 네 권한을 모두 허용한다. 배터리 최적화 제외도 허용한다.

- [ ] **Step 4: 화면 끄고 10분 기록**

1. '기록 시작'을 누른다. 상단 알림에 '발걸음 실험 기록 중'과 '도착'·'탑승' 버튼이 떠야 한다.
2. 알림의 '도착'을 한 번 눌러 버튼이 '출발'로 바뀌는지 본다. 다시 눌러 '도착'으로 되돌린다.
3. 폰을 주머니에 넣고 **화면을 끈 채** 5분 걷고, 5분 서 있는다.
4. 화면을 켜고 상태 카드를 확인한다. 경과가 10분 안팎이고 gps.csv 행 수가 계속 늘고 있어야 한다.
5. '기록 종료'를 누른다.

- [ ] **Step 5: PC로 꺼내기**

저장소 루트에서 실행한다(Bash).

```bash
mkdir -p research/data/sessions
adb pull /sdcard/Android/data/com.travelfootsteps.app/files/sessions/ research/data/
ls research/data/sessions
```

Expected: `<yyyyMMdd-HHmmss>-groundTruth` 폴더가 보인다. `git status`에 `research/`가 나타나지 않아야 한다(.gitignore).

- [ ] **Step 6: 점검 도구로 판정**

Run (`app/`에서): `dart run tool/check_session.dart ../research/data/sessions/<세션 폴더>`

아래 기준과 비교한다(10분 기준).

| 파일 | 통과 기준 | 실패하면 |
|---|---|---|
| `gps.csv` | rows ≥ 540, median ≤ 1100ms, max < 10000ms(화면 꺼진 동안 끊김 없음) | GPS 스트림이 서비스 isolate에서 멈춘 것 |
| `accel.csv` | rows ≥ 24000, median ≤ 25ms, max < 2000ms | sensors_plus가 화면 꺼지면 멈춘 것 |
| `os_steps.csv` | 걸은 5분 동안 `count` 행이 있다 | pedometer가 서비스 isolate에서 동작하지 않는 것 |
| `activity.csv` | rows ≥ 1, 걷는 동안 `WALKING` 또는 `RUNNING` 값이 있다 | 활동 인식이 서비스 isolate에서 동작하지 않는 것 |
| `battery.csv` | rows ≥ 18, median ≈ 30000ms | 배터리 읽기 실패 |
| `battery.csv`의 empty | `charge_uah`가 empty에 **없다** | 기기가 전하량을 지원하지 않음 → 설계 10장 위험 2(배터리 %와 GPS 시간으로 대신 보고) |
| `marks.csv` | 알림 버튼 두 번 → `arrive`, `depart` 2행 | 알림 버튼 처리 실패 |
| `meta.json` | `errors`가 비었거나 원인을 설명할 수 있다 | 오류 내용에 따라 판단 |

- [ ] **Step 7: 결과 기록**

`docs/research/device-check.md`를 만들고 결과를 적는다. 좌표 같은 위치 정보는 적지 않는다.

```markdown
# 실기기 점검 결과 (R1 기록 서비스)

- 점검일: <YYYY-MM-DD>
- 기종 / Android SDK: <meta.json의 deviceModel> / <androidSdk>
- 앱 커밋: <git rev-parse --short HEAD>
- 조건: 주머니, 화면 꺼짐, 걷기 5분 + 서 있기 5분

| 파일 | rows | median | max | 판정 | 메모 |
|---|---|---|---|---|---|
| gps.csv | | | | | |
| accel.csv | | | | | |
| os_steps.csv | | | | | |
| activity.csv | | | | | |
| battery.csv | | | | | charge_uah 지원: 예/아니오 |
| marks.csv | | | | | |

meta.json errors: <없음 또는 내용>

결론: <통과 / 실패한 센서와 대응>
```

**멈춤 조건:** 표에서 하나라도 '실패'가 나오면 Task 11로 넘어가지 않는다. 실패한 센서, 점검 도구 출력, `meta.json`의 errors를 사용자에게 보고한다. 해당 센서를 Kotlin(`device_probe`)으로 대체할지 사용자와 정한다. 전하량 미지원만 실패면 기록하고 계속 진행한다(설계상 대체 지표가 있다).

- [ ] **Step 8: 커밋**

```bash
git add docs/research/device-check.md
git commit -m "docs: R1 기록 서비스 실기기 점검 결과를 기록한다"
```

---

### Task 11: 관찰 표시와 휴대 위치 UI

**Files:**
- Create: `app/lib/features/footsteps/lab/lab_marks_panel.dart`
- Modify: `app/lib/features/footsteps/lab/lab_page.dart`
- Test: `app/test/footsteps/lab/lab_marks_panel_test.dart`

**Interfaces:**
- Consumes: `RecordingController.sendMark`, `recordingControllerProvider` (Task 7), `Mark`, `MarkKind`, `VehicleType`, `CarryPosition` (Task 3), `FakeRecordingController`, `pumpLab` (Task 8 테스트)
- Produces:
  - `class LabMarksPanel({required bool enabled, required bool atPlace, required bool onVehicle})`
  - `class LabCarrySelector({required String value, required ValueChanged<String> onChanged})`
  - 버튼 Key: `mark-arrive`, `mark-depart`, `mark-board-bus`, `mark-board-subway`, `mark-alight`, `mark-count-start`, `mark-count-end`, `mark-note`
  - 휴대 위치 Key: `carry-hand`, `carry-pocket`, `carry-bag`

- [ ] **Step 1: 실패하는 위젯 테스트 작성**

`app/test/footsteps/lab/lab_marks_panel_test.dart`:

```dart
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
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `flutter test test/footsteps/lab/lab_marks_panel_test.dart`
Expected: FAIL (`mark-board-bus` Key를 찾지 못함)

- [ ] **Step 3: 표시 패널 구현**

`app/lib/features/footsteps/lab/lab_marks_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../recording/mark.dart';
import '../recording/recording_providers.dart';

/// 관찰 표시 버튼(설계 4-2 `marks.csv`). 시각은 버튼을 누른 순간이다 — 이름을 입력하는 동안
/// 걸어도 도착 시각이 밀리지 않게 대화상자를 띄우기 전에 잡는다.
class LabMarksPanel extends ConsumerWidget {
  const LabMarksPanel({
    super.key,
    required this.enabled,
    required this.atPlace,
    required this.onVehicle,
  });

  final bool enabled;
  final bool atPlace;
  final bool onVehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 대화상자를 기다린 뒤에도 쓰므로 미리 잡아 둔다(await 뒤에 context를 쓰지 않는다).
    final controller = ref.read(recordingControllerProvider);
    final messenger = ScaffoldMessenger.of(context);

    void send(Mark mark) {
      controller.sendMark(mark);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('표시함: ${mark.kind.csvName} ${mark.value}')));
    }

    VoidCallback? simple(MarkKind kind, [String value = '']) => enabled
        ? () => send(Mark(at: DateTime.now().toUtc(), kind: kind, value: value))
        : null;

    VoidCallback? asking(
      MarkKind kind,
      String title, {
      bool numeric = false,
      bool allowEmpty = true,
    }) {
      if (!enabled) return null;
      return () async {
        final at = DateTime.now().toUtc();
        final text = await _askText(context, title, numeric: numeric);
        if (text == null) return;
        if (!allowEmpty && text.isEmpty) return;
        if (numeric && int.tryParse(text) == null) return;
        send(Mark(at: at, kind: kind, value: text));
      };
    }

    Widget button(String key, String label, VoidCallback? onPressed) => OutlinedButton(
          key: Key(key),
          onPressed: onPressed,
          child: Text(label),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('관찰 표시', style: Theme.of(context).textTheme.titleMedium),
        Text('지금: ${atPlace ? '장소 안' : '이동 중'} · ${onVehicle ? '탈것 탑승 중' : '도보'}'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            button('mark-arrive', '도착', asking(MarkKind.arrive, '장소 이름(선택)')),
            button('mark-depart', '출발', simple(MarkKind.depart)),
            button('mark-board-bus', '버스 탑승', simple(MarkKind.board, VehicleType.bus)),
            button('mark-board-subway', '지하철 탑승', simple(MarkKind.board, VehicleType.subway)),
            button('mark-alight', '하차', simple(MarkKind.alight)),
            button('mark-count-start', '걸음 세기 시작', simple(MarkKind.countStart)),
            button(
              'mark-count-end',
              '걸음 세기 끝',
              asking(MarkKind.countEnd, '센 걸음 수', numeric: true, allowEmpty: false),
            ),
            button('mark-note', '메모', asking(MarkKind.note, '메모', allowEmpty: false)),
          ],
        ),
      ],
    );
  }
}

Future<String?> _askText(BuildContext context, String title, {bool numeric = false}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(title: title, numeric: numeric),
    );

/// 글 한 줄을 받는 대화상자. 입력 컨트롤러를 대화상자 State가 들고 dispose한다 — pop 직후에 바로
/// 해제하면 닫히는 애니메이션 동안 TextField가 해제된 컨트롤러를 써서 오류가 난다.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({required this.title, required this.numeric});

  final String title;
  final bool numeric;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('mark-dialog-field'),
        controller: _controller,
        autofocus: true,
        keyboardType: widget.numeric ? TextInputType.number : TextInputType.text,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
        TextButton(
          key: const Key('mark-dialog-ok'),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('확인'),
        ),
      ],
    );
  }
}

/// 휴대 위치 선택. 위치에 따라 걸음 감지 결과가 달라 분석 때 나눠 본다.
class LabCarrySelector extends StatelessWidget {
  const LabCarrySelector({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _labels = {
    CarryPosition.hand: '손',
    CarryPosition.pocket: '주머니',
    CarryPosition.bag: '가방',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final position in CarryPosition.all)
          ChoiceChip(
            key: Key('carry-$position'),
            label: Text(_labels[position]!),
            selected: value == position,
            onSelected: (_) => onChanged(position),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: 실험 화면에 붙이기**

`app/lib/features/footsteps/lab/lab_page.dart`의 import에 추가한다.

```dart
import 'lab_marks_panel.dart';
```

`_LabPageState`에 휴대 위치 변경 처리를 추가한다(`_toggle` 메서드 다음).

```dart
  void _changeCarry(String position) {
    if (position == _carry) return;
    setState(() => _carry = position);
    // 기록 중이면 바뀐 시각을 표시로 남긴다. 시작 전이면 meta.json의 carryInitial로만 들어간다.
    if (_running) {
      ref.read(recordingControllerProvider).sendMark(
            Mark(at: DateTime.now().toUtc(), kind: MarkKind.carry, value: position),
          );
    }
  }
```

`build`의 `ListView` children에서 `const SizedBox(height: 8),`(제목 '정답 기록 모드' 다음)과 `FilledButton(` 사이에 다음을 넣는다.

```dart
          const Text('휴대 위치'),
          LabCarrySelector(value: _carry, onChanged: _changeCarry),
          const SizedBox(height: 8),
```

같은 children의 마지막 항목 `LabStatusCard(status: _status, running: _running),` 다음에 다음을 넣는다.

```dart
          const SizedBox(height: 16),
          LabMarksPanel(
            enabled: _running,
            atPlace: _status?.atPlace ?? false,
            onVehicle: _status?.onVehicle ?? false,
          ),
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `flutter test test/footsteps/lab/`
Expected: PASS (lab_page_test 6 + lab_marks_panel_test 6)

Run: `dart analyze`
Expected: 새 경고 없음

- [ ] **Step 6: 커밋**

```bash
git add app/lib/features/footsteps/lab/lab_marks_panel.dart app/lib/features/footsteps/lab/lab_page.dart app/test/footsteps/lab/lab_marks_panel_test.dart
git commit -m "feat(app): 실험 화면에서 관찰 표시와 휴대 위치를 남긴다"
```

---

### Task 12: 세션 목록과 zip 공유

**Files:**
- Modify: `app/pubspec.yaml` (`share_plus`, `archive`)
- Create: `app/lib/features/footsteps/recording/session_library.dart`
- Create: `app/lib/features/footsteps/lab/lab_sessions_panel.dart`
- Modify: `app/lib/features/footsteps/recording/recording_providers.dart`
- Modify: `app/lib/features/footsteps/lab/lab_page.dart`
- Test: `app/test/footsteps/recording/session_library_test.dart`
- Test: `app/test/footsteps/lab/lab_sessions_panel_test.dart`

**Interfaces:**
- Consumes: `SessionMetaStore`, `SessionMeta`, `SessionSchema` (Task 2), `defaultSessionsRoot` (Task 7)
- Produces:
  - `class SessionSummary({required String id, required Directory directory, required int sizeBytes, SessionMeta? meta})` + `Duration? get duration`
  - `class SessionLibrary(Future<Directory> Function() root)` — `Future<List<SessionSummary>> list()`, `Future<File> zip(SessionSummary session, Directory outDir)`
  - `final sessionLibraryProvider = Provider<SessionLibrary>`
  - `final sessionSharerProvider = Provider<Future<void> Function(SessionSummary session)>`
  - `class LabSessionsPanel({required int refreshToken})`

- [ ] **Step 1: 의존성 추가**

`app/pubspec.yaml`의 `flutter_foreground_task:` 줄 다음에 추가한다.

```yaml
  # 세션 폴더를 zip으로 묶어 Android 공유 창으로 보낸다(adb가 없는 팀원용).
  share_plus: ^13.3.1
  archive: ^4.0.7
```

Run: `flutter pub get`

- [ ] **Step 2: 실패하는 테스트 작성 (목록·zip)**

`app/test/footsteps/recording/session_library_test.dart`:

```dart
import 'dart:io';

import 'package:app/features/footsteps/recording/recording_mode.dart';
import 'package:app/features/footsteps/recording/session_library.dart';
import 'package:app/features/footsteps/recording/session_meta.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<Directory> _session(Directory root, String id, {DateTime? endedAt}) async {
  final dir = Directory(p.join(root.path, id))..createSync(recursive: true);
  File(p.join(dir.path, 'gps.csv')).writeAsStringSync('t_ms,lat\n1,37.5\n');
  await SessionMetaStore(File(p.join(dir.path, 'meta.json'))).write(SessionMeta(
    sessionId: id,
    mode: RecordingMode.groundTruth,
    deviceModel: 'samsung SM-S921N',
    androidSdk: 35,
    appVersion: '1.0.0',
    startedAt: DateTime.utc(2026, 11, 9, 1),
    endedAt: endedAt,
    carryInitial: 'hand',
  ));
  return dir;
}

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('session_library_test'));
  tearDown(() async => root.delete(recursive: true));

  test('세션을 최신순으로 나열하고 크기·meta·기록 시간을 담는다', () async {
    await _session(root, '20261109-080000-groundTruth', endedAt: DateTime.utc(2026, 11, 9, 2, 2));
    await _session(root, '20261110-090000-groundTruth');

    final sessions = await SessionLibrary(() async => root).list();
    expect(sessions.map((s) => s.id), ['20261110-090000-groundTruth', '20261109-080000-groundTruth']);
    expect(sessions.last.duration, const Duration(hours: 1, minutes: 2));
    expect(sessions.first.duration, isNull); // 아직 끝나지 않았거나 비정상 종료
    expect(sessions.first.sizeBytes, greaterThan(0));
    expect(sessions.first.meta!.deviceModel, 'samsung SM-S921N');
  });

  test('세션 폴더가 아직 없으면 빈 목록이다', () async {
    final missing = Directory(p.join(root.path, 'nope'));
    expect(await SessionLibrary(() async => missing).list(), isEmpty);
  });

  test('meta.json이 깨져 있어도 목록에서 빠지지 않는다', () async {
    final dir = Directory(p.join(root.path, '20261111-100000-groundTruth'))..createSync();
    File(p.join(dir.path, 'meta.json')).writeAsStringSync('{broken');

    final sessions = await SessionLibrary(() async => root).list();
    expect(sessions.single.meta, isNull);
  });

  test('zip은 세션 폴더의 파일을 모두 담는다', () async {
    await _session(root, '20261109-080000-groundTruth');
    final library = SessionLibrary(() async => root);
    final session = (await library.list()).single;
    final out = await Directory.systemTemp.createTemp('zip_out');
    addTearDown(() => out.delete(recursive: true));

    final zip = await library.zip(session, out);
    expect(p.basename(zip.path), '20261109-080000-groundTruth.zip');
    final names = ZipDecoder().decodeBytes(await zip.readAsBytes()).files.map((f) => f.name);
    expect(names.any((n) => n.endsWith('gps.csv')), isTrue);
    expect(names.any((n) => n.endsWith('meta.json')), isTrue);
  });
}
```

- [ ] **Step 3: 테스트가 실패하는지 확인**

Run: `flutter test test/footsteps/recording/session_library_test.dart`
Expected: FAIL (URI가 없다는 컴파일 오류)

- [ ] **Step 4: 목록·zip 구현**

`app/lib/features/footsteps/recording/session_library.dart`:

```dart
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'session_meta.dart';
import 'session_schema.dart';

class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.directory,
    required this.sizeBytes,
    this.meta,
  });

  final String id;
  final Directory directory;
  final int sizeBytes;

  /// meta.json을 읽지 못하면(없음, 깨짐) null. 그래도 목록에서 빼지 않는다 — 데이터는 남아 있을 수 있다.
  final SessionMeta? meta;

  /// 정상 종료한 세션만 값이 있다.
  Duration? get duration {
    final m = meta;
    final ended = m?.endedAt;
    return m == null || ended == null ? null : ended.difference(m.startedAt);
  }
}

/// 기기에 쌓인 세션 폴더 목록과 zip 묶기.
class SessionLibrary {
  SessionLibrary(this._root);

  final Future<Directory> Function() _root;

  Future<List<SessionSummary>> list() async {
    final root = await _root();
    if (!await root.exists()) return const [];
    final summaries = <SessionSummary>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      var size = 0;
      await for (final file in entity.list(recursive: true)) {
        if (file is File) size += await file.length();
      }
      SessionMeta? meta;
      try {
        meta = await SessionMetaStore(File(p.join(entity.path, SessionSchema.metaFile))).read();
      } catch (_) {
        meta = null;
      }
      summaries.add(SessionSummary(
        id: p.basename(entity.path),
        directory: entity,
        sizeBytes: size,
        meta: meta,
      ));
    }
    // 폴더 이름이 시작 시각으로 시작하므로 이름 역순이 최신순이다.
    summaries.sort((a, b) => b.id.compareTo(a.id));
    return summaries;
  }

  Future<File> zip(SessionSummary session, Directory outDir) async {
    final zipPath = p.join(outDir.path, '${session.id}.zip');
    await ZipFileEncoder().zipDirectory(session.directory, filename: zipPath);
    return File(zipPath);
  }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `flutter test test/footsteps/recording/session_library_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 6: provider 추가**

`app/lib/features/footsteps/recording/recording_providers.dart`를 다음 내용으로 바꾼다.

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../lab/recording_permissions.dart';
import 'recording_controller.dart';
import 'session_library.dart';

final recordingControllerProvider =
    Provider<RecordingController>((ref) => ForegroundRecordingController());

/// 권한 요청 함수. 위젯 테스트는 실제 권한 창 대신 정해 둔 결과를 넣는다.
final recordingPermissionRequesterProvider =
    Provider<Future<List<PermissionItem>> Function()>((ref) => requestRecordingPermissions);

final sessionLibraryProvider = Provider<SessionLibrary>((ref) => SessionLibrary(defaultSessionsRoot));

/// 세션 하나를 zip으로 묶어 Android 공유 창을 연다. zip은 앱 캐시 폴더에 만든다.
final sessionSharerProvider = Provider<Future<void> Function(SessionSummary session)>((ref) {
  final library = ref.watch(sessionLibraryProvider);
  return (session) async {
    final zip = await library.zip(session, await getTemporaryDirectory());
    await SharePlus.instance.share(
      ShareParams(files: [XFile(zip.path)], subject: '발걸음 세션 ${session.id}'),
    );
  };
});
```

`XFile`을 찾지 못한다는 컴파일 오류가 나면 `app/pubspec.yaml`에 `cross_file: ^0.3.4`를 추가하고, 이 파일에 `import 'package:cross_file/cross_file.dart';`를 추가한다.

- [ ] **Step 7: 실패하는 패널 테스트 작성**

`app/test/footsteps/lab/lab_sessions_panel_test.dart`:

```dart
import 'dart:io';

import 'package:app/features/footsteps/lab/lab_sessions_panel.dart';
import 'package:app/features/footsteps/recording/recording_mode.dart';
import 'package:app/features/footsteps/recording/recording_providers.dart';
import 'package:app/features/footsteps/recording/session_library.dart';
import 'package:app/features/footsteps/recording/session_meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLibrary implements SessionLibrary {
  _FakeLibrary(this.sessions);

  final List<SessionSummary> sessions;
  int listCalls = 0;

  @override
  Future<List<SessionSummary>> list() async {
    listCalls++;
    return sessions;
  }

  @override
  Future<File> zip(SessionSummary session, Directory outDir) => throw UnimplementedError();
}

SessionSummary _summary(String id, {DateTime? endedAt, int errors = 0}) => SessionSummary(
      id: id,
      directory: Directory(id),
      sizeBytes: 12 * 1024 * 1024,
      meta: SessionMeta(
        sessionId: id,
        mode: RecordingMode.groundTruth,
        deviceModel: 'm',
        androidSdk: 35,
        appVersion: '1',
        startedAt: DateTime.utc(2026, 11, 9, 1),
        endedAt: endedAt,
        carryInitial: 'hand',
        errors: [
          for (var i = 0; i < errors; i++)
            SessionError(at: DateTime.utc(2026), source: 'gps', message: 'x'),
        ],
      ),
    );

void main() {
  testWidgets('세션마다 크기·기록 시간·오류 수를 보여 주고, 공유를 누르면 그 세션을 공유한다', (tester) async {
    final library = _FakeLibrary([
      _summary('20261110-090000-groundTruth'),
      _summary('20261109-080000-groundTruth', endedAt: DateTime.utc(2026, 11, 9, 2, 2), errors: 2),
    ]);
    final shared = <String>[];

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionLibraryProvider.overrideWithValue(library),
        sessionSharerProvider.overrideWithValue((s) async => shared.add(s.id)),
      ],
      child: const MaterialApp(home: Scaffold(body: LabSessionsPanel(refreshToken: 0))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('20261110-090000-groundTruth'), findsOneWidget);
    expect(find.text('12.0MB · 기록 중이거나 비정상 종료 · 오류 0건'), findsOneWidget);
    expect(find.text('12.0MB · 62분 · 오류 2건'), findsOneWidget);

    await tester.tap(find.byKey(const Key('share-20261109-080000-groundTruth')));
    await tester.pumpAndSettle();
    expect(shared, ['20261109-080000-groundTruth']);
  });

  testWidgets('refreshToken이 바뀌면 목록을 다시 읽는다', (tester) async {
    final library = _FakeLibrary(const []);
    Widget panel(int token) => ProviderScope(
          overrides: [sessionLibraryProvider.overrideWithValue(library)],
          child: MaterialApp(home: Scaffold(body: LabSessionsPanel(refreshToken: token))),
        );

    await tester.pumpWidget(panel(0));
    await tester.pumpAndSettle();
    expect(find.text('저장된 세션이 없습니다.'), findsOneWidget);

    await tester.pumpWidget(panel(1));
    await tester.pumpAndSettle();
    expect(library.listCalls, 2);
  });
}
```

- [ ] **Step 8: 테스트가 실패하는지 확인**

Run: `flutter test test/footsteps/lab/lab_sessions_panel_test.dart`
Expected: FAIL (URI가 없다는 컴파일 오류)

- [ ] **Step 9: 패널 구현**

`app/lib/features/footsteps/lab/lab_sessions_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../recording/recording_providers.dart';
import '../recording/session_library.dart';

/// 기기에 저장된 세션 목록과 zip 공유(설계 4-3). [refreshToken]이 바뀌면 다시 읽는다 —
/// 기록을 끝낸 직후 새 세션이 목록에 바로 나타나게 하려고 실험 화면이 값을 올린다.
class LabSessionsPanel extends ConsumerStatefulWidget {
  const LabSessionsPanel({super.key, required this.refreshToken});

  final int refreshToken;

  @override
  ConsumerState<LabSessionsPanel> createState() => _LabSessionsPanelState();
}

class _LabSessionsPanelState extends ConsumerState<LabSessionsPanel> {
  late Future<List<SessionSummary>> _sessions;

  @override
  void initState() {
    super.initState();
    _sessions = ref.read(sessionLibraryProvider).list();
  }

  @override
  void didUpdateWidget(LabSessionsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _sessions = ref.read(sessionLibraryProvider).list();
    }
  }

  String _subtitle(SessionSummary s) {
    final size = (s.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
    final duration = s.duration;
    final time = duration == null ? '기록 중이거나 비정상 종료' : '${duration.inMinutes}분';
    return '${size}MB · $time · 오류 ${s.meta?.errors.length ?? 0}건';
  }

  Future<void> _share(SessionSummary session) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(sessionSharerProvider)(session);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('공유하지 못했습니다: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('세션', style: Theme.of(context).textTheme.titleMedium),
        const Text('PC: adb pull /sdcard/Android/data/com.travelfootsteps.app/files/sessions/'),
        FutureBuilder<List<SessionSummary>>(
          future: _sessions,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('목록을 읽지 못했습니다: ${snapshot.error}');
            final sessions = snapshot.data;
            if (sessions == null) return const LinearProgressIndicator();
            if (sessions.isEmpty) return const Text('저장된 세션이 없습니다.');
            return Column(
              children: [
                for (final session in sessions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(session.id),
                    subtitle: Text(_subtitle(session)),
                    trailing: IconButton(
                      key: Key('share-${session.id}'),
                      icon: const Icon(Icons.share),
                      tooltip: 'zip으로 공유',
                      onPressed: () => _share(session),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
```

- [ ] **Step 10: 실험 화면에 붙이기**

`app/lib/features/footsteps/lab/lab_page.dart`의 import에 추가한다.

```dart
import 'lab_sessions_panel.dart';
```

`_LabPageState`의 필드 묶음(`String _carry = CarryPosition.hand;` 다음)에 추가한다.

```dart
  int _sessionsVersion = 0;
```

`_toggle`의 종료 분기에서 아래 블록을

```dart
          setState(() {
            _running = false;
            _status = null;
          });
```

다음으로 바꾼다.

```dart
          setState(() {
            _running = false;
            _status = null;
            _sessionsVersion++;
          });
```

`build`의 `ListView` children 맨 끝(`LabMarksPanel(...)` 다음)에 추가한다.

```dart
          const SizedBox(height: 16),
          LabSessionsPanel(refreshToken: _sessionsVersion),
```

`app/test/footsteps/lab/lab_page_test.dart`의 `pumpLab`이 실제 세션 폴더를 읽지 않게 기본 override에 빈 목록 라이브러리를 넣는다. import에 추가한다.

```dart
import 'dart:io';

import 'package:app/features/footsteps/recording/session_library.dart';
```

같은 파일 맨 아래에 추가한다.

```dart
class _EmptyLibrary implements SessionLibrary {
  @override
  Future<List<SessionSummary>> list() async => const [];

  @override
  Future<File> zip(SessionSummary session, Directory outDir) => throw UnimplementedError();
}
```

`pumpLab`의 overrides 목록에서 `...extra,` 앞에 추가한다.

```dart
      sessionLibraryProvider.overrideWithValue(_EmptyLibrary()),
```

`app/test/router_test.dart`의 실험 화면 테스트 overrides에도 같은 이유로 추가한다. import에 `package:app/features/footsteps/recording/session_library.dart`와 `dart:io`를 더하고, 파일 아래에 위와 같은 `_EmptyLibrary` 클래스를 두고, overrides에 `sessionLibraryProvider.overrideWithValue(_EmptyLibrary()),`를 넣는다.

- [ ] **Step 11: 전체 확인**

Run: `flutter test`
Expected: 전체 PASS

Run: `dart analyze`
Expected: 새 경고 없음

Run: `flutter build apk --debug`
Expected: 빌드 성공

- [ ] **Step 12: 커밋**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/features/footsteps/recording/session_library.dart app/lib/features/footsteps/recording/recording_providers.dart app/lib/features/footsteps/lab/lab_sessions_panel.dart app/lib/features/footsteps/lab/lab_page.dart app/test/footsteps/recording/session_library_test.dart app/test/footsteps/lab/lab_sessions_panel_test.dart app/test/footsteps/lab/lab_page_test.dart app/test/router_test.dart
git commit -m "feat(app): 실험 화면에서 세션 목록을 보고 zip으로 공유한다"
```

---

### Task 13: 팀원용 기록 안내와 최종 확인

**Files:**
- Create: `docs/research/recording-guide.md`

- [ ] **Step 1: 안내 문서 작성**

`docs/research/recording-guide.md`:

````markdown
# 정답 기록 안내 (팀원용)

연구 정확도 실험(설계 문서 8-1)에 쓸 '정답 기록'을 남기는 방법이다. 배터리 실험은 이 모드로 하지 않는다(R4 정책 실행 모드).

## 1. 준비 (처음 한 번)

1. 최신 `research` 브랜치 앱을 설치한다(`app/`에서 `flutter run --debug`).
2. 로그인 → 발걸음 탭 → 세계지도 아래 '방문 국가 … 총 걸음' 문구를 **길게 누른다** → '발걸음 실험' 화면.
3. '권한 → 확인·요청'에서 위치·신체 활동·알림·배터리 최적화 제외를 모두 허용한다.

## 2. 기록하기

1. 휴대 위치(손·주머니·가방)를 고르고 '기록 시작'을 누른다. 상단 알림이 떠 있는 동안 기록 중이다.
2. 화면은 꺼도 된다. 충전기는 꽂지 않는다.
3. 관찰 표시는 **그 순간에** 남긴다.

| 상황 | 누를 것 | 어디서 |
|---|---|---|
| 카페·가게 등 장소에 들어감 | 도착 | 알림 버튼 또는 화면(장소 이름 입력 가능) |
| 장소에서 나옴 | 출발 | 알림 버튼 또는 화면 |
| 버스·지하철을 탐 | 탑승 | 화면(버스/지하철 구분) 또는 알림 버튼(종류 미지정) |
| 내림 | 하차 | 화면 또는 알림 버튼 |
| 걸음 세기 시작 | 걸음 세기 시작 | 화면 |
| 다 셈 | 걸음 세기 끝 → 센 걸음 수 입력 | 화면 |
| 폰을 주머니→가방 등으로 옮김 | 휴대 위치 칩 | 화면 |

- 머문 곳은 **10분 이상** 있을 때만 도착·출발을 남긴다(분석 기준 T = 10분).
- 걸음 세기는 100~300걸음짜리 구간으로, 세션마다 2~3번 한다.
- 알림 버튼은 토글이다. '도착'을 누르면 '출발'로 바뀐다.

4. 끝나면 '기록 종료'를 누른다.

## 3. 꺼내기

- **PC + adb:** 저장소 루트에서 `adb pull /sdcard/Android/data/com.travelfootsteps.app/files/sessions/ research/data/`
- **adb가 없으면:** 실험 화면 '세션' 목록에서 공유 버튼 → zip을 팀 드라이브에 올린다.

## 4. 확인하기

`app/`에서 `dart run tool/check_session.dart ../research/data/sessions/<세션 폴더>`를 실행한다. gps.csv의 median이 1000ms 안팎이고 max가 10초를 넘지 않으면 정상이다.

## 5. 주의

- 세션 데이터에는 실제 이동 경로가 들어 있다. **git에 올리지 않는다**(`research/data/`는 .gitignore 대상). 팀 드라이브로만 공유한다.
- `research/sessions.yaml`에 세션 id, 코스, 휴대 위치, 용도(pilot/eval)를 적는다(R6에서 만든다).
````

- [ ] **Step 2: 전체 테스트·분석·빌드 최종 확인**

Run (`app/`에서): `flutter test`
Expected: 전체 PASS

Run (`packages/device_probe/`에서): `flutter test`
Expected: PASS

Run (`app/`에서): `dart analyze`
Expected: 새 경고 없음

- [ ] **Step 3: AI 트레일러 확인**

Run: `git log --format=%B origin/master..HEAD | grep -iE "co-authored|claude"`
Expected: 출력 없음

- [ ] **Step 4: 커밋**

```bash
git add docs/research/recording-guide.md
git commit -m "docs: 팀원용 정답 기록 안내를 추가한다"
```
