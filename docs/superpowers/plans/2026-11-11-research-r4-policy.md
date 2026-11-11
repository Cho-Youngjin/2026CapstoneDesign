# R4 제안 정책·폰 실행기·정책 실행 모드 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 제안 수집 정책 `step_budget`(모듈 B)을 공용 패키지에 더한다. 그 정책을 폰에서 돌리는 실행기와, 배터리 실험용 **정책 실행 모드**를 앱에 붙인다. 기준 정책 `still_suppress`는 Zhuang 외(2010) 원문대로 고친다.

**Architecture:**
- 정책은 R2와 같이 사건을 받아 할 일만 돌려준다.
  - `step_budget`은 걸음 감지기의 상태(보행·정지·기타 움직임)와 측위 뒤 걸음 수로 측위 시점을 정한다.
  - 정책 상태를 `ReportsState`로 알려, fixes.csv의 state 열에 `vehicle`이 처음 나온다.
- 폰 실행기 `PolicyRunner`는 순수 Dart로 패키지에 둔다. R7 여행 기록도 같은 실행기를 쓴다.
  - 재생기와 같은 규칙으로 할 일을 실제 동작으로 바꾼다: RequestFix 합치기, 연속 측위, 깨우기, 1초 가속도 묶음.
  - GPS·타이머·시계는 포트(`LocationPort`·`WakeScheduler`·clock)로 밖에서 넣는다. 그래서 테스트가 시간을 손으로 넘긴다.
- 앱의 기록 서비스는 모드마다 기록기를 바꿔 끼운다(`SessionRecorder`).
  - 정책 실행 모드(`PolicyRecorder`)는 정책이 쓰는 센서만 켠다.
  - 쓰는 파일은 측위 결과·할 일·깨우기 지연·배터리·관찰 표시와 끝날 때의 summary.json이다.
  - fixes.csv·actions.csv·summary.json은 재생기와 같은 형식이라, R6가 재생 결과와 실기기 결과를 같은 코드로 읽는다.

**Tech Stack:**
- Dart 3.13.2(footstep_core)
- Flutter 3.47.2(app)
- 플러그인: geolocator 14, flutter_foreground_task 11, sensors_plus, pedometer, flutter_activity_recognition

**설계 문서·근거:**
- `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md`
  - 4-1: 모드
  - 5-3: `step_budget` 규칙·절제 스위치
  - 5-5: 폰 실행기
  - 8-2: 배터리 실험
  - 10장: 위험 3, 타이머 지연
- Zhuang, Kim, Singh, "Improving Energy Efficiency of Location Sensing on Smartphones", MobiSys 2010 — 바탕화면 `1814433.1814464.pdf`
  - 3.2절: 억제 중 확인 측위
  - 4.4절: 1분마다 상태 확인
  - 그림 10(b): 직전·이번 상태가 모두 정지일 때 GPS 해제
  - 5.3절
- Paek, Kim, Govindan, RAPS, MobiSys 2010 — 바탕화면 `1814433.1814463.pdf`
  - `time_speed`는 RAPS의 장소·시간대별 속도 이력과 활동 비율을 쓰지 않는 단순화판이다.
  - 사용자와 이 차이를 고치지 않고 한계로 적기로 했다(2026-11-11).

## 설계 검증 (Python·Dart 시제품, 커밋하지 않음)

이 계획의 패키지·앱 코드는 임시 작업 폴더에서 먼저 그대로 짜서 검증했다.
- 패키지: `dart test` 161개 통과
- 앱: `flutter test` 714개 통과
- `dart analyze`: 둘 다 0건

아래 실제 세션 재생 값이 Task 7의 확인 기준이다. 세션은 `20261109-213324-groundTruth`(15분 47초, 손에 들고 걷기 약 7분 + 실내 정지, 첫 1분과 끝은 폰 만지기)이고, ttff는 0이다.

| 정책 | 감지기 | 파라미터 | 측위 | GPS 켜짐 |
|---|---|---|---|---|
| `fixed_1m` | os | — | 16 | 7초 |
| `continuous_10m` | os | — | 53 | 947초 |
| `activity_gated` | os | — | 53 | 500초 |
| `still_suppress` (Zhuang) | os | — | 11 | 4초 |
| `still_suppress` (Zhuang) | adaptive | — | 12 | 5초 |
| `step_budget` | os | — | 18 | 8초 |
| `step_budget` | adaptive | — | 16 | 9초 |
| `step_budget` | brajdic | — | 17 | 10초 |
| `step_budget` | adaptive | `e_m=25` | 35 | 23초 |
| `step_budget` | adaptive | `e_m=100` | 9 | 5초 |
| `step_budget` | adaptive | `use_steps=false` | 20 | 10초 |
| `step_budget` | adaptive | `suppress_still=false` | 29 | 25초 |
| `step_budget` | adaptive | `vehicle_probe=false` | 16 | 9초 |

**검증 중에 정한 설계 하나 — 상태가 30초 이어져야 그 상태로 잰다.**
- 처음에는 정지·기타 움직임이 시작되자마자 쟀다.
- 그런데 제안판 감지기는 폰을 만지는 동안 상태가 몇 초 단위로 바뀐다. 그래서 첫 1분에만 15번을 쟀고, 전체는 42회였다.
- 30초 유지 조건을 넣자 16회가 되었고, E를 25·50·100m로 바꾸면 35·16·9회로 단조롭게 바뀐다.

## Global Constraints

- 작업 브랜치는 `policy`다. `steps`에서 갈라지며, `steps`는 PR #36으로 리뷰 중이다. 다른 브랜치를 만들지 않는다.
- 커밋에 `Co-Authored-By`, `Claude-Session` 같은 AI 트레일러를 넣지 않는다. push 전에 `git log --format=%B origin/steps..HEAD | grep -iE "co-authored|claude"`가 빈 결과인지 확인한다.
- `packages/footstep_core`는 Flutter에 의존하지 않는다. 런타임 의존성은 `path`와 `args`뿐이고, 개발 의존성은 `test`와 `lints`다.
- 패키지 안의 시각은 모두 `int` UTC epoch 밀리초다. 패키지 로직에서 `DateTime.now()`나 난수를 쓰지 않는다. 실행기는 시계·GPS·타이머를 밖에서 받는다.
- 정책 id는 다음과 같다: `hourly`, `fixed_30s`, `fixed_1m`, `fixed_5m`, `continuous_10m`, `speed_adaptive`, `time_speed`, `still_suppress`, `activity_gated`, `step_budget`.
- `step_budget` 값은 다음과 같다.
  - 파라미터와 기본값
    - `e_m`: 50(E, m)
    - `stride_m`: 0.75
    - `use_steps`, `suppress_still`, `vehicle_probe`: 모두 true(절제 스위치)
  - 고정값
    - 걷기 속도 1.4m/s, 탈것 기준 시속 12km
    - 상태 유지 30초, 정지 확인 5분, 확인 측위 간격 30초
    - 대기 5초~10분
    - 실패 재시도 30초 → 1분 → 2분 → 5분
    - 배터리 20% 미만이면 E×2
- `still_suppress`(Zhuang) 값은 다음과 같다.
  - 확인 주기 `interval_s`는 60이다.
  - 직전·이번 확인이 모두 정지여야 건너뛴다.
  - 억제 중 확인 측위 `verify_s`는 300이다.
- 실행기는 가속도를 재생기와 같은 1초 묶음(`AccelBatcher`)으로 넣는다. Wakeup은 실제로 깬 시각으로 보내고, 예약·실제 시각을 wakeups.csv에 남긴다.
- 정책 실행 모드가 쓰는 파일은 fixes.csv·actions.csv·wakeups.csv·battery.csv·marks.csv·meta.json·summary.json뿐이다.
  - 1초 GPS와 가속도 원본은 쓰지 않는다.
  - 센서는 정책이 쓰는 것만 켠다(`PolicySensorNeeds`).
- 테스트·분석은 다음 명령으로 한다.
  - 패키지(`packages/footstep_core/`): `dart test`, `dart analyze`
  - 앱(`app/`): `flutter test`, `dart analyze`. `flutter analyze`는 이 PC에서 경로 문제로 죽는다.
- 수집한 세션 데이터(`research/data/`)와 결과는 커밋하지 않는다.
- 코드 주석은 한국어로 '왜'를 적는다.
- `flutter install`은 기존 앱을 지워 폰의 세션·로그인·권한이 사라진다. 실기기 확인 전에 세션을 PC로 옮긴다.

## 파일 구조

```
packages/footstep_core/
  lib/src/policies/still_suppress_policy.dart  Zhuang 원문대로(연속 2회 정지, 5분 확인 측위) (Task 1)
  lib/src/params.dart                          + flag (Task 2)
  lib/src/policies/step_budget_policy.dart     제안 정책 (Task 2)
  lib/src/policies/policy_registry.dart        + step_budget, still_suppress verify_s (Task 1·2)
  lib/src/replay/accel_batches.dart            + AccelBatcher(실시간판) (Task 3)
  lib/src/runner/runner_ports.dart             LocationPort, WakeScheduler, RunnerSink, WakeupRecord, RunnerSchema (Task 3)
  lib/src/runner/run_summary.dart              RunSummary (Task 3)
  lib/src/runner/policy_runner.dart            PolicyRunner (Task 3)
  lib/footstep_core.dart                       export 추가 (Task 2·3·6)
app/lib/features/footsteps/recording/
  session_recorder.dart                        SessionRecorder 인터페이스 (Task 4)
  ground_truth_recorder.dart                   implements SessionRecorder (Task 4)
  recorder_status.dart                         + policyState, stepsSinceFix (Task 4)
  policy_choice.dart                           PolicyChoice, PolicySensorNeeds (Task 4)
  policy_session_files.dart                    정책 실행 모드 파일 (Task 4)
  policy_recorder.dart                         PolicyRecorder (Task 4)
  plugin_location_port.dart                    GeolocatorLocationPort, TimerWakeScheduler (Task 5)
  recording_mode.dart / recording_config.dart / session_meta.dart   policy 모드·설정 (Task 5)
  session_recorder_factory.dart                모드별 기록기 만들기 (Task 5)
  recording_task_handler.dart / recording_controller.dart          모드별 기록기 연결 (Task 5)
app/lib/features/footsteps/lab/
  lab_mode_panel.dart, lab_page.dart, lab_status_card.dart          모드·정책 선택 화면 (Task 6)
docs/research/battery-experiment-guide.md      배터리 실험 안내 (Task 7)
docs/research/policy-mode-check.md             정책 실행 모드 실기기 확인 결과 (Task 8)
```

---

### Task 1: `still_suppress`를 Zhuang 원문대로 고친다

**Files:**
- Modify: `packages/footstep_core/lib/src/policies/still_suppress_policy.dart`(전체 교체)
- Modify: `packages/footstep_core/lib/src/policies/policy_registry.dart`(`still_suppress` 줄)
- Test: `packages/footstep_core/test/policies/basic_policies_test.dart`(StillSuppressPolicy 그룹 교체)
- Test: `packages/footstep_core/test/registry_test.dart`(1줄 교체)
- Test: `packages/footstep_core/test/replay/replay_engine_test.dart`(테스트 1개 기대값)

**Interfaces:**
- Consumes: R2의 `CollectionPolicy`, `StepUpdate`, `Wakeup`, `RequestFix`, `WakeAt`
- Produces:
  - `StillSuppressPolicy({int intervalMs = 60000, int verifyMs = 300000})`
  - `params == {'interval_s': 60, 'verify_s': 300}`
  - 정책 목록 파라미터 `verify_s`

- [ ] **Step 1: 실패하는 테스트 작성**

`test/policies/basic_policies_test.dart`에서 `group('StillSuppressPolicy (Zhuang 외 2010: 정지 중 측위 억제)', () { ... });` 전체를 다음으로 바꾼다. 파일 맨 위의 `step()` 도우미는 그대로 쓴다.

```dart
  group('StillSuppressPolicy (Zhuang 외 2010: 정지 중 측위 억제)', () {
    const ctx0 = PolicyContext(nowMs: 0);
    PolicyContext at(int t) => PolicyContext(nowMs: t);
    Wakeup tick(int t) => Wakeup(tMs: t, tag: 'tick');

    test('보행 중에는 주기마다 측위한다', () {
      final policy = StillSuppressPolicy();
      expect(policy.onStart(ctx0), [const RequestFix(), const WakeAt(tMs: 60000, tag: 'tick')]);

      policy.onEvent(step(1000, StepState.walking), at(1000));
      expect(policy.onEvent(tick(60000), at(60000)),
          [const RequestFix(), const WakeAt(tMs: 120000, tag: 'tick')]);
    });

    test('정지가 직전·이번 확인에서 연달아 보여야 측위를 건너뛴다', () {
      final policy = StillSuppressPolicy()..onStart(ctx0);
      policy.onEvent(step(1000, StepState.still), at(1000));

      // 첫 정지 확인: 잠깐 멈춘 것일 수 있어 아직 측위한다.
      expect(policy.onEvent(tick(60000), at(60000)),
          [const RequestFix(), const WakeAt(tMs: 120000, tag: 'tick')]);
      // 두 번째 연속 정지: 건너뛰고 다음 확인만 예약한다.
      expect(policy.onEvent(tick(120000), at(120000)), [const WakeAt(tMs: 180000, tag: 'tick')]);
    });

    test('억제하는 동안에도 마지막 측위 뒤 5분이 지나면 확인 측위를 한다', () {
      final policy = StillSuppressPolicy()..onStart(ctx0);
      policy.onEvent(step(1000, StepState.still), at(1000));
      policy.onEvent(tick(60000), at(60000)); // 측위(마지막 측위 60초)

      for (final t in [120000, 180000, 240000, 300000]) {
        expect(policy.onEvent(tick(t), at(t)), [WakeAt(tMs: t + 60000, tag: 'tick')], reason: '$t');
      }
      expect(policy.onEvent(tick(360000), at(360000)),
          [const RequestFix(), const WakeAt(tMs: 420000, tag: 'tick')]);
      expect(policy.onEvent(tick(420000), at(420000)), [const WakeAt(tMs: 480000, tag: 'tick')]);
    });

    test('억제 중에 걷기 시작하면 다음 확인에서 바로 측위한다', () {
      final policy = StillSuppressPolicy()..onStart(ctx0);
      policy.onEvent(step(1000, StepState.still), at(1000));
      policy.onEvent(tick(60000), at(60000));
      policy.onEvent(tick(120000), at(120000)); // 억제

      policy.onEvent(step(130000, StepState.walking), at(130000));
      expect(policy.onEvent(tick(180000), at(180000)),
          [const RequestFix(), const WakeAt(tMs: 240000, tag: 'tick')]);
    });

    test('걸음 정보가 아직 없으면 측위한다', () {
      final policy = StillSuppressPolicy(intervalMs: 120000)..onStart(ctx0);

      expect(policy.onEvent(tick(120000), at(120000)),
          [const RequestFix(), const WakeAt(tMs: 240000, tag: 'tick')]);
      expect(policy.id, 'still_suppress');
      expect(policy.params, {'interval_s': 120, 'verify_s': 300});
    });

    test('onStart는 이전 실행의 상태를 지운다', () {
      final policy = StillSuppressPolicy()..onStart(ctx0);
      policy.onEvent(step(1000, StepState.still), at(1000));
      policy.onEvent(tick(60000), at(60000));

      policy.onStart(ctx0); // 같은 인스턴스를 다시 쓴다
      expect(policy.onEvent(tick(60000), at(60000)),
          [const RequestFix(), const WakeAt(tMs: 120000, tag: 'tick')]);
    });
  });
```

`test/registry_test.dart`에서 다음 줄을

```dart
    expect(createPolicy('still_suppress', {'interval_s': '120'}).params, {'interval_s': 120});
```

다음으로 바꾼다:

```dart
    expect(createPolicy('still_suppress', {'interval_s': '120'}).params,
        {'interval_s': 120, 'verify_s': 300});
    expect(createPolicy('still_suppress', {'verify_s': '600'}).params, {'interval_s': 60, 'verify_s': 600});
```

`test/replay/replay_engine_test.dart`의 `test('정지로 시작한 세션에서 still_suppress는 주기 측위를 건너뛴다', ...)`에서 다음 부분을

```dart
    // 5분 동안 걸음 수가 그대로다. 첫 OS 걸음 읽기에서 정지가 알려지면 시작 때 한 번만 측위한다.
```

```dart
    expect(result.summary.fixRequests, 1);
    expect(result.fixes.single.tMs, 0);
    expect(result.fixes.single.state, 'still');
```

각각 다음으로 바꾼다(나머지 줄은 그대로):

```dart
    // 5분 동안 걸음 수가 그대로다. 첫 OS 걸음 읽기에서 정지가 알려지면, 시작 때와 첫 정지 확인(1분) 때만
    // 측위하고 두 번째 연속 정지 확인부터 건너뛴다(Zhuang 외 2010). 확인 측위(5분)는 세션 끝(5분) 뒤라 없다.
```

```dart
    expect(result.summary.fixRequests, 2);
    expect(result.fixes.map((f) => f.tMs), [0, 60000]);
    expect(result.fixes.map((f) => f.state), ['still', 'still']);
```

- [ ] **Step 2: 실패 확인**

Run (`packages/footstep_core/`에서): `dart test test/policies/basic_policies_test.dart test/registry_test.dart test/replay/replay_engine_test.dart`

Expected: FAIL. 두 번째 연속 정지 전에 건너뛰고, `verify_s`가 없고, 측위가 1회뿐이다.

- [ ] **Step 3: 구현**

`lib/src/policies/still_suppress_policy.dart` 전체:

```dart
import '../events/policy_action.dart';
import '../events/policy_event.dart';
import 'collection_policy.dart';

/// 정지 중 측위 억제(Zhuang 외, "Improving Energy Efficiency of Location Sensing on Smartphones",
/// MobiSys 2010의 Sensing suppRession). [intervalMs](1분)마다 상태를 확인해 측위하되, 직전 확인과 이번 확인이
/// 모두 정지일 때만 측위를 건너뛴다(원문 그림 10(b) 8~9행 — 정지가 한 번만 보이면 잠깐 멈춘 것일 수 있다).
/// 억제하는 동안에도 [verifyMs]마다 확인 측위를 한다(원문 3.2절의 확인 장치). 확인 주기는 원문에 값이 없어
/// 제안 정책(step_budget)의 정지 확인 주기 5분과 맞춘다. 원문은 확인 때마다 몇 초씩 가속도를 읽지만,
/// 이 정책은 걸음 감지기가 알려 준 상태를 쓴다. 걸음 정보가 아직 없으면 측위한다.
class StillSuppressPolicy implements CollectionPolicy {
  StillSuppressPolicy({this.intervalMs = 60000, this.verifyMs = 300000});

  static const _tag = 'tick';

  final int intervalMs;
  final int verifyMs;

  StepState? _state;
  bool _previousTickStill = false;
  int _lastRequestMs = 0;

  @override
  String get id => 'still_suppress';

  @override
  Map<String, Object> get params => {'interval_s': intervalMs ~/ 1000, 'verify_s': verifyMs ~/ 1000};

  @override
  List<PolicyAction> onStart(PolicyContext ctx) {
    // 같은 인스턴스를 다시 써도 이전 실행의 상태가 남아 첫 판단을 흐리지 않게 한다.
    _state = null;
    _previousTickStill = false;
    _lastRequestMs = ctx.nowMs;
    return [const RequestFix(), WakeAt(tMs: ctx.nowMs + intervalMs, tag: _tag)];
  }

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    switch (event) {
      case StepUpdate(:final state):
        _state = state;
        return const [];
      case Wakeup(:final tag) when tag == _tag:
        final next = WakeAt(tMs: event.tMs + intervalMs, tag: _tag);
        final still = _state == StepState.still;
        final suppress = still && _previousTickStill;
        _previousTickStill = still;
        if (suppress && event.tMs - _lastRequestMs < verifyMs) return [next];
        _lastRequestMs = event.tMs;
        return [const RequestFix(), next];
      default:
        return const [];
    }
  }
}
```

