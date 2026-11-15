# R2 공용 패키지·재생기·기준 정책 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flutter 없이 도는 Dart 패키지 `packages/footstep_core`를 만든다. 이 패키지로 R1이 기록한 세션 폴더를 PC에서 재생하고, 현재 앱 방식·고정 주기·논문 방식·상용 방식의 기준 정책이 '어떤 GPS 점을 남겼을지'를 `fixes.csv`·`actions.csv`·`summary.json`으로 내보낸다.

**Architecture:**
- 정책은 사건(`PolicyEvent`)을 받아 할 일(`PolicyAction`)만 돌려준다. 시계와 GPS는 직접 건드리지 않는다(설계 2장 D5).
- 재생기는 세션의 모든 CSV를 시각순으로 합쳐 가상 시계로 흘려보낸다. 정책이 `RequestFix`를 내면 '요청 시각 + 측위 지연' 이후의 첫 GPS 행을 돌려준다. 그래서 정책은 미래 정보를 쓸 수 없다.
- 가속도·OS 걸음은 걸음 감지기를 거쳐 `StepUpdate`가 된다. R2는 OS 센서판 감지기만 만들고, 논문 기준판·제안판은 R3이 같은 인터페이스로 더한다.
- 앱과 재생기가 같은 파일 계약을 쓰도록, R1의 세션 스키마와 CSV 도우미를 이 패키지로 옮긴다. 앱의 기존 파일은 다시 내보내기만 한다.

**Tech Stack:** Dart 3.13.2(순수 Dart 패키지), `path`, `args`, 개발용 `test`·`lints`.

**설계 문서:**
- `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md` 5-1(사건과 할 일), 5-3(정책 목록), 5-4(재생기), 5-7(테스트)
- 실기기 점검 결과 `docs/research/device-check.md`: 가속도 약 100Hz, 실내 정지 GPS 약 7초 간격, 속도·방향 음수는 '모름'

## Global Constraints