`lib/src/policies/policy_registry.dart`의 `still_suppress` 줄을 바꾼다:

```dart
    case 'still_suppress':
      reader.allowOnly(const {'interval_s', 'verify_s'});
      return StillSuppressPolicy(
        intervalMs: (reader.positive('interval_s', 60) * 1000).round(),
        verifyMs: (reader.positive('verify_s', 300) * 1000).round(),
      );
```

- [ ] **Step 4: 통과 확인**

Run: `dart test`(전체)와 `dart analyze` → 모두 통과, 0건.

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core/lib/src/policies/still_suppress_policy.dart packages/footstep_core/lib/src/policies/policy_registry.dart packages/footstep_core/test/policies/basic_policies_test.dart packages/footstep_core/test/registry_test.dart packages/footstep_core/test/replay/replay_engine_test.dart
git commit -m "fix(footstep_core): 정지 억제 기준 정책을 Zhuang 원문대로 연속 정지 확인과 확인 측위로 고친다"
```

---

### Task 2: 제안 정책 `step_budget`

**Files:**
- Modify: `packages/footstep_core/lib/src/params.dart`(전체 교체 — `flag` 추가)
- Create: `packages/footstep_core/lib/src/policies/step_budget_policy.dart`
- Modify: `packages/footstep_core/lib/src/policies/policy_registry.dart`(전체 교체)
- Modify: `packages/footstep_core/lib/footstep_core.dart`(export 1줄)
- Test: `packages/footstep_core/test/policies/step_budget_policy_test.dart`
- Test: `packages/footstep_core/test/registry_test.dart`

**Interfaces:**
- Consumes:
  - R2: `CollectionPolicy`, `ReportsState`, `PolicyContext`, 사건·할 일, `haversineMeters`, `Fix`
  - Task 1: 정책 목록
- Produces:
  - `ParamReader.flag(String key, bool fallback)`. true·false·1·0만 받고, 아니면 ArgumentError다.
  - `StepBudgetPolicy({double errorBudgetM = 50, double strideM = 0.75, bool useSteps = true, bool suppressStill = true, bool vehicleProbe = true}) implements CollectionPolicy, ReportsState`
    - `id == 'step_budget'`
    - `stateLabel`: `unknown` · `walking` · `still` · `otherMotion` · `vehicle`
    - 깨우기 tag: `<까닭>#<번호>`. 까닭은 `budget`·`stay`·`check`·`probe1`·`probe2`·`vehicle`·`retry`이다.
  - `policyIds`의 마지막에 `'step_budget'`
  - 정책 목록 파라미터: `e_m`, `stride_m`, `use_steps`, `suppress_still`, `vehicle_probe`

- [ ] **Step 1: 실패하는 테스트 작성**

`test/policies/step_budget_policy_test.dart`:

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

StepUpdate step(int tMs, StepState state, [int steps = 0]) =>
    StepUpdate(tMs: tMs, state: state, totalSteps: steps, stepsSinceLastFix: steps);

/// 기준 위치(북위 37.5°)에서 [dLat]도 북쪽. 0.003°는 약 334m다.
Fix fixAt(int tMs, {double dLat = 0, double accuracyM = 5}) =>
    Fix(tMs: tMs, lat: 37.5 + dLat, lng: 127.0, accuracyM: accuracyM);

PolicyContext at(int nowMs, [Fix? lastFix]) => PolicyContext(nowMs: nowMs, lastFix: lastFix);

FixResult ok(Fix fix) => FixResult(tMs: fix.tMs, fix: fix);

FixResult failed(int tMs) => FixResult(tMs: tMs);

Wakeup wake(int tMs, String tag) => Wakeup(tMs: tMs, tag: tag);

/// 시작 측위(1초)를 받은 정책과 그 위치.
(StepBudgetPolicy, Fix) started([StepBudgetPolicy? policy]) {
  final p = policy ?? StepBudgetPolicy();
  p.onStart(at(0));
  final f0 = fixAt(1000);
  p.onEvent(ok(f0), at(1000, f0));
  return (p, f0);
}

void main() {
  test('시작하면 바로 한 번 측위하고, 걸음 정보 전에는 상태를 모른다', () {
    final policy = StepBudgetPolicy();
    expect(policy.onStart(at(0)), [const RequestFix()]);
    expect(policy.stateLabel, 'unknown');
    expect(policy.id, 'step_budget');
    expect(policy.params, {
      'e_m': 50.0,
      'stride_m': 0.75,
      'use_steps': true,
      'suppress_still': true,
      'vehicle_probe': true,
    });
  });

  group('보행', () {
    test('마지막 오차 + 걸음 수 × 보폭이 E를 넘을 때만 측위하고, 응답을 기다리는 동안은 다시 요청하지 않는다', () {
      final (p, f0) = started();
      expect(p.onEvent(step(2000, StepState.walking), at(2000, f0)), isEmpty);
      expect(p.stateLabel, 'walking');

      // 5 + 60 × 0.75 = 50: 아직 넘지 않았다.
      expect(p.onEvent(step(30000, StepState.walking, 60), at(30000, f0)), isEmpty);
      // 5 + 61 × 0.75 = 50.75 > 50.
      expect(p.onEvent(step(31000, StepState.walking, 61), at(31000, f0)), [const RequestFix()]);
      expect(p.onEvent(step(32000, StepState.walking, 62), at(32000, f0)), isEmpty);

      final f1 = fixAt(33000);
      expect(p.onEvent(ok(f1), at(33000, f1)), isEmpty);
      expect(p.onEvent(step(34000, StepState.walking, 1), at(34000, f1)), isEmpty);
    });

    test('배터리가 20% 미만이면 E를 2배로 보고, 다시 오르면 되돌린다', () {
      final (p, f0) = started();
      p.onEvent(step(2000, StepState.walking), at(2000, f0));
      p.onEvent(const BatteryLevel(tMs: 2500, pct: 19), at(2500, f0));

      // 5 + 126 × 0.75 = 99.5 ≤ 100
      expect(p.onEvent(step(3000, StepState.walking, 126), at(3000, f0)), isEmpty);
      // 5 + 127 × 0.75 = 100.25 > 100
      expect(p.onEvent(step(4000, StepState.walking, 127), at(4000, f0)), [const RequestFix()]);

      final f1 = fixAt(5000);
      p.onEvent(ok(f1), at(5000, f1));
      p.onEvent(const BatteryLevel(tMs: 5500, pct: 50), at(5500, f1));
      expect(p.onEvent(step(6000, StepState.walking, 61), at(6000, f1)), [const RequestFix()]);
    });

    test('걸음 수를 쓰지 않으면(절제) 걷기 속도 1.4m/s로 짐작해 오차가 E를 넘는 시각에 잰다', () {
      final (p, f0) = started(StepBudgetPolicy(useSteps: false));
      // (50 − 5) / 1.4 = 32.143초. 걸음 수는 보지 않는다.
      expect(p.onEvent(step(2000, StepState.walking, 999), at(2000, f0)),
          [const WakeAt(tMs: 33143, tag: 'budget#1')]);
      expect(p.onEvent(wake(33143, 'budget#1'), at(33143, f0)), [const RequestFix()]);

      final f1 = fixAt(34000);
      expect(p.onEvent(ok(f1), at(34000, f1)), [const WakeAt(tMs: 66143, tag: 'budget#2')]);
    });
  });

  group('정지', () {
    test('정지가 30초 이어지면 한 번 재어 머문 곳을 남기고, 그 뒤로는 5분마다 확인만 한다', () {
      final (p, f0) = started();
      expect(p.onEvent(step(2000, StepState.still), at(2000, f0)),
          [const WakeAt(tMs: 32000, tag: 'stay#1')]);
      expect(p.stateLabel, 'still');
      expect(p.onEvent(wake(32000, 'stay#1'), at(32000, f0)), [const RequestFix()]);

      final stay = fixAt(33000);
      expect(p.onEvent(ok(stay), at(33000, stay)), [const WakeAt(tMs: 333000, tag: 'check#2')]);
      expect(p.onEvent(wake(333000, 'check#2'), at(333000, stay)), [const RequestFix()]);

      final same = fixAt(334000, dLat: 0.0001); // 약 11m: 머문 곳 그대로
      expect(p.onEvent(ok(same), at(334000, same)), [const WakeAt(tMs: 634000, tag: 'check#3')]);
      expect(p.stateLabel, 'still');
    });

    test('정지가 30초 이어지지 않으면(잠깐 멈춤) 재지 않는다', () {
      final (p, f0) = started();
      p.onEvent(step(2000, StepState.still), at(2000, f0));
      expect(p.onEvent(step(10000, StepState.walking), at(10000, f0)), isEmpty);
      expect(p.onEvent(wake(32000, 'stay#1'), at(32000, f0)), isEmpty);
    });

    test('확인한 위치가 머문 곳에서 벗어났으면 걸음 없이 움직이는 탈것으로 보고 time_speed 규칙으로 잰다', () {
      final (p, f0) = started();
      p.onEvent(step(2000, StepState.still), at(2000, f0));
      p.onEvent(wake(32000, 'stay#1'), at(32000, f0));
      final stay = fixAt(33000);
      p.onEvent(ok(stay), at(33000, stay));
      p.onEvent(wake(333000, 'check#2'), at(333000, stay));

      final moved = fixAt(334000, dLat: 0.003); // 약 334m
      // 속도 하한 시속 12km(3.333m/s): (50 − 5) / 3.333 = 13.5초 뒤
      expect(p.onEvent(ok(moved), at(334000, moved)), [const WakeAt(tMs: 347500, tag: 'vehicle#3')]);
      expect(p.stateLabel, 'vehicle');
    });

    test('정지 억제를 끄면(절제) 정지해도 걷기 속도로 짐작해 계속 잰다', () {
      final (p, f0) = started(StepBudgetPolicy(suppressStill: false));
      expect(p.onEvent(step(2000, StepState.still), at(2000, f0)),
          [const WakeAt(tMs: 33143, tag: 'budget#1')]);
    });

    test('상태가 바뀌면 앞 상태에서 예약한 깨우기는 무시한다', () {
      final (p, f0) = started();
      p.onEvent(step(2000, StepState.still), at(2000, f0));
      p.onEvent(wake(32000, 'stay#1'), at(32000, f0));
      final stay = fixAt(33000);
      p.onEvent(ok(stay), at(33000, stay)); // check#2 예약

      p.onEvent(step(60000, StepState.walking), at(60000, stay));
      expect(p.onEvent(wake(333000, 'check#2'), at(333000, stay)), isEmpty);
    });
  });

  group('기타 움직임과 탈것', () {
    test('30초 이어지면 30초 간격 확인 측위 두 번의 속도를 보고, 시속 12km 이상이면 탈것이며 탈것 진동은 다시 확인하지 않는다', () {
      final (p, f0) = started();
      expect(p.onEvent(step(2000, StepState.otherMotion), at(2000, f0)),
          [const WakeAt(tMs: 32000, tag: 'probe1#1')]);
      expect(p.stateLabel, 'otherMotion');
      expect(p.onEvent(wake(32000, 'probe1#1'), at(32000, f0)), [const RequestFix()]);

      final probe1 = fixAt(33000);
      expect(p.onEvent(ok(probe1), at(33000, probe1)), [const WakeAt(tMs: 63000, tag: 'probe2#2')]);
      expect(p.onEvent(wake(63000, 'probe2#2'), at(63000, probe1)), [const RequestFix()]);

      final probe2 = fixAt(64000, dLat: 0.003); // 약 334m / 31초 ≈ 10.8m/s
      // (50 − 5) / 10.8 ≈ 4.2초 → 최소 5초
      expect(p.onEvent(ok(probe2), at(64000, probe2)), [const WakeAt(tMs: 69000, tag: 'vehicle#3')]);
      expect(p.stateLabel, 'vehicle');

      expect(p.onEvent(step(65000, StepState.otherMotion), at(65000, probe2)), isEmpty);
      expect(p.stateLabel, 'vehicle');

      expect(p.onEvent(wake(69000, 'vehicle#3'), at(69000, probe2)), [const RequestFix()]);
      final v1 = fixAt(70000, dLat: 0.003); // 신호 대기: 그대로 → 속도 하한으로 13.5초
      expect(p.onEvent(ok(v1), at(70000, v1)), [const WakeAt(tMs: 83500, tag: 'vehicle#4')]);

      // 내려서 걸으면 보행이고, 탈것 예약은 무시한다.
      expect(p.onEvent(step(71000, StepState.walking), at(71000, v1)), isEmpty);
      expect(p.stateLabel, 'walking');
      expect(p.onEvent(wake(83500, 'vehicle#4'), at(83500, v1)), isEmpty);
    });

    test('확인 측위 두 번이 느리면(폰 만지기 등) 정지처럼 5분마다 확인만 한다', () {
      final (p, f0) = started();
      p.onEvent(step(2000, StepState.otherMotion), at(2000, f0));
      p.onEvent(wake(32000, 'probe1#1'), at(32000, f0));
      final probe1 = fixAt(33000);
      p.onEvent(ok(probe1), at(33000, probe1));
      p.onEvent(wake(63000, 'probe2#2'), at(63000, probe1));

      final probe2 = fixAt(64000);
      expect(p.onEvent(ok(probe2), at(64000, probe2)), [const WakeAt(tMs: 364000, tag: 'check#3')]);
      expect(p.stateLabel, 'otherMotion');
    });

    test('탈것 확인을 끄면(절제) 기타 움직임을 정지처럼 다룬다', () {
      final (p, f0) = started(StepBudgetPolicy(vehicleProbe: false));
      expect(p.onEvent(step(2000, StepState.otherMotion), at(2000, f0)),
          [const WakeAt(tMs: 32000, tag: 'stay#1')]);
      expect(p.onEvent(wake(32000, 'stay#1'), at(32000, f0)), [const RequestFix()]);
      final stay = fixAt(33000);
      expect(p.onEvent(ok(stay), at(33000, stay)), [const WakeAt(tMs: 333000, tag: 'check#2')]);
      expect(p.stateLabel, 'otherMotion');
    });
  });

  test('측위가 거듭 실패하면 30초 → 1분 → 2분 → 5분(최대)으로 늘리고, 그 사이에는 걸음이 넘쳐도 요청하지 않는다', () {
    final p = StepBudgetPolicy();
    p.onStart(at(0));
    expect(p.onEvent(failed(15000), at(15000)), [const WakeAt(tMs: 45000, tag: 'retry#1')]);
    expect(p.onEvent(step(20000, StepState.walking, 100), at(20000)), isEmpty);

    var now = 45000;
    var seq = 1;
    for (final delay in [60000, 120000, 300000, 300000]) {
      expect(p.onEvent(wake(now, 'retry#$seq'), at(now)), [const RequestFix()]);
      final failAt = now + 15000;
      seq++;
      expect(p.onEvent(failed(failAt), at(failAt)), [WakeAt(tMs: failAt + delay, tag: 'retry#$seq')]);
      now = failAt + delay;
    }

    // 성공하면 다시 30초부터다.
    expect(p.onEvent(wake(now, 'retry#$seq'), at(now)), [const RequestFix()]);
    final fix = fixAt(now + 5000);
    expect(p.onEvent(ok(fix), at(now + 5000, fix)), isEmpty);
    expect(p.onEvent(step(now + 6000, StepState.walking, 100), at(now + 6000, fix)), [const RequestFix()]);
    seq++;
    expect(p.onEvent(failed(now + 21000), at(now + 21000)),
        [WakeAt(tMs: now + 51000, tag: 'retry#$seq')]);
  });

  test('onStart는 이전 실행의 상태를 지운다', () {
    final (p, f0) = started();
    p.onEvent(step(2000, StepState.still), at(2000, f0));
    p.onEvent(const BatteryLevel(tMs: 2500, pct: 10), at(2500, f0));

    expect(p.onStart(at(0)), [const RequestFix()]);
    expect(p.stateLabel, 'unknown');
    final f1 = fixAt(1000);
    p.onEvent(ok(f1), at(1000, f1));
    p.onEvent(step(2000, StepState.walking), at(2000, f1));
    expect(p.onEvent(step(3000, StepState.walking, 61), at(3000, f1)), [const RequestFix()]);
  });
}
```

`test/registry_test.dart`:

1. `expect(policyIds, [ ... ]);` 목록의 마지막 줄 `'speed_adaptive', 'time_speed', 'still_suppress', 'activity_gated',`를 다음으로 바꾼다:

```dart
      'speed_adaptive', 'time_speed', 'still_suppress', 'activity_gated', 'step_budget',
```

2. `test('모르는 정책·파라미터·잘못된 숫자는 ArgumentError다', ...)` 바로 앞에 더한다:

```dart
  test('제안 정책 step_budget은 E·보폭과 절제 실험 스위치를 받는다', () {
    expect(createPolicy('step_budget', {'e_m': '25', 'use_steps': 'false', 'vehicle_probe': '0'}).params, {
      'e_m': 25.0,
      'stride_m': 0.75,
      'use_steps': false,
      'suppress_still': true,
      'vehicle_probe': false,
    });
    expect(() => createPolicy('step_budget', {'use_steps': 'no'}), throwsArgumentError);
    expect(() => createPolicy('step_budget', {'e_m': '0'}), throwsArgumentError);
  });

```

- [ ] **Step 2: 실패 확인**

Run: `dart test test/policies/step_budget_policy_test.dart test/registry_test.dart`
Expected: 컴파일 오류(`StepBudgetPolicy` 없음)

- [ ] **Step 3: 구현**

`lib/src/params.dart` 전체:

```dart
/// 실험 설정의 문자열 파라미터(k=v)를 읽는다. 모르는 키·잘못된 숫자는 ArgumentError다 — 실험 설정 오타로
/// 엉뚱한 기본값이 조용히 쓰이는 것을 막는다. 정책 목록과 걸음 감지기 목록이 같이 쓴다.
class ParamReader {
  ParamReader(this.owner, this.params);

  /// 오류 문구에 쓰는 이름. 예: '정책 time_speed', '걸음 감지기 adaptive'.
  final String owner;
  final Map<String, String> params;

  void allowOnly(Set<String> keys) {
    final unknown = params.keys.where((k) => !keys.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw ArgumentError('$owner에 없는 파라미터: ${unknown.join(', ')}');
    }
  }

  double positive(String key, double fallback) {
    final raw = params[key];
    if (raw == null) return fallback;
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite || value <= 0) {
      throw ArgumentError('$key는 양수여야 합니다: $raw');
    }
    return value;
  }

  int positiveInt(String key, int fallback) {
    final raw = params[key];
    if (raw == null) return fallback;
    final value = int.tryParse(raw);
    if (value == null || value <= 0) throw ArgumentError('$key는 양의 정수여야 합니다: $raw');
    return value;
  }

  /// 켜고 끄는 스위치(절제 실험). true·false 또는 1·0만 받는다.
  bool flag(String key, bool fallback) {
    final raw = params[key];
    if (raw == null) return fallback;
    switch (raw.toLowerCase()) {
      case 'true' || '1':
        return true;
      case 'false' || '0':
        return false;
    }
    throw ArgumentError('$key는 true 또는 false여야 합니다: $raw');
  }
}
```

`lib/src/policies/step_budget_policy.dart`:

```dart
import 'dart:math' as math;

import '../events/policy_action.dart';
import '../events/policy_event.dart';
import '../geo.dart';
import '../model/fix.dart';
import 'collection_policy.dart';

/// 지금 정책이 보는 이동 상태. 이름이 fixes.csv의 state 열이 된다.
enum _Mode { unknown, walking, still, otherMotion, vehicle }

/// 측위를 요청한 까닭. 응답이 오면 이 까닭에 따라 다음 할 일을 정한다.
enum _Purpose { start, budget, stay, check, probe1, probe2, vehicle }