- 작업 브랜치는 `replay`다(`research`에서 갈라짐. `research`는 PR #33으로 리뷰 중). 다른 브랜치를 만들지 않는다.
- 커밋에 `Co-Authored-By`, `Claude-Session` 같은 AI 트레일러를 넣지 않는다. push 전에 `git log --format=%B origin/master..HEAD | grep -iE "co-authored|claude"`가 빈 결과인지 확인한다.
- `packages/footstep_core`는 Flutter에 의존하지 않는다. 런타임 의존성은 `path`와 `args`뿐이고, 개발 의존성은 `test`와 `lints`다.
- 패키지 안의 시각은 모두 `int` UTC epoch 밀리초(`tMs`, `nowMs`)이고, 시간 길이도 밀리초(`...Ms`)다. 패키지 로직에서 `DateTime.now()`나 난수를 쓰지 않는다(재생 결과가 항상 같아야 한다).
- 입력 파일 이름과 열은 설계 문서 4-2(`SessionSchema`)를 따른다. 출력은 설계 문서 5-4를 따른다: `fixes.csv` = `t_ms,lat,lng,accuracy_m,steps_since_prev,state,kind`, `actions.csv` = `t_ms,action,args`, `summary.json`.
- 정책 id는 설계 문서 5-3 그대로다: `hourly`, `continuous_10m`, `fixed_30s`, `fixed_1m`, `fixed_5m`, `speed_adaptive`, `time_speed`, `still_suppress`, `activity_gated`.
- 실측 사실: 가속도는 약 100Hz로 들어온다(50Hz로 가정하지 않는다). gps.csv의 `speed_mps`·`bearing_deg`가 음수면 '모름'(null)이다.
- 패키지 테스트·분석은 `packages/footstep_core/`에서 `dart test`, `dart analyze`로 한다. 앱을 고친 태스크는 `app/`에서 `flutter test`와 `dart analyze`도 돌린다(`flutter analyze`는 이 PC에서 경로 문제로 죽는다).
- 수집한 세션 데이터(`research/data/`)와 재생 결과는 커밋하지 않는다.
- 코드 주석은 한국어로 '왜'를 적는다.

## 파일 구조

```
packages/footstep_core/
  pubspec.yaml, analysis_options.yaml, .gitignore
  lib/footstep_core.dart                    공개 API(아래 파일들을 export)
  lib/src/session/session_schema.dart       세션 파일 이름·헤더 (앱에서 옮김)
  lib/src/session/csv.dart                  splitCsvLine, csvRecords, formatCsvField (앱에서 옮김)
  lib/src/session/session_reader.dart       세션 폴더 → SessionData
  lib/src/model/fix.dart                    Fix
  lib/src/model/readings.dart               AccelReading, OsStepReading, ActivityReading, BatteryLevelReading
  lib/src/geo.dart                          haversineMeters
  lib/src/events/policy_event.dart          StepState, PolicyEvent과 하위 사건
  lib/src/events/policy_action.dart         PolicyAction과 하위 할 일
  lib/src/policies/collection_policy.dart   CollectionPolicy, PolicyContext, ReportsState
  lib/src/policies/fixed_interval_policy.dart   hourly, fixed_*
  lib/src/policies/continuous_policy.dart       continuous_10m
  lib/src/policies/still_suppress_policy.dart   still_suppress
  lib/src/policies/speed_adaptive_policy.dart   speed_adaptive
  lib/src/policies/time_speed_policy.dart       time_speed
  lib/src/policies/activity_gated_policy.dart   activity_gated
  lib/src/policies/policy_registry.dart         id → 정책
  lib/src/detectors/step_detector.dart      StepDetector 인터페이스
  lib/src/detectors/os_step_detector.dart   OS 센서판
  lib/src/detectors/detector_registry.dart  id → 감지기
  lib/src/replay/replay_result.dart         FixRecord, ActionRecord, ReplaySummary, ReplayResult
  lib/src/replay/replay_engine.dart         replaySession, ReplayConfig
  lib/src/replay/replay_output.dart         ReplaySchema, writeReplayOutput
  lib/src/cli/replay_cli.dart               runReplayCli
  bin/replay.dart                           dart run footstep_core:replay
  test/...                                  태스크별 테스트
docs/research/replay-guide.md               재생기 사용 안내
```

수정하는 기존 파일은 다음과 같다(Task 1).
- `app/pubspec.yaml`: `footstep_core` path 의존성
- `app/lib/features/footsteps/recording/session_schema.dart`: 다시 내보내기만
- `app/lib/features/footsteps/recording/session_check.dart`: CSV 도우미를 공용 패키지에서 가져와 다시 내보내기
- `app/lib/features/footsteps/recording/csv_writer.dart`: `formatCsvField`를 공용 패키지에서 가져와 다시 내보내기

---

### Task 1: 패키지 뼈대 + 세션 계약·CSV 도우미 옮기기

**Files:**
- Create: `packages/footstep_core/pubspec.yaml`, `analysis_options.yaml`, `.gitignore`
- Create: `packages/footstep_core/lib/footstep_core.dart`
- Create: `packages/footstep_core/lib/src/session/session_schema.dart`
- Create: `packages/footstep_core/lib/src/session/csv.dart`
- Test: `packages/footstep_core/test/session/csv_test.dart`
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/features/footsteps/recording/session_schema.dart`
- Modify: `app/lib/features/footsteps/recording/session_check.dart`
- Modify: `app/lib/features/footsteps/recording/csv_writer.dart`

**Interfaces:**
- Produces:
  - `abstract final class SessionSchema` — 앱에 있던 상수 그대로(`gpsFile`, `gpsHeader`, `accelFile`, `accelHeader`, `osStepsFile`, `osStepsHeader`, `activityFile`, `activityHeader`, `batteryFile`, `batteryHeader`, `marksFile`, `marksHeader`, `metaFile`)
  - `List<String> splitCsvLine(String line)`
  - `List<String> csvRecords(List<String> lines)`
  - `String formatCsvField(Object? value)`

- [ ] **Step 1: 패키지 파일 만들기**

`packages/footstep_core/pubspec.yaml`:

```yaml
name: footstep_core
description: 발걸음 연구 공용 로직(수집 정책·걸음 감지·재생기). Flutter 없이 앱과 PC에서 같은 코드로 돈다.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.13.2
```

`packages/footstep_core/analysis_options.yaml`:

```yaml
include: package:lints/recommended.yaml
```

`packages/footstep_core/.gitignore`:

```
.dart_tool/
pubspec.lock
```

개발 의존성을 추가한다(`packages/footstep_core/`에서).

```bash
dart pub add --dev test lints
```

Expected: `pubspec.yaml`에 `dev_dependencies: lints: ^x`, `test: ^x`가 생긴다.

- [ ] **Step 2: 실패하는 테스트 작성**

`packages/footstep_core/test/session/csv_test.dart`:

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

void main() {
  test('따옴표 안의 쉼표·이중 따옴표를 한 필드로 읽는다', () {
    expect(splitCsvLine('1,arrive,"카페, 2층"'), ['1', 'arrive', '카페, 2층']);
    expect(splitCsvLine('1,note,"그가 ""여기"""'), ['1', 'note', '그가 "여기"']);
    expect(splitCsvLine('1,,3'), ['1', '', '3']);
  });

  test('따옴표 안 줄바꿈으로 쪼개진 줄을 한 행으로 합친다', () {
    expect(
      csvRecords(['t_ms,kind,value', '1,note,"첫 줄', '둘째 줄"', '2,arrive,']),
      ['t_ms,kind,value', '1,note,"첫 줄\n둘째 줄"', '2,arrive,'],
    );
  });

  test('닫히지 않은 꼬리는 깨진 행 하나로 남긴다', () {
    expect(csvRecords(['1,note,"끝나지 않음']), ['1,note,"끝나지 않음']);
  });

  test('formatCsvField로 쓴 행을 splitCsvLine이 그대로 되읽는다', () {
    final fields = ['카페, 2층', '그가 "여기"', '', '37.5'];
    expect(splitCsvLine(fields.map(formatCsvField).join(',')), fields);
  });

  test('formatCsvField: null·NaN은 빈칸, bool은 1/0', () {
    expect(formatCsvField(null), '');
    expect(formatCsvField(double.nan), '');
    expect(formatCsvField(true), '1');
    expect(formatCsvField(false), '0');
    expect(formatCsvField(1762650000000), '1762650000000');
  });

  test('세션 스키마는 설계 문서 4-2의 파일 이름과 헤더다', () {
    expect(SessionSchema.gpsFile, 'gps.csv');
    expect(SessionSchema.gpsHeader,
        ['t_ms', 'fix_t_ms', 'lat', 'lng', 'accuracy_m', 'speed_mps', 'bearing_deg', 'altitude_m']);
    expect(SessionSchema.batteryHeader,
        ['t_ms', 'charge_uah', 'current_ua', 'level_pct', 'temp_c', 'plugged']);
    expect(SessionSchema.metaFile, 'meta.json');
  });
}
```

- [ ] **Step 3: 테스트가 실패하는지 확인**

Run (`packages/footstep_core/`에서): `dart test`
Expected: FAIL. `package:footstep_core/footstep_core.dart`가 없다는 컴파일 오류

- [ ] **Step 4: 공용 코드 작성**

`packages/footstep_core/lib/src/session/session_schema.dart`:

```dart
/// 세션 폴더의 파일 이름과 CSV 헤더(설계 문서 4-2). 앱의 기록기와 PC 재생기·분석이 같은 이름과 열
/// 순서를 쓰도록 이 패키지 한곳에 둔다. 바꾸면 설계 문서도 함께 바꿔야 한다.
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

`packages/footstep_core/lib/src/session/csv.dart`:

```dart
/// 따옴표로 감싼 필드(쉼표·이중 따옴표 포함)를 처리하는 CSV 한 줄 분리. [formatCsvField]의 서식과 짝이다.
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

/// 물리적 줄 목록을 논리적 CSV 행으로 합친다. 따옴표 안의 줄바꿈(메모 등)이 readAsLines에서 두 줄로
/// 쪼개지므로, 따옴표가 닫히지 않은 줄은 다음 줄과 줄바꿈으로 이어 붙인다. 이미 합쳐진 행을 넣어도 같다.
List<String> csvRecords(List<String> lines) {
  final records = <String>[];
  StringBuffer? open;
  var openQuotes = 0;
  for (final line in lines) {
    final pending = open;
    if (pending == null) {
      final quotes = '"'.allMatches(line).length;
      if (quotes.isEven) {
        records.add(line);
      } else {
        open = StringBuffer(line);
        openQuotes = quotes;
      }
    } else {
      pending.write('\n');
      pending.write(line);
      openQuotes += '"'.allMatches(line).length;
      if (openQuotes.isEven) {
        records.add(pending.toString());
        open = null;
      }
    }
  }
  // 따옴표가 끝내 안 닫힌 꼬리는 깨진 행으로 그대로 남겨, 호출하는 쪽이 건너뛰게 한다.
  if (open != null) records.add(open.toString());
  return records;
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

`packages/footstep_core/lib/footstep_core.dart`:

```dart
/// 발걸음 연구 공용 로직. 앱(기록 서비스)과 PC 재생기가 같은 코드를 쓴다(설계 문서 2장 D2).
library;

export 'src/session/csv.dart';
export 'src/session/session_schema.dart';
```

- [ ] **Step 5: 패키지 테스트 통과 확인**

Run (`packages/footstep_core/`에서): `dart test`
Expected: PASS (6 tests)

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 6: 앱이 공용 패키지를 쓰도록 바꾸기**

`app/pubspec.yaml`의 `device_probe:` 묶음(두 줄) 바로 다음에 추가한다.

```yaml
  footstep_core:
    path: ../packages/footstep_core
```

`app/lib/features/footsteps/recording/session_schema.dart`의 내용 전체를 다음으로 바꾼다.

```dart
// 세션 파일 이름과 헤더는 공용 패키지(footstep_core)가 가진다 — 앱(기록)과 PC 재생기가 같은 계약을
// 쓰게 하려고. 기존 import 경로가 깨지지 않도록 여기서 다시 내보낸다.
export 'package:footstep_core/footstep_core.dart' show SessionSchema;
```

`app/lib/features/footsteps/recording/session_check.dart`:
- `List<String> splitCsvLine(String line) { ... }` 함수 전체와 그 위 doc 주석을 지운다.
- `List<String> csvRecords(List<String> lines) { ... }` 함수 전체와 그 위 doc 주석을 지운다.
- 파일 위쪽 import 묶음에 다음 두 줄을 추가한다. 이 파일을 import하는 `session_marks.dart`와 테스트가 그대로 동작하게 다시 내보낸다.

```dart
import 'package:footstep_core/footstep_core.dart' show csvRecords, splitCsvLine;
export 'package:footstep_core/footstep_core.dart' show csvRecords, splitCsvLine;
```

- 파일 위의 주석 `// 이 파일은 dart:io와 path만 쓴다. ...`를 다음으로 바꾼다.

```dart
// 이 파일은 dart:io, path, 순수 Dart 패키지 footstep_core만 쓴다. tool/check_session.dart가 Flutter 없이
// `dart run`으로 불러 쓰기 때문이다.
```

`app/lib/features/footsteps/recording/csv_writer.dart`:
- 파일 끝의 `String formatCsvField(Object? value) { ... }` 함수 전체와 그 위 doc 주석을 지운다.
- import 묶음에 다음 두 줄을 추가한다(기존 테스트가 `csv_writer.dart`에서 `formatCsvField`를 가져다 쓴다).

```dart
import 'package:footstep_core/footstep_core.dart' show formatCsvField;
export 'package:footstep_core/footstep_core.dart' show formatCsvField;
```

- [ ] **Step 7: 앱 확인**

Run (`app/`에서): `flutter pub get`
Expected: `Got dependencies!`

Run: `flutter test`
Expected: 전체 PASS (테스트 수는 이 태스크 전과 같다)

Run: `dart analyze`
Expected: `No issues found!`

로컬에 R1 세션이 있으면 점검 도구가 그대로 도는지 본다(Bash, `app/`에서).

```bash
S=$(ls -d ../research/data/sessions/*/ 2>/dev/null | head -1); [ -n "$S" ] && dart run tool/check_session.dart "$S" | head -3 || echo "세션 없음 — 건너뜀"
```

Expected: `gps.csv ... rows=` 줄이 나오거나 `세션 없음 — 건너뜀`

- [ ] **Step 8: 커밋**

```bash
git add packages/footstep_core app/pubspec.yaml app/pubspec.lock app/lib/features/footsteps/recording/session_schema.dart app/lib/features/footsteps/recording/session_check.dart app/lib/features/footsteps/recording/csv_writer.dart
git status --short packages/footstep_core   # .dart_tool/, pubspec.lock이 없어야 한다
git commit -m "feat(footstep_core): 공용 Dart 패키지를 만들고 세션 계약과 CSV 도우미를 옮긴다"
```

---

### Task 2: 모델·거리·사건·할 일·인터페이스

**Files:**
- Create: `packages/footstep_core/lib/src/model/fix.dart`
- Create: `packages/footstep_core/lib/src/model/readings.dart`
- Create: `packages/footstep_core/lib/src/geo.dart`
- Create: `packages/footstep_core/lib/src/events/policy_event.dart`
- Create: `packages/footstep_core/lib/src/events/policy_action.dart`
- Create: `packages/footstep_core/lib/src/policies/collection_policy.dart`
- Create: `packages/footstep_core/lib/src/detectors/step_detector.dart`
- Modify: `packages/footstep_core/lib/footstep_core.dart`
- Test: `packages/footstep_core/test/model_test.dart`

**Interfaces:**
- Produces:
  - `class Fix({required int tMs, required double lat, required double lng, required double accuracyM, double? speedMps, double? bearingDeg})`
  - `class AccelReading({required int tMs, required double x, required double y, required double z})`
  - `class OsStepReading({required int tMs, required String kind, required String value})` + `static const count = 'count'`, `static const status = 'status'`
  - `class ActivityReading({required int tMs, required String type, required String confidence})`
  - `class BatteryLevelReading({required int tMs, required int levelPct})`
  - `double haversineMeters(double lat1, double lng1, double lat2, double lng2)`
  - `enum StepState { still, walking, otherMotion }`
  - `sealed class PolicyEvent({required int tMs})`의 하위
    - `StepUpdate({tMs, state, totalSteps, stepsSinceLastFix, double? cadenceHz})`
    - `ActivityUpdate({tMs, type, confidence})`
    - `FixResult({tMs, Fix? fix})` + `bool get failed`
    - `ContinuousFix({tMs, required Fix fix})`
    - `Wakeup({tMs, required String tag})`
    - `BatteryLevel({tMs, required int pct})`
  - `sealed class PolicyAction`(`String get logName`, `String get logArgs`, 값 비교 `==`)의 하위
    - `RequestFix({int timeoutMs = 15000})`
    - `StartContinuous({int intervalMs = 1000, double distanceFilterM = 0})`
    - `StopContinuous()`
    - `WakeAt({required int tMs, required String tag})`
  - `class PolicyContext({required int nowMs, Fix? lastFix})`
  - `abstract interface class CollectionPolicy { String get id; Map<String, Object> get params; List<PolicyAction> onStart(PolicyContext ctx); List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx); }`
  - `abstract interface class ReportsState { String get stateLabel; }`
  - `abstract interface class StepDetector { String get id; StepState get state; int get totalSteps; int get stepsSinceLastFix; StepUpdate? onAccel(int tMs, List<AccelReading> batch); StepUpdate? onOsStep(OsStepReading reading); void onFix(); }`

- [ ] **Step 1: 실패하는 테스트 작성**

`packages/footstep_core/test/model_test.dart`:

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

void main() {
  test('위도 1도는 약 111,195m이고, 같은 점은 0m다', () {
    expect(haversineMeters(37.0, 127.0, 38.0, 127.0), closeTo(111195, 1));
    expect(haversineMeters(37.5, 127.0, 37.5, 127.0), 0);
  });

  test('할 일은 값으로 비교하고, actions.csv용 이름과 인자를 낸다', () {
    expect(const RequestFix(), const RequestFix());
    expect(const RequestFix(timeoutMs: 5000), isNot(const RequestFix()));
    expect(const WakeAt(tMs: 61000, tag: 'tick'), const WakeAt(tMs: 61000, tag: 'tick'));

    expect(const RequestFix().logName, 'request_fix');
    expect(const RequestFix().logArgs, 'timeout_ms=15000');
    expect(const StartContinuous(intervalMs: 1000, distanceFilterM: 10).logName, 'start_continuous');
    expect(const StartContinuous(intervalMs: 1000, distanceFilterM: 10).logArgs,
        'interval_ms=1000 distance_filter_m=10.0');
    expect(const StopContinuous().logName, 'stop_continuous');
    expect(const StopContinuous().logArgs, '');
    expect(const WakeAt(tMs: 61000, tag: 'tick').logName, 'wake_at');
    expect(const WakeAt(tMs: 61000, tag: 'tick').logArgs, 't_ms=61000 tag=tick');
  });

  test('FixResult는 위치가 없으면 실패다', () {
    const fix = Fix(tMs: 1000, lat: 37.5, lng: 127.0, accuracyM: 5);
    expect(const FixResult(tMs: 1000, fix: fix).failed, isFalse);
    expect(const FixResult(tMs: 16000).failed, isTrue);
  });

  test('OS 걸음 읽기의 kind 상수는 os_steps.csv 계약과 같다', () {
    expect(OsStepReading.count, 'count');
    expect(OsStepReading.status, 'status');
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `dart test test/model_test.dart`
Expected: FAIL (`haversineMeters`, `RequestFix` 등이 정의되지 않았다는 컴파일 오류)

- [ ] **Step 3: 구현**

`packages/footstep_core/lib/src/model/fix.dart`:

```dart
/// GPS 위치 하나. [tMs]는 기록 시각(gps.csv의 t_ms)이다 — 재생기는 이 시각을 '그 위치를 알 수 있게 된
/// 때'로 쓴다. 속도·방향은 기기가 모르면 null이다.
class Fix {
  const Fix({
    required this.tMs,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    this.speedMps,
    this.bearingDeg,
  });

  final int tMs;
  final double lat;
  final double lng;
  final double accuracyM;
  final double? speedMps;
  final double? bearingDeg;
}
```

`packages/footstep_core/lib/src/model/readings.dart`:

```dart
/// 가속도 표본 하나(m/s², 중력 포함).
class AccelReading {
  const AccelReading({required this.tMs, required this.x, required this.y, required this.z});

  final int tMs;
  final double x;
  final double y;
  final double z;
}

/// os_steps.csv의 행 하나. [kind]가 [count]면 value는 부팅 후 누적 걸음 수, [status]면 OS 보행 상태다.
class OsStepReading {
  const OsStepReading({required this.tMs, required this.kind, required this.value});

  static const count = 'count';
  static const status = 'status';

  final int tMs;
  final String kind;
  final String value;
}

/// 구글 활동 인식 결과 하나. type은 IN_VEHICLE·ON_BICYCLE·RUNNING·STILL·WALKING·UNKNOWN,
/// confidence는 HIGH·MEDIUM·LOW다.
class ActivityReading {
  const ActivityReading({required this.tMs, required this.type, required this.confidence});

  final int tMs;
  final String type;
  final String confidence;
}

/// 배터리 잔량(%) 하나. 정책은 잔량만 쓴다(배터리 20% 미만 대응, 설계 5-3).
class BatteryLevelReading {
  const BatteryLevelReading({required this.tMs, required this.levelPct});

  final int tMs;
  final int levelPct;
}
```

`packages/footstep_core/lib/src/geo.dart`:

```dart
import 'dart:math' as math;

/// 두 좌표 사이 거리(m). 지구를 반지름 6,371,008.8m인 구로 보는 haversine 식이다 — 걷는 거리 수준에서는
/// 타원체 식과 차이가 오차 예산(25m~)보다 훨씬 작다.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusM = 6371008.8;
  double rad(double degrees) => degrees * math.pi / 180;
  final sinLat = math.sin(rad(lat2 - lat1) / 2);
  final sinLng = math.sin(rad(lng2 - lng1) / 2);
  final a = sinLat * sinLat + math.cos(rad(lat1)) * math.cos(rad(lat2)) * sinLng * sinLng;
  return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(a)));
}
```

`packages/footstep_core/lib/src/events/policy_event.dart`:

```dart
import '../model/fix.dart';

/// 걸음 감지기가 판단한 지금 상태(설계 5-2). otherMotion은 흔들림은 있는데 걸음 박자가 없을 때다(탈것 의심).
enum StepState { still, walking, otherMotion }

/// 정책이 받는 사건. [tMs]는 사건이 일어난 시각이다.
sealed class PolicyEvent {
  const PolicyEvent({required this.tMs});

  final int tMs;
}

/// 걸음 감지기의 상태나 걸음 수가 바뀌었다.
final class StepUpdate extends PolicyEvent {
  const StepUpdate({
    required super.tMs,
    required this.state,
    required this.totalSteps,
    required this.stepsSinceLastFix,
    this.cadenceHz,
  });

  final StepState state;
  final int totalSteps;
  final int stepsSinceLastFix;

  /// 초당 걸음 수. 감지기가 모르면 null이다(OS 센서판).
  final double? cadenceHz;
}

/// 구글 활동 인식 결과가 들어왔다.
final class ActivityUpdate extends PolicyEvent {
  const ActivityUpdate({required super.tMs, required this.type, required this.confidence});

  final String type;
  final String confidence;
}

/// 정책이 낸 RequestFix의 결과. [fix]가 null이면 제한 시간 안에 위치를 못 받았다.
final class FixResult extends PolicyEvent {
  const FixResult({required super.tMs, this.fix});

  final Fix? fix;

  bool get failed => fix == null;
}

/// 연속 측위 중 들어온 위치.
final class ContinuousFix extends PolicyEvent {
  const ContinuousFix({required super.tMs, required this.fix});

  final Fix fix;
}

/// 정책이 WakeAt으로 예약한 시각이 됐다.
final class Wakeup extends PolicyEvent {
  const Wakeup({required super.tMs, required this.tag});

  final String tag;
}

/// 배터리 잔량(%)이 바뀌었다.
final class BatteryLevel extends PolicyEvent {
  const BatteryLevel({required super.tMs, required this.pct});

  final int pct;
}
```

`packages/footstep_core/lib/src/events/policy_action.dart`:

```dart
/// 정책이 돌려주는 할 일(설계 5-1). 실행기(재생 또는 폰)가 실제 동작으로 바꾼다. 테스트가 결과를 목록으로
/// 비교할 수 있게 값으로 비교한다.
sealed class PolicyAction {
  const PolicyAction();

  /// actions.csv의 action 열.
  String get logName;

  /// actions.csv의 args 열(k=v를 공백으로 구분).
  String get logArgs;
}

/// GPS를 켜서 위치를 한 번 받는다. [timeoutMs] 안에 못 받으면 실패다(현재 앱의 측위 제한 15초).
final class RequestFix extends PolicyAction {
  const RequestFix({this.timeoutMs = 15000});

  final int timeoutMs;

  @override
  String get logName => 'request_fix';

  @override
  String get logArgs => 'timeout_ms=$timeoutMs';

  @override
  bool operator ==(Object other) => other is RequestFix && other.timeoutMs == timeoutMs;

  @override
  int get hashCode => Object.hash('RequestFix', timeoutMs);

  @override
  String toString() => 'RequestFix(timeoutMs: $timeoutMs)';
}

/// 연속 측위를 켠다. 위치는 [intervalMs]마다, 마지막으로 알린 위치에서 [distanceFilterM] 이상 움직였을
/// 때만 알린다(안드로이드 위치 요청의 간격·거리 필터와 같은 뜻).
final class StartContinuous extends PolicyAction {
  const StartContinuous({this.intervalMs = 1000, this.distanceFilterM = 0});

  final int intervalMs;
  final double distanceFilterM;

  @override
  String get logName => 'start_continuous';

  @override
  String get logArgs => 'interval_ms=$intervalMs distance_filter_m=$distanceFilterM';

  @override
  bool operator ==(Object other) =>
      other is StartContinuous &&
      other.intervalMs == intervalMs &&
      other.distanceFilterM == distanceFilterM;

  @override
  int get hashCode => Object.hash('StartContinuous', intervalMs, distanceFilterM);

  @override
  String toString() => 'StartContinuous(intervalMs: $intervalMs, distanceFilterM: $distanceFilterM)';
}

/// 연속 측위를 끈다.
final class StopContinuous extends PolicyAction {
  const StopContinuous();

  @override
  String get logName => 'stop_continuous';

  @override
  String get logArgs => '';

  @override
  bool operator ==(Object other) => other is StopContinuous;

  @override
  int get hashCode => 'StopContinuous'.hashCode;

  @override
  String toString() => 'StopContinuous()';
}

/// [tMs]에 Wakeup([tag]) 사건을 보내 달라고 예약한다.
final class WakeAt extends PolicyAction {
  const WakeAt({required this.tMs, required this.tag});

  final int tMs;
  final String tag;

  @override
  String get logName => 'wake_at';

  @override
  String get logArgs => 't_ms=$tMs tag=$tag';

  @override
  bool operator ==(Object other) => other is WakeAt && other.tMs == tMs && other.tag == tag;

  @override
  int get hashCode => Object.hash('WakeAt', tMs, tag);

  @override
  String toString() => 'WakeAt(tMs: $tMs, tag: $tag)';
}
```

`packages/footstep_core/lib/src/policies/collection_policy.dart`:

```dart
import '../events/policy_action.dart';
import '../events/policy_event.dart';
import '../model/fix.dart';

/// 정책이 판단할 때 쓰는 현재 정보. [lastFix]는 실행기가 마지막으로 정책에 알린 위치다(단발·연속 모두).
class PolicyContext {
  const PolicyContext({required this.nowMs, this.lastFix});

  final int nowMs;
  final Fix? lastFix;
}

/// 수집 정책(설계 5-1). 시계·GPS·타이머를 직접 쓰지 않고, 사건을 받아 할 일만 돌려준다 — 그래서 같은 정책을
/// 폰 실행기와 PC 재생기에서 똑같이 돌릴 수 있다.
abstract interface class CollectionPolicy {
  /// 정책 id(설계 5-3의 표). summary.json과 결과 폴더 이름에 쓴다.
  String get id;

  /// 결과에 함께 남길 파라미터(예: {'e_m': 50.0}).
  Map<String, Object> get params;

  List<PolicyAction> onStart(PolicyContext ctx);

  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx);
}

/// 정책이 지금 상태를 이름으로 알려 준다(fixes.csv의 state 열). 구현하지 않은 정책은 걸음 감지기 상태를 쓴다.
/// 제안 정책(R4)은 걸음 감지기에 없는 'vehicle' 상태를 이걸로 알린다.
abstract interface class ReportsState {
  String get stateLabel;
}
```

`packages/footstep_core/lib/src/detectors/step_detector.dart`:

```dart
import '../events/policy_event.dart';
import '../model/readings.dart';

/// 걸음 감지기(모듈 A, 설계 5-2). 가속도 묶음이나 OS 걸음 읽기를 받아, 상태나 걸음 수가 바뀌었을 때만
/// [StepUpdate]를 돌려준다. 바뀐 게 없으면 null이다.
abstract interface class StepDetector {
  String get id;

  StepState get state;

  int get totalSteps;

  /// 마지막 [onFix] 이후 걸음 수. fixes.csv의 steps_since_prev 열이 된다.
  int get stepsSinceLastFix;

  /// 가속도 묶음(약 1초 분량). [tMs]는 묶음의 마지막 표본 시각이다 — 감지기는 이것을 시계로도 쓴다.
  StepUpdate? onAccel(int tMs, List<AccelReading> batch);

  StepUpdate? onOsStep(OsStepReading reading);

  /// 실행기가 위치를 정책에 알린 직후 부른다.
  void onFix();
}
```

`packages/footstep_core/lib/footstep_core.dart`의 export 목록을 다음으로 바꾼다.

```dart
export 'src/detectors/step_detector.dart';
export 'src/events/policy_action.dart';
export 'src/events/policy_event.dart';
export 'src/geo.dart';
export 'src/model/fix.dart';
export 'src/model/readings.dart';
export 'src/policies/collection_policy.dart';
export 'src/session/csv.dart';
export 'src/session/session_schema.dart';
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `dart test`
Expected: PASS (csv_test 6 + model_test 4)

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core
git commit -m "feat(footstep_core): 정책이 주고받는 사건·할 일과 모델을 정한다"
```

---

### Task 3: 세션 폴더 읽기 (`readSession`)

**Files:**
- Create: `packages/footstep_core/lib/src/session/session_reader.dart`
- Modify: `packages/footstep_core/lib/footstep_core.dart`
- Test: `packages/footstep_core/test/session/session_reader_test.dart`

**Interfaces:**
- Consumes: `SessionSchema`, `splitCsvLine`, `csvRecords` (Task 1), `Fix`, `AccelReading`, `OsStepReading`, `ActivityReading`, `BatteryLevelReading` (Task 2)
- Produces:
  - `class SessionData({required String sessionId, List<Fix> fixes, List<AccelReading> accel, List<OsStepReading> osSteps, List<ActivityReading> activities, List<BatteryLevelReading> battery, int skippedRows})` — 목록은 모두 시각순, `int? get startMs`, `int? get endMs`
  - `Future<SessionData> readSession(Directory dir)`

- [ ] **Step 1: path 의존성 추가**

Run (`packages/footstep_core/`에서): `dart pub add path`

- [ ] **Step 2: 실패하는 테스트 작성**

`packages/footstep_core/test/session/session_reader_test.dart`:

```dart
import 'dart:io';

import 'package:footstep_core/footstep_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory session;

  void write(String name, List<String> lines) =>
      File(p.join(session.path, name)).writeAsStringSync('${lines.join('\n')}\n');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('session_reader_test');
    session = Directory(p.join(root.path, '20261109-213324-groundTruth'))..createSync();
  });

  tearDown(() async => root.delete(recursive: true));

  test('각 CSV를 시각순으로 읽고, 깨진 행은 건너뛰며 센다', () async {
    write('gps.csv', [
      't_ms,fix_t_ms,lat,lng,accuracy_m,speed_mps,bearing_deg,altitude_m',
      '2000,1990,37.5,127.0,8.5,1.2,90,30',
      '1000,990,37.4,126.9,5.0,-1,-1,30',
      'broken',
    ]);
    write('accel.csv', ['t_ms,x,y,z', '1010,0.1,9.8,0.2', '1000,0,9.7,0']);
    write('os_steps.csv', ['t_ms,kind,value', '1000,count,1520', '1500,status,walking']);
    write('activity.csv', ['t_ms,type,confidence', '1200,WALKING,HIGH']);
    write('battery.csv', [
      't_ms,charge_uah,current_ua,level_pct,temp_c,plugged',
      '1000,3705000,-193,90,30.8,0',
      '31000,,-150,,30.8,0',
    ]);

    final data = await readSession(session);

    expect(data.sessionId, '20261109-213324-groundTruth');
    expect(data.fixes.map((f) => f.tMs), [1000, 2000]);
    expect(data.fixes.first.speedMps, isNull); // 음수 속도는 '모름'
    expect(data.fixes.first.bearingDeg, isNull);
    expect(data.fixes.last.speedMps, 1.2);
    expect(data.fixes.last.accuracyM, 8.5);
    expect(data.accel.map((a) => a.tMs), [1000, 1010]);
    expect(data.osSteps.map((s) => s.kind), [OsStepReading.count, OsStepReading.status]);
    expect(data.activities.single.type, 'WALKING');
    expect(data.battery.single.levelPct, 90);
    expect(data.skippedRows, 2); // gps의 'broken', 잔량이 빈 배터리 행
    expect(data.startMs, 1000);
    expect(data.endMs, 2000);
  });

  test('같은 시각의 행은 파일 순서를 지킨다', () async {
    write('os_steps.csv', ['t_ms,kind,value', '1000,count,10', '1000,status,walking']);

    final data = await readSession(session);
    expect(data.osSteps.map((s) => s.kind), [OsStepReading.count, OsStepReading.status]);
  });

  test('파일이 없으면 빈 목록이고 시작·끝 시각은 null이다', () async {
    final data = await readSession(session);

    expect(data.fixes, isEmpty);
    expect(data.accel, isEmpty);
    expect(data.startMs, isNull);
    expect(data.endMs, isNull);
  });
}
```

- [ ] **Step 3: 테스트가 실패하는지 확인**

Run: `dart test test/session/session_reader_test.dart`
Expected: FAIL (`readSession`이 정의되지 않았다는 컴파일 오류)

- [ ] **Step 4: 구현**

`packages/footstep_core/lib/src/session/session_reader.dart`:

```dart
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../model/fix.dart';
import '../model/readings.dart';
import 'csv.dart';
import 'session_schema.dart';

/// 세션 폴더 하나를 읽은 결과. 목록은 모두 시각순이다.
class SessionData {
  const SessionData({
    required this.sessionId,
    this.fixes = const [],
    this.accel = const [],
    this.osSteps = const [],
    this.activities = const [],
    this.battery = const [],
    this.skippedRows = 0,
  });

  final String sessionId;
  final List<Fix> fixes;
  final List<AccelReading> accel;
  final List<OsStepReading> osSteps;
  final List<ActivityReading> activities;
  final List<BatteryLevelReading> battery;

  /// 읽지 못해 건너뛴 행 수(서비스가 쓰다 죽어 잘린 줄 등).
  final int skippedRows;

  /// 가장 이른 기록 시각. 기록이 하나도 없으면 null이다.
  int? get startMs {
    final firsts = [
      if (fixes.isNotEmpty) fixes.first.tMs,
      if (accel.isNotEmpty) accel.first.tMs,
      if (osSteps.isNotEmpty) osSteps.first.tMs,
      if (activities.isNotEmpty) activities.first.tMs,
      if (battery.isNotEmpty) battery.first.tMs,
    ];
    return firsts.isEmpty ? null : firsts.reduce(math.min);
  }

  /// 가장 늦은 기록 시각. 기록이 하나도 없으면 null이다.
  int? get endMs {
    final lasts = [
      if (fixes.isNotEmpty) fixes.last.tMs,
      if (accel.isNotEmpty) accel.last.tMs,
      if (osSteps.isNotEmpty) osSteps.last.tMs,
      if (activities.isNotEmpty) activities.last.tMs,
      if (battery.isNotEmpty) battery.last.tMs,
    ];
    return lasts.isEmpty ? null : lasts.reduce(math.max);
  }
}

/// R1이 쓴 세션 폴더(설계 4-2)를 읽는다. 없는 파일은 빈 목록이고, 읽을 수 없는 행은 건너뛰고 센다.
Future<SessionData> readSession(Directory dir) async {
  var skipped = 0;

  Future<List<T>> load<T>(
    String fileName,
    T? Function(List<String> fields) parse,
    int Function(T item) timeOf,
  ) async {
    final file = File(p.join(dir.path, fileName));
    if (!await file.exists()) return <T>[];
    final items = <T>[];
    for (final record in csvRecords(await file.readAsLines()).skip(1)) {
      if (record.isEmpty) continue;
      final item = parse(splitCsvLine(record));
      if (item == null) {
        skipped++;
      } else {
        items.add(item);
      }
    }
    return _sortedByTime(items, timeOf);
  }

  final fixes = await load(SessionSchema.gpsFile, _parseGps, (Fix f) => f.tMs);
  final accel = await load(SessionSchema.accelFile, _parseAccel, (AccelReading a) => a.tMs);
  final osSteps = await load(SessionSchema.osStepsFile, _parseOsStep, (OsStepReading s) => s.tMs);
  final activities =
      await load(SessionSchema.activityFile, _parseActivity, (ActivityReading a) => a.tMs);
  final battery =
      await load(SessionSchema.batteryFile, _parseBattery, (BatteryLevelReading b) => b.tMs);

  return SessionData(
    sessionId: p.basename(dir.path),
    fixes: fixes,
    accel: accel,
    osSteps: osSteps,
    activities: activities,
    battery: battery,
    skippedRows: skipped,
  );
}

/// 시각순으로 정렬하되 같은 시각은 원래 순서를 지킨다(List.sort는 안정 정렬이 아니다).
List<T> _sortedByTime<T>(List<T> items, int Function(T item) timeOf) {
  final order = List<int>.generate(items.length, (i) => i);
  order.sort((a, b) {
    final byTime = timeOf(items[a]).compareTo(timeOf(items[b]));
    return byTime != 0 ? byTime : a.compareTo(b);
  });
  return [for (final i in order) items[i]];
}

Fix? _parseGps(List<String> f) {
  if (f.length < 5) return null;
  final t = int.tryParse(f[0]);
  final lat = double.tryParse(f[2]);
  final lng = double.tryParse(f[3]);
  final accuracy = double.tryParse(f[4]);
  if (t == null || lat == null || lng == null || accuracy == null) return null;
  return Fix(
    tMs: t,
    lat: lat,
    lng: lng,
    accuracyM: accuracy,
    speedMps: _nonNegative(f, 5),
    bearingDeg: _nonNegative(f, 6),
  );
}

/// geolocator는 모르는 속도·방향을 음수로 준다. 음수와 빈칸은 null('모름')로 읽는다.
double? _nonNegative(List<String> f, int index) {
  if (index >= f.length) return null;
  final value = double.tryParse(f[index]);
  return value == null || value < 0 ? null : value;
}

AccelReading? _parseAccel(List<String> f) {
  if (f.length < 4) return null;
  final t = int.tryParse(f[0]);
  final x = double.tryParse(f[1]);
  final y = double.tryParse(f[2]);
  final z = double.tryParse(f[3]);
  if (t == null || x == null || y == null || z == null) return null;
  return AccelReading(tMs: t, x: x, y: y, z: z);
}

OsStepReading? _parseOsStep(List<String> f) {
  if (f.length < 3) return null;
  final t = int.tryParse(f[0]);
  if (t == null || f[1].isEmpty) return null;
  return OsStepReading(tMs: t, kind: f[1], value: f[2]);
}

ActivityReading? _parseActivity(List<String> f) {
  if (f.length < 3) return null;
  final t = int.tryParse(f[0]);
  if (t == null || f[1].isEmpty) return null;
  return ActivityReading(tMs: t, type: f[1], confidence: f[2]);
}

BatteryLevelReading? _parseBattery(List<String> f) {
  if (f.length < 4) return null;
  final t = int.tryParse(f[0]);
  final level = int.tryParse(f[3]);
  if (t == null || level == null) return null;
  return BatteryLevelReading(tMs: t, levelPct: level);
}
```

`packages/footstep_core/lib/footstep_core.dart`의 export 목록에 추가한다(알파벳 순서 유지).

```dart
export 'src/session/session_reader.dart';
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `dart test`
Expected: PASS (지금까지 13 tests)

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 6: 커밋**

```bash
git add packages/footstep_core
git commit -m "feat(footstep_core): R1 세션 폴더를 읽는다"
```

---

### Task 4: OS 센서판 걸음 감지기 (`OsStepDetector`)

**Files:**
- Create: `packages/footstep_core/lib/src/detectors/os_step_detector.dart`
- Modify: `packages/footstep_core/lib/footstep_core.dart`
- Test: `packages/footstep_core/test/detectors/os_step_detector_test.dart`

**Interfaces:**
- Consumes: `StepDetector`, `StepUpdate`, `StepState`, `OsStepReading`, `AccelReading` (Task 2)
- Produces: `class OsStepDetector implements StepDetector` — `OsStepDetector({int walkingWindowMs = 4000})`, `id == 'os'`

- [ ] **Step 1: 실패하는 테스트 작성**

`packages/footstep_core/test/detectors/os_step_detector_test.dart`:

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

OsStepReading count(int tMs, int value) =>
    OsStepReading(tMs: tMs, kind: OsStepReading.count, value: '$value');

OsStepReading status(int tMs, String value) =>
    OsStepReading(tMs: tMs, kind: OsStepReading.status, value: value);

void main() {
  test('첫 누적값은 기준이고, 늘어나면 보행과 걸음 수를 알린다', () {
    final detector = OsStepDetector();

    expect(detector.onOsStep(count(1000, 1520)), isNull);
    final update = detector.onOsStep(count(2000, 1525))!;

    expect(update.tMs, 2000);
    expect(update.state, StepState.walking);
    expect(update.totalSteps, 5);
    expect(update.stepsSinceLastFix, 5);
    expect(detector.id, 'os');
  });

  test('마지막 걸음 뒤 4초가 지나면 가속도 묶음 시각으로 정지를 알린다', () {
    final detector = OsStepDetector()
      ..onOsStep(count(1000, 100))
      ..onOsStep(count(2000, 103));

    expect(detector.onAccel(5000, const []), isNull); // 3초 뒤: 아직 보행
    final update = detector.onAccel(6500, const [])!;
    expect(update.state, StepState.still);
    expect(detector.onAccel(7500, const []), isNull); // 이미 정지
  });

  test('OS 상태가 walking이면 걸음 누적이 늦게 와도 보행으로 본다', () {
    final detector = OsStepDetector();

    expect(detector.onOsStep(status(1000, 'walking'))!.state, StepState.walking);
    expect(detector.onAccel(20000, const []), isNull);
    expect(detector.onOsStep(status(21000, 'stopped'))!.state, StepState.still);
  });

  test('onFix는 마지막 측위 이후 걸음 수를 0으로 되돌린다', () {
    final detector = OsStepDetector()
      ..onOsStep(count(1000, 0))
      ..onOsStep(count(2000, 10));
    expect(detector.stepsSinceLastFix, 10);

    detector.onFix();
    expect(detector.stepsSinceLastFix, 0);
    final update = detector.onOsStep(count(3000, 14))!;
    expect(update.stepsSinceLastFix, 4);
    expect(update.totalSteps, 14);
  });

  test('누적값이 줄면(재부팅 등) 기준을 다시 잡아 걸음을 이어 센다', () {
    final detector = OsStepDetector()
      ..onOsStep(count(1000, 500))
      ..onOsStep(count(2000, 510));

    detector.onOsStep(count(3000, 3));
    final update = detector.onOsStep(count(4000, 8))!;
    expect(update.totalSteps, 15);
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `dart test test/detectors/os_step_detector_test.dart`
Expected: FAIL (`OsStepDetector`가 정의되지 않았다는 컴파일 오류)

- [ ] **Step 3: 구현**

`packages/footstep_core/lib/src/detectors/os_step_detector.dart`:

```dart
import '../events/policy_event.dart';
import '../model/readings.dart';
import 'step_detector.dart';

/// OS 걸음 센서판 감지기(설계 5-2). 누적 걸음 수가 최근 [walkingWindowMs] 안에 늘었거나 OS 보행 상태가
/// walking이면 보행, 아니면 정지로 본다. 흔들림을 보지 않으므로 기타 움직임(탈것)은 구분하지 못한다.
///
/// OS 걸음 센서는 걸음을 몇 초씩 묶어 늦게 알리기도 한다. 그래서 정지 판단은 걸음 이벤트가 아니라 가속도
/// 묶음 시각([onAccel])을 시계로 삼아 내린다.
class OsStepDetector implements StepDetector {
  OsStepDetector({this.walkingWindowMs = 4000});

  final int walkingWindowMs;

  int? _base;
  int _total = 0;
  int _totalAtLastFix = 0;
  int? _lastIncreaseMs;
  String _lastStatus = 'unknown';
  StepState _state = StepState.still;

  @override
  String get id => 'os';

  @override
  StepState get state => _state;

  @override
  int get totalSteps => _total;

  @override
  int get stepsSinceLastFix => _total - _totalAtLastFix;

  @override
  StepUpdate? onOsStep(OsStepReading reading) {
    var increased = false;
    if (reading.kind == OsStepReading.count) {
      final value = int.tryParse(reading.value);
      if (value == null) return null;
      final base = _base ??= value;
      final total = value - base;
      if (total < _total) {
        // 누적값이 줄었다(재부팅 등). 지금까지 센 걸음을 이어 가도록 기준을 다시 잡는다.
        _base = value - _total;
      } else if (total > _total) {
        _total = total;
        _lastIncreaseMs = reading.tMs;
        increased = true;
      }
    } else if (reading.kind == OsStepReading.status) {
      _lastStatus = reading.value;
    }
    return _update(reading.tMs, stepsChanged: increased);
  }

  @override
  StepUpdate? onAccel(int tMs, List<AccelReading> batch) => _update(tMs, stepsChanged: false);

  @override
  void onFix() => _totalAtLastFix = _total;

  StepUpdate? _update(int tMs, {required bool stepsChanged}) {
    final last = _lastIncreaseMs;
    final recentlyStepped = last != null && tMs - last <= walkingWindowMs;
    final next =
        recentlyStepped || _lastStatus == 'walking' ? StepState.walking : StepState.still;
    if (next == _state && !stepsChanged) return null;
    _state = next;
    return StepUpdate(
      tMs: tMs,
      state: _state,
      totalSteps: _total,
      stepsSinceLastFix: stepsSinceLastFix,
    );
  }
}
```

`packages/footstep_core/lib/footstep_core.dart`의 export 목록에 추가한다.

```dart
export 'src/detectors/os_step_detector.dart';
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `dart test`
Expected: PASS (지금까지 18 tests)

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core
git commit -m "feat(footstep_core): OS 걸음 센서판 걸음 감지기를 추가한다"
```

---

### Task 5: 기준 정책 ① 고정 주기·연속·정지 억제

**Files:**
- Create: `packages/footstep_core/lib/src/policies/fixed_interval_policy.dart`
- Create: `packages/footstep_core/lib/src/policies/continuous_policy.dart`
- Create: `packages/footstep_core/lib/src/policies/still_suppress_policy.dart`
- Modify: `packages/footstep_core/lib/footstep_core.dart`
- Test: `packages/footstep_core/test/policies/basic_policies_test.dart`

**Interfaces:**
- Consumes: `CollectionPolicy`, `PolicyContext`, `PolicyEvent`과 하위, `PolicyAction`과 하위, `StepState` (Task 2)
- Produces:
  - `FixedIntervalPolicy({required String id, required int intervalMs})` — `params == {'interval_s': intervalMs ~/ 1000}`
  - `ContinuousPolicy({String id = 'continuous_10m', int intervalMs = 1000, double distanceFilterM = 10})` — `params == {'interval_ms': ..., 'distance_filter_m': ...}`
  - `StillSuppressPolicy({int intervalMs = 60000})` — `id == 'still_suppress'`, `params == {'interval_s': intervalMs ~/ 1000}`

- [ ] **Step 1: 실패하는 테스트 작성**

`packages/footstep_core/test/policies/basic_policies_test.dart`:

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

StepUpdate step(int tMs, StepState state) =>
    StepUpdate(tMs: tMs, state: state, totalSteps: 0, stepsSinceLastFix: 0);

void main() {
  group('FixedIntervalPolicy (현재 앱 1시간 방식, 고정 주기)', () {
    test('시작하면 바로 측위하고 다음 주기를 예약한다', () {
      final policy = FixedIntervalPolicy(id: 'fixed_1m', intervalMs: 60000);

      expect(policy.onStart(const PolicyContext(nowMs: 1000)),
          [const RequestFix(), const WakeAt(tMs: 61000, tag: 'tick')]);
      expect(policy.id, 'fixed_1m');
      expect(policy.params, {'interval_s': 60});
    });

    test('주기가 되면 측위하고 그 시각 기준으로 다음 주기를 예약한다', () {
      final policy = FixedIntervalPolicy(id: 'hourly', intervalMs: 3600000);

      expect(policy.onEvent(const Wakeup(tMs: 3601000, tag: 'tick'), const PolicyContext(nowMs: 3601000)),
          [const RequestFix(), const WakeAt(tMs: 7201000, tag: 'tick')]);
    });

    test('다른 사건에는 아무것도 하지 않는다', () {
      final policy = FixedIntervalPolicy(id: 'fixed_30s', intervalMs: 30000);
      const ctx = PolicyContext(nowMs: 5000);

      expect(policy.onEvent(const Wakeup(tMs: 5000, tag: 'other'), ctx), isEmpty);
      expect(policy.onEvent(step(5000, StepState.walking), ctx), isEmpty);
      expect(policy.onEvent(const FixResult(tMs: 5000), ctx), isEmpty);
    });
  });

  group('ContinuousPolicy (현재 앱 10m 연속 방식)', () {
    test('시작하면 1초·10m 연속 측위를 켜고 그 뒤에는 아무것도 하지 않는다', () {
      final policy = ContinuousPolicy();

      expect(policy.onStart(const PolicyContext(nowMs: 0)),
          [const StartContinuous(intervalMs: 1000, distanceFilterM: 10)]);
      expect(policy.onEvent(const Wakeup(tMs: 10, tag: 'tick'), const PolicyContext(nowMs: 10)),
          isEmpty);
      expect(policy.id, 'continuous_10m');
      expect(policy.params, {'interval_ms': 1000, 'distance_filter_m': 10.0});
    });
  });

  group('StillSuppressPolicy (Zhuang 외 2010: 정지 중 측위 억제)', () {
    test('보행 중에는 주기마다 측위한다', () {
      final policy = StillSuppressPolicy();
      expect(policy.onStart(const PolicyContext(nowMs: 0)),
          [const RequestFix(), const WakeAt(tMs: 60000, tag: 'tick')]);

      policy.onEvent(step(1000, StepState.walking), const PolicyContext(nowMs: 1000));
      expect(policy.onEvent(const Wakeup(tMs: 60000, tag: 'tick'), const PolicyContext(nowMs: 60000)),
          [const RequestFix(), const WakeAt(tMs: 120000, tag: 'tick')]);
    });

    test('정지 중에는 측위를 건너뛰고 다음 주기만 예약한다', () {
      final policy = StillSuppressPolicy()..onStart(const PolicyContext(nowMs: 0));

      policy.onEvent(step(1000, StepState.still), const PolicyContext(nowMs: 1000));
      expect(policy.onEvent(const Wakeup(tMs: 60000, tag: 'tick'), const PolicyContext(nowMs: 60000)),
          [const WakeAt(tMs: 120000, tag: 'tick')]);
    });

    test('걸음 정보가 아직 없으면 측위한다', () {
      final policy = StillSuppressPolicy(intervalMs: 120000)..onStart(const PolicyContext(nowMs: 0));

      expect(policy.onEvent(const Wakeup(tMs: 120000, tag: 'tick'), const PolicyContext(nowMs: 120000)),
          [const RequestFix(), const WakeAt(tMs: 240000, tag: 'tick')]);
      expect(policy.id, 'still_suppress');
      expect(policy.params, {'interval_s': 120});
    });
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `dart test test/policies/basic_policies_test.dart`
Expected: FAIL (정책 클래스가 정의되지 않았다는 컴파일 오류)

- [ ] **Step 3: 구현**

`packages/footstep_core/lib/src/policies/fixed_interval_policy.dart`:

```dart
import '../events/policy_action.dart';
import '../events/policy_event.dart';
import 'collection_policy.dart';

/// 고정 주기 측위. `hourly`(현재 앱의 WorkManager 1시간 방식)와 `fixed_30s`·`fixed_1m`·`fixed_5m`이
/// 이 정책이다(설계 5-3). 다음 주기는 깨어난 시각 기준으로 잡아 주기가 밀리지 않게 한다.
class FixedIntervalPolicy implements CollectionPolicy {
  FixedIntervalPolicy({required this.id, required this.intervalMs});

  static const _tag = 'tick';

  @override
  final String id;

  final int intervalMs;

  @override
  Map<String, Object> get params => {'interval_s': intervalMs ~/ 1000};

  @override
  List<PolicyAction> onStart(PolicyContext ctx) =>
      [const RequestFix(), WakeAt(tMs: ctx.nowMs + intervalMs, tag: _tag)];

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    if (event is Wakeup && event.tag == _tag) {
      return [const RequestFix(), WakeAt(tMs: event.tMs + intervalMs, tag: _tag)];
    }
    return const [];
  }
}
```

`packages/footstep_core/lib/src/policies/continuous_policy.dart`:

```dart
import '../events/policy_action.dart';
import '../events/policy_event.dart';
import 'collection_policy.dart';

/// 연속 측위. `continuous_10m`은 현재 앱의 실시간 경로 방식(1초, 거리 필터 10m)이다(설계 5-3).
class ContinuousPolicy implements CollectionPolicy {
  ContinuousPolicy({this.id = 'continuous_10m', this.intervalMs = 1000, this.distanceFilterM = 10});

  @override
  final String id;

  final int intervalMs;
  final double distanceFilterM;

  @override
  Map<String, Object> get params =>
      {'interval_ms': intervalMs, 'distance_filter_m': distanceFilterM};

  @override
  List<PolicyAction> onStart(PolicyContext ctx) =>
      [StartContinuous(intervalMs: intervalMs, distanceFilterM: distanceFilterM)];

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) => const [];
}
```

`packages/footstep_core/lib/src/policies/still_suppress_policy.dart`:

```dart
import '../events/policy_action.dart';
import '../events/policy_event.dart';
import 'collection_policy.dart';

/// 정지 중 측위 억제(Zhuang 외, MobiSys 2010의 원리). 고정 주기로 측위하되, 걸음 감지기가 정지라고 하면
/// 그 주기의 측위를 건너뛴다. 걸음 정보가 아직 없으면 측위한다.
class StillSuppressPolicy implements CollectionPolicy {
  StillSuppressPolicy({this.intervalMs = 60000});

  static const _tag = 'tick';

  final int intervalMs;
  StepState? _state;

  @override
  String get id => 'still_suppress';

  @override
  Map<String, Object> get params => {'interval_s': intervalMs ~/ 1000};

  @override
  List<PolicyAction> onStart(PolicyContext ctx) =>
      [const RequestFix(), WakeAt(tMs: ctx.nowMs + intervalMs, tag: _tag)];

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    switch (event) {
      case StepUpdate(:final state):
        _state = state;
        return const [];
      case Wakeup(:final tag) when tag == _tag:
        final next = WakeAt(tMs: event.tMs + intervalMs, tag: _tag);
        return _state == StepState.still ? [next] : [const RequestFix(), next];
      default:
        return const [];
    }
  }
}
```

`packages/footstep_core/lib/footstep_core.dart`의 export 목록에 추가한다.

```dart
export 'src/policies/continuous_policy.dart';
export 'src/policies/fixed_interval_policy.dart';
export 'src/policies/still_suppress_policy.dart';
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `dart test`
Expected: PASS (지금까지 25 tests)

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core
git commit -m "feat(footstep_core): 고정 주기·연속·정지 억제 기준 정책을 추가한다"
```

---

### Task 6: 기준 정책 ② 속도 적응·시간×속도

**Files:**
- Create: `packages/footstep_core/lib/src/policies/speed_adaptive_policy.dart`
- Create: `packages/footstep_core/lib/src/policies/time_speed_policy.dart`
- Modify: `packages/footstep_core/lib/footstep_core.dart`
- Test: `packages/footstep_core/test/policies/adaptive_policies_test.dart`

**Interfaces:**
- Consumes: Task 2의 타입들
- Produces:
  - `SpeedAdaptivePolicy({double stillSpeedMps = 0.5, double vehicleSpeedMps = 2.5, int stillIntervalMs = 120000, int walkIntervalMs = 30000, int vehicleIntervalMs = 10000, int failureRetryMs = 30000})` — `id == 'speed_adaptive'`
  - `TimeSpeedPolicy({double errorBudgetM = 50, double minSpeedMps = 1.4, int minWaitMs = 5000, int maxWaitMs = 600000, int failureRetryMs = 30000})` — `id == 'time_speed'`, `params == {'e_m': errorBudgetM}`

- [ ] **Step 1: 실패하는 테스트 작성**

`packages/footstep_core/test/policies/adaptive_policies_test.dart`:

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

Fix fix(int tMs, {double accuracy = 8, double? speed}) =>
    Fix(tMs: tMs, lat: 37.5, lng: 127.0, accuracyM: accuracy, speedMps: speed);

List<PolicyAction> afterFix(CollectionPolicy policy, Fix f) =>
    policy.onEvent(FixResult(tMs: f.tMs, fix: f), PolicyContext(nowMs: f.tMs, lastFix: f));

void main() {
  group('SpeedAdaptivePolicy (Galeana-Zapién 외 2014: 속도에 따라 간격 조절)', () {
    test('시작하면 측위하고, 깨어나면 다시 측위한다', () {
      final policy = SpeedAdaptivePolicy();

      expect(policy.onStart(const PolicyContext(nowMs: 0)), [const RequestFix()]);
      expect(policy.onEvent(const Wakeup(tMs: 30000, tag: 'next'), const PolicyContext(nowMs: 30000)),
          [const RequestFix()]);
      expect(policy.id, 'speed_adaptive');
    });

    test('마지막 속도 구간에 따라 다음 측위 간격을 정한다', () {
      final policy = SpeedAdaptivePolicy();

      expect(afterFix(policy, fix(10000, speed: 0.2)), [const WakeAt(tMs: 130000, tag: 'next')]);
      expect(afterFix(policy, fix(10000, speed: 1.3)), [const WakeAt(tMs: 40000, tag: 'next')]);
      expect(afterFix(policy, fix(10000, speed: 8)), [const WakeAt(tMs: 20000, tag: 'next')]);
      expect(afterFix(policy, fix(10000)), [const WakeAt(tMs: 40000, tag: 'next')]); // 속도 모름 → 보행 간격
    });

    test('측위에 실패하면 30초 뒤 다시 시도한다', () {
      final policy = SpeedAdaptivePolicy();

      expect(policy.onEvent(const FixResult(tMs: 15000), const PolicyContext(nowMs: 15000)),
          [const WakeAt(tMs: 45000, tag: 'next')]);
    });
  });

  group('TimeSpeedPolicy (EnTracked·RAPS: 마지막 오차 + 속도 × 시간 > E이면 측위)', () {
    test('오차 예산이 다 찰 시각에 깨어나 측위한다', () {
      final policy = TimeSpeedPolicy();

      expect(policy.onStart(const PolicyContext(nowMs: 0)), [const RequestFix()]);
      // (50 - 8) / max(1.2, 1.4) = 30초
      expect(afterFix(policy, fix(0, accuracy: 8, speed: 1.2)), [const WakeAt(tMs: 30000, tag: 'next')]);
      expect(policy.onEvent(const Wakeup(tMs: 30000, tag: 'next'), const PolicyContext(nowMs: 30000)),
          [const RequestFix()]);
    });

    test('빠르면 최소 5초, 오차가 이미 예산보다 크면 최소 간격으로 다시 잰다', () {
      final policy = TimeSpeedPolicy();

      expect(afterFix(policy, fix(0, accuracy: 8, speed: 10)), [const WakeAt(tMs: 5000, tag: 'next')]);
      expect(afterFix(policy, fix(0, accuracy: 60, speed: 1.0)), [const WakeAt(tMs: 5000, tag: 'next')]);
    });

    test('정지해 있어도 걷기 속도(1.4m/s)를 하한으로 써서 10분을 넘기지 않는다', () {
      final policy = TimeSpeedPolicy(errorBudgetM: 25);

      // (25 - 5) / 1.4 = 14.2857초 → 14286ms
      expect(afterFix(policy, fix(0, accuracy: 5, speed: 0)), [const WakeAt(tMs: 14286, tag: 'next')]);
      expect(policy.params, {'e_m': 25.0});
      expect(policy.id, 'time_speed');
    });

    test('측위에 실패하면 30초 뒤 다시 시도한다', () {
      final policy = TimeSpeedPolicy();

      expect(policy.onEvent(const FixResult(tMs: 15000), const PolicyContext(nowMs: 15000)),
          [const WakeAt(tMs: 45000, tag: 'next')]);
    });
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `dart test test/policies/adaptive_policies_test.dart`
Expected: FAIL (정책 클래스가 정의되지 않았다는 컴파일 오류)

- [ ] **Step 3: 구현**

`packages/footstep_core/lib/src/policies/speed_adaptive_policy.dart`:

```dart
import '../events/policy_action.dart';
import '../events/policy_event.dart';
import 'collection_policy.dart';

/// 속도 적응 측위(Galeana-Zapién 외, Sensors 2014의 원리). 마지막 측위의 속도 구간에 따라 다음 측위 간격을
/// 정한다. 구간 경계와 간격은 우리 재현값이다(정지 0.5m/s 미만 → 2분, 보행 → 30초, 시속 9km 이상 → 10초).
/// 예비용 세션으로 조정할 수 있게 생성자 파라미터로 둔다.
class SpeedAdaptivePolicy implements CollectionPolicy {
  SpeedAdaptivePolicy({
    this.stillSpeedMps = 0.5,
    this.vehicleSpeedMps = 2.5,
    this.stillIntervalMs = 120000,
    this.walkIntervalMs = 30000,
    this.vehicleIntervalMs = 10000,
    this.failureRetryMs = 30000,
  });

  static const _tag = 'next';

  final double stillSpeedMps;
  final double vehicleSpeedMps;
  final int stillIntervalMs;
  final int walkIntervalMs;
  final int vehicleIntervalMs;
  final int failureRetryMs;

  @override
  String get id => 'speed_adaptive';

  @override
  Map<String, Object> get params => {
        'still_speed_mps': stillSpeedMps,
        'vehicle_speed_mps': vehicleSpeedMps,
        'still_interval_s': stillIntervalMs ~/ 1000,
        'walk_interval_s': walkIntervalMs ~/ 1000,
        'vehicle_interval_s': vehicleIntervalMs ~/ 1000,
      };

  @override
  List<PolicyAction> onStart(PolicyContext ctx) => [const RequestFix()];

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    switch (event) {
      case FixResult(:final fix):
        final waitMs = fix == null ? failureRetryMs : _intervalFor(fix.speedMps);
        return [WakeAt(tMs: event.tMs + waitMs, tag: _tag)];
      case Wakeup(:final tag) when tag == _tag:
        return [const RequestFix()];
      default:
        return const [];
    }
  }

  int _intervalFor(double? speedMps) {
    // 속도를 모르면 보행으로 본다 — 정지로 보면 움직이는 사람의 경로를 2분씩 놓친다.
    if (speedMps == null) return walkIntervalMs;
    if (speedMps < stillSpeedMps) return stillIntervalMs;
    if (speedMps >= vehicleSpeedMps) return vehicleIntervalMs;
    return walkIntervalMs;
  }
}
```

`packages/footstep_core/lib/src/policies/time_speed_policy.dart`:

```dart
import 'dart:math' as math;

import '../events/policy_action.dart';
import '../events/policy_event.dart';
import 'collection_policy.dart';

/// 시간 × 속도 오차 추정 측위(EnTracked, MobiSys 2009 · RAPS, MobiSys 2010의 원리).
/// '마지막 측위 오차 + 속도 × 경과 시간'이 오차 예산 E를 넘는 시각에 다시 측위한다.
/// 속도는 마지막 측위의 속도를 쓰되 걷기 속도 1.4m/s를 하한으로 둔다 — 서 있다가 걷기 시작해도 오차가 예산을
/// 넘기 전에 다시 재기 위해서다. 제안 정책(R4)은 이 '시간 × 속도' 대신 실제 걸음 수를 쓴다.
class TimeSpeedPolicy implements CollectionPolicy {
  TimeSpeedPolicy({
    this.errorBudgetM = 50,
    this.minSpeedMps = 1.4,
    this.minWaitMs = 5000,
    this.maxWaitMs = 600000,
    this.failureRetryMs = 30000,
  });

  static const _tag = 'next';

  final double errorBudgetM;
  final double minSpeedMps;
  final int minWaitMs;
  final int maxWaitMs;
  final int failureRetryMs;

  @override
  String get id => 'time_speed';

  @override
  Map<String, Object> get params => {'e_m': errorBudgetM};

  @override
  List<PolicyAction> onStart(PolicyContext ctx) => [const RequestFix()];

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    switch (event) {
      case FixResult(:final fix):
        final waitMs = fix == null
            ? failureRetryMs
            : _waitFor(fix.accuracyM, fix.speedMps ?? 0);
        return [WakeAt(tMs: event.tMs + waitMs, tag: _tag)];
      case Wakeup(:final tag) when tag == _tag:
        return [const RequestFix()];
      default:
        return const [];
    }
  }

  int _waitFor(double accuracyM, double speedMps) {
    final remainingM = errorBudgetM - accuracyM;
    if (remainingM <= 0) return minWaitMs;
    final speed = math.max(speedMps, minSpeedMps);
    final waitMs = (remainingM / speed * 1000).round();
    return waitMs.clamp(minWaitMs, maxWaitMs);
  }
}
```

`packages/footstep_core/lib/footstep_core.dart`의 export 목록에 추가한다.

```dart
export 'src/policies/speed_adaptive_policy.dart';
export 'src/policies/time_speed_policy.dart';
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `dart test`
Expected: PASS (지금까지 32 tests)

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core
git commit -m "feat(footstep_core): 속도 적응·시간×속도 기준 정책을 추가한다"
```

---

### Task 7: 기준 정책 ③ 활동 인식 연동 + 정책·감지기 목록

**Files:**
- Create: `packages/footstep_core/lib/src/policies/activity_gated_policy.dart`
- Create: `packages/footstep_core/lib/src/policies/policy_registry.dart`
- Create: `packages/footstep_core/lib/src/detectors/detector_registry.dart`
- Modify: `packages/footstep_core/lib/footstep_core.dart`
- Test: `packages/footstep_core/test/policies/activity_gated_policy_test.dart`
- Test: `packages/footstep_core/test/registry_test.dart`

**Interfaces:**
- Consumes: Task 2의 타입들, Task 4 `OsStepDetector`, Task 5·6의 정책들
- Produces:
  - `ActivityGatedPolicy({int intervalMs = 1000, double distanceFilterM = 10})` — `id == 'activity_gated'`
  - `const List<String> policyIds`
  - `CollectionPolicy createPolicy(String id, [Map<String, String> params = const {}])` — 모르는 id나 파라미터면 `ArgumentError`
  - `const List<String> detectorIds`
  - `StepDetector createDetector(String id)` — 모르는 id면 `ArgumentError`

- [ ] **Step 1: 실패하는 테스트 작성**

`packages/footstep_core/test/policies/activity_gated_policy_test.dart`:

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

List<PolicyAction> activity(CollectionPolicy policy, int tMs, String type, String confidence) =>
    policy.onEvent(ActivityUpdate(tMs: tMs, type: type, confidence: confidence),
        PolicyContext(nowMs: tMs));

void main() {
  test('시작하면 연속 측위를 켜고, 확실한 정지면 끄고, 확실한 움직임이면 다시 켠다', () {
    final policy = ActivityGatedPolicy();

    expect(policy.onStart(const PolicyContext(nowMs: 0)),
        [const StartContinuous(intervalMs: 1000, distanceFilterM: 10)]);
    expect(activity(policy, 1000, 'STILL', 'HIGH'), [const StopContinuous()]);
    expect(activity(policy, 2000, 'STILL', 'HIGH'), isEmpty); // 이미 꺼짐
    expect(activity(policy, 3000, 'WALKING', 'MEDIUM'),
        [const StartContinuous(intervalMs: 1000, distanceFilterM: 10)]);
    expect(activity(policy, 4000, 'IN_VEHICLE', 'HIGH'), isEmpty); // 이미 켜짐
    expect(policy.id, 'activity_gated');
  });

  test('신뢰도가 낮거나 모르는 활동은 무시한다', () {
    final policy = ActivityGatedPolicy()..onStart(const PolicyContext(nowMs: 0));

    expect(activity(policy, 1000, 'STILL', 'LOW'), isEmpty);
    expect(activity(policy, 2000, 'UNKNOWN', 'HIGH'), isEmpty);
  });
}
```

`packages/footstep_core/test/registry_test.dart`:

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

void main() {
  test('설계 문서 5-3의 정책 id로 정책을 만든다', () {
    expect(policyIds, [
      'hourly', 'fixed_30s', 'fixed_1m', 'fixed_5m', 'continuous_10m',
      'speed_adaptive', 'time_speed', 'still_suppress', 'activity_gated',
    ]);
    for (final id in policyIds) {
      expect(createPolicy(id).id, id);
    }
    expect(createPolicy('hourly').params, {'interval_s': 3600});
    expect(createPolicy('fixed_5m').params, {'interval_s': 300});
  });

  test('파라미터를 받는 정책은 값을 바꿀 수 있다', () {
    expect(createPolicy('time_speed', {'e_m': '25'}).params, {'e_m': 25.0});
    expect(createPolicy('still_suppress', {'interval_s': '120'}).params, {'interval_s': 120});
  });

  test('모르는 정책·파라미터·잘못된 숫자는 ArgumentError다', () {
    expect(() => createPolicy('nope'), throwsArgumentError);
    expect(() => createPolicy('fixed_1m', {'e_m': '25'}), throwsArgumentError);
    expect(() => createPolicy('time_speed', {'e_m': 'abc'}), throwsArgumentError);
    expect(() => createPolicy('time_speed', {'e_m': '-5'}), throwsArgumentError);
  });

  test('걸음 감지기 id로 감지기를 만든다', () {
    expect(detectorIds, ['os']);
    expect(createDetector('os').id, 'os');
    expect(() => createDetector('adaptive'), throwsArgumentError);
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `dart test test/policies/activity_gated_policy_test.dart test/registry_test.dart`
Expected: FAIL (`ActivityGatedPolicy`, `createPolicy` 등이 정의되지 않았다는 컴파일 오류)

- [ ] **Step 3: 구현**

`packages/footstep_core/lib/src/policies/activity_gated_policy.dart`:

```dart
import '../events/policy_action.dart';
import '../events/policy_event.dart';
import 'collection_policy.dart';

/// 상용 방식: 구글 활동 인식 연동(설계 2장 D6). 활동 인식이 확실한 정지(STILL)라고 하면 연속 측위를 끄고,
/// 확실한 움직임이면 다시 켠다. 구글이 소개한 Life360 사례와 Transistorsoft 위치 라이브러리의 원리다.
/// 처음에는 움직이는 중으로 보고 켠다 — 정지로 시작하면 활동 인식 첫 결과가 오기 전의 이동을 놓친다.
class ActivityGatedPolicy implements CollectionPolicy {
  ActivityGatedPolicy({this.intervalMs = 1000, this.distanceFilterM = 10});

  static const _moving = {'WALKING', 'RUNNING', 'ON_BICYCLE', 'IN_VEHICLE'};
  static const _confident = {'HIGH', 'MEDIUM'};

  final int intervalMs;
  final double distanceFilterM;
  bool _on = false;

  @override
  String get id => 'activity_gated';

  @override
  Map<String, Object> get params =>
      {'interval_ms': intervalMs, 'distance_filter_m': distanceFilterM};

  StartContinuous get _start =>
      StartContinuous(intervalMs: intervalMs, distanceFilterM: distanceFilterM);

  @override
  List<PolicyAction> onStart(PolicyContext ctx) {
    _on = true;
    return [_start];
  }

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    if (event is! ActivityUpdate || !_confident.contains(event.confidence)) return const [];
    if (event.type == 'STILL' && _on) {
      _on = false;
      return const [StopContinuous()];
    }
    if (_moving.contains(event.type) && !_on) {
      _on = true;
      return [_start];
    }
    return const [];
  }
}
```

`packages/footstep_core/lib/src/policies/policy_registry.dart`:

```dart
import 'activity_gated_policy.dart';
import 'collection_policy.dart';
import 'continuous_policy.dart';
import 'fixed_interval_policy.dart';
import 'speed_adaptive_policy.dart';
import 'still_suppress_policy.dart';
import 'time_speed_policy.dart';

/// 재생기 CLI가 받는 정책 id(설계 문서 5-3의 표). R4가 제안 정책 `step_budget`을 더한다.
const policyIds = [
  'hourly', 'fixed_30s', 'fixed_1m', 'fixed_5m', 'continuous_10m',
  'speed_adaptive', 'time_speed', 'still_suppress', 'activity_gated',
];

/// id와 파라미터(문자열 k=v)로 정책을 만든다. 모르는 id·파라미터, 양수가 아닌 숫자는 ArgumentError다 —
/// 실험 설정 오타로 엉뚱한 기본값이 조용히 쓰이는 것을 막는다.
CollectionPolicy createPolicy(String id, [Map<String, String> params = const {}]) {
  void allowOnly(Set<String> keys) {
    final unknown = params.keys.where((k) => !keys.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw ArgumentError('정책 $id에 없는 파라미터: ${unknown.join(', ')}');
    }
  }

  double positive(String key, double fallback) {
    final raw = params[key];
    if (raw == null) return fallback;
    final value = double.tryParse(raw);
    if (value == null || value <= 0) throw ArgumentError('$key는 양수여야 합니다: $raw');
    return value;
  }

  switch (id) {
    case 'hourly':
      allowOnly(const {});
      return FixedIntervalPolicy(id: id, intervalMs: 3600000);
    case 'fixed_30s':
      allowOnly(const {});
      return FixedIntervalPolicy(id: id, intervalMs: 30000);
    case 'fixed_1m':
      allowOnly(const {});
      return FixedIntervalPolicy(id: id, intervalMs: 60000);
    case 'fixed_5m':
      allowOnly(const {});
      return FixedIntervalPolicy(id: id, intervalMs: 300000);
    case 'continuous_10m':
      allowOnly(const {});
      return ContinuousPolicy();
    case 'speed_adaptive':
      allowOnly(const {});
      return SpeedAdaptivePolicy();
    case 'time_speed':
      allowOnly(const {'e_m'});
      return TimeSpeedPolicy(errorBudgetM: positive('e_m', 50));
    case 'still_suppress':
      allowOnly(const {'interval_s'});
      return StillSuppressPolicy(intervalMs: (positive('interval_s', 60) * 1000).round());
    case 'activity_gated':
      allowOnly(const {});
      return ActivityGatedPolicy();
    default:
      throw ArgumentError('알 수 없는 정책: $id (가능: ${policyIds.join(', ')})');
  }
}
```

`packages/footstep_core/lib/src/detectors/detector_registry.dart`:

```dart
import 'os_step_detector.dart';
import 'step_detector.dart';

/// 재생기 CLI가 받는 걸음 감지기 id. R3이 논문 기준판(brajdic)과 제안판(adaptive)을 더한다.
const detectorIds = ['os'];

StepDetector createDetector(String id) => switch (id) {
      'os' => OsStepDetector(),
      _ => throw ArgumentError('알 수 없는 걸음 감지기: $id (가능: ${detectorIds.join(', ')})'),
    };
```

`packages/footstep_core/lib/footstep_core.dart`의 export 목록에 추가한다.

```dart
export 'src/detectors/detector_registry.dart';
export 'src/policies/activity_gated_policy.dart';
export 'src/policies/policy_registry.dart';
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `dart test`
Expected: PASS (지금까지 38 tests)

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core
git commit -m "feat(footstep_core): 활동 인식 연동 정책과 정책·감지기 목록을 추가한다"
```

---

### Task 8: 재생 엔진 (`replaySession`)

**Files:**
- Create: `packages/footstep_core/lib/src/replay/replay_result.dart`
- Create: `packages/footstep_core/lib/src/replay/replay_engine.dart`
- Modify: `packages/footstep_core/lib/footstep_core.dart`
- Test: `packages/footstep_core/test/replay/replay_engine_test.dart`

**Interfaces:**
- Consumes:
  - `SessionData` (Task 3)
  - `StepDetector`, `OsStepDetector` (Task 2, 4)
  - `CollectionPolicy`, `PolicyContext`, `ReportsState`, 사건·할 일 (Task 2)
  - `haversineMeters` (Task 2)
  - `FixedIntervalPolicy` (Task 5, 테스트에서 사용)
- Produces:
  - `class ReplayConfig({int ttffMs = 0, int accelBatchMs = 1000})`
  - `class FixRecord({required Fix fix, required int stepsSincePrev, required String state, required String kind})` + `int get tMs` — kind는 `single` 또는 `continuous`
  - `class ActionRecord({required int tMs, required PolicyAction action})`
  - `class ReplaySummary(...)` — 필드 `sessionId, policyId, policyParams, detectorId, ttffMs, startMs, endMs, fixRequests, fixSuccesses, fixFailures, continuousFixes, gpsOnMs`, 계산값 `durationMs`, `totalFixes`, `fixesPerHour`, `Map<String, Object?> toJson()`
  - `class ReplayResult({required List<FixRecord> fixes, required List<ActionRecord> actions, required ReplaySummary summary})`
  - `ReplayResult replaySession(SessionData data, CollectionPolicy policy, StepDetector detector, {ReplayConfig config = const ReplayConfig()})` — 기록이 없는 세션이면 `ArgumentError`

**재생 규칙(테스트가 고정하는 것)**
- 세션 시작 시각(`data.startMs`)에 `policy.onStart`를 부르고, 끝 시각(`data.endMs`)까지의 사건만 처리한다(끝 시각과 같은 사건은 처리한다).
- 같은 시각이면 예약 사건(깨우기·측위 응답)을 센서 사건보다 먼저 처리한다. 센서 사건끼리는 gps → 가속도 → OS 걸음 → 활동 → 배터리 순서다.
- `RequestFix`(t): `t + ttff` 이후의 첫 gps 행을, 그 행이 `t + timeoutMs` 안이면 그 행의 시각에 `FixResult(fix)`로 준다. 아니면 `t + timeoutMs`에 `FixResult(null)`(실패)을 준다. 응답을 기다리는 중의 새 요청은 무시한다.
- `StartContinuous`(t): `t + ttff`부터 gps 행을 흘려보낸다. 직전에 알린 행과의 간격이 `intervalMs × 0.9` 이상이고 거리가 `distanceFilterM` 이상일 때만 `ContinuousFix`로 알린다. 켜져 있는 동안 다시 받으면 설정을 바꿔 새로 시작한다.
- GPS 켜짐 시간: 단발은 요청부터 응답(또는 실패)까지, 연속은 켠 때부터 끈 때까지. 끝 시각에 켜져 있거나 기다리는 중이면 끝 시각까지 더한다.
- 위치를 정책에 알릴 때마다 기록(`FixRecord`)에 그때까지의 `detector.stepsSinceLastFix`와 상태를 남긴 뒤 `detector.onFix()`를 부른다. 상태는 정책이 `ReportsState`면 그 값, 아니면 감지기 상태 이름이다.
- 가속도는 첫 표본부터 `accelBatchMs` 길이 창으로 묶고, 묶음의 마지막 표본 시각에 감지기에 넘긴다. 배터리는 잔량이 바뀔 때만 `BatteryLevel`로 알린다.

- [ ] **Step 1: 실패하는 테스트 작성**

`packages/footstep_core/test/replay/replay_engine_test.dart`:

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

/// 정해 둔 할 일을 돌려주고 받은 사건을 모으는 시험용 정책.
class _Scripted implements CollectionPolicy {
  _Scripted({this.startActions = const [], this.onWake = const {}});

  final List<PolicyAction> startActions;
  final Map<String, List<PolicyAction>> onWake;
  final events = <PolicyEvent>[];

  @override
  String get id => 'scripted';

  @override
  Map<String, Object> get params => const {};

  @override
  List<PolicyAction> onStart(PolicyContext ctx) => startActions;

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    events.add(event);
    if (event is Wakeup) return onWake[event.tag] ?? const [];
    return const [];
  }
}

Fix gps(int tMs, {double lat = 37.5, double lng = 127.0}) =>
    Fix(tMs: tMs, lat: lat, lng: lng, accuracyM: 5);

List<Fix> everySecond(int fromMs, int toMs) => [for (var t = fromMs; t <= toMs; t += 1000) gps(t)];

SessionData session({
  List<Fix> fixes = const [],
  List<AccelReading> accel = const [],
  List<OsStepReading> osSteps = const [],
}) =>
    SessionData(sessionId: 'test', fixes: fixes, accel: accel, osSteps: osSteps);

OsStepReading count(int tMs, int value) =>
    OsStepReading(tMs: tMs, kind: OsStepReading.count, value: '$value');

void main() {
  test('RequestFix는 요청 시각 이후의 첫 GPS 행을 그 행의 시각에 돌려준다', () {
    final policy = _Scripted(
      startActions: [const WakeAt(tMs: 2500, tag: 'a')],
      onWake: {'a': [const RequestFix()]},
    );

    final result = replaySession(session(fixes: everySecond(0, 10000)), policy, OsStepDetector());

    expect(result.fixes.single.tMs, 3000);
    expect(result.fixes.single.kind, 'single');
    final response = policy.events.whereType<FixResult>().single;
    expect(response.tMs, 3000);
    expect(response.fix!.tMs, greaterThanOrEqualTo(2500)); // 미래 정보 없음
    expect(result.summary.fixRequests, 1);
    expect(result.summary.fixSuccesses, 1);
    expect(result.summary.gpsOnMs, 500);
  });

  test('ttff만큼 늦은 첫 행을 받는다', () {
    final policy = _Scripted(
      startActions: [const WakeAt(tMs: 2500, tag: 'a')],
      onWake: {'a': [const RequestFix()]},
    );

    final result = replaySession(session(fixes: everySecond(0, 10000)), policy, OsStepDetector(),
        config: const ReplayConfig(ttffMs: 5000));

    expect(result.fixes.single.tMs, 8000);
    expect(result.summary.gpsOnMs, 5500);
  });

  test('GPS 공백이 제한 시간보다 길면 제한 시간에 실패를 알린다', () {
    final policy = _Scripted(
      startActions: [const WakeAt(tMs: 2500, tag: 'a')],
      onWake: {'a': [const RequestFix()]},
    );
    final fixes = [...everySecond(0, 2000), ...everySecond(30000, 40000)];

    final result = replaySession(session(fixes: fixes), policy, OsStepDetector());

    final response = policy.events.whereType<FixResult>().single;
    expect(response.tMs, 17500);
    expect(response.failed, isTrue);
    expect(result.fixes, isEmpty);
    expect(result.summary.fixFailures, 1);
    expect(result.summary.gpsOnMs, 15000);
  });

  test('연속 측위는 간격·거리 필터대로 행을 흘려보내고 켜진 시간을 센다', () {
    // 1초에 북쪽으로 3m씩 움직인다 → 10m 필터면 4초(12m)마다 알린다.
    const degPerMeter = 1 / 111195;
    final fixes = [
      for (var s = 0; s <= 30; s++) gps(s * 1000, lat: 37.5 + s * 3 * degPerMeter),
    ];
    final policy = _Scripted(
      startActions: [
        const StartContinuous(intervalMs: 1000, distanceFilterM: 10),
        const WakeAt(tMs: 20000, tag: 'stop'),
      ],
      onWake: {'stop': [const StopContinuous()]},
    );

    final result = replaySession(session(fixes: fixes), policy, OsStepDetector());

    expect(result.fixes.map((f) => f.tMs), [0, 4000, 8000, 12000, 16000]);
    expect(result.fixes.every((f) => f.kind == 'continuous'), isTrue);
    expect(result.summary.continuousFixes, 5);
    expect(result.summary.gpsOnMs, 20000);
  });

  test('가속도 묶음과 OS 걸음이 걸음 감지기를 거쳐 정책에 간다', () {
    final policy = _Scripted();
    final accel = [
      for (var t = 0; t <= 8000; t += 10) AccelReading(tMs: t, x: 0, y: 9.8, z: 0),
    ];

    replaySession(session(accel: accel, osSteps: [count(0, 100), count(1000, 103)]), policy,
        OsStepDetector());

    final updates = policy.events.whereType<StepUpdate>().toList();
    expect(updates.map((u) => (u.tMs, u.state)), [(1000, StepState.walking), (5990, StepState.still)]);
  });

  test('측위 기록에 직전 측위 이후 걸음 수와 상태가 들어간다', () {
    final policy = _Scripted(
      startActions: [const WakeAt(tMs: 2000, tag: 'a'), const WakeAt(tMs: 4000, tag: 'b')],
      onWake: {'a': [const RequestFix()], 'b': [const RequestFix()]},
    );
    final data = session(
      fixes: everySecond(0, 5000),
      osSteps: [count(0, 0), count(1000, 10), count(3000, 15)],
    );

    final result = replaySession(data, policy, OsStepDetector());

    expect(result.fixes.map((f) => f.stepsSincePrev), [10, 5]);
    expect(result.fixes.map((f) => f.state), ['walking', 'walking']);
  });

  test('1분 고정 주기로 10분을 재생하면 측위 11번(0분~10분)이다', () {
    final data = session(fixes: everySecond(0, 600000));

    final instant = replaySession(
        data, FixedIntervalPolicy(id: 'fixed_1m', intervalMs: 60000), OsStepDetector());
    expect(instant.summary.fixRequests, 11);
    expect(instant.summary.fixSuccesses, 11);
    expect(instant.summary.gpsOnMs, 0);

    final delayed = replaySession(
        data, FixedIntervalPolicy(id: 'fixed_1m', intervalMs: 60000), OsStepDetector(),
        config: const ReplayConfig(ttffMs: 5000));
    expect(delayed.summary.fixSuccesses, 10); // 마지막 요청의 응답은 세션이 끝난 뒤다
    expect(delayed.summary.gpsOnMs, 50000);
  });

  test('같은 입력이면 항상 같은 결과다', () {
    final data = session(fixes: everySecond(0, 300000));
    ReplayResult run() =>
        replaySession(data, FixedIntervalPolicy(id: 'fixed_30s', intervalMs: 30000), OsStepDetector());

    final a = run();
    final b = run();
    expect(a.summary.toJson(), b.summary.toJson());
    expect(a.fixes.map((f) => f.tMs), b.fixes.map((f) => f.tMs));
    expect(a.actions.map((r) => '${r.tMs} ${r.action}'), b.actions.map((r) => '${r.tMs} ${r.action}'));
  });

  test('summary는 R6 분석이 읽을 키로 내보낸다', () {
    final result = replaySession(session(fixes: everySecond(0, 3600000)),
        FixedIntervalPolicy(id: 'fixed_5m', intervalMs: 300000), OsStepDetector());

    final json = result.summary.toJson();
    expect(json['session_id'], 'test');
    expect(json['policy_id'], 'fixed_5m');
    expect(json['policy_params'], {'interval_s': 300});
    expect(json['detector_id'], 'os');
    expect(json['duration_s'], 3600.0);
    expect(json['total_fixes'], 13);
    expect(json['fixes_per_hour'], 13.0);
  });

  test('기록이 없는 세션은 ArgumentError다', () {
    expect(() => replaySession(session(), _Scripted(), OsStepDetector()), throwsArgumentError);
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `dart test test/replay/replay_engine_test.dart`
Expected: FAIL (`replaySession`이 정의되지 않았다는 컴파일 오류)

- [ ] **Step 3: 결과 타입 구현**

`packages/footstep_core/lib/src/replay/replay_result.dart`:

```dart
import '../events/policy_action.dart';
import '../model/fix.dart';

/// 정책에 알린 위치 하나(fixes.csv의 행).
class FixRecord {
  const FixRecord({
    required this.fix,
    required this.stepsSincePrev,
    required this.state,
    required this.kind,
  });

  final Fix fix;

  /// 직전에 알린 위치 이후 걸음 수.
  final int stepsSincePrev;

  /// 정책 상태(ReportsState) 또는 걸음 감지기 상태 이름.
  final String state;

  /// `single`(RequestFix 응답) 또는 `continuous`(연속 측위).
  final String kind;

  int get tMs => fix.tMs;
}

/// 정책이 낸 할 일 하나(actions.csv의 행).
class ActionRecord {
  const ActionRecord({required this.tMs, required this.action});

  final int tMs;
  final PolicyAction action;
}

/// 재생 한 번의 요약(summary.json). 키는 R6 분석(Python)이 읽기 쉬운 snake_case다.
class ReplaySummary {
  const ReplaySummary({
    required this.sessionId,
    required this.policyId,
    required this.policyParams,
    required this.detectorId,
    required this.ttffMs,
    required this.startMs,
    required this.endMs,
    required this.fixRequests,
    required this.fixSuccesses,
    required this.fixFailures,
    required this.continuousFixes,
    required this.gpsOnMs,
  });

  final String sessionId;
  final String policyId;
  final Map<String, Object> policyParams;
  final String detectorId;
  final int ttffMs;
  final int startMs;
  final int endMs;
  final int fixRequests;
  final int fixSuccesses;
  final int fixFailures;
  final int continuousFixes;

  /// 추정 GPS 켜짐 시간. 단발은 요청~응답, 연속은 켠 때~끈 때.
  final int gpsOnMs;

  int get durationMs => endMs - startMs;

  int get totalFixes => fixSuccesses + continuousFixes;

  double get fixesPerHour => durationMs == 0 ? 0 : totalFixes / (durationMs / 3600000);

  Map<String, Object?> toJson() => {
        'session_id': sessionId,
        'policy_id': policyId,
        'policy_params': policyParams,
        'detector_id': detectorId,
        'ttff_ms': ttffMs,
        'start_ms': startMs,
        'end_ms': endMs,
        'duration_s': durationMs / 1000,
        'fix_requests': fixRequests,
        'fix_successes': fixSuccesses,
        'fix_failures': fixFailures,
        'continuous_fixes': continuousFixes,
        'total_fixes': totalFixes,
        'gps_on_s': gpsOnMs / 1000,
        'fixes_per_hour': fixesPerHour,
      };
}

class ReplayResult {
  const ReplayResult({required this.fixes, required this.actions, required this.summary});

  final List<FixRecord> fixes;
  final List<ActionRecord> actions;
  final ReplaySummary summary;
}
```

- [ ] **Step 4: 재생 엔진 구현**

`packages/footstep_core/lib/src/replay/replay_engine.dart`:

```dart
import 'dart:math' as math;

import '../detectors/step_detector.dart';
import '../events/policy_action.dart';
import '../events/policy_event.dart';
import '../geo.dart';
import '../model/fix.dart';
import '../model/readings.dart';
import '../policies/collection_policy.dart';
import '../session/session_reader.dart';
import 'replay_result.dart';

/// 재생 설정(설계 5-4).
class ReplayConfig {
  const ReplayConfig({this.ttffMs = 0, this.accelBatchMs = 1000});

  /// GPS를 켠 뒤 첫 위치가 나오기까지 걸린다고 가정하는 시간. 기록은 GPS가 계속 켜져 있던 값이라
  /// '켜자마자 위치가 나온다'고 가정하게 되는 약점을 0·5·10초로 바꿔 가며 줄인다.
  final int ttffMs;

  /// 가속도를 걸음 감지기에 넘기는 묶음 길이. 표본 간격은 기기마다 다르다(Galaxy S23은 약 10ms).
  final int accelBatchMs;
}

/// 세션 기록으로 정책을 재생한다. 정책은 요청한 시각 이후의 정보만 받으므로 미래 정보를 쓸 수 없고,
/// 같은 입력이면 항상 같은 결과가 나온다(설계 5-4).
ReplayResult replaySession(
  SessionData data,
  CollectionPolicy policy,
  StepDetector detector, {
  ReplayConfig config = const ReplayConfig(),
}) =>
    _Replay(data, policy, detector, config).run();

sealed class _External {
  const _External(this.tMs, this.order);

  final int tMs;

  /// 같은 시각일 때의 처리 순서(작을수록 먼저).
  final int order;
}

final class _GpsRow extends _External {
  _GpsRow(this.fix) : super(fix.tMs, 0);

  final Fix fix;
}

final class _AccelBatch extends _External {
  _AccelBatch(this.readings) : super(readings.last.tMs, 1);

  final List<AccelReading> readings;
}

final class _OsStep extends _External {
  _OsStep(this.reading) : super(reading.tMs, 2);

  final OsStepReading reading;
}

final class _Activity extends _External {
  _Activity(this.reading) : super(reading.tMs, 3);

  final ActivityReading reading;
}

final class _Battery extends _External {
  _Battery(this.reading) : super(reading.tMs, 4);

  final BatteryLevelReading reading;
}

sealed class _Scheduled {
  _Scheduled(this.tMs);

  final int tMs;
}

final class _Wake extends _Scheduled {
  _Wake(super.tMs, this.tag);

  final String tag;
}

final class _FixResponse extends _Scheduled {
  _FixResponse(super.tMs, {required this.requestMs, this.fix});

  final int requestMs;
  final Fix? fix;
}

class _Replay {
  _Replay(this.data, this.policy, this.detector, this.config);

  final SessionData data;
  final CollectionPolicy policy;
  final StepDetector detector;
  final ReplayConfig config;

  final _fixes = <FixRecord>[];
  final _actions = <ActionRecord>[];

  /// 예약 사건. 시각순으로 유지하고, 같은 시각은 예약한 순서대로 둔다.
  final _scheduled = <_Scheduled>[];

  int _nowMs = 0;
  Fix? _lastFix;
  _FixResponse? _pendingFix;
  StartContinuous? _continuous;
  int _continuousSinceMs = 0;
  Fix? _lastContinuous;

  int _fixRequests = 0;
  int _fixSuccesses = 0;
  int _fixFailures = 0;
  int _continuousFixes = 0;
  int _gpsOnMs = 0;

  ReplayResult run() {
    final start = data.startMs;
    final end = data.endMs;
    if (start == null || end == null) {
      throw ArgumentError('세션에 기록이 없습니다: ${data.sessionId}');
    }
    final timeline = _buildTimeline();

    _nowMs = start;
    _apply(policy.onStart(_ctx()));

    var next = 0;
    while (true) {
      final external = next < timeline.length ? timeline[next] : null;
      final scheduled = _scheduled.isEmpty ? null : _scheduled.first;
      if (external == null && scheduled == null) break;
      // 같은 시각이면 예약 사건(깨우기·측위 응답)을 먼저 처리한다 — 결정적인 순서를 위해서다.
      if (scheduled != null && (external == null || scheduled.tMs <= external.tMs)) {
        if (scheduled.tMs > end) break;
        _nowMs = scheduled.tMs;
        _scheduled.removeAt(0);
        _handleScheduled(scheduled);
      } else {
        // 여기 오면 external은 null이 아니다(둘 다 null인 경우는 위에서 끝났다).
        final event = external!;
        if (event.tMs > end) break;
        _nowMs = event.tMs;
        next++;
        _handleExternal(event);
      }
    }

    // 끝 시각에 켜져 있거나 응답을 기다리는 중이면 끝 시각까지 GPS가 켜져 있던 것으로 센다.
    if (_continuous != null) _gpsOnMs += end - _continuousSinceMs;
    final pending = _pendingFix;
    if (pending != null) _gpsOnMs += end - pending.requestMs;

    return ReplayResult(
      fixes: List.unmodifiable(_fixes),
      actions: List.unmodifiable(_actions),
      summary: ReplaySummary(
        sessionId: data.sessionId,
        policyId: policy.id,
        policyParams: policy.params,
        detectorId: detector.id,
        ttffMs: config.ttffMs,
        startMs: start,
        endMs: end,
        fixRequests: _fixRequests,
        fixSuccesses: _fixSuccesses,
        fixFailures: _fixFailures,
        continuousFixes: _continuousFixes,
        gpsOnMs: _gpsOnMs,
      ),
    );
  }

  PolicyContext _ctx() => PolicyContext(nowMs: _nowMs, lastFix: _lastFix);

  List<_External> _buildTimeline() {
    final items = <_External>[
      for (final fix in data.fixes) _GpsRow(fix),
      ..._accelBatches(),
      for (final reading in data.osSteps) _OsStep(reading),
      for (final reading in data.activities) _Activity(reading),
      ..._batteryChanges(),
    ];
    final order = List<int>.generate(items.length, (i) => i);
    order.sort((a, b) {
      final x = items[a];
      final y = items[b];
      final byTime = x.tMs.compareTo(y.tMs);
      if (byTime != 0) return byTime;
      final byKind = x.order.compareTo(y.order);
      return byKind != 0 ? byKind : a.compareTo(b);
    });
    return [for (final i in order) items[i]];
  }

  Iterable<_AccelBatch> _accelBatches() sync* {
    var batch = <AccelReading>[];
    int? windowStart;
    for (final reading in data.accel) {
      final start = windowStart ??= reading.tMs;
      if (reading.tMs - start >= config.accelBatchMs && batch.isNotEmpty) {
        yield _AccelBatch(batch);
        batch = <AccelReading>[];
        windowStart = reading.tMs;
      }
      batch.add(reading);
    }
    if (batch.isNotEmpty) yield _AccelBatch(batch);
  }

  Iterable<_Battery> _batteryChanges() sync* {
    int? last;
    for (final reading in data.battery) {
      if (reading.levelPct != last) {
        last = reading.levelPct;
        yield _Battery(reading);
      }
    }
  }

  void _handleExternal(_External event) {
    switch (event) {
      case _GpsRow(:final fix):
        _maybeDeliverContinuous(fix);
      case _AccelBatch(:final readings):
        _deliverStep(detector.onAccel(event.tMs, readings));
      case _OsStep(:final reading):
        _deliverStep(detector.onOsStep(reading));
      case _Activity(:final reading):
        _deliver(ActivityUpdate(tMs: event.tMs, type: reading.type, confidence: reading.confidence));
      case _Battery(:final reading):
        _deliver(BatteryLevel(tMs: event.tMs, pct: reading.levelPct));
    }
  }

  void _handleScheduled(_Scheduled event) {
    switch (event) {
      case _Wake(:final tag):
        _deliver(Wakeup(tMs: event.tMs, tag: tag));
      case _FixResponse(:final requestMs, :final fix):
        _pendingFix = null;
        _gpsOnMs += event.tMs - requestMs;
        if (fix == null) {
          _fixFailures++;
        } else {
          _fixSuccesses++;
          _recordFix(fix, 'single');
        }
        _deliver(FixResult(tMs: event.tMs, fix: fix));
    }
  }

  void _maybeDeliverContinuous(Fix row) {
    final settings = _continuous;
    if (settings == null) return;
    // 연속 측위를 켜도 첫 위치는 ttff 뒤에 나온다.
    if (row.tMs < _continuousSinceMs + config.ttffMs) return;
    final last = _lastContinuous;
    if (last != null) {
      // 간격은 10% 여유를 둔다 — 1초를 요청해도 실제 기록 간격은 990~1010ms로 흔들린다.
      if (row.tMs - last.tMs < settings.intervalMs * 0.9) return;
      if (settings.distanceFilterM > 0 &&
          haversineMeters(last.lat, last.lng, row.lat, row.lng) < settings.distanceFilterM) {
        return;
      }
    }
    _lastContinuous = row;
    _continuousFixes++;
    _recordFix(row, 'continuous');
    _deliver(ContinuousFix(tMs: row.tMs, fix: row));
  }

  void _recordFix(Fix fix, String kind) {
    _fixes.add(FixRecord(
      fix: fix,
      stepsSincePrev: detector.stepsSinceLastFix,
      state: _stateLabel(),
      kind: kind,
    ));
    detector.onFix();
    _lastFix = fix;
  }

  String _stateLabel() {
    if (policy case ReportsState(:final stateLabel)) return stateLabel;
    return detector.state.name;
  }

  void _deliverStep(StepUpdate? update) {
    if (update != null) _deliver(update);
  }

  void _deliver(PolicyEvent event) => _apply(policy.onEvent(event, _ctx()));

  void _apply(List<PolicyAction> actions) {
    for (final action in actions) {
      _actions.add(ActionRecord(tMs: _nowMs, action: action));
      switch (action) {
        case RequestFix(:final timeoutMs):
          _requestFix(timeoutMs);
        case final StartContinuous start:
          if (_continuous != null) _gpsOnMs += _nowMs - _continuousSinceMs;
          _continuous = start;
          _continuousSinceMs = _nowMs;
          _lastContinuous = null;
        case StopContinuous():
          if (_continuous != null) {
            _gpsOnMs += _nowMs - _continuousSinceMs;
            _continuous = null;
          }
        case WakeAt(:final tMs, :final tag):
          _schedule(_Wake(math.max(tMs, _nowMs), tag));
      }
    }
  }

  void _requestFix(int timeoutMs) {
    // 이미 응답을 기다리는 중이면 새로 켜지 않는다 — 실제 기기도 진행 중인 요청에 합쳐진다.
    if (_pendingFix != null) return;
    _fixRequests++;
    final deadline = _nowMs + timeoutMs;
    final index = _firstFixAtOrAfter(_nowMs + config.ttffMs);
    final row = index < data.fixes.length ? data.fixes[index] : null;
    final response = row != null && row.tMs <= deadline
        ? _FixResponse(row.tMs, requestMs: _nowMs, fix: row)
        : _FixResponse(deadline, requestMs: _nowMs);
    _pendingFix = response;
    _schedule(response);
  }

  int _firstFixAtOrAfter(int tMs) {
    var low = 0;
    var high = data.fixes.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (data.fixes[mid].tMs < tMs) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  void _schedule(_Scheduled event) {
    // 같은 시각인 사건 뒤에 넣어 예약한 순서를 지킨다.
    var i = _scheduled.length;
    while (i > 0 && _scheduled[i - 1].tMs > event.tMs) {
      i--;
    }
    _scheduled.insert(i, event);
  }
}
```

`packages/footstep_core/lib/footstep_core.dart`의 export 목록에 추가한다.

```dart
export 'src/replay/replay_engine.dart';
export 'src/replay/replay_result.dart';
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `dart test`
Expected: PASS (지금까지 48 tests)

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 6: 커밋**

```bash
git add packages/footstep_core
git commit -m "feat(footstep_core): 세션 기록으로 정책을 재생하는 엔진을 추가한다"
```

---

### Task 9: 재생 결과 파일 쓰기

**Files:**
- Create: `packages/footstep_core/lib/src/replay/replay_output.dart`
- Modify: `packages/footstep_core/lib/footstep_core.dart`
- Test: `packages/footstep_core/test/replay/replay_output_test.dart`

**Interfaces:**
- Consumes: `ReplayResult`, `FixRecord`, `ActionRecord`, `ReplaySummary` (Task 8), `formatCsvField` (Task 1)
- Produces:
  - `abstract final class ReplaySchema` — `fixesFile = 'fixes.csv'`, `fixesHeader`, `actionsFile = 'actions.csv'`, `actionsHeader`, `summaryFile = 'summary.json'`
  - `Future<void> writeReplayOutput(ReplayResult result, Directory outDir)`

- [ ] **Step 1: 실패하는 테스트 작성**

`packages/footstep_core/test/replay/replay_output_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:footstep_core/footstep_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('replay_output_test'));
  tearDown(() async => root.delete(recursive: true));

  test('fixes.csv·actions.csv·summary.json을 설계 문서 5-4 형식으로 쓴다', () async {
    const fix = Fix(tMs: 1000, lat: 37.5665, lng: 126.978, accuracyM: 4.5);
    const result = ReplayResult(
      fixes: [FixRecord(fix: fix, stepsSincePrev: 12, state: 'walking', kind: 'single')],
      actions: [
        ActionRecord(tMs: 0, action: RequestFix()),
        ActionRecord(tMs: 0, action: WakeAt(tMs: 60000, tag: 'tick')),
      ],
      summary: ReplaySummary(
        sessionId: 's1',
        policyId: 'fixed_1m',
        policyParams: {'interval_s': 60},
        detectorId: 'os',
        ttffMs: 0,
        startMs: 0,
        endMs: 120000,
        fixRequests: 1,
        fixSuccesses: 1,
        fixFailures: 0,
        continuousFixes: 0,
        gpsOnMs: 1000,
      ),
    );
    final out = Directory(p.join(root.path, 'nested', 'out'));

    await writeReplayOutput(result, out);

    expect(File(p.join(out.path, 'fixes.csv')).readAsLinesSync(), [
      't_ms,lat,lng,accuracy_m,steps_since_prev,state,kind',
      '1000,37.5665,126.978,4.5,12,walking,single',
    ]);
    expect(File(p.join(out.path, 'actions.csv')).readAsLinesSync(), [
      't_ms,action,args',
      '0,request_fix,timeout_ms=15000',
      '0,wake_at,t_ms=60000 tag=tick',
    ]);
    final summary =
        jsonDecode(File(p.join(out.path, 'summary.json')).readAsStringSync()) as Map<String, Object?>;
    expect(summary['policy_id'], 'fixed_1m');
    expect(summary['total_fixes'], 1);
    expect(summary['gps_on_s'], 1.0);
  });
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `dart test test/replay/replay_output_test.dart`
Expected: FAIL (`writeReplayOutput`이 정의되지 않았다는 컴파일 오류)

- [ ] **Step 3: 구현**

`packages/footstep_core/lib/src/replay/replay_output.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../session/csv.dart';
import 'replay_result.dart';

/// 재생 결과 파일 이름과 헤더(설계 문서 5-4). R5 복원·R6 분석이 이 이름으로 읽는다.
abstract final class ReplaySchema {
  static const fixesFile = 'fixes.csv';
  static const fixesHeader = [
    't_ms', 'lat', 'lng', 'accuracy_m', 'steps_since_prev', 'state', 'kind',
  ];

  static const actionsFile = 'actions.csv';
  static const actionsHeader = ['t_ms', 'action', 'args'];

  static const summaryFile = 'summary.json';
}

/// 재생 결과를 [outDir]에 쓴다. 폴더가 없으면 만든다.
Future<void> writeReplayOutput(ReplayResult result, Directory outDir) async {
  await outDir.create(recursive: true);

  String csv(List<String> header, Iterable<List<Object?>> rows) {
    final buffer = StringBuffer()..writeln(header.join(','));
    for (final row in rows) {
      buffer.writeln(row.map(formatCsvField).join(','));
    }
    return buffer.toString();
  }

  await File(p.join(outDir.path, ReplaySchema.fixesFile)).writeAsString(
    csv(ReplaySchema.fixesHeader, [
      for (final r in result.fixes)
        [r.tMs, r.fix.lat, r.fix.lng, r.fix.accuracyM, r.stepsSincePrev, r.state, r.kind],
    ]),
    flush: true,
  );
  await File(p.join(outDir.path, ReplaySchema.actionsFile)).writeAsString(
    csv(ReplaySchema.actionsHeader, [
      for (final r in result.actions) [r.tMs, r.action.logName, r.action.logArgs],
    ]),
    flush: true,
  );
  await File(p.join(outDir.path, ReplaySchema.summaryFile)).writeAsString(
    const JsonEncoder.withIndent('  ').convert(result.summary.toJson()),
    flush: true,
  );
}
```

`packages/footstep_core/lib/footstep_core.dart`의 export 목록에 추가한다.

```dart
export 'src/replay/replay_output.dart';
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `dart test`
Expected: PASS (지금까지 49 tests)

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core
git commit -m "feat(footstep_core): 재생 결과를 fixes·actions·summary 파일로 쓴다"
```

---

### Task 10: 재생 CLI + 실제 세션 확인 + 사용 안내

**Files:**
- Create: `packages/footstep_core/lib/src/cli/replay_cli.dart`
- Create: `packages/footstep_core/bin/replay.dart`
- Create: `docs/research/replay-guide.md`
- Test: `packages/footstep_core/test/cli/replay_cli_test.dart`

**Interfaces:**
- Consumes:
  - `readSession` (Task 3)
  - `createPolicy`, `policyIds`, `createDetector`, `detectorIds` (Task 7)
  - `replaySession`, `ReplayConfig` (Task 8)
  - `writeReplayOutput` (Task 9)
- Produces:
  - `Future<int> runReplayCli(List<String> arguments, {StringSink? out, StringSink? err})` — 종료 코드: 0 성공, 64 사용법 오류, 65 기록 없는 세션, 66 세션 폴더 없음
  - `dart run footstep_core:replay --session <폴더> --policy <id> --out <폴더> [--param k=v ...] [--detector os] [--ttff 초]`

- [ ] **Step 1: args 의존성 추가**

Run (`packages/footstep_core/`에서): `dart pub add args`

- [ ] **Step 2: 실패하는 테스트 작성**

`packages/footstep_core/test/cli/replay_cli_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:footstep_core/src/cli/replay_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory session;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('replay_cli_test');
    session = Directory(p.join(root.path, 'mini-groundTruth'))..createSync();
    // 2분 동안 1초마다 같은 자리 GPS
    final rows = [for (var t = 0; t <= 120000; t += 1000) '$t,$t,37.5,127.0,5.0,0,0,30'];
    File(p.join(session.path, 'gps.csv')).writeAsStringSync(
        't_ms,fix_t_ms,lat,lng,accuracy_m,speed_mps,bearing_deg,altitude_m\n${rows.join('\n')}\n');
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() async => root.delete(recursive: true));

  test('필수 옵션이 없으면 사용법을 알리고 64를 돌려준다', () async {
    expect(await runReplayCli(const [], out: out, err: err), 64);
    expect(err.toString(), contains('사용법'));
  });

  test('모르는 정책이면 64를 돌려준다', () async {
    final code = await runReplayCli(
        ['--session', session.path, '--policy', 'nope', '--out', p.join(root.path, 'o')],
        out: out, err: err);
    expect(code, 64);
    expect(err.toString(), contains('알 수 없는 정책'));
  });

  test('세션 폴더가 없으면 66을 돌려준다', () async {
    final code = await runReplayCli(
        ['--session', p.join(root.path, 'missing'), '--policy', 'fixed_1m', '--out', p.join(root.path, 'o')],
        out: out, err: err);
    expect(code, 66);
  });

  test('재생해 결과 파일을 쓰고 한 줄 요약을 출력한다', () async {
    final outDir = p.join(root.path, 'out');
    final code = await runReplayCli(
        ['--session', session.path, '--policy', 'fixed_1m', '--out', outDir], out: out, err: err);

    expect(code, 0, reason: err.toString());
    expect(out.toString(), contains('fixed_1m fixes=3'));
    expect(File(p.join(outDir, 'fixes.csv')).readAsLinesSync(), hasLength(4)); // 헤더 + 0·60·120초
    expect(File(p.join(outDir, 'actions.csv')).existsSync(), isTrue);
  });

  test('--param과 --ttff가 정책·재생 설정에 들어간다', () async {
    final outDir = p.join(root.path, 'out2');
    final code = await runReplayCli([
      '--session', session.path, '--policy', 'time_speed', '--param', 'e_m=25',
      '--ttff', '5', '--out', outDir,
    ], out: out, err: err);

    expect(code, 0, reason: err.toString());
    final summary =
        jsonDecode(File(p.join(outDir, 'summary.json')).readAsStringSync()) as Map<String, Object?>;
    expect(summary['policy_params'], {'e_m': 25.0});
    expect(summary['ttff_ms'], 5000);
  });

  test('--param 형식이 틀리면 64를 돌려준다', () async {
    final code = await runReplayCli([
      '--session', session.path, '--policy', 'time_speed', '--param', 'e_m', '--out', p.join(root.path, 'o'),
    ], out: out, err: err);
    expect(code, 64);
  });
}
```

- [ ] **Step 3: 테스트가 실패하는지 확인**

Run: `dart test test/cli/replay_cli_test.dart`
Expected: FAIL (`replay_cli.dart`가 없다는 컴파일 오류)

- [ ] **Step 4: 구현**

`packages/footstep_core/lib/src/cli/replay_cli.dart`:

```dart
import 'dart:io';

import 'package:args/args.dart';

import '../detectors/detector_registry.dart';
import '../detectors/step_detector.dart';
import '../policies/collection_policy.dart';
import '../policies/policy_registry.dart';
import '../replay/replay_engine.dart';
import '../replay/replay_output.dart';
import '../replay/replay_result.dart';
import '../session/session_reader.dart';

const _usage = '사용법: dart run footstep_core:replay --session <세션 폴더> --policy <정책 id> '
    '--out <결과 폴더> [--param k=v ...] [--detector os] [--ttff 초]';

/// 재생기 CLI(설계 5-4). 종료 코드는 sysexits 관례를 따른다: 0 성공, 64 사용법 오류,
/// 65 기록 없는 세션, 66 세션 폴더 없음. 테스트가 출력을 확인할 수 있게 [out]·[err]를 받는다.
Future<int> runReplayCli(List<String> arguments, {StringSink? out, StringSink? err}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final parser = ArgParser()
    ..addOption('session', help: 'R1 세션 폴더')
    ..addOption('policy', help: '정책 id (${policyIds.join(', ')})')
    ..addMultiOption('param', help: '정책 파라미터 k=v (여러 번 줄 수 있다)', splitCommas: false)
    ..addOption('detector', defaultsTo: 'os', help: '걸음 감지기 (${detectorIds.join(', ')})')
    ..addOption('ttff', defaultsTo: '0', help: '측위 지연(초): 0·5·10')
    ..addOption('out', help: '결과 폴더(fixes.csv, actions.csv, summary.json)');

  int usageError(String message) {
    stderrSink
      ..writeln(message)
      ..writeln(_usage)
      ..writeln(parser.usage);
    return 64;
  }

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    return usageError(e.message);
  }

  final sessionPath = args.option('session');
  final policyId = args.option('policy');
  final outPath = args.option('out');
  if (sessionPath == null || policyId == null || outPath == null) {
    return usageError('--session, --policy, --out은 꼭 줘야 합니다.');
  }

  final ttffSeconds = double.tryParse(args.option('ttff')!);
  if (ttffSeconds == null || ttffSeconds < 0) return usageError('--ttff는 0 이상의 초여야 합니다.');

  final params = <String, String>{};
  for (final pair in args.multiOption('param')) {
    final i = pair.indexOf('=');
    if (i <= 0) return usageError('--param은 k=v 형식이어야 합니다: $pair');
    params[pair.substring(0, i)] = pair.substring(i + 1);
  }

  late final CollectionPolicy policy;
  late final StepDetector detector;
  try {
    policy = createPolicy(policyId, params);
    detector = createDetector(args.option('detector')!);
  } on ArgumentError catch (e) {
    return usageError('${e.message}');
  }

  final sessionDir = Directory(sessionPath);
  if (!await sessionDir.exists()) {
    stderrSink.writeln('세션 폴더가 없습니다: $sessionPath');
    return 66;
  }
  final data = await readSession(sessionDir);

  final ReplayResult result;
  try {
    result = replaySession(data, policy, detector,
        config: ReplayConfig(ttffMs: (ttffSeconds * 1000).round()));
  } on ArgumentError catch (e) {
    stderrSink.writeln('${e.message}');
    return 65;
  }

  await writeReplayOutput(result, Directory(outPath));
  final s = result.summary;
  stdoutSink.writeln('${s.policyId} fixes=${s.totalFixes} requests=${s.fixRequests} '
      'failures=${s.fixFailures} gps_on=${(s.gpsOnMs / 1000).toStringAsFixed(0)}s '
      'fixes/h=${s.fixesPerHour.toStringAsFixed(1)} skipped_rows=${data.skippedRows} -> $outPath');
  return 0;
}
```

`packages/footstep_core/bin/replay.dart`:

```dart
import 'dart:io';

import 'package:footstep_core/src/cli/replay_cli.dart';

/// `dart run footstep_core:replay ...` (packages/footstep_core/에서). 사용법은 docs/research/replay-guide.md.
Future<void> main(List<String> arguments) async {
  exitCode = await runReplayCli(arguments);
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `dart test`
Expected: PASS (지금까지 55 tests)

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 6: 실제 세션으로 확인**

로컬에 R1 세션(`research/data/sessions/`)이 있으면 대표 정책 몇 개를 돌려 본다(Bash, `packages/footstep_core/`에서). 결과는 임시 폴더에 쓰고 커밋하지 않는다.

```bash
S=../../research/data/sessions/20261109-213324-groundTruth
O="$(mktemp -d)"
if [ -d "$S" ]; then
  for P in hourly fixed_1m continuous_10m speed_adaptive time_speed still_suppress activity_gated; do
    dart run footstep_core:replay --session "$S" --policy "$P" --out "$O/$P"
  done
else
  echo "세션 없음 — 건너뜀"
fi
rm -rf "$O"
```

Expected (세션이 있을 때): 정책마다 한 줄 요약이 나오고 종료 코드가 0이다. 이 세션(15분 47초, 밖에서 걷기 + 실내 정지)이면 다음과 같아야 한다.
- `hourly`: fixes=1
- `fixed_1m`: fixes=16 안팎
- `continuous_10m`: fixes가 수십~수백, `gps_on`이 세션 길이(약 947초)와 같다
- 나머지: 오류 없이 끝난다

출력 일곱 줄을 태스크 보고서에 그대로 붙인다. 위 범위를 벗어나면 멈추고 보고한다(재생 규칙 또는 세션 읽기에 문제가 있다는 뜻이다).

- [ ] **Step 7: 사용 안내 작성**

`docs/research/replay-guide.md`:

````markdown
# 재생기 사용 안내 (R2)

R1로 기록한 세션 폴더를 PC에서 재생해, 각 수집 방식이 '어떤 GPS 점을 남겼을지'를 파일로 만든다. 설계는
`docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md` 5-4절이다.

## 실행

`packages/footstep_core/`에서 실행한다.

```bash
dart run footstep_core:replay --session <세션 폴더> --policy <정책 id> --out <결과 폴더> \
  [--param k=v ...] [--detector os] [--ttff 초]
```

예: `dart run footstep_core:replay --session ../../research/data/sessions/20261109-213324-groundTruth --policy time_speed --param e_m=25 --ttff 5 --out ../../research/results/replay/s1-time_speed-e25-ttff5`

## 정책

| id | 방식 | 파라미터 |
|---|---|---|
| `hourly` | 현재 앱 1시간 주기 | 없음 |
| `continuous_10m` | 현재 앱 실시간 경로(1초, 10m 필터) | 없음 |
| `fixed_30s` · `fixed_1m` · `fixed_5m` | 고정 주기 | 없음 |
| `speed_adaptive` | Galeana-Zapién 외(2014): 마지막 속도로 간격 조절(정지 2분, 보행 30초, 시속 9km 이상 10초) | 없음 |
| `time_speed` | EnTracked·RAPS: 마지막 오차 + 속도 × 시간 > E이면 측위(속도 하한 1.4m/s) | `e_m`(기본 50) |
| `still_suppress` | Zhuang 외(2010): 고정 주기, 정지 중이면 건너뜀 | `interval_s`(기본 60) |
| `activity_gated` | 상용 방식: 활동 인식 STILL이면 연속 측위 끔, 움직임이면 켬 | 없음 |

제안 정책 `step_budget`은 R4에서, 걸음 감지기 `brajdic`·`adaptive`는 R3에서 추가된다. 지금 감지기는 `os`(OS 걸음 센서)뿐이다.

## 결과 파일

| 파일 | 내용 |
|---|---|
| `fixes.csv` | `t_ms,lat,lng,accuracy_m,steps_since_prev,state,kind` — 정책이 남긴 점. kind는 `single`(단발) 또는 `continuous` |
| `actions.csv` | `t_ms,action,args` — 정책이 낸 할 일 전부 |
| `summary.json` | 측위 요청·성공·실패 수, 연속 측위 점 수, 추정 GPS 켜짐 시간(`gps_on_s`), 시간당 점 수 |

## 해석할 때 주의

- 재생은 '켜자마자 위치가 나온다'를 가정한다. `--ttff 5`·`--ttff 10`으로 바꿔 가며 민감도를 본다.
- 실내에서 정지해 있으면 정답 GPS 자체가 약 7초 간격이다(실기기 점검). 그 구간의 단발 측위는 응답이 최대 7초 늦게 잡힌다.
- 결과 폴더(`research/results/`)와 세션(`research/data/`)은 커밋하지 않는다.
````

- [ ] **Step 8: 커밋**

```bash
git add packages/footstep_core docs/research/replay-guide.md
git commit -m "feat(footstep_core): 재생기 CLI와 사용 안내를 추가한다"
```

- [ ] **Step 9: 마무리 확인**

Run (`packages/footstep_core/`에서): `dart test` / `dart analyze`
Expected: 전체 PASS / `No issues found!`

Run (`app/`에서): `flutter test` / `dart analyze`
Expected: 전체 PASS / `No issues found!`

Run: `git log --format=%B origin/master..HEAD | grep -iE "co-authored|claude"`
Expected: 출력 없음