/// 제안 수집 정책(설계 5-3). 오차 예산 E 안에서 GPS를 가장 적게 켜도록, 실제로 움직인 만큼만 잰다.
/// - 보행: '마지막 측위 오차 + 그 뒤 걸음 수 × 보폭'이 E를 넘으면 잰다(time_speed는 시간 × 속도로 짐작한다).
/// - 정지: 정지가 30초 이어지면 한 번 재어 머문 곳을 남기고, 그 뒤로는 5분마다 확인만 한다. 확인한 위치가 머문
///   곳에서 벗어났으면 걸음 없이 움직이는 것(버스·지하철)으로 보고 탈것 상태로 바꾼다.
/// - 기타 움직임: 30초 이어지면 30초 간격 확인 측위 두 번으로 속도를 보고, 시속 12km 이상이면 탈것이다.
///   아니면 정지처럼 다룬다.
/// - 탈것: time_speed 규칙('오차 + 속도 × 경과 시간 > E'가 되는 시각에 잰다)으로 잰다. 걸음이 다시 나오면 보행이다.
/// - 측위가 거듭 실패하면(지하철·실내) 다시 시도하는 간격을 30초 → 1분 → 2분 → 5분으로 늘린다.
/// - 배터리가 20% 미만이면 E를 2배로 키운다.
class StepBudgetPolicy implements CollectionPolicy, ReportsState {
  StepBudgetPolicy({
    this.errorBudgetM = 50,
    this.strideM = 0.75,
    this.useSteps = true,
    this.suppressStill = true,
    this.vehicleProbe = true,
  });

  /// 오차 예산 E(m).
  final double errorBudgetM;

  /// 보폭(m). 걸음 수를 움직인 거리로 바꾼다.
  final double strideM;

  /// 절제 실험 스위치. false면 걸음 수 대신 '경과 시간 × 1.4m/s'로 움직인 거리를 짐작한다.
  final bool useSteps;

  /// 절제 실험 스위치. false면 정지해도 측위를 줄이지 않는다(걷기 속도로 움직인다고 보고 계속 잰다).
  final bool suppressStill;

  /// 절제 실험 스위치. false면 기타 움직임에서 탈것 확인 측위를 하지 않고 정지처럼 다룬다.
  final bool vehicleProbe;

  /// 걸음 수를 쓰지 않을 때 가정하는 걷기 속도(m/s, time_speed와 같은 값).
  static const walkingSpeedMps = 1.4;

  /// 이 속도(시속 12km) 이상으로 움직이면 탈것이다.
  static const vehicleSpeedMps = 12 / 3.6;
  /// 정지·기타 움직임이 이만큼 이어져야 그 상태로 측위한다. 폰을 만지거나 신호에 잠깐 멈출 때마다 상태가 몇 초
  /// 단위로 바뀌는데, 바뀔 때마다 재면 실제 세션의 첫 1분에만 15번을 쟀다.
  static const settleMs = 30000;
  static const stillCheckMs = 300000;
  static const probeGapMs = 30000;
  static const minWaitMs = 5000;
  static const maxWaitMs = 600000;
  static const retryDelaysMs = [30000, 60000, 120000, 300000];
  static const lowBatteryPct = 20;

  _Mode _mode = _Mode.unknown;
  _Purpose _purpose = _Purpose.start;
  bool _awaiting = false;
  int _failures = 0;
  int? _retryUntilMs;
  String? _retryTag;
  bool _lowBattery = false;

  /// 정지·느린 기타 움직임에서 기준으로 삼는 위치(머문 곳, 첫 확인 측위).
  Fix? _anchor;
  Fix? _previousVehicleFix;
  double _vehicleSpeedMps = 0;

  /// 지금 유효한 깨우기 예약. 상태가 바뀌면 지워서 앞 상태의 예약이 와도 무시한다(WakeAt은 취소할 수 없다).
  String? _armedTag;
  _Purpose _armedPurpose = _Purpose.budget;
  int _timerSeq = 0;

  @override
  String get id => 'step_budget';

  @override
  Map<String, Object> get params => {
        'e_m': errorBudgetM,
        'stride_m': strideM,
        'use_steps': useSteps,
        'suppress_still': suppressStill,
        'vehicle_probe': vehicleProbe,
      };

  @override
  String get stateLabel => _mode.name;

  double get _budget => errorBudgetM * (_lowBattery ? 2 : 1);

  @override
  List<PolicyAction> onStart(PolicyContext ctx) {
    // 같은 인스턴스를 다시 써도 이전 실행의 상태가 남지 않게 한다.
    _mode = _Mode.unknown;
    _awaiting = false;
    _failures = 0;
    _retryUntilMs = null;
    _retryTag = null;
    _lowBattery = false;
    _anchor = null;
    _previousVehicleFix = null;
    _vehicleSpeedMps = 0;
    _armedTag = null;
    return _request(_Purpose.start, ctx.nowMs);
  }

  @override
  List<PolicyAction> onEvent(PolicyEvent event, PolicyContext ctx) {
    switch (event) {
      case StepUpdate(:final state, :final stepsSinceLastFix):
        return _onStep(state, stepsSinceLastFix, event.tMs, ctx);
      case FixResult(:final fix):
        return fix == null ? _onFailure(event.tMs) : _onFix(fix, ctx);
      case Wakeup(:final tag):
        return _onWakeup(tag, event.tMs);
      case BatteryLevel(:final pct):
        _lowBattery = pct < lowBatteryPct;
        return const [];
      default:
        return const [];
    }
  }

  List<PolicyAction> _onStep(StepState state, int stepsSinceLastFix, int nowMs, PolicyContext ctx) {
    final next = switch (state) {
      StepState.walking => _Mode.walking,
      StepState.still => _Mode.still,
      // 탈것으로 판단한 뒤의 흔들림은 탈것 진동이다 — 다시 확인하지 않는다.
      StepState.otherMotion => _mode == _Mode.vehicle ? _Mode.vehicle : _Mode.otherMotion,
    };
    final actions = <PolicyAction>[];
    if (next != _mode) actions.addAll(_enter(next, nowMs, ctx));
    if (_mode == _Mode.walking && useSteps) {
      final accuracy = ctx.lastFix?.accuracyM ?? 0;
      if (accuracy + stepsSinceLastFix * strideM > _budget) {
        actions.addAll(_request(_Purpose.budget, nowMs));
      }
    }
    return actions;
  }

  List<PolicyAction> _enter(_Mode mode, int nowMs, PolicyContext ctx) {
    _mode = mode;
    // 앞 상태에서 낸 요청·예약은 이제 뜻이 없다. 기다리던 응답은 그냥 위치 하나로 받는다.
    _armedTag = null;
    _purpose = _Purpose.budget;
    switch (mode) {
      case _Mode.walking:
        return useSteps ? const [] : _armWalkingTimer(nowMs, ctx);
      case _Mode.still:
        return suppressStill ? _arm(_Purpose.stay, nowMs + settleMs) : _armWalkingTimer(nowMs, ctx);
      case _Mode.otherMotion:
        return _arm(vehicleProbe ? _Purpose.probe1 : _Purpose.stay, nowMs + settleMs);
      case _Mode.vehicle:
      case _Mode.unknown:
        return const [];
    }
  }

  List<PolicyAction> _onFix(Fix fix, PolicyContext ctx) {
    _awaiting = false;
    _failures = 0;
    _retryUntilMs = null;
    _retryTag = null;
    switch (_purpose) {
      case _Purpose.start:
      case _Purpose.budget:
        // 걸음 수를 쓰지 않는 보행·정지(절제 실험)는 다음 측위 시각을 다시 잡는다.
        return _usesWalkingTimer
            ? _arm(_Purpose.budget, fix.tMs + _waitMs(fix.accuracyM, walkingSpeedMps))
            : const [];
      case _Purpose.stay:
        _anchor = fix;
        return _arm(_Purpose.check, fix.tMs + stillCheckMs);
      case _Purpose.check:
        final anchor = _anchor;
        if (anchor != null && _moved(anchor, fix)) {
          // 걸음 없이 자리를 옮겼다 — 걸음이 나오지 않는 탈것(버스·지하철)이다.
          return _becomeVehicle(_speedBetween(anchor, fix), fix, ctx);
        }
        _anchor ??= fix;
        return _arm(_Purpose.check, fix.tMs + stillCheckMs);
      case _Purpose.probe1:
        _anchor = fix;
        return _arm(_Purpose.probe2, fix.tMs + probeGapMs);
      case _Purpose.probe2:
        final anchor = _anchor;
        final speed = anchor == null ? 0.0 : _speedBetween(anchor, fix);
        if (speed >= vehicleSpeedMps) return _becomeVehicle(speed, fix, ctx);
        // 느린 흔들림(폰 만지기 등)은 정지처럼 다룬다: 이 자리를 기준으로 5분마다 확인만 한다.
        _anchor = fix;
        return _arm(_Purpose.check, fix.tMs + stillCheckMs);
      case _Purpose.vehicle:
        final previous = _previousVehicleFix;
        if (previous != null && fix.tMs > previous.tMs) {
          _vehicleSpeedMps = _speedBetween(previous, fix);
        }
        _previousVehicleFix = fix;
        return _armVehicle(fix);
    }
  }

  List<PolicyAction> _becomeVehicle(double speedMps, Fix fix, PolicyContext ctx) {
    _enter(_Mode.vehicle, fix.tMs, ctx);
    _vehicleSpeedMps = speedMps;
    _previousVehicleFix = fix;
    return _armVehicle(fix);
  }

  /// time_speed 규칙: 지금 오차 + 속도 × 경과 시간이 예산을 넘는 시각에 다시 잰다. 탈것이라 판단한 속도
  /// 하한(시속 12km)을 둬, 신호 대기로 잠깐 멈춘 속도 때문에 너무 오래 쉬지 않게 한다.
  List<PolicyAction> _armVehicle(Fix fix) => _arm(_Purpose.vehicle,
      fix.tMs + _waitMs(fix.accuracyM, math.max(_vehicleSpeedMps, vehicleSpeedMps)));

  List<PolicyAction> _onFailure(int nowMs) {
    _awaiting = false;
    final delay = retryDelaysMs[math.min(_failures, retryDelaysMs.length - 1)];
    _failures++;
    _retryUntilMs = nowMs + delay;
    _timerSeq++;
    final tag = 'retry#$_timerSeq';
    _retryTag = tag;
    return [WakeAt(tMs: nowMs + delay, tag: tag)];
  }

  List<PolicyAction> _onWakeup(String tag, int nowMs) {
    if (tag == _retryTag) {
      _retryTag = null;
      _retryUntilMs = null;
      return _request(_purpose, nowMs);
    }
    if (tag != _armedTag) return const []; // 상태가 바뀌어 무효가 된 예약
    _armedTag = null;
    return _request(_armedPurpose, nowMs);
  }

  /// 측위를 요청한다. 응답을 기다리는 중이거나 실패 뒤 다시 시도할 시각 전이면 까닭만 바꾸고 기다린다 —
  /// 걸음이 계속 들어와도 지하철 안에서 GPS를 쉬지 않고 켜지 않게 한다.
  List<PolicyAction> _request(_Purpose purpose, int nowMs) {
    _purpose = purpose;
    if (_awaiting) return const [];
    final retryUntil = _retryUntilMs;
    if (retryUntil != null && nowMs < retryUntil) return const [];
    _awaiting = true;
    return const [RequestFix()];
  }

  List<PolicyAction> _arm(_Purpose purpose, int atMs) {
    _timerSeq++;
    final tag = '${purpose.name}#$_timerSeq';
    _armedTag = tag;
    _armedPurpose = purpose;
    return [WakeAt(tMs: atMs, tag: tag)];
  }

  bool get _usesWalkingTimer =>
      (_mode == _Mode.walking && !useSteps) || (_mode == _Mode.still && !suppressStill);

  /// 걸음 수를 쓰지 않을 때: 걷기 속도로 움직인다고 보고 오차가 예산을 넘는 시각에 깨운다.
  List<PolicyAction> _armWalkingTimer(int nowMs, PolicyContext ctx) {
    final last = ctx.lastFix;
    if (last == null) return _request(_Purpose.budget, nowMs);
    return _arm(_Purpose.budget, last.tMs + _waitMs(last.accuracyM, walkingSpeedMps));
  }

  int _waitMs(double accuracyM, double speedMps) {
    final remainingM = _budget - accuracyM;
    if (remainingM <= 0) return minWaitMs;
    return (remainingM / speedMps * 1000).round().clamp(minWaitMs, maxWaitMs);
  }

  bool _moved(Fix from, Fix to) =>
      haversineMeters(from.lat, from.lng, to.lat, to.lng) >
      math.max(_budget, from.accuracyM + to.accuracyM);

  double _speedBetween(Fix from, Fix to) {
    final seconds = (to.tMs - from.tMs) / 1000;
    if (seconds <= 0) return 0;
    return haversineMeters(from.lat, from.lng, to.lat, to.lng) / seconds;
  }
}
```

`lib/src/policies/policy_registry.dart` 전체(Task 1의 `still_suppress` 변경을 포함한다):

```dart
import '../params.dart';
import 'activity_gated_policy.dart';
import 'collection_policy.dart';
import 'continuous_policy.dart';
import 'fixed_interval_policy.dart';
import 'speed_adaptive_policy.dart';
import 'step_budget_policy.dart';
import 'still_suppress_policy.dart';
import 'time_speed_policy.dart';

/// 재생기 CLI와 정책 실행 모드가 받는 정책 id(설계 문서 5-3의 표). 마지막 `step_budget`이 제안 정책이다.
const policyIds = [
  'hourly', 'fixed_30s', 'fixed_1m', 'fixed_5m', 'continuous_10m',
  'speed_adaptive', 'time_speed', 'still_suppress', 'activity_gated', 'step_budget',
];

/// id와 파라미터(문자열 k=v)로 정책을 만든다. 모르는 id·파라미터, 양수가 아닌 숫자는 ArgumentError다.
CollectionPolicy createPolicy(String id, [Map<String, String> params = const {}]) {
  final reader = ParamReader('정책 $id', params);
  switch (id) {
    case 'hourly':
      reader.allowOnly(const {});
      return FixedIntervalPolicy(id: id, intervalMs: 3600000);
    case 'fixed_30s':
      reader.allowOnly(const {});
      return FixedIntervalPolicy(id: id, intervalMs: 30000);
    case 'fixed_1m':
      reader.allowOnly(const {});
      return FixedIntervalPolicy(id: id, intervalMs: 60000);
    case 'fixed_5m':
      reader.allowOnly(const {});
      return FixedIntervalPolicy(id: id, intervalMs: 300000);
    case 'continuous_10m':
      reader.allowOnly(const {});
      return ContinuousPolicy();
    case 'speed_adaptive':
      reader.allowOnly(const {});
      return SpeedAdaptivePolicy();
    case 'time_speed':
      reader.allowOnly(const {'e_m'});
      return TimeSpeedPolicy(errorBudgetM: reader.positive('e_m', 50));
    case 'still_suppress':
      reader.allowOnly(const {'interval_s', 'verify_s'});
      return StillSuppressPolicy(
        intervalMs: (reader.positive('interval_s', 60) * 1000).round(),
        verifyMs: (reader.positive('verify_s', 300) * 1000).round(),
      );
    case 'activity_gated':
      reader.allowOnly(const {});
      return ActivityGatedPolicy();
    case 'step_budget':
      reader.allowOnly(const {'e_m', 'stride_m', 'use_steps', 'suppress_still', 'vehicle_probe'});
      return StepBudgetPolicy(
        errorBudgetM: reader.positive('e_m', 50),
        strideM: reader.positive('stride_m', 0.75),
        useSteps: reader.flag('use_steps', true),
        suppressStill: reader.flag('suppress_still', true),
        vehicleProbe: reader.flag('vehicle_probe', true),
      );
    default:
      throw ArgumentError('알 수 없는 정책: $id (가능: ${policyIds.join(', ')})');
  }
}
```

`lib/footstep_core.dart`의 export 목록에서 `export 'src/policies/still_suppress_policy.dart';` 바로 앞에 더한다:

```dart
export 'src/policies/step_budget_policy.dart';
```

- [ ] **Step 4: 통과 확인**

Run: `dart test`(전체)와 `dart analyze` → 모두 통과, 0건.

**기대값과 다르면 상수나 규칙을 바꾸지 말고 멈춰서 보고한다(DONE_WITH_CONCERNS).** 이 테스트의 값은 시제품으로 그대로 검증했다.

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core/lib packages/footstep_core/test
git commit -m "feat(footstep_core): 걸음 수 오차 예산으로 측위하는 제안 정책 step_budget을 추가한다"
```

---

### Task 3: 폰 실행기 `PolicyRunner`

**Files:**
- Modify: `packages/footstep_core/lib/src/replay/accel_batches.dart`(전체 교체 — `AccelBatcher` 추가, `accelBatches`는 그 위에서)
- Create: `packages/footstep_core/lib/src/runner/runner_ports.dart`
- Create: `packages/footstep_core/lib/src/runner/run_summary.dart`
- Create: `packages/footstep_core/lib/src/runner/policy_runner.dart`
- Modify: `packages/footstep_core/lib/footstep_core.dart`(export 3줄)
- Test: `packages/footstep_core/test/runner/policy_runner_test.dart`
- Test: `packages/footstep_core/test/replay/accel_batches_test.dart`(테스트 1개 추가)

**Interfaces:**
- Consumes:
  - R2: `CollectionPolicy`, `ReportsState`, 사건·할 일, `FixRecord`, `ActionRecord`, `ReplaySchema`
  - R3: `StepDetector`
  - Task 2: `StepBudgetPolicy`(테스트)
- Produces:
  - `AccelBatcher(int batchMs)`
    - `List<AccelReading>? add(AccelReading)`
    - `List<AccelReading>? flush()`
    - 패키지 내부용이다.
  - `abstract interface class LocationPort`
    - `Future<Fix?> currentFix({required int timeoutMs})`
    - `Stream<Fix> continuousFixes({required int intervalMs, required double distanceFilterM})`
  - `abstract interface class WakeScheduler`
    - `Object schedule(int atMs, void Function() callback)`
    - `void cancel(Object handle)`
  - `class WakeupRecord({required int tMs, required String tag, required int scheduledMs})` + `delayMs`
  - `abstract interface class RunnerSink`: `fix(FixRecord)`, `action(ActionRecord)`, `wakeup(WakeupRecord)`
  - `abstract final class RunnerSchema`
    - `wakeupsFile = 'wakeups.csv'`
    - `wakeupsHeader = ['t_ms', 'tag', 'scheduled_ms', 'delay_ms']`
  - `class RunSummary(...)` + `toJson()`
    - 재생기 summary와 같은 키에 `wakeups`, `wake_delay_median_ms`, `wake_delay_max_ms`를 더한다.
  - `class PolicyRunner({required CollectionPolicy policy, required StepDetector detector, required LocationPort location, required WakeScheduler scheduler, required int Function() clock, required RunnerSink sink, int accelBatchMs = 1000})`
    - 메서드: `start()`, `addAccel`, `addOsStep`, `addActivity`, `addBatteryLevel(int tMs, int pct)`, `Future<RunSummary> stop()`
    - 속성: `isRunning`, `lastFix`, `fixCount`, `stepsSinceLastFix`, `stateLabel`

- [ ] **Step 1: 실패하는 테스트 작성**

`test/runner/policy_runner_test.dart`:

```dart
import 'dart:async';

import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

/// 시간을 손으로 넘기는 예약기. [runUntil]이 그 시각까지의 예약을 시각 순서로 부른다.
class _FakeScheduler implements WakeScheduler {
  final _entries = <({int handle, int atMs, void Function() callback})>[];
  int _next = 0;

  int get pending => _entries.length;

  @override
  Object schedule(int atMs, void Function() callback) {
    final handle = _next++;
    _entries.add((handle: handle, atMs: atMs, callback: callback));
    return handle;
  }

  @override
  void cancel(Object handle) => _entries.removeWhere((e) => e.handle == handle);

  void runUntil(int nowMs) {
    while (true) {
      final due = _entries.where((e) => e.atMs <= nowMs).toList()
        ..sort((a, b) => a.atMs.compareTo(b.atMs));
      if (due.isEmpty) return;
      _entries.remove(due.first);
      due.first.callback();
    }
  }
}

class _FakeLocation implements LocationPort {
  final requests = <({int timeoutMs, Completer<Fix?> completer})>[];
  final streams = <({int intervalMs, double distanceFilterM, StreamController<Fix> controller})>[];

  @override
  Future<Fix?> currentFix({required int timeoutMs}) {
    final completer = Completer<Fix?>();
    requests.add((timeoutMs: timeoutMs, completer: completer));
    return completer.future;
  }

  @override
  Stream<Fix> continuousFixes({required int intervalMs, required double distanceFilterM}) {
    final controller = StreamController<Fix>();
    streams.add((intervalMs: intervalMs, distanceFilterM: distanceFilterM, controller: controller));
    return controller.stream;
  }
}

class _Sink implements RunnerSink {
  final fixes = <FixRecord>[];
  final actions = <ActionRecord>[];
  final wakeups = <WakeupRecord>[];

  @override
  void fix(FixRecord record) => fixes.add(record);

  @override
  void action(ActionRecord record) => actions.add(record);

  @override
  void wakeup(WakeupRecord record) => wakeups.add(record);
}

/// 받은 사건을 모으고, 미리 정한 할 일을 돌려주는 정책.
class _Scripted implements CollectionPolicy {
  _Scripted({this.startActions = const [], this.respond});

  final List<PolicyAction> startActions;
  final List<PolicyAction> Function(PolicyEvent event)? respond;
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
    return respond?.call(event) ?? const [];
  }
}

Fix fixAt(int tMs) => Fix(tMs: tMs, lat: 37.5, lng: 127.0, accuracyM: 5);

AccelReading accel(int tMs) => AccelReading(tMs: tMs, x: 0, y: 9.81, z: 0);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late int now;
  late _FakeScheduler scheduler;
  late _FakeLocation location;
  late _Sink sink;

  PolicyRunner runner(CollectionPolicy policy, {StepDetector? detector}) => PolicyRunner(
        policy: policy,
        detector: detector ?? OsStepDetector(),
        location: location,
        scheduler: scheduler,
        clock: () => now,
        sink: sink,
      );

  setUp(() {
    now = 0;
    scheduler = _FakeScheduler();
    location = _FakeLocation();
    sink = _Sink();
  });

  test('RequestFix는 위치를 한 번 요청하고, 응답을 기록한 뒤 정책에 FixResult로 알린다', () async {
    final r = runner(TimeSpeedPolicy())..start();
    expect(location.requests.single.timeoutMs, 15000);
    expect(sink.actions.map((a) => a.action), [const RequestFix()]);

    now = 3000;
    location.requests.single.completer.complete(fixAt(3000));
    await settle();

    expect(sink.fixes.single.kind, 'single');
    expect(sink.fixes.single.state, 'still'); // OS 센서판 감지기의 처음 상태
    // TimeSpeed: (50 − 5) / 1.4 = 32.143초 뒤
    expect(sink.actions.last.action, const WakeAt(tMs: 35143, tag: 'next'));
    expect(r.lastFix?.tMs, 3000);
    expect(r.fixCount, 1);
  });

  test('WakeAt은 예약한 시각에 깨우고, 늦게 깬 만큼을 기록하며 실제로 깬 시각으로 알린다', () async {
    final policy = _Scripted(
      startActions: const [WakeAt(tMs: 10000, tag: 'tick')],
      respond: (e) => e is Wakeup ? const [RequestFix()] : const [],
    );
    runner(policy).start();

    now = 10500;
    scheduler.runUntil(now);

    expect(sink.wakeups.single.scheduledMs, 10000);
    expect(sink.wakeups.single.delayMs, 500);
    expect((policy.events.single as Wakeup).tMs, 10500);
    expect(location.requests, hasLength(1));
  });

  test('응답을 기다리는 중의 RequestFix는 합친다(위치 요청은 한 번)', () async {
    final r = runner(_Scripted(startActions: const [RequestFix(), RequestFix()]))..start();

    expect(sink.actions, hasLength(2));
    expect(location.requests, hasLength(1));
    final summary = await r.stop();
    expect(summary.fixRequests, 1);
  });

  test('위치를 못 받거나(null) 오류가 나면 실패로 세고 FixResult(null)을 알린다', () async {
    final policy = _Scripted(
      startActions: const [RequestFix()],
      respond: (e) => e is FixResult && e.failed ? const [RequestFix()] : const [],
    );
    final r = runner(policy)..start();

    now = 15000;
    location.requests.single.completer.complete(null);
    await settle();
    expect((policy.events.single as FixResult).failed, isTrue);

    now = 16000;
    location.requests.last.completer.completeError(StateError('위치 서비스 꺼짐'));
    await settle();
    expect(policy.events.whereType<FixResult>().where((e) => e.failed), hasLength(2));

    final summary = await r.stop();
    expect(summary.fixFailures, 2);
    expect(sink.fixes, isEmpty);
  });

  test('연속 측위는 간격·거리 필터로 구독하고 들어온 위치를 continuous로 기록하며, 끄면 켜진 시간을 센다', () async {
    final policy = _Scripted(
      startActions: const [StartContinuous(intervalMs: 1000, distanceFilterM: 10)],
      respond: (e) => e is ContinuousFix && e.tMs >= 2000 ? const [StopContinuous()] : const [],
    );
    final r = runner(policy)..start();
    final stream = location.streams.single;
    expect((stream.intervalMs, stream.distanceFilterM), (1000, 10.0));

    now = 1000;
    stream.controller.add(fixAt(1000));
    await settle();
    now = 2000;
    stream.controller.add(fixAt(2000));
    await settle();

    expect(sink.fixes.map((f) => (f.tMs, f.kind)), [(1000, 'continuous'), (2000, 'continuous')]);
    expect(stream.controller.hasListener, isFalse); // StopContinuous로 끊었다

    now = 5000;
    final summary = await r.stop();
    expect(summary.continuousFixes, 2);
    expect(summary.gpsOnMs, 2000);
  });

  test('가속도는 1초 묶음으로 걸음 감지기에 넣고, 나온 StepUpdate를 정책에 알린다', () async {
    final policy = _Scripted();
    final r = runner(policy, detector: AdaptiveStepDetector())..start();

    for (var t = 0; t <= 2000; t += 10) {
      r.addAccel(accel(t));
    }

    // 0~990ms 묶음이 1000ms 표본에서 닫히고, 1000~1990ms 묶음이 2000ms 표본에서 닫힌다.
    final updates = policy.events.whereType<StepUpdate>().toList();
    expect(updates.single.tMs, 990); // 정지를 처음 알린 묶음 끝
    expect(updates.single.state, StepState.still);
  });

  test('배터리 잔량은 바뀔 때만 알린다', () {
    final policy = _Scripted();
    final r = runner(policy)..start();

    r.addBatteryLevel(1000, 80);
    r.addBatteryLevel(31000, 80);
    r.addBatteryLevel(61000, 79);

    expect(policy.events.whereType<BatteryLevel>().map((e) => e.pct), [80, 79]);
  });

  test('위치를 알릴 때 그때까지의 걸음 수를 기록하고 걸음 감지기의 onFix를 부른다', () async {
    final r = runner(_Scripted(startActions: const [RequestFix()]))..start();
    r.addOsStep(const OsStepReading(tMs: 100, kind: OsStepReading.count, value: '100'));
    r.addOsStep(const OsStepReading(tMs: 200, kind: OsStepReading.count, value: '112'));
    expect(r.stepsSinceLastFix, 12);

    now = 3000;
    location.requests.single.completer.complete(fixAt(3000));
    await settle();

    expect(sink.fixes.single.stepsSincePrev, 12);
    expect(sink.fixes.single.state, 'walking');
    expect(r.stepsSinceLastFix, 0);
  });

  test('stop은 예약을 취소하고 그 뒤에 온 응답을 무시하며, 요약을 돌려준다', () async {
    final policy = _Scripted(startActions: const [RequestFix(), WakeAt(tMs: 60000, tag: 'tick')]);
    final r = runner(policy)..start();
    expect(scheduler.pending, 1);

    now = 4000;
    final summary = await r.stop();
    expect(scheduler.pending, 0);
    expect(summary.fixRequests, 1);
    expect(summary.gpsOnMs, 4000); // 응답을 기다리던 동안
    expect(summary.endMs, 4000);
    expect(summary.toJson()['policy_id'], 'scripted');

    location.requests.single.completer.complete(fixAt(5000));
    await settle();
    expect(sink.fixes, isEmpty);
    expect(policy.events, isEmpty);
  });

  test('제안 정책은 실행기에서도 상태 이름(ReportsState)을 기록에 남긴다', () async {
    final r = runner(StepBudgetPolicy())..start();
    expect(r.stateLabel, 'unknown');

    now = 2000;
    location.requests.single.completer.complete(fixAt(2000));
    await settle();
    expect(sink.fixes.single.state, 'unknown');
  });
}
```

`test/replay/accel_batches_test.dart`: import에 `import 'package:footstep_core/src/replay/accel_batches.dart';`가 이미 있다. `main()`의 닫는 중괄호 바로 앞에 더한다:

```dart
  test('AccelBatcher는 묶음이 닫힐 때만 돌려주고, flush로 남은 표본을 낸다(폰 실행기용 실시간판)', () {
    final batcher = AccelBatcher(1000);
    final closed = <(int, int)>[];
    for (var t = 0; t <= 2500; t += 10) {
      final batch = batcher.add(AccelReading(tMs: t, x: 0, y: 9.8, z: 0));
      if (batch != null) closed.add((batch.first.tMs, batch.last.tMs));
    }
    expect(closed, [(0, 990), (1000, 1990)]);
    final rest = batcher.flush()!;
    expect((rest.first.tMs, rest.last.tMs), (2000, 2500));
    expect(batcher.flush(), isNull);
  });
```

- [ ] **Step 2: 실패 확인**

Run: `dart test test/runner/ test/replay/accel_batches_test.dart`
Expected: 컴파일 오류(`PolicyRunner`, `AccelBatcher` 없음)

- [ ] **Step 3: 구현**

`lib/src/replay/accel_batches.dart` 전체:

```dart
import '../model/readings.dart';

/// 가속도를 [batchMs] 길이 묶음으로 모은다(실시간판). 앞 묶음이 시작된 뒤 [batchMs]가 지난 표본이 오면 앞 묶음을
/// 닫는다. 재생기([accelBatches])와 폰 실행기가 이 하나의 규칙을 같이 쓴다 — 제안 감지기의 출력은 묶음 크기에
/// 따라 달라져서(R3), 둘이 다르게 묶으면 재생 결과와 실기기 동작이 어긋난다.
class AccelBatcher {
  AccelBatcher(this.batchMs);

  final int batchMs;

  var _batch = <AccelReading>[];
  int? _windowStart;

  /// [reading]을 넣는다. 이 표본 때문에 앞 묶음이 닫히면 그 묶음을 돌려준다.
  List<AccelReading>? add(AccelReading reading) {
    final start = _windowStart ??= reading.tMs;
    List<AccelReading>? closed;
    if (reading.tMs - start >= batchMs && _batch.isNotEmpty) {
      closed = _batch;
      _batch = <AccelReading>[];
      _windowStart = reading.tMs;
    }
    _batch.add(reading);
    return closed;
  }

  /// 남은 표본을 마지막 묶음으로 돌려준다. 없으면 null이다.
  List<AccelReading>? flush() {
    if (_batch.isEmpty) return null;
    final rest = _batch;
    _batch = <AccelReading>[];
    _windowStart = null;
    return rest;
  }
}

/// 가속도를 [batchMs] 길이 묶음으로 나눈다([AccelBatcher]와 같은 규칙). 재생기와 걸음 감지 평가가 쓴다.
Iterable<List<AccelReading>> accelBatches(List<AccelReading> accel, int batchMs) sync* {
  final batcher = AccelBatcher(batchMs);
  for (final reading in accel) {
    final closed = batcher.add(reading);
    if (closed != null) yield closed;
  }
  final rest = batcher.flush();
  if (rest != null) yield rest;
}
```

`lib/src/runner/runner_ports.dart`:

```dart
import '../model/fix.dart';
import '../replay/replay_result.dart';

/// 실행기가 GPS를 다루는 창구. 폰에서는 geolocator, 테스트에서는 가짜를 넣는다.
abstract interface class LocationPort {
  /// 위치를 한 번 받는다. [timeoutMs] 안에 못 받으면 null이다.
  Future<Fix?> currentFix({required int timeoutMs});

  /// 연속 측위. [intervalMs]·[distanceFilterM]은 기기의 위치 요청 설정으로 넘긴다. 구독을 끊으면 GPS를 끈다.
  Stream<Fix> continuousFixes({required int intervalMs, required double distanceFilterM});
}

/// 깨우기 예약. 폰에서는 Timer, 테스트에서는 시간을 손으로 넘기는 가짜를 쓴다.
abstract interface class WakeScheduler {
  /// [atMs](UTC epoch ms, 지났으면 바로)에 [callback]을 부른다. [schedule] 안에서 바로 부르지는 않는다.
  /// 돌려준 값을 [cancel]에 넘겨 취소한다.
  Object schedule(int atMs, void Function() callback);

  void cancel(Object handle);
}

/// 깨우기 하나의 기록(wakeups.csv의 행). 화면이 꺼지면 타이머가 늦게 깰 수 있어(설계 10장 위험 3) 예약 시각과
/// 실제 깬 시각을 함께 남긴다.
class WakeupRecord {
  const WakeupRecord({required this.tMs, required this.tag, required this.scheduledMs});

  /// 실제로 깬 시각.
  final int tMs;
  final String tag;
  final int scheduledMs;

  int get delayMs => tMs - scheduledMs;
}

/// 실행기가 남기는 기록을 받는 곳. 폰에서는 세션 폴더의 CSV에 쓴다.
abstract interface class RunnerSink {
  void fix(FixRecord record);

  void action(ActionRecord record);

  void wakeup(WakeupRecord record);
}

/// 정책 실행 모드가 세션 폴더에 쓰는 파일 중 재생기에 없는 것(R6 분석이 읽는다). fixes.csv·actions.csv는
/// 재생기와 같은 형식([ReplaySchema])이다.
abstract final class RunnerSchema {
  static const wakeupsFile = 'wakeups.csv';
  static const wakeupsHeader = ['t_ms', 'tag', 'scheduled_ms', 'delay_ms'];
}
```

`lib/src/runner/run_summary.dart`:

```dart
/// 폰에서 정책을 한 번 돌린 요약(정책 실행 모드의 summary.json). 키는 재생기 요약과 맞춰 R6 분석이 두 결과를
/// 같은 코드로 읽게 한다. 재생기에 없는 깨우기 지연을 더한다.
class RunSummary {
  const RunSummary({
    required this.policyId,
    required this.policyParams,
    required this.detectorId,
    required this.detectorParams,
    required this.startMs,
    required this.endMs,
    required this.fixRequests,
    required this.fixSuccesses,
    required this.fixFailures,
    required this.continuousFixes,
    required this.gpsOnMs,
    required this.wakeDelaysMs,
  });

  final String policyId;
  final Map<String, Object> policyParams;
  final String detectorId;
  final Map<String, Object> detectorParams;
  final int startMs;
  final int endMs;
  final int fixRequests;
  final int fixSuccesses;
  final int fixFailures;
  final int continuousFixes;

  /// 추정 GPS 켜짐 시간. 단발은 요청~응답, 연속은 켠 때~끈 때. 실기기 배터리 결과와 견주는 보조 지표다.
  final int gpsOnMs;

  /// 깨우기마다 예약보다 늦게 깬 시간(ms).
  final List<int> wakeDelaysMs;

  int get durationMs => endMs - startMs;

  int get totalFixes => fixSuccesses + continuousFixes;

  Map<String, Object?> toJson() {
    final delays = [...wakeDelaysMs]..sort();
    return {
      'policy_id': policyId,
      'policy_params': policyParams,
      'detector_id': detectorId,
      'detector_params': detectorParams,
      'start_ms': startMs,
      'end_ms': endMs,
      'duration_s': durationMs / 1000,
      'fix_requests': fixRequests,
      'fix_successes': fixSuccesses,
      'fix_failures': fixFailures,
      'continuous_fixes': continuousFixes,
      'total_fixes': totalFixes,
      'gps_on_s': gpsOnMs / 1000,
      'fixes_per_hour': durationMs == 0 ? 0 : totalFixes / (durationMs / 3600000),
      'wakeups': delays.length,
      'wake_delay_median_ms': delays.isEmpty ? null : delays[delays.length ~/ 2],
      'wake_delay_max_ms': delays.isEmpty ? null : delays.last,
    };
  }
}
```

`lib/src/runner/policy_runner.dart`:

```dart
import 'dart:async';
import 'dart:math' as math;

import '../detectors/step_detector.dart';
import '../events/policy_action.dart';
import '../events/policy_event.dart';
import '../model/fix.dart';
import '../model/readings.dart';
import '../policies/collection_policy.dart';
import '../replay/accel_batches.dart';
import '../replay/replay_result.dart';
import 'run_summary.dart';
import 'runner_ports.dart';

/// 폰에서 정책을 실제로 돌리는 실행기(설계 5-5, R4 정책 실행 모드·R7 여행 기록이 같이 쓴다).
/// 재생기와 같은 규칙으로 할 일을 실제 동작으로 바꾼다.
/// - RequestFix → 위치 한 번. 응답을 기다리는 중의 새 요청은 합친다.
/// - StartContinuous·StopContinuous → 연속 측위 구독·해제.
/// - WakeAt → 타이머. 실제로 깬 시각으로 Wakeup을 보내고, 늦게 깬 만큼을 기록한다.
/// 위치를 알릴 때는 그때까지의 걸음 수와 상태를 기록하고 걸음 감지기의 onFix를 부른다. 가속도는 재생기와 같은
/// 1초 묶음([AccelBatcher])으로 걸음 감지기에 넣는다. 시계·GPS·타이머는 밖에서 넣어, 테스트가 시간을 손으로 넘긴다.
class PolicyRunner {
  PolicyRunner({
    required this.policy,
    required this.detector,
    required this.location,
    required this.scheduler,
    required this.clock,
    required this.sink,
    int accelBatchMs = 1000,
  }) : _batcher = AccelBatcher(accelBatchMs);

  final CollectionPolicy policy;
  final StepDetector detector;
  final LocationPort location;
  final WakeScheduler scheduler;

  /// 지금 시각(UTC epoch ms).
  final int Function() clock;
  final RunnerSink sink;
  final AccelBatcher _batcher;

  bool _running = false;
  int _startMs = 0;
  Fix? _lastFix;
  int? _lastBatteryPct;

  bool _fixPending = false;
  int _requestStartMs = 0;
  StreamSubscription<Fix>? _continuous;
  int _continuousSinceMs = 0;
  final _wakeHandles = <Object>{};

  int _fixRequests = 0;
  int _fixSuccesses = 0;
  int _fixFailures = 0;
  int _continuousFixes = 0;
  int _gpsOnMs = 0;
  final _wakeDelaysMs = <int>[];

  bool get isRunning => _running;

  Fix? get lastFix => _lastFix;

  int get fixCount => _fixSuccesses + _continuousFixes;

  int get stepsSinceLastFix => detector.stepsSinceLastFix;

  /// fixes.csv의 state 열과 같은 이름. 정책이 상태를 알리면(ReportsState) 그것을, 아니면 걸음 감지기 상태를 쓴다.
  String get stateLabel {
    if (policy case ReportsState(:final stateLabel)) return stateLabel;
    return detector.state.name;
  }

  void start() {
    if (_running) return;
    _running = true;
    _startMs = clock();
    _apply(policy.onStart(_ctx()));
  }

  void addAccel(AccelReading reading) {
    if (!_running) return;
    final batch = _batcher.add(reading);
    if (batch != null) _deliverStep(detector.onAccel(batch.last.tMs, batch));
  }

  void addOsStep(OsStepReading reading) {
    if (!_running) return;
    _deliverStep(detector.onOsStep(reading));
  }

  void addActivity(ActivityReading reading) {
    if (!_running) return;
    _deliver(ActivityUpdate(tMs: reading.tMs, type: reading.type, confidence: reading.confidence));
  }

  /// 배터리 잔량은 바뀔 때만 정책에 알린다(재생기와 같은 규칙).
  void addBatteryLevel(int tMs, int pct) {
    if (!_running || pct == _lastBatteryPct) return;
    _lastBatteryPct = pct;
    _deliver(BatteryLevel(tMs: tMs, pct: pct));
  }

  /// 멈추고 요약을 돌려준다. 예약한 깨우기를 취소하고 연속 측위를 끊는다. 그 뒤에 오는 응답은 무시한다.
  Future<RunSummary> stop() async {
    final now = clock();
    if (_running) {
      _running = false;
      for (final handle in _wakeHandles) {
        scheduler.cancel(handle);
      }
      _wakeHandles.clear();
      final continuous = _continuous;
      if (continuous != null) {
        _gpsOnMs += now - _continuousSinceMs;
        _continuous = null;
        await continuous.cancel();
      }
      if (_fixPending) {
        _gpsOnMs += now - _requestStartMs;
        _fixPending = false;
      }
    }
    return RunSummary(
      policyId: policy.id,
      policyParams: policy.params,
      detectorId: detector.id,
      detectorParams: detector.params,
      startMs: _startMs,
      endMs: now,
      fixRequests: _fixRequests,
      fixSuccesses: _fixSuccesses,
      fixFailures: _fixFailures,
      continuousFixes: _continuousFixes,
      gpsOnMs: _gpsOnMs,
      wakeDelaysMs: List.unmodifiable(_wakeDelaysMs),
    );
  }

  PolicyContext _ctx() => PolicyContext(nowMs: clock(), lastFix: _lastFix);

  void _deliverStep(StepUpdate? update) {
    if (update != null) _deliver(update);
  }

  void _deliver(PolicyEvent event) => _apply(policy.onEvent(event, _ctx()));

  void _apply(List<PolicyAction> actions) {
    for (final action in actions) {
      if (!_running) return;
      sink.action(ActionRecord(tMs: clock(), action: action));
      switch (action) {
        case RequestFix(:final timeoutMs):
          _requestFix(timeoutMs);
        case final StartContinuous settings:
          _startContinuous(settings);
        case StopContinuous():
          _stopContinuous();
        case WakeAt(:final tMs, :final tag):
          _scheduleWake(tMs, tag);
      }
    }
  }

  void _requestFix(int timeoutMs) {
    // 응답을 기다리는 중이면 새로 켜지 않는다 — 재생기와 같은 규칙이고, 실제 기기도 진행 중인 요청에 합친다.
    if (_fixPending) return;
    _fixPending = true;
    _fixRequests++;
    _requestStartMs = clock();
    unawaited(location
        .currentFix(timeoutMs: timeoutMs)
        .catchError((Object _) => null) // 위치 서비스 오류도 실패로 다룬다(정책이 다시 시도할 수 있게)
        .then(_onFixResult));
  }

  void _onFixResult(Fix? fix) {
    if (!_running || !_fixPending) return;
    final now = clock();
    _fixPending = false;
    _gpsOnMs += now - _requestStartMs;
    if (fix == null) {
      _fixFailures++;
    } else {
      _fixSuccesses++;
      _record(fix, 'single');
    }
    _deliver(FixResult(tMs: now, fix: fix));
  }

  void _startContinuous(StartContinuous settings) {
    final now = clock();
    final previous = _continuous;
    if (previous != null) {
      // 켜져 있는데 다시 받으면 설정을 바꿔 새로 켠다(재생기와 같은 규칙).
      _gpsOnMs += now - _continuousSinceMs;
      unawaited(previous.cancel());
    }
    _continuousSinceMs = now;
    _continuous = location
        .continuousFixes(intervalMs: settings.intervalMs, distanceFilterM: settings.distanceFilterM)
        .listen(_onContinuousFix, onError: (Object _) {});
  }

  void _stopContinuous() {
    final continuous = _continuous;
    if (continuous == null) return;
    _gpsOnMs += clock() - _continuousSinceMs;
    _continuous = null;
    unawaited(continuous.cancel());
  }

  void _onContinuousFix(Fix fix) {
    if (!_running) return;
    _continuousFixes++;
    _record(fix, 'continuous');
    _deliver(ContinuousFix(tMs: fix.tMs, fix: fix));
  }

  void _record(Fix fix, String kind) {
    sink.fix(FixRecord(
      fix: fix,
      stepsSincePrev: detector.stepsSinceLastFix,
      state: stateLabel,
      kind: kind,
    ));
    detector.onFix();
    _lastFix = fix;
  }

  void _scheduleWake(int atMs, String tag) {
    late final Object handle;
    handle = scheduler.schedule(atMs, () {
      _wakeHandles.remove(handle);
      if (!_running) return;
      final now = clock();
      final record = WakeupRecord(tMs: now, tag: tag, scheduledMs: atMs);
      sink.wakeup(record);
      _wakeDelaysMs.add(math.max(0, record.delayMs));
      // 정책은 실제로 깬 시각을 받는다. 늦게 깨도 다음 예약이 그 시각 기준으로 잡혀 한꺼번에 몰리지 않는다.
      _deliver(Wakeup(tMs: now, tag: tag));
    });
    _wakeHandles.add(handle);
  }
}
```

`lib/footstep_core.dart`의 export 목록에서 `export 'src/replay/replay_result.dart';` 다음에 더한다(알파벳 순서):

```dart
export 'src/runner/policy_runner.dart';
export 'src/runner/run_summary.dart';
export 'src/runner/runner_ports.dart';
```

- [ ] **Step 4: 통과 확인**

Run: `dart test`(전체, 재생기·걸음 평가 테스트가 그대로 통과해야 한다 — 묶음 규칙이 같다)와 `dart analyze` → 0건.

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core/lib packages/footstep_core/test
git commit -m "feat(footstep_core): 폰에서 정책을 돌리는 실행기와 실시간 가속도 묶기를 추가한다"
```

---

### Task 4: 앱 — 정책 실행 기록기

**Files:**
- Create: `app/lib/features/footsteps/recording/session_recorder.dart`
- Modify: `app/lib/features/footsteps/recording/ground_truth_recorder.dart`(implements + @override)
- Modify: `app/lib/features/footsteps/recording/recorder_status.dart`(전체 교체)
- Create: `app/lib/features/footsteps/recording/policy_choice.dart`
- Create: `app/lib/features/footsteps/recording/policy_session_files.dart`
- Create: `app/lib/features/footsteps/recording/policy_recorder.dart`
- Test: `app/test/footsteps/recording/policy_choice_test.dart`
- Test: `app/test/footsteps/recording/policy_recorder_test.dart`

**Interfaces:**
- Consumes:
  - Task 3: `PolicyRunner`, `LocationPort`, `WakeScheduler`, `RunnerSink`, `RunnerSchema`
  - R2: `ReplaySchema`, `createPolicy`, `createDetector`
  - R1: `SensorSources`, `CsvWriter`, `FieldState`, `Mark`, `SessionError`, `SessionSchema`
- Produces:
  - `abstract interface class SessionRecorder`
    - `field`, `start()`, `tick()`, `mark(Mark)`, `status`, `stop()`
    - `GroundTruthRecorder`가 구현한다.
  - `RecorderStatus.policyState`(String?), `RecorderStatus.stepsSinceFix`(int?)
    - JSON 키도 같은 이름이다.
  - `class PolicyChoice({required String policyId, required String detectorId, Map<String, String> policyParams = const {}, Map<String, String> detectorParams = const {}})`
    - `toJson`·`fromJson`과 값 비교를 한다.
  - `class PolicySensorNeeds({accel, osSteps, activity})`, `PolicySensorNeeds.of(PolicyChoice)`, `stepPolicyIds = {'still_suppress', 'step_budget'}`
  - `class PolicySessionFiles`
    - `static Future<PolicySessionFiles> open(Directory)`
    - writer: `fixes`, `actions`, `wakeups`, `battery`, `marks`
    - `summaryFile`, `flushAll()`, `closeAll()`
  - `class PolicyRecorder({required SensorSources sources, required PolicySessionFiles files, required DateTime Function() clock, required void Function(SessionError) onError, required CollectionPolicy policy, required StepDetector detector, required LocationPort location, required WakeScheduler scheduler, required PolicySensorNeeds needs, Duration batteryInterval = const Duration(seconds: 30)}) implements SessionRecorder`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/footsteps/recording/policy_choice_test.dart`:

```dart
import 'package:app/features/footsteps/recording/policy_choice.dart';
import 'package:app/features/footsteps/recording/recorder_status.dart';
import 'package:app/features/footsteps/recording/recording_messages.dart';
import 'package:flutter_test/flutter_test.dart';

const _choice = PolicyChoice(
  policyId: 'step_budget',
  policyParams: {'e_m': '25'},
  detectorId: 'adaptive',
  detectorParams: {'n_confirm': '6'},
);

void main() {
  test('고른 정책은 json으로 오가고 값으로 비교한다', () {
    final back = PolicyChoice.fromJson(_choice.toJson());
    expect(back, _choice);
    expect(back.hashCode, _choice.hashCode);
    expect(back == const PolicyChoice(policyId: 'step_budget', detectorId: 'adaptive'), isFalse);
  });

  test('걸음 정보를 쓰는 정책만 걸음 감지기의 센서를 켜고, 활동 인식은 activity_gated만 켠다', () {
    PolicySensorNeeds needs(String policy, String detector) =>
        PolicySensorNeeds.of(PolicyChoice(policyId: policy, detectorId: detector));

    final adaptive = needs('step_budget', 'adaptive');
    expect((adaptive.accel, adaptive.osSteps, adaptive.activity), (true, false, false));
    final os = needs('still_suppress', 'os');
    expect((os.accel, os.osSteps, os.activity), (false, true, false));
    final fixed = needs('fixed_1m', 'adaptive');
    expect((fixed.accel, fixed.osSteps, fixed.activity), (false, false, false));
    final gated = needs('activity_gated', 'os');
    expect((gated.accel, gated.osSteps, gated.activity), (false, false, true));
  });

  test('상태 메시지는 정책 상태와 측위 뒤 걸음 수를 함께 오가고, 키가 없으면 null이다', () {
    final status = RecorderStatus(
      startedAt: DateTime.utc(2026, 11, 11),
      rowCounts: const {'fixes.csv': 3},
      errorCount: 0,
      atPlace: false,
      onVehicle: false,
      policyState: 'walking',
      stepsSinceFix: 42,
    );
    final back = decodeStatusMessage(encodeStatusMessage(status))!;
    expect(back.policyState, 'walking');
    expect(back.stepsSinceFix, 42);

    final old = RecorderStatus(
      startedAt: DateTime.utc(2026, 11, 11),
      rowCounts: const {},
      errorCount: 0,
      atPlace: false,
      onVehicle: false,
    );
    expect(decodeStatusMessage(encodeStatusMessage(old))!.policyState, isNull);
  });
}
```

`app/test/footsteps/recording/policy_recorder_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/footsteps/recording/mark.dart';
import 'package:app/features/footsteps/recording/policy_choice.dart';
import 'package:app/features/footsteps/recording/policy_recorder.dart';
import 'package:app/features/footsteps/recording/policy_session_files.dart';
import 'package:app/features/footsteps/recording/sensor_samples.dart';
import 'package:app/features/footsteps/recording/session_meta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footstep_core/footstep_core.dart';
import 'package:path/path.dart' as p;

class _FakeSources implements SensorSources {
  _FakeSources(this.clock);

  final DateTime Function() clock;
  final gpsController = StreamController<GpsSample>();
  final accelController = StreamController<AccelSample>();
  final stepsController = StreamController<OsStepSample>();
  final activityController = StreamController<ActivitySample>();
  int batteryLevel = 87;
  int batteryReads = 0;

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
    batteryReads++;
    return BatterySample(
      at: clock(),
      chargeUah: 3012000,
      currentUa: -180,
      levelPct: batteryLevel,
      tempC: 31.5,
      plugged: false,
    );
  }
}

class _FakeLocation implements LocationPort {
  final requests = <Completer<Fix?>>[];

  @override
  Future<Fix?> currentFix({required int timeoutMs}) {
    final completer = Completer<Fix?>();
    requests.add(completer);
    return completer.future;
  }

  @override
  Stream<Fix> continuousFixes({required int intervalMs, required double distanceFilterM}) =>
      const Stream.empty();
}

class _FakeScheduler implements WakeScheduler {
  final scheduled = <({int atMs, void Function() callback})>[];

  @override
  Object schedule(int atMs, void Function() callback) {
    final entry = (atMs: atMs, callback: callback);
    scheduled.add(entry);
    return entry;
  }

  @override
  void cancel(Object handle) => scheduled.remove(handle);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late Directory dir;
  late DateTime now;
  late _FakeSources sources;
  late _FakeLocation location;
  late _FakeScheduler scheduler;
  late PolicySessionFiles files;
  late List<SessionError> errors;

  List<String> lines(String name) => File(p.join(dir.path, name)).readAsLinesSync();

  Future<PolicyRecorder> recorder(PolicyChoice choice) async {
    files = await PolicySessionFiles.open(dir);
    return PolicyRecorder(
      sources: sources,
      files: files,
      clock: () => now,
      onError: errors.add,
      policy: createPolicy(choice.policyId, choice.policyParams),
      detector: createDetector(choice.detectorId, choice.detectorParams),
      location: location,
      scheduler: scheduler,
      needs: PolicySensorNeeds.of(choice),
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('policy_recorder_test');
    now = DateTime.utc(2026, 11, 11, 1);
    sources = _FakeSources(() => now);
    location = _FakeLocation();
    scheduler = _FakeScheduler();
    errors = [];
  });

  tearDown(() async {
    await files.closeAll();
    await dir.delete(recursive: true);
  });

  test('정책 실행 모드는 정책이 쓰는 센서만 켜고, 측위 결과·할 일·배터리를 재생기와 같은 형식으로 쓴다', () async {
    final r = await recorder(const PolicyChoice(policyId: 'step_budget', detectorId: 'adaptive'));
    await r.start();

    expect(sources.accelController.hasListener, isTrue);
    expect(sources.stepsController.hasListener, isFalse);
    expect(sources.activityController.hasListener, isFalse);
    expect(sources.gpsController.hasListener, isFalse); // 1초 GPS는 쓰지 않는다
    expect(location.requests, hasLength(1)); // step_budget은 시작하자마자 한 번 잰다

    final t0 = now.millisecondsSinceEpoch;
    now = now.add(const Duration(seconds: 3));
    location.requests.single.complete(
        Fix(tMs: now.millisecondsSinceEpoch, lat: 37.5665, lng: 126.978, accuracyM: 6.5));
    await _settle();
    await r.tick();

    final t1 = now.millisecondsSinceEpoch;
    expect(lines('fixes.csv'), [
      't_ms,lat,lng,accuracy_m,steps_since_prev,state,kind',
      '$t1,37.5665,126.978,6.5,0,unknown,single',
    ]);
    expect(lines('actions.csv'), ['t_ms,action,args', '$t0,request_fix,timeout_ms=15000']);
    expect(lines('battery.csv')[1], '$t0,3012000,-180,87,31.5,0');
    expect(lines('wakeups.csv'), ['t_ms,tag,scheduled_ms,delay_ms']);

    final status = r.status;
    expect(status.policyState, 'unknown');
    expect(status.lastGpsAccuracyM, 6.5);
    expect(status.rowCounts['fixes.csv'], 1);
  });

  test('걸음을 쓰지 않는 정책은 걸음 센서를 켜지 않고, activity_gated는 활동 인식만 켠다', () async {
    final fixed = await recorder(const PolicyChoice(policyId: 'fixed_1m', detectorId: 'adaptive'));
    await fixed.start();
    expect(sources.accelController.hasListener, isFalse);
    expect(sources.stepsController.hasListener, isFalse);
    expect(sources.activityController.hasListener, isFalse);
    await fixed.stop();

    sources = _FakeSources(() => now);
    final gated = await recorder(const PolicyChoice(policyId: 'activity_gated', detectorId: 'os'));
    await gated.start();
    expect(sources.activityController.hasListener, isTrue);
    expect(sources.stepsController.hasListener, isFalse);
  });

  test('관찰 표시는 marks.csv에 쓰고 알림 버튼 상태에 반영한다', () async {
    final r = await recorder(const PolicyChoice(policyId: 'fixed_1m', detectorId: 'os'));
    await r.start();
    r.mark(Mark(at: now, kind: MarkKind.board, value: 'bus'));
    await r.tick();

    expect(lines('marks.csv')[1], '${now.millisecondsSinceEpoch},board,bus');
    expect(r.field.onVehicle, isTrue);
  });

  test('stop하면 summary.json을 쓰고, 예약한 깨우기를 거둔다', () async {
    final r = await recorder(const PolicyChoice(policyId: 'fixed_1m', detectorId: 'os'));
    await r.start();
    expect(scheduler.scheduled, hasLength(1)); // 1분 뒤 다음 측위

    now = now.add(const Duration(minutes: 2));
    await r.stop();

    expect(scheduler.scheduled, isEmpty);
    final summary =
        jsonDecode(File(p.join(dir.path, 'summary.json')).readAsStringSync()) as Map<String, Object?>;
    expect(summary['policy_id'], 'fixed_1m');
    expect(summary['detector_id'], 'os');
    expect(summary['fix_requests'], 1);
    expect(summary['duration_s'], 120.0);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run (`app/`에서): `flutter test test/footsteps/recording/policy_choice_test.dart test/footsteps/recording/policy_recorder_test.dart`
Expected: 컴파일 오류(파일 없음)

- [ ] **Step 3: 구현**

`lib/features/footsteps/recording/session_recorder.dart`:

```dart
import 'mark.dart';
import 'recorder_status.dart';

/// 기록 서비스가 모드와 상관없이 기록기를 다루는 창구(정답 기록·정책 실행). 서비스는 시작·5초 tick·관찰 표시·
/// 종료만 알면 되고, 어떤 센서를 켜고 무엇을 쓸지는 모드별 기록기가 정한다.
abstract interface class SessionRecorder {
  /// 지금 장소 안인지, 탈것에 탔는지. 알림 버튼 토글이 다음 표시를 정할 때 쓴다.
  FieldState get field;

  Future<void> start();

  /// 서비스의 반복 이벤트(5초)마다 부른다. 배터리 읽기와 디스크 쓰기를 맡긴다.
  Future<void> tick();

  void mark(Mark mark);

  RecorderStatus get status;

  Future<void> stop();
}
```

`lib/features/footsteps/recording/ground_truth_recorder.dart`:
1. `import 'session_schema.dart';` 바로 앞에 `import 'session_recorder.dart';`를 더한다.
2. `class GroundTruthRecorder {`를 `class GroundTruthRecorder implements SessionRecorder {`로 바꾼다.
3. 다음 여섯 멤버 바로 위에 각각 `@override` 줄을 더한다. 해당 줄은 `final FieldState field = FieldState();`, `Future<void> start() async {`, `Future<void> tick() async {`, `void mark(Mark mark) {`, `RecorderStatus get status {`, `Future<void> stop() async {`이다. 기존 문서 주석이 있으면 주석과 선언 사이에 넣는다.

`lib/features/footsteps/recording/recorder_status.dart` 전체:

```dart
/// 기록 서비스가 5초마다 화면에 보내는 상태. 실험 화면이 "센서가 지금 값을 내고 있는가"를 보여 준다.
class RecorderStatus {
  const RecorderStatus({
    required this.startedAt,
    required this.rowCounts,
    required this.errorCount,
    required this.atPlace,
    required this.onVehicle,
    this.carry,
    this.lastGpsAccuracyM,
    this.lastOsSteps,
    this.lastChargeUah,
    this.lastLevelPct,
    this.policyState,
    this.stepsSinceFix,
  });

  final DateTime startedAt;

  /// 파일 이름 → 이번 실행에서 쓴 행 수.
  final Map<String, int> rowCounts;
  final int errorCount;
  final bool atPlace;
  final bool onVehicle;

  /// 서비스가 알고 있는 지금 휴대 위치. 화면이 이 값으로 선택 칩을 맞춘다.
  final String? carry;
  final double? lastGpsAccuracyM;
  final int? lastOsSteps;
  final int? lastChargeUah;
  final int? lastLevelPct;

  /// 정책 실행 모드에서 정책이 보는 지금 상태(fixes.csv의 state와 같은 이름). 정답 기록 모드에서는 null이다.
  final String? policyState;

  /// 정책 실행 모드에서 마지막 측위 뒤 걸음 수.
  final int? stepsSinceFix;

  Map<String, Object?> toJson() => {
        'startedAt': startedAt.millisecondsSinceEpoch,
        'rowCounts': rowCounts,
        'errorCount': errorCount,
        'atPlace': atPlace,
        'onVehicle': onVehicle,
        'carry': carry,
        'lastGpsAccuracyM': lastGpsAccuracyM,
        'lastOsSteps': lastOsSteps,
        'lastChargeUah': lastChargeUah,
        'lastLevelPct': lastLevelPct,
        'policyState': policyState,
        'stepsSinceFix': stepsSinceFix,
      };

  factory RecorderStatus.fromJson(Map<String, Object?> json) => RecorderStatus(
        startedAt: DateTime.fromMillisecondsSinceEpoch(json['startedAt'] as int, isUtc: true),
        rowCounts: (json['rowCounts'] as Map).map((k, v) => MapEntry(k as String, v as int)),
        errorCount: json['errorCount'] as int,
        atPlace: json['atPlace'] as bool,
        onVehicle: json['onVehicle'] as bool,
        carry: json['carry'] as String?,
        lastGpsAccuracyM: (json['lastGpsAccuracyM'] as num?)?.toDouble(),
        lastOsSteps: json['lastOsSteps'] as int?,
        lastChargeUah: json['lastChargeUah'] as int?,
        lastLevelPct: json['lastLevelPct'] as int?,
        policyState: json['policyState'] as String?,
        stepsSinceFix: json['stepsSinceFix'] as int?,
      );
}
```

`lib/features/footsteps/recording/policy_choice.dart`:

```dart
import 'package:flutter/foundation.dart' show mapEquals;

/// 정책 실행 모드에서 고른 정책·걸음 감지기와 파라미터. 파라미터는 문자열 k=v 그대로 두고, 해석은
/// footstep_core의 정책·감지기 목록(createPolicy·createDetector)이 맡는다 — 재생기와 같은 이름·검사를 쓴다.
class PolicyChoice {
  const PolicyChoice({
    required this.policyId,
    required this.detectorId,
    this.policyParams = const {},
    this.detectorParams = const {},
  });

  final String policyId;
  final String detectorId;
  final Map<String, String> policyParams;
  final Map<String, String> detectorParams;

  Map<String, Object?> toJson() => {
        'policyId': policyId,
        'policyParams': policyParams,
        'detectorId': detectorId,
        'detectorParams': detectorParams,
      };

  factory PolicyChoice.fromJson(Map<String, Object?> json) => PolicyChoice(
        policyId: json['policyId'] as String,
        detectorId: json['detectorId'] as String,
        policyParams: Map<String, String>.from(json['policyParams'] as Map? ?? const {}),
        detectorParams: Map<String, String>.from(json['detectorParams'] as Map? ?? const {}),
      );

  @override
  bool operator ==(Object other) =>
      other is PolicyChoice &&
      other.policyId == policyId &&
      other.detectorId == detectorId &&
      mapEquals(other.policyParams, policyParams) &&
      mapEquals(other.detectorParams, detectorParams);

  @override
  int get hashCode => Object.hash(
        policyId,
        detectorId,
        Object.hashAllUnordered(policyParams.entries.map((e) => '${e.key}=${e.value}')),
        Object.hashAllUnordered(detectorParams.entries.map((e) => '${e.key}=${e.value}')),
      );

  @override
  String toString() => 'PolicyChoice($policyId $policyParams, $detectorId $detectorParams)';
}

/// 정책 실행 모드에서 켤 센서. 쓰지 않는 센서를 켜면 그 전력이 배터리 측정에 섞인다(설계 5-5).
class PolicySensorNeeds {
  const PolicySensorNeeds({required this.accel, required this.osSteps, required this.activity});

  /// 걸음 정보(StepUpdate)를 쓰는 정책. 나머지 정책은 걸음 감지기를 돌려도 결과가 같아 센서를 켜지 않는다.
  static const stepPolicyIds = {'still_suppress', 'step_budget'};

  final bool accel;
  final bool osSteps;
  final bool activity;

  /// 걸음 정보를 쓰는 정책만 걸음 감지기의 센서를 켠다 — OS 센서판이면 걸음 센서, 가속도판(brajdic·adaptive)이면
  /// 가속도. 활동 인식은 그것을 쓰는 activity_gated만 켠다.
  factory PolicySensorNeeds.of(PolicyChoice choice) {
    final usesSteps = stepPolicyIds.contains(choice.policyId);
    return PolicySensorNeeds(
      accel: usesSteps && choice.detectorId != 'os',
      osSteps: usesSteps && choice.detectorId == 'os',
      activity: choice.policyId == 'activity_gated',
    );
  }
}
```

`lib/features/footsteps/recording/policy_session_files.dart`:

```dart
import 'dart:io';

import 'package:footstep_core/footstep_core.dart' show ReplaySchema, RunnerSchema;
import 'package:path/path.dart' as p;

import 'csv_writer.dart';
import 'session_schema.dart';

/// 정책 실행 모드의 세션 파일(설계 5-5): 측위 결과(fixes.csv)·할 일(actions.csv)·깨우기 지연(wakeups.csv)·
/// 배터리·관찰 표시와, 끝날 때 쓰는 summary.json. fixes.csv·actions.csv·summary.json은 재생기와 같은 이름·형식이라
/// R6 분석이 재생 결과와 실기기 결과를 같은 코드로 읽는다.
class PolicySessionFiles {
  PolicySessionFiles._({
    required this.directory,
    required this.fixes,
    required this.actions,
    required this.wakeups,
    required this.battery,
    required this.marks,
  });

  static Future<PolicySessionFiles> open(Directory directory) async {
    Future<CsvWriter> openCsv(String name, List<String> header) =>
        CsvWriter.open(File(p.join(directory.path, name)), header);

    return PolicySessionFiles._(
      directory: directory,
      fixes: await openCsv(ReplaySchema.fixesFile, ReplaySchema.fixesHeader),
      actions: await openCsv(ReplaySchema.actionsFile, ReplaySchema.actionsHeader),
      wakeups: await openCsv(RunnerSchema.wakeupsFile, RunnerSchema.wakeupsHeader),
      battery: await openCsv(SessionSchema.batteryFile, SessionSchema.batteryHeader),
      marks: await openCsv(SessionSchema.marksFile, SessionSchema.marksHeader),
    );
  }

  final Directory directory;
  final CsvWriter fixes;
  final CsvWriter actions;
  final CsvWriter wakeups;
  final CsvWriter battery;
  final CsvWriter marks;

  File get summaryFile => File(p.join(directory.path, ReplaySchema.summaryFile));

  List<CsvWriter> get all => [fixes, actions, wakeups, battery, marks];

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

`lib/features/footsteps/recording/policy_recorder.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:footstep_core/footstep_core.dart';

import 'mark.dart';
import 'policy_choice.dart';
import 'policy_session_files.dart';
import 'recorder_status.dart';
import 'sensor_samples.dart';
import 'session_meta.dart';
import 'session_recorder.dart';

/// 정책 실행 모드(설계 4-1·5-5, 배터리 실험). 고른 정책 하나를 걸음 감지기와 함께 폰에서 돌리고, 측위 결과·할 일·
/// 깨우기 지연·배터리·관찰 표시만 쓴다. 1초 GPS와 가속도 원본은 쓰지 않는다 — 정답 기록을 같이 돌리면 배터리
/// 측정이 오염된다. 센서도 정책이 쓰는 것만 켠다([PolicySensorNeeds]).
///
/// 타이머를 안에 두지 않는다. 기록 서비스가 5초마다 [tick]을 불러 배터리 읽기와 디스크 쓰기를 맡긴다.
class PolicyRecorder implements SessionRecorder {
  PolicyRecorder({
    required this.sources,
    required this.files,
    required this.clock,
    required this.onError,
    required CollectionPolicy policy,
    required StepDetector detector,
    required LocationPort location,
    required WakeScheduler scheduler,
    required this.needs,
    this.batteryInterval = const Duration(seconds: 30),
  }) {
    _runner = PolicyRunner(
      policy: policy,
      detector: detector,
      location: location,
      scheduler: scheduler,
      clock: () => clock().millisecondsSinceEpoch,
      sink: _FileSink(files),
    );
  }

  final SensorSources sources;
  final PolicySessionFiles files;
  final DateTime Function() clock;
  final void Function(SessionError error) onError;
  final PolicySensorNeeds needs;
  final Duration batteryInterval;
  late final PolicyRunner _runner;

  @override
  final FieldState field = FieldState();

  final _subscriptions = <StreamSubscription<Object?>>[];
  DateTime? _startedAt;
  DateTime? _lastBatteryAt;
  int _errorCount = 0;
  int? _lastChargeUah;
  int? _lastLevelPct;

  @override
  Future<void> start() async {
    _startedAt = clock();
    _runner.start();
    if (needs.accel) {
      _listen(sources.accel(), 'accel', (AccelSample s) {
        _runner.addAccel(AccelReading(tMs: s.at.millisecondsSinceEpoch, x: s.x, y: s.y, z: s.z));
      });
    }
    if (needs.osSteps) {
      _listen(sources.osSteps(), 'os_steps', (OsStepSample s) {
        _runner.addOsStep(
            OsStepReading(tMs: s.at.millisecondsSinceEpoch, kind: s.kind, value: s.value));
      });
    }
    if (needs.activity) {
      _listen(sources.activity(), 'activity', (ActivitySample s) {
        _runner.addActivity(ActivityReading(
            tMs: s.at.millisecondsSinceEpoch, type: s.type, confidence: s.confidence));
      });
    }
    await _readBattery();
  }

  /// 센서 하나가 실패해도 나머지는 계속 돈다. 실패는 meta.json의 errors로 남긴다.
  void _listen<T>(Stream<T> stream, String source, void Function(T sample) onSample) {
    _subscriptions.add(stream.listen(onSample, onError: (Object e) => _reportError(source, e)));
  }

  @override
  Future<void> tick() async {
    final last = _lastBatteryAt;
    if (last == null || clock().difference(last) >= batteryInterval) await _readBattery();
    await files.flushAll();
  }

  @override
  void mark(Mark mark) {
    field.observe(mark);
    files.marks.add(mark.toCsvRow());
  }

  @override
  RecorderStatus get status {
    return RecorderStatus(
      startedAt: _startedAt ?? clock(),
      rowCounts: {
        ReplaySchema.fixesFile: files.fixes.totalRows,
        ReplaySchema.actionsFile: files.actions.totalRows,
        RunnerSchema.wakeupsFile: files.wakeups.totalRows,
        SessionSchema.batteryFile: files.battery.totalRows,
        SessionSchema.marksFile: files.marks.totalRows,
      },
      errorCount: _errorCount,
      atPlace: field.atPlace,
      onVehicle: field.onVehicle,
      carry: field.carry,
      lastGpsAccuracyM: _runner.lastFix?.accuracyM,
      lastChargeUah: _lastChargeUah,
      lastLevelPct: _lastLevelPct,
      policyState: _runner.stateLabel,
      stepsSinceFix: _runner.stepsSinceLastFix,
    );
  }

  @override
  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final summary = await _runner.stop();
    try {
      await files.summaryFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(summary.toJson()),
        flush: true,
      );
    } catch (e) {
      _reportError('summary', e);
    }
    await files.closeAll();
  }

  Future<void> _readBattery() async {
    _lastBatteryAt = clock();
    try {
      final battery = await sources.readBattery();
      files.battery.add(battery.toCsvRow());
      _lastChargeUah = battery.chargeUah;
      final level = battery.levelPct;
      _lastLevelPct = level;
      // 정책이 배터리 20% 미만 대응을 할 수 있게 잔량을 알린다(바뀔 때만 — 실행기가 거른다).
      if (level != null) _runner.addBatteryLevel(battery.at.millisecondsSinceEpoch, level);
    } catch (e) {
      _reportError('battery', e);
    }
  }

  void _reportError(String source, Object error) {
    _errorCount++;
    onError(SessionError(at: clock(), source: source, message: '$error'));
  }
}

/// 실행기의 기록을 세션 CSV에 쓴다. 열 순서는 재생기 결과와 같다.
class _FileSink implements RunnerSink {
  _FileSink(this.files);

  final PolicySessionFiles files;

  @override
  void fix(FixRecord record) => files.fixes.add([
        record.tMs,
        record.fix.lat,
        record.fix.lng,
        record.fix.accuracyM,
        record.stepsSincePrev,
        record.state,
        record.kind,
      ]);

  @override
  void action(ActionRecord record) =>
      files.actions.add([record.tMs, record.action.logName, record.action.logArgs]);

  @override
  void wakeup(WakeupRecord record) =>
      files.wakeups.add([record.tMs, record.tag, record.scheduledMs, record.delayMs]);
}
```

- [ ] **Step 4: 통과 확인**

Run (`app/`에서): `flutter test test/footsteps/recording/`와 `dart analyze lib test` → 통과, 0건. 이어서 `flutter test`(전체) → 통과.

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/footsteps/recording app/test/footsteps/recording
git commit -m "feat(app): 고른 정책만 돌려 측위 결과와 배터리를 쓰는 정책 실행 기록기를 추가한다"
```

---

### Task 5: 앱 — 기록 서비스에 정책 실행 모드를 붙인다

**Files:**
- Create: `app/lib/features/footsteps/recording/plugin_location_port.dart`
- Modify (전체 교체): `recording_mode.dart`, `recording_config.dart`, `session_meta.dart`, `recording_task_handler.dart`, `recording_controller.dart` (모두 `app/lib/features/footsteps/recording/`)
- Create: `app/lib/features/footsteps/recording/session_recorder_factory.dart`
- Modify (전체 교체): `app/test/footsteps/lab/fake_recording_controller.dart`
- Test: `app/test/footsteps/recording/plugin_location_port_test.dart`
- Test: `app/test/footsteps/recording/policy_mode_config_test.dart`

**Interfaces:**
- Consumes:
  - Task 4: `SessionRecorder`, `PolicyRecorder`, `PolicySessionFiles`, `PolicyChoice`, `PolicySensorNeeds`
  - Task 3: `LocationPort`, `WakeScheduler`
- Produces:
  - `RecordingMode.policy`. 세션 폴더 이름은 `…-policy`다.
  - `RecordingConfig.policy`, `SessionMeta.policy`(`PolicyChoice?`)
    - JSON 키 `policy`
  - `GeolocatorLocationPort({required DateTime Function() clock})`, `TimerWakeScheduler({required DateTime Function() clock})`
  - `Fix fixFromPosition(Position position, DateTime receivedAt)`
  - `Future<SessionRecorder> openSessionRecorder(RecordingConfig config, Directory sessionDir, {required DateTime Function() clock, required void Function(SessionError) onError})`
  - `RecordingController.start({required RecordingMode mode, required String carryInitial, String? note, PolicyChoice? policy})`
  - `FakeRecordingController.starts`의 각 원소는 `({RecordingMode mode, String carry, PolicyChoice? policy})`다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/footsteps/recording/plugin_location_port_test.dart`:

```dart
import 'package:app/features/footsteps/recording/plugin_location_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

Position _position({double speed = 1.3, double heading = 270}) => Position(
      latitude: 37.5665,
      longitude: 126.978,
      timestamp: DateTime.utc(2026, 11, 11, 0, 59, 59),
      accuracy: 6.5,
      altitude: 38,
      altitudeAccuracy: 3,
      heading: heading,
      headingAccuracy: 10,
      speed: speed,
      speedAccuracy: 0.5,
    );

void main() {
  test('위치는 받은 시각으로 Fix가 되고, 음수 속도·방향은 모르는 값(null)이다', () {
    final receivedAt = DateTime.utc(2026, 11, 11, 1);
    final fix = fixFromPosition(_position(), receivedAt);
    expect(fix.tMs, receivedAt.millisecondsSinceEpoch);
    expect((fix.lat, fix.lng, fix.accuracyM), (37.5665, 126.978, 6.5));
    expect((fix.speedMps, fix.bearingDeg), (1.3, 270.0));

    final unknown = fixFromPosition(_position(speed: -1, heading: -1), receivedAt);
    expect((unknown.speedMps, unknown.bearingDeg), (null, null));
  });

  test('타이머 예약기는 예약한 시각에 부르고, 지난 시각이면 바로 부르며, 취소하면 부르지 않는다', () async {
    final scheduler = TimerWakeScheduler(clock: DateTime.now);
    final calls = <String>[];
    final now = DateTime.now().millisecondsSinceEpoch;

    scheduler.schedule(now + 30, () => calls.add('soon'));
    scheduler.schedule(now - 1000, () => calls.add('past'));
    final cancelled = scheduler.schedule(now + 30, () => calls.add('cancelled'));
    scheduler.cancel(cancelled);
    expect(calls, isEmpty); // schedule 안에서 바로 부르지 않는다

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(calls, ['past', 'soon']);
  });
}
```

`app/test/footsteps/recording/policy_mode_config_test.dart`:

```dart
import 'package:app/features/footsteps/recording/policy_choice.dart';
import 'package:app/features/footsteps/recording/recording_config.dart';
import 'package:app/features/footsteps/recording/recording_mode.dart';
import 'package:app/features/footsteps/recording/session_meta.dart';
import 'package:flutter_test/flutter_test.dart';

const _choice = PolicyChoice(
  policyId: 'step_budget',
  policyParams: {'e_m': '25'},
  detectorId: 'adaptive',
  detectorParams: {'n_confirm': '6'},
);

void main() {
  test('정책 실행 모드의 기록 설정과 meta.json은 고른 정책을 함께 오가고, 정답 기록 모드는 null이다', () {
    const config = RecordingConfig(
      mode: RecordingMode.policy,
      sessionDir: '/s/20261111-090000-policy',
      carryInitial: 'pocket',
      policy: _choice,
    );
    final back = RecordingConfig.fromJson(config.toJson());
    expect(back.mode, RecordingMode.policy);
    expect(back.policy, _choice);

    final meta = SessionMeta(
      sessionId: '20261111-090000-policy',
      mode: RecordingMode.policy,
      deviceModel: 'samsung SM-S911N',
      androidSdk: 36,
      appVersion: '1.0.0',
      startedAt: DateTime.utc(2026, 11, 11),
      carryInitial: 'pocket',
      policy: _choice,
    );
    final metaBack = SessionMeta.fromJson(meta.toJson());
    expect(metaBack.policy, _choice);
    expect(meta.toJson()['policy'], {
      'policyId': 'step_budget',
      'policyParams': {'e_m': '25'},
      'detectorId': 'adaptive',
      'detectorParams': {'n_confirm': '6'},
    });
    expect(metaBack.copyWith(endedAt: DateTime.utc(2026, 11, 11, 1)).policy, _choice);

    const truth = RecordingConfig(mode: RecordingMode.groundTruth, sessionDir: '/s', carryInitial: 'hand');
    expect(RecordingConfig.fromJson(truth.toJson()).policy, isNull);
    expect(sessionDirName(DateTime(2026, 11, 11, 9), RecordingMode.policy), '20261111-090000-policy');
  });
}
```

- [ ] **Step 2: 실패 확인**

Run (`app/`에서): `flutter test test/footsteps/recording/plugin_location_port_test.dart test/footsteps/recording/policy_mode_config_test.dart`
Expected: 컴파일 오류(`plugin_location_port.dart`·`RecordingMode.policy`·`policy` 인자 없음)

- [ ] **Step 3: 구현**

`lib/features/footsteps/recording/plugin_location_port.dart`:

```dart
import 'dart:async';

import 'package:footstep_core/footstep_core.dart' show Fix, LocationPort, WakeScheduler;
import 'package:geolocator/geolocator.dart';

/// [LocationPort]의 실제 구현(geolocator, 설계 5-5). 정책 실행 모드에서 기록 서비스 isolate 안에서 부른다.
class GeolocatorLocationPort implements LocationPort {
  GeolocatorLocationPort({required this.clock});

  final DateTime Function() clock;

  @override
  Future<Fix?> currentFix({required int timeoutMs}) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(milliseconds: timeoutMs),
        ),
      );
      return fixFromPosition(position, clock());
    } on TimeoutException {
      // 제한 시간 안에 못 받았다(실내·지하철). 실행기가 실패로 정책에 알린다.
      return null;
    }
  }

  @override
  Stream<Fix> continuousFixes({required int intervalMs, required double distanceFilterM}) =>
      Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilterM.round(),
          intervalDuration: Duration(milliseconds: intervalMs),
        ),
      ).map((position) => fixFromPosition(position, clock()));
}

/// geolocator의 위치를 정책이 쓰는 [Fix]로 바꾼다. 시각은 앱이 받은 시각이다 — gps.csv의 t_ms와 같은 뜻이고,
/// 재생기도 이 시각을 '그 위치를 알 수 있게 된 때'로 쓴다. 속도·방향이 음수면 기기가 모르는 것이라 null이다.
Fix fixFromPosition(Position position, DateTime receivedAt) => Fix(
      tMs: receivedAt.millisecondsSinceEpoch,
      lat: position.latitude,
      lng: position.longitude,
      accuracyM: position.accuracy,
      speedMps: position.speed < 0 ? null : position.speed,
      bearingDeg: position.heading < 0 ? null : position.heading,
    );

/// [WakeScheduler]의 실제 구현. 기록 서비스는 부분 wake lock을 잡고 돌아서(설계 4-1) Dart 타이머가 깬다. 화면이
/// 꺼져 늦게 깨면 그 지연이 wakeups.csv에 남는다.
class TimerWakeScheduler implements WakeScheduler {
  TimerWakeScheduler({required this.clock});

  final DateTime Function() clock;

  @override
  Object schedule(int atMs, void Function() callback) {
    final delayMs = atMs - clock().millisecondsSinceEpoch;
    return Timer(Duration(milliseconds: delayMs < 0 ? 0 : delayMs), callback);
  }

  @override
  void cancel(Object handle) => (handle as Timer).cancel();
}
```

`lib/features/footsteps/recording/recording_mode.dart` 전체:

```dart
/// 기록 서비스 모드. 한 번에 하나만 돈다(설계 4-1) — 두 모드를 같이 돌리면 배터리 측정이 오염된다.
/// `groundTruth`는 모든 센서를 최대 빈도로 저장하고(R1), `policy`는 고른 정책 하나만 돌려 측위 결과와 배터리만
/// 저장한다(R4, 배터리 실험). R7이 `trip`을 더한다.
enum RecordingMode { groundTruth, policy }

String _two(int n) => n.toString().padLeft(2, '0');

/// 세션 폴더 이름이자 세션 id. 폴더 목록만 보고도 언제 무슨 모드였는지 알 수 있게 기기 현지 시각을 쓴다.
/// intl 대신 직접 만든다 — 서비스 isolate에서는 화면 쪽 로케일 초기화가 되어 있지 않다.
String sessionDirName(DateTime startLocal, RecordingMode mode) {
  final t = startLocal;
  return '${t.year}${_two(t.month)}${_two(t.day)}-${_two(t.hour)}${_two(t.minute)}${_two(t.second)}'
      '-${mode.name}';
}
```

`lib/features/footsteps/recording/recording_config.dart` 전체:

```dart
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
```

`lib/features/footsteps/recording/session_meta.dart` 전체:

```dart
import 'dart:convert';
import 'dart:io';

import 'policy_choice.dart';
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
    this.policy,
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

  /// 정책 실행 모드에서 고른 정책·감지기(설계 4-2의 policy). 정답 기록 모드에서는 null이다.
  final PolicyChoice? policy;
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
        policy: policy,
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
        'policy': policy?.toJson(),
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
        policy: json['policy'] == null
            ? null
            : PolicyChoice.fromJson((json['policy'] as Map).cast<String, Object?>()),
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

`lib/features/footsteps/recording/session_recorder_factory.dart`:

```dart
import 'dart:io';

import 'package:footstep_core/footstep_core.dart' show createDetector, createPolicy;

import 'ground_truth_recorder.dart';
import 'plugin_location_port.dart';
import 'plugin_sensor_sources.dart';
import 'policy_choice.dart';
import 'policy_recorder.dart';
import 'policy_session_files.dart';
import 'recording_config.dart';
import 'recording_mode.dart';
import 'session_files.dart';
import 'session_meta.dart';
import 'session_recorder.dart';

/// 기록 서비스가 모드에 맞는 기록기를 만든다. 플러그인을 직접 부르므로 기록 서비스 isolate 안에서만 쓴다.
/// 정책·감지기 설정이 잘못됐으면 파일을 만들기 전에 ArgumentError로 멈춘다(서비스가 시작 실패로 남긴다).
Future<SessionRecorder> openSessionRecorder(
  RecordingConfig config,
  Directory sessionDir, {
  required DateTime Function() clock,
  required void Function(SessionError error) onError,
}) async {
  switch (config.mode) {
    case RecordingMode.groundTruth:
      return GroundTruthRecorder(
        sources: PluginSensorSources(),
        files: await SessionFiles.open(sessionDir),
        clock: clock,
        onError: onError,
      );
    case RecordingMode.policy:
      final choice = config.policy;
      if (choice == null) throw StateError('정책 실행 모드인데 고른 정책이 없습니다.');
      final policy = createPolicy(choice.policyId, choice.policyParams);
      final detector = createDetector(choice.detectorId, choice.detectorParams);
      return PolicyRecorder(
        sources: PluginSensorSources(),
        files: await PolicySessionFiles.open(sessionDir),
        clock: clock,
        onError: onError,
        policy: policy,
        detector: detector,
        location: GeolocatorLocationPort(clock: clock),
        scheduler: TimerWakeScheduler(clock: clock),
        needs: PolicySensorNeeds.of(choice),
      );
  }
}
```

`lib/features/footsteps/recording/recording_task_handler.dart` 전체:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:device_probe/device_probe.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as p;

import 'mark.dart';
import 'recording_config.dart';
import 'recording_messages.dart';
import 'session_marks.dart';
import 'session_meta.dart';
import 'session_recorder.dart';
import 'session_recorder_factory.dart';
import 'session_schema.dart';

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
/// [RecordingConfig.mode]에 맞는 기록기(정답 기록·정책 실행)를 붙이고, 모드와 상관없는 일(meta.json, 알림 버튼,
/// 5초 tick, 화면 상태 전달)만 맡는다.
class RecordingTaskHandler extends TaskHandler {
  SessionRecorder? _recorder;
  SessionMetaStore? _metaStore;
  SessionMeta? _meta;

  DateTime _now() => DateTime.now().toUtc();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 이 isolate에서 Dart 쪽 등록이 필요한 플러그인(geolocator_android 등)을 쓰려면 먼저 불러야 한다.
    DartPluginRegistrant.ensureInitialized();

    try {
      final raw = await FlutterForegroundTask.getData<String>(key: RecordingConfig.storageKey);
      if (raw == null) {
        await FlutterForegroundTask.stopService();
        return;
      }
      final config = RecordingConfig.fromJson(jsonDecode(raw) as Map<String, Object?>);
      final sessionDir = Directory(config.sessionDir);
      // 열기 전에 읽는다. 시스템이 서비스를 다시 띄운 경우 marks.csv에 이전 표시가 남아 있다.
      final previousMarks = await readSessionMarks(sessionDir);
      final metaStore = SessionMetaStore(File(p.join(sessionDir.path, SessionSchema.metaFile)));
      _metaStore = metaStore;
      _meta = await metaStore.read() ?? await _newMeta(config);
      if (starter == TaskStarter.system) {
        // 시스템이 서비스를 죽였다 다시 띄웠다. 같은 세션 폴더에 이어 쓰되, 공백 구간을 분석에서 알 수 있게 남긴다.
        _meta = _meta!.withError(
          SessionError(at: _now(), source: 'service', message: 'restarted by system'),
        );
      }
      await metaStore.write(_meta!);

      final recorder = await openSessionRecorder(config, sessionDir, clock: _now, onError: _addError);
      _recorder = recorder;
      // 새 기록기의 토글 상태는 비어 있다. 이어 쓰는 세션이면 이미 남은 표시를 다시 흘려 넣어(marks.csv에는
      // 다시 쓰지 않는다) 도착/출발·탑승/하차 버튼과 휴대 위치가 끊기기 전 상태에서 이어지게 한다.
      recorder.field.carry = config.carryInitial;
      for (final mark in previousMarks) {
        recorder.field.observe(mark);
      }
      if (previousMarks.isNotEmpty) {
        unawaited(FlutterForegroundTask.updateService(
          notificationButtons: recordingNotificationButtons(recorder.field),
        ));
      }
      await recorder.start();
    } catch (e) {
      // 시작에 실패했는데 알림만 남아 있으면 테스터가 기록되는 줄 알고 걷는다. 이유를 남기고 서비스를 끈다.
      await _recordStartFailure(e);
      await FlutterForegroundTask.stopService();
    }
  }

  /// 시작 실패를 meta.json에 남긴다. 메타 저장소가 아직 없거나 쓰기마저 실패하면 포기한다.
  Future<void> _recordStartFailure(Object error) async {
    final store = _metaStore;
    if (store == null) return;
    try {
      final meta = _meta ?? await store.read();
      if (meta == null) return;
      _meta = meta.withError(
        SessionError(at: _now(), source: 'service', message: 'start failed: $error'),
      );
      await store.write(_meta!);
    } catch (_) {
      // 달리 보고할 곳이 없다.
    }
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
      policy: config.policy,
    );
  }

  void _addError(SessionError error) {
    final meta = _meta;
    final store = _metaStore;
    if (meta == null || store == null) return;
    _meta = meta.withError(error);
    // 메타 쓰기 실패는 달리 보고할 곳이 없다. 기다리지 않는 Future의 오류가 서비스 isolate에서
    // 잡히지 않은 예외로 새지 않도록 삼킨다.
    unawaited(store.write(_meta!).catchError((Object _) {}));
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    final recorder = _recorder;
    if (recorder == null) return;
    unawaited(_tickAndReport(recorder));
  }

  Future<void> _tickAndReport(SessionRecorder recorder) async {
    // tick을 기다리지 않고 부르므로, 실패하면 오류가 잡히지 않은 채 서비스 isolate 밖으로 샌다.
    // 세션 오류로 남기고, 화면 상태는 tick 성공 여부와 상관없이 계속 보낸다.
    try {
      await recorder.tick();
    } catch (e) {
      _addError(SessionError(at: _now(), source: 'flush', message: '$e'));
    }
    FlutterForegroundTask.sendDataToMain(encodeStatusMessage(recorder.status));
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
    try {
      await _recorder?.stop();
    } finally {
      // 기록기를 닫다 실패해도 종료 시각은 남긴다. 분석이 세션 길이를 이 값으로 잰다.
      final meta = _meta;
      final store = _metaStore;
      if (meta != null && store != null) {
        _meta = meta.copyWith(endedAt: _now());
        await store.write(_meta!);
      }
    }
  }
}
```

`lib/features/footsteps/recording/recording_controller.dart` 전체:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'mark.dart';
import 'policy_choice.dart';
import 'recorder_status.dart';
import 'recording_config.dart';
import 'recording_messages.dart';
import 'recording_mode.dart';
import 'recording_task_handler.dart';

/// 실험 화면이 기록 서비스를 다루는 창구. 위젯 테스트는 가짜 구현을 넣는다.
abstract interface class RecordingController {
  Future<bool> isRunning();
  /// [policy]는 정책 실행 모드에서만 준다.
  Future<void> start({
    required RecordingMode mode,
    required String carryInitial,
    String? note,
    PolicyChoice? policy,
  });
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
    this._sessionsRoot = defaultSessionsRoot,
    this._clock = DateTime.now,
  });

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
    PolicyChoice? policy,
  }) async {
    final root = await _sessionsRoot();
    final dir = Directory(p.join(root.path, sessionDirName(_clock(), mode)));
    await dir.create(recursive: true);
    final config = RecordingConfig(
      mode: mode,
      sessionDir: dir.path,
      carryInitial: carryInitial,
      note: note,
      policy: policy,
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
      notificationText: switch (mode) {
        RecordingMode.groundTruth => '정답 기록 모드 · 알림 버튼으로 도착·탑승을 표시하세요',
        RecordingMode.policy => '정책 실행 모드(${policy?.policyId}) · 알림 버튼으로 도착·탑승을 표시하세요',
      },
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

`test/footsteps/lab/fake_recording_controller.dart` 전체:

```dart
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
```

- [ ] **Step 4: 통과 확인**

Run (`app/`에서): `flutter test`(전체)와 `dart analyze lib test` → 통과, 0건. 정답 기록 모드의 기존 테스트가 그대로 통과해야 한다.

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/footsteps/recording app/test/footsteps
git commit -m "feat(app): 기록 서비스가 모드에 맞는 기록기를 붙여 정책 실행 모드를 돌린다"
```

---

### Task 6: 앱 — 실험 화면에서 정책 실행 모드를 고른다

**Files:**
- Create: `app/lib/features/footsteps/lab/lab_mode_panel.dart`
- Modify (전체 교체): `app/lib/features/footsteps/lab/lab_page.dart`, `app/lib/features/footsteps/lab/lab_status_card.dart`
- Modify: `packages/footstep_core/lib/footstep_core.dart`(export 1줄 — `parseKeyValues`)
- Test: `app/test/footsteps/lab/lab_page_test.dart`(import 1줄, 테스트 3개 추가)

**Interfaces:**
- Consumes:
  - Task 5: `RecordingMode.policy`, `RecordingController.start(policy:)`, `FakeRecordingController.starts[].policy`
  - Task 4: `PolicyChoice`, `RecorderStatus.policyState`·`stepsSinceFix`
  - R3: `policyIds`, `detectorIds`, `createPolicy`, `createDetector`, `parseKeyValues`
- Produces:
  - `LabModePanel`
  - 화면 키: `lab-mode`(SegmentedButton), `lab-policy`·`lab-detector`(DropdownButton), `lab-policy-params`(TextField)
  - 기본 선택은 `step_budget`·`adaptive`이다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/footsteps/lab/lab_page_test.dart`:
1. import 목록의 `import 'package:app/features/footsteps/recording/mark.dart';` 다음에 `import 'package:app/features/footsteps/recording/policy_choice.dart';`를 더한다.
2. `testWidgets('이미 기록 중이면 들어오자마자 종료 버튼을 보여 준다', ...)` 바로 앞에 더한다:

```dart
  testWidgets('정책 실행을 고르면 정책·감지기·파라미터로 기록을 시작한다', (tester) async {
    final controller = FakeRecordingController();
    await pumpLab(tester, controller);

    expect(find.byKey(const Key('lab-policy')), findsNothing);
    await tester.tap(find.text('정책 실행'));
    await tester.pumpAndSettle();
    expect(find.text('step_budget'), findsOneWidget);
    expect(find.text('adaptive'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('lab-policy-params')), 'e_m=25  use_steps=false');
    await tester.tap(find.byKey(const Key('lab-start-stop')));
    await tester.pumpAndSettle();

    expect(controller.starts.single.mode, RecordingMode.policy);
    expect(
      controller.starts.single.policy,
      const PolicyChoice(
        policyId: 'step_budget',
        detectorId: 'adaptive',
        policyParams: {'e_m': '25', 'use_steps': 'false'},
      ),
    );
  });

  testWidgets('정책 파라미터가 잘못되면 기록을 시작하지 않고 이유를 보여 준다', (tester) async {
    final controller = FakeRecordingController();
    await pumpLab(tester, controller);
    await tester.tap(find.text('정책 실행'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('lab-policy-params')), 'e_m=abc');
    await tester.tap(find.byKey(const Key('lab-start-stop')));
    await tester.pumpAndSettle();

    expect(controller.starts, isEmpty);
    expect(find.textContaining('양수여야'), findsOneWidget);
    expect(find.text('기록 시작'), findsOneWidget);
  });

  testWidgets('기록 중에는 모드를 바꿀 수 없고, 정책 실행 상태를 보여 준다', (tester) async {
    final controller = FakeRecordingController()..running = true;
    await pumpLab(tester, controller);
    final mode = tester.widget<SegmentedButton<RecordingMode>>(find.byKey(const Key('lab-mode')));
    expect(mode.onSelectionChanged, isNull);

    controller.statusController.add(RecorderStatus(
      startedAt: DateTime.now().toUtc(),
      rowCounts: const {'fixes.csv': 3},
      errorCount: 0,
      atPlace: false,
      onVehicle: false,
      policyState: 'walking',
      stepsSinceFix: 42,
    ));
    await tester.pumpAndSettle();
    expect(find.text('정책 상태: walking · 측위 뒤 걸음: 42'), findsOneWidget);
  });
```

- [ ] **Step 2: 실패 확인**

Run (`app/`에서): `flutter test test/footsteps/lab/lab_page_test.dart`
Expected: FAIL(`정책 실행` 버튼 없음)

- [ ] **Step 3: 구현**

`packages/footstep_core/lib/footstep_core.dart`의 export 목록 맨 앞(`export 'src/detectors/adaptive_step_detector.dart';` 앞)에 더한다:

```dart
export 'src/cli/key_values.dart';
```

`app/lib/features/footsteps/lab/lab_mode_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:footstep_core/footstep_core.dart' show detectorIds, policyIds;

import '../recording/recording_mode.dart';

/// 기록 모드 선택(설계 4-1). 정책 실행 모드(배터리 실험)는 정책·걸음 감지기·파라미터를 고른다. 기록 중에는 바꿀 수
/// 없다 — 한 세션은 한 설정으로만 돈다.
class LabModePanel extends StatelessWidget {
  const LabModePanel({
    super.key,
    required this.mode,
    required this.policyId,
    required this.detectorId,
    required this.paramsController,
    required this.enabled,
    required this.onModeChanged,
    required this.onPolicyChanged,
    required this.onDetectorChanged,
  });

  final RecordingMode mode;
  final String policyId;
  final String detectorId;
  final TextEditingController paramsController;
  final bool enabled;
  final ValueChanged<RecordingMode> onModeChanged;
  final ValueChanged<String> onPolicyChanged;
  final ValueChanged<String> onDetectorChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<RecordingMode>(
          key: const Key('lab-mode'),
          segments: const [
            ButtonSegment(value: RecordingMode.groundTruth, label: Text('정답 기록')),
            ButtonSegment(value: RecordingMode.policy, label: Text('정책 실행')),
          ],
          selected: {mode},
          onSelectionChanged: enabled ? (selection) => onModeChanged(selection.single) : null,
        ),
        if (mode == RecordingMode.policy) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('정책 '),
              DropdownButton<String>(
                key: const Key('lab-policy'),
                value: policyId,
                items: [
                  for (final id in policyIds) DropdownMenuItem(value: id, child: Text(id)),
                ],
                onChanged: enabled ? (id) => onPolicyChanged(id!) : null,
              ),
            ],
          ),
          Row(
            children: [
              const Text('걸음 감지기 '),
              DropdownButton<String>(
                key: const Key('lab-detector'),
                value: detectorId,
                items: [
                  for (final id in detectorIds) DropdownMenuItem(value: id, child: Text(id)),
                ],
                onChanged: enabled ? (id) => onDetectorChanged(id!) : null,
              ),
            ],
          ),
          TextField(
            key: const Key('lab-policy-params'),
            controller: paramsController,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: '정책 파라미터(빈칸으로 구분, 예: e_m=50 use_steps=false)',
            ),
          ),
        ],
      ],
    );
  }
}
```

`app/lib/features/footsteps/lab/lab_page.dart` 전체:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footstep_core/footstep_core.dart' show createDetector, createPolicy, parseKeyValues;

import '../recording/mark.dart';
import '../recording/policy_choice.dart';
import '../recording/recorder_status.dart';
import '../recording/recording_mode.dart';
import '../recording/recording_providers.dart';
import 'lab_marks_panel.dart';
import 'lab_mode_panel.dart';
import 'lab_permissions_panel.dart';
import 'lab_sessions_panel.dart';
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
  RecordingMode _mode = RecordingMode.groundTruth;
  String _policyId = 'step_budget';
  String _detectorId = 'adaptive';
  final _paramsController = TextEditingController();
  int _sessionsVersion = 0;
  StreamSubscription<RecorderStatus>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(recordingControllerProvider);
    _statusSubscription = controller.statusStream().listen((status) {
      if (!mounted) return;
      setState(() {
        _status = status;
        // 서비스가 휴대 위치의 기준이다. 화면이 새로 열렸거나 알림에서 바뀐 경우에도 실제 값을 따른다.
        final carry = status.carry;
        if (carry != null) _carry = carry;
      });
    });
    controller.isRunning().then((running) {
      if (mounted) setState(() => _running = running);
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _paramsController.dispose();
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
            _sessionsVersion++;
          });
        }
      } else {
        final policy = _mode == RecordingMode.policy ? _policyChoice() : null;
        await controller.start(mode: _mode, carryInitial: _carry, policy: policy);
        if (mounted) setState(() => _running = true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 화면에서 고른 정책 설정. 시작 전에 footstep_core 목록으로 한 번 만들어 보아, 파라미터 오타는 서비스를 켜기 전에
  /// 알린다(서비스 안에서 실패하면 알림만 잠깐 떴다 사라진다).
  PolicyChoice _policyChoice() {
    final params = parseKeyValues(
      _paramsController.text.split(RegExp(r'\s+')).where((pair) => pair.isNotEmpty),
    );
    createPolicy(_policyId, params);
    createDetector(_detectorId);
    return PolicyChoice(policyId: _policyId, policyParams: params, detectorId: _detectorId);
  }

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
          Text('기록 모드', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          LabModePanel(
            mode: _mode,
            policyId: _policyId,
            detectorId: _detectorId,
            paramsController: _paramsController,
            enabled: !_running && !_busy,
            onModeChanged: (mode) => setState(() => _mode = mode),
            onPolicyChanged: (id) => setState(() => _policyId = id),
            onDetectorChanged: (id) => setState(() => _detectorId = id),
          ),
          const SizedBox(height: 8),
          const Text('휴대 위치'),
          LabCarrySelector(value: _carry, onChanged: _changeCarry),
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
          const SizedBox(height: 16),
          LabMarksPanel(
            enabled: _running,
            atPlace: _status?.atPlace ?? false,
            onVehicle: _status?.onVehicle ?? false,
          ),
          const SizedBox(height: 16),
          LabSessionsPanel(refreshToken: _sessionsVersion),
        ],
      ),
    );
  }
}
```

`app/lib/features/footsteps/lab/lab_status_card.dart` 전체:

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
            if (s.policyState != null)
              Text('정책 상태: ${s.policyState} · 측위 뒤 걸음: ${s.stepsSinceFix ?? '-'}'),
            Text('오류: ${s.errorCount}건'),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 통과 확인**

Run (`app/`에서): `flutter test`(전체)와 `dart analyze lib test` → 통과, 0건. (`packages/footstep_core/`에서도 `dart test`, `dart analyze`)

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/footsteps/lab app/test/footsteps/lab packages/footstep_core/lib/footstep_core.dart
git commit -m "feat(app): 실험 화면에서 정책 실행 모드와 정책·감지기·파라미터를 고른다"
```

---

### Task 7: 실제 세션 재생 확인 + 배터리 실험 안내

**Files:**
- Create: `docs/research/battery-experiment-guide.md`
- Modify: `docs/research/replay-guide.md`, `docs/research/recording-guide.md`
- Modify: `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md`(5-3, 5-5)

**Interfaces:**
- Consumes: Task 1~6 전체
- Produces: 문서만

- [ ] **Step 1: 실제 세션으로 확인**

로컬에 R1 세션이 있으면 다음을 돌린다(Bash, `packages/footstep_core/`에서). 결과는 임시 폴더에 쓰고 지운다.

```bash
S=../../research/data/sessions/20261109-213324-groundTruth
O="$(mktemp -d)"
if [ -d "$S" ]; then
  while read -r P D X; do
    args="--policy $P --detector $D"; [ -n "$X" ] && args="$args --param $X"
    dart run footstep_core:replay --session "$S" $args --out "$O/x"
  done <<'EOF'
fixed_1m os
continuous_10m os
activity_gated os
still_suppress os
still_suppress adaptive
step_budget os
step_budget adaptive
step_budget brajdic
step_budget adaptive e_m=25
step_budget adaptive e_m=100
step_budget adaptive use_steps=false
step_budget adaptive suppress_still=false
step_budget adaptive vehicle_probe=false
EOF
else
  echo "세션 없음 — 건너뜀"
fi
rm -rf "$O"
```

Expected (세션이 있을 때): 모든 줄의 종료 코드가 0이고, 측위 횟수·GPS 켜짐이 '설계 검증' 표와 **같다**. 재생은 결정적이다. 출력 13줄을 태스크 보고서에 그대로 붙인다. 다르면 멈추고 보고한다.

- [ ] **Step 2: 앱 빌드 확인**

`app/`에서 `flutter build apk --debug`가 성공하는지 본다. 정책 실행 모드가 플러그인(geolocator·타이머)을 서비스 isolate에서 부르므로 빌드까지 확인한다.
- `compileSdk` 37 관련 실패는 정션 우회를 쓴다(메모리의 SDK 37 정션 안내).
- 경로 문제로 실패하면 결과를 보고하고 넘어간다. 실기기 확인(Task 8)에서 다시 빌드한다.

- [ ] **Step 3: 안내 문서 작성**

`docs/research/battery-experiment-guide.md`:

````markdown
# 배터리 실험 안내 (R4)

같은 폰·같은 코스에서 수집 방식만 바꿔 배터리 소모를 잰다(설계 문서 8-2). 실험 화면의 **정책 실행** 모드로 한다. 이 모드는 고른 정책 하나와 그 정책이 쓰는 센서만 켜고, 측위 결과·배터리만 기록한다. 1초 GPS·가속도 원본을 쓰는 정답 기록 모드는 같이 돌리지 않는다 — 배터리 측정이 오염된다.

## 1. 비교할 방식

| 방식 | 정책 | 걸음 감지기 | 파라미터 |
|---|---|---|---|
| 현재 앱 실시간 경로 | `continuous_10m` | (안 씀) | — |
| 같은 품질의 고정 주기 | `fixed_30s`·`fixed_1m`·`fixed_5m` 중 재생 결과로 고른 하나 | (안 씀) | — |
| 상용 방식 | `activity_gated` | (안 씀) | — |
| 제안 | `step_budget` | `os` 또는 `adaptive` | `e_m=50` |

- 여유가 있으면 `step_budget`을 두 감지기(`os`·`adaptive`)로 모두 잰다. `adaptive`는 가속도를 계속 읽으므로, 그 전력까지 포함한 값이 나온다. `os`는 전용 저전력 칩을 쓴다.
- 걸음 정보를 쓰지 않는 정책은 걸음 감지기를 골라도 센서를 켜지 않는다.

## 2. 통제 조건

- 시작 배터리 **80~90%**, 충전기 분리. 이 기종(Galaxy S23)은 100%에서 전하량 값이 변하지 않는다(`docs/research/device-check.md`).
- 화면 꺼짐, 같은 네트워크 설정(Wi-Fi·모바일 데이터 켬/끔을 실험 내내 같게), 다른 앱 종료, 정답 기록 모드 끔.
- 같은 코스, 비슷한 시간대. 방식마다 **3회 이상** 반복하고, 방식 순서는 섞는다(예: 1일차 A-B-C-D, 2일차 C-D-A-B, 3일차 B-A-D-C).
- 측정 중에는 폰을 만지지 않는다(화면이 켜지면 그 전력이 섞인다). 도착·출발·탑승은 알림 버튼으로만 남긴다.

## 3. 한 회 진행 순서

PC(Git Bash)에서 폰을 USB로 연결한 상태로 시작한다.

1. 배터리 통계 초기화: `adb shell dumpsys batterystats --reset`
2. 실험 화면 → **정책 실행** → 정책·걸음 감지기를 고르고 파라미터를 적는다(예: `e_m=50`) → **기록 시작**.
3. 충전기·USB를 분리하고 화면을 끈 채 코스를 이동한다.
4. 끝나면 실험 화면에서 **기록 종료**.
5. USB를 다시 연결하고 배터리 통계를 저장한다. 세션 폴더 이름은 실험 화면 세션 목록에 나온다:

   ```bash
   MSYS_NO_PATHCONV=1 adb pull /sdcard/Android/data/com.travelfootsteps.app/files/sessions/<세션 폴더> research/data/sessions/
   adb shell dumpsys batterystats > research/data/sessions/<세션 폴더>/batterystats.txt
   ```

Git Bash에서는 `/sdcard` 경로가 바뀌지 않게 `MSYS_NO_PATHCONV=1`을 붙인다.

## 4. 세션 폴더의 파일

| 파일 | 내용 |
|---|---|
| `fixes.csv` | `t_ms,lat,lng,accuracy_m,steps_since_prev,state,kind` — 정책에 알린 위치(재생기와 같은 형식) |
| `actions.csv` | `t_ms,action,args` — 정책이 낸 할 일 |
| `wakeups.csv` | `t_ms,tag,scheduled_ms,delay_ms` — 예약한 깨우기가 실제로 늦게 깬 정도 |
| `battery.csv` | 30초마다 전하량(`charge_uah`)·전류·잔량 |
| `marks.csv` | 알림 버튼·실험 화면 관찰 표시 |
| `meta.json` | 기기·시작/끝 시각·오류, `policy`(고른 정책·감지기·파라미터) |
| `summary.json` | 측위 요청·성공·실패, 추정 GPS 켜짐 시간, 깨우기 지연 중앙값·최댓값 |
| `batterystats.txt` | 끝난 뒤 저장한 `dumpsys batterystats` 출력 |

## 5. 결과를 볼 때

- **주 지표는 `battery.csv`의 `charge_uah` 감소량 ÷ 시간(mAh/h)**이다. 이 기종은 3.7 mAh 계단으로 줄어서, 1시간 실험이면 계단 하나가 2~2.5% 오차다. 시작·끝을 계단이 바뀐 직후 시점으로 맞추면 오차를 줄일 수 있다. `plugged=1` 행은 뺀다.
- `current_ua` 열은 이 기종에서 실제로 mA 단위다. 전류 적분은 교차 확인용으로 함께 본다.
- `summary.json`의 `gps_on_s`(추정 GPS 켜짐 시간)와 `batterystats.txt`의 GPS 사용 시간을 견준다.
- `wakeups.csv`·`wake_delay_*`: 화면이 꺼지면 타이머가 늦게 깰 수 있다. 지연이 크면 정책이 의도보다 드물게 쟀다는 뜻이라 보고서 한계에 적는다(설계 10장 위험 3).
- `fix_failures`가 많으면(실내·지하철) 정책이 다시 시도하는 간격을 늘렸는지 `actions.csv`로 본다.
- 결과 폴더(`research/results/`)와 세션(`research/data/`)은 커밋하지 않는다.
````

`docs/research/replay-guide.md`의 '정책' 절 표에서 다음 행을

```markdown
| `still_suppress` | Zhuang 외(2010): 고정 주기, 정지 중이면 건너뜀 | `interval_s`(기본 60) |
```

다음 두 행으로 바꾼다:

```markdown
| `still_suppress` | Zhuang 외(2010): 1분마다 확인, 직전·이번 확인이 모두 정지면 건너뜀, 억제 중에도 5분마다 확인 측위 | `interval_s`(기본 60), `verify_s`(기본 300) |
| `step_budget` | **제안**: 보행은 '오차 + 걸음 수 × 보폭 > E'일 때, 정지는 30초 이어지면 한 번 + 5분 확인, 기타 움직임은 확인 측위 두 번으로 탈것(시속 12km 이상)이면 time_speed 규칙 | `e_m`(50), `stride_m`(0.75), `use_steps`·`suppress_still`·`vehicle_probe`(true, 절제 실험) |
```

그 표 아래의 `제안 정책 `step_budget`은 R4에서, 걸음 감지기 `brajdic`·`adaptive`는 R3에서 추가된다. 지금 감지기는 `os`(OS 걸음 센서)뿐이다.` 줄을 지우고, 그 자리에 다음 문단을 넣는다:

```markdown
`time_speed`는 RAPS(Paek 외 2010)의 장소·시간대별 속도 이력과 가속도 활동 비율을 쓰지 않고, 마지막 측위 속도만 쓰는 단순화판이다. 보고서에 이 차이를 적는다. 같은 정책을 폰에서 돌리는 방법(배터리 실험)은 `docs/research/battery-experiment-guide.md`에 있다.
```

`docs/research/recording-guide.md` 맨 위 문단의 `배터리 실험은 이 모드로 하지 않는다(R4 정책 실행 모드).`를 `배터리 실험은 이 모드로 하지 않는다 — 실험 화면의 '정책 실행' 모드로 한다(docs/research/battery-experiment-guide.md).`로 바꾼다.

설계 문서:
1. 5-3 표의 `still_suppress` 행을 다음으로 바꾼다:

```markdown
| `still_suppress` | Zhuang 외(2010): 1분마다 상태를 확인해 측위하되, 직전·이번 확인이 모두 정지면 건너뛴다. 억제 중에도 5분마다 확인 측위를 한다(원문 3.2절, 주기는 원문에 없어 step_budget과 맞춤) | R2(R4에서 원문대로 고침) |
```

2. `step_budget` 규칙 표의 '정지' 행 동작 칸 전체를 다음으로 바꾼다: `정지가 30초 이어지면 한 번 측위하고(머문 곳 위치) 이후 측위하지 않는다. 대신 5분마다 확인 측위를 해, 머문 곳에서 벗어났으면(걸음 없이 움직이는 버스) 탈것 상태로 바꾼다.`

3. '기타 움직임' 행 동작 칸을 다음으로 바꾼다: `30초 이어지면 30초 간격 확인 측위 두 번으로 속도를 본다. 시속 12km 이상이면 탈것 상태로 보고 `time_speed` 규칙으로 측위한다(속도 하한 시속 12km). 느리면 정지처럼 5분마다 확인한다. 걸음이 다시 나오면 보행으로 돌아간다.`

4. 그 표 바로 아래(절제 실험용 스위치 목록 앞)에 다음 한 줄을 넣는다: `상태가 30초 이어져야 그 상태로 측위하는 이유: 폰을 만지는 동안 걸음 감지기 상태가 몇 초 단위로 바뀌어, 바뀔 때마다 재면 실제 세션 첫 1분에만 15번을 쟀다(R4 설계 검증).`

5. 5-5의 마지막 항목(`**정책 실행 모드(배터리 실험)**는 …`) 다음에 다음 항목들을 더한다:

```markdown
- 실행기(`PolicyRunner`)는 패키지에 순수 Dart로 두고, GPS·타이머·시계를 포트로 받는다(R7 여행 기록이 같은 실행기를 쓴다). 가속도는 재생기와 같은 1초 묶음으로 넣는다.
- Wakeup은 실제로 깬 시각으로 보낸다. 늦게 깬 만큼은 `wakeups.csv`(`t_ms,tag,scheduled_ms,delay_ms`)에 남고, 끝날 때 `summary.json`(재생기 요약과 같은 키 + 깨우기 지연 중앙값·최댓값)을 쓴다.
- 정책이 쓰는 센서만 켠다: 걸음 정보를 쓰는 정책(`still_suppress`·`step_budget`)만 걸음 감지기의 센서(OS 센서판이면 걸음 센서, 가속도판이면 가속도)를, `activity_gated`만 활동 인식을 켠다.
```

- [ ] **Step 4: 커밋**

```bash
git add docs/research docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md
git commit -m "docs: 배터리 실험 안내를 추가하고 정책 문서에 제안 정책과 Zhuang 기준을 적는다"
```

- [ ] **Step 5: 마무리 확인**

- `packages/footstep_core/`: `dart test`, `dart analyze` → 통과, 0건
- `app/`: `flutter test`, `dart analyze` → 통과, 0건
- `git status`에 `research/`가 없다
- `git log --format=%B origin/steps..HEAD | grep -iE "co-authored|claude"`가 빈 결과다

---

### Task 8: 정책 실행 모드 실기기 확인 (컨트롤러와 사용자가 함께)

이 태스크는 서브에이전트가 아니라 컨트롤러가 사용자와 함께 한다. 폰은 Galaxy S23이고 USB 디버깅을 쓴다.

**Files:**
- Create: `docs/research/policy-mode-check.md`

- [ ] **Step 1: 폰의 세션 백업**

`flutter install`은 기존 앱을 지운다. 먼저 폰의 세션을 PC로 옮긴다(Git Bash):

```bash
MSYS_NO_PATHCONV=1 adb pull /sdcard/Android/data/com.travelfootsteps.app/files/sessions/ research/data/sessions-backup-$(date +%Y%m%d)/
```

- [ ] **Step 2: 빌드·설치**

`app/`에서 `flutter build apk --debug` 후 `flutter install`(또는 `adb install -r build/app/outputs/flutter-apk/app-debug.apk` — `-r`은 데이터를 지키지만 서명이 달라 실패하면 `flutter install`). 로그인·권한(위치 항상 허용, 신체 활동, 알림)을 다시 준다.

- [ ] **Step 3: 정책 실행 세션 두 개 (사용자)**

배터리 90% 이하, 충전기 분리, 화면 꺼짐 상태에서 진행한다.
1. **`step_budget` + `adaptive`, 파라미터 없음, 약 15분**
   - 걷기 5분, 실내에서 멈춰 있기 5분, 다시 걷기 5분.
   - 멈췄을 때 알림의 '도착' 버튼, 다시 걸을 때 '출발' 버튼을 누른다.
2. **`fixed_1m` + `os`, 약 5분**: 걸어도 되고 멈춰 있어도 된다.

- [ ] **Step 4: 꺼내서 확인**

```bash
MSYS_NO_PATHCONV=1 adb pull /sdcard/Android/data/com.travelfootsteps.app/files/sessions/<세션 폴더> research/data/sessions/
```

확인할 것:
- 세션 폴더 이름이 `…-policy`인지
- 파일이 `fixes.csv`·`actions.csv`·`wakeups.csv`·`battery.csv`·`marks.csv`·`meta.json`·`summary.json`뿐인지. `gps.csv`·`accel.csv`는 없어야 한다.
- `step_budget` 세션
  - `fixes.csv`의 state가 `walking`·`still`로 바뀌는지
  - 걷는 동안 측위가 약 30초(약 61걸음)마다인지
  - 멈춘 뒤 30초 즈음에 한 번 재는지
- `wakeups.csv`의 `delay_ms` 분포: 화면이 꺼진 동안 늦게 깨는지 본다. summary.json의 `wake_delay_median_ms`·`wake_delay_max_ms`를 적는다.
- `meta.json`의 `policy`와 `summary.json`의 `policy_params`·`detector_params`
- `battery.csv` 30초 간격, `meta.json`의 errors

- [ ] **Step 5: 결과 기록**

`docs/research/policy-mode-check.md`에 R1의 `device-check.md` 형식으로 적는다(세션, 조건, 파일별 결과, 깨우기 지연, 결론). 실제 세션 데이터는 커밋하지 않는다.

```bash
git add docs/research/policy-mode-check.md
git commit -m "docs: 정책 실행 모드 실기기 확인 결과를 기록한다"
```
