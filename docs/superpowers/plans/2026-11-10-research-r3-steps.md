# R3 걸음 감지(논문 기준판·제안판) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 모듈 A 걸음 감지기 두 개를 `packages/footstep_core`에 더한다. 논문 기준판 `brajdic`(Brajdic & Harle 2013의 STD_TH + WPD)과 제안판 `adaptive`(걸음 대역 + 흔들림·박자 판정 + 적응형 임계값 + 연속 N걸음 소급 카운트)다. 재생기에서 `--detector`로 고를 수 있게 하고, 감지기만 세션에 돌려 걸음 시각·상태·걸음 세기 구간 오차를 내보내는 `steps` CLI를 만든다.

**Architecture:**
- 두 감지기는 R2의 `StepDetector` 인터페이스를 그대로 구현한다. 그래서 재생기와 (R4의) 폰 실행기가 감지기를 갈아 끼울 수 있다.
- 입력 가속도는 기기마다 표본 간격이 다르다(Galaxy S23은 약 10ms). 그래서 두 감지기 모두 가속도 크기를 20ms 격자로 다시 표본화한 뒤 처리한다. 파라미터는 '초' 단위로 정한다.
- 제안판의 '박자'는 정규화 자기상관의 **봉우리**로 본다. 느린 흔들림(버스의 좌우 흔들림)은 짧은 지연에서 상관이 높을 뿐 봉우리가 없다. 신호는 걸음 대역(0.7~3Hz)만 남긴다. 이렇게 정한 근거는 설계 검증용 Python 시제품의 결과다(아래 '설계 검증').
- 걸음 감지 평가(설계 7-2)에는 걸음마다의 시각이 필요하다. 소급 카운트한 걸음은 묶음 끝 시각에 더해지기 때문이다. 감지기는 선택 인터페이스 `StepTimeline`으로 걸음 시각을 내준다. `steps` CLI는 그것과 관찰 표시(`marks.csv`)를 함께 써서 구간별 걸음 수를 낸다.

**Tech Stack:** Dart 3.13.2(순수 Dart 패키지), `path`, `args`, 개발용 `test`·`lints`.

**설계 문서·근거:**
- `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md` 5-2(걸음 감지기), 5-4(`--detector os|brajdic|adaptive`), 5-7(테스트), 7-2(걸음 감지 지표)
- 팀 자료 `바탕화면/종설/중간 이후 아이디어/종설_연구주제_연구방법.md` 4-1(출발 파라미터)
- 이권희·김광현·오종택, 「위치 추적을 위한 스마트폰 센서를 이용한 걸음 수 검출에 관한 연구」, JIIBC 18(3), 2018, 식 (4)
  - `Tmax(i+1) = 1/3 × (0.5 × (Pmax(i) + Pmax(i−1)))`
  - `Tmin = 0.94`(중력 단위, 고정)
- Brajdic & Harle, UbiComp 2013: STD_TH(0.8초 창, 표준편차 0.6), WPD
  - **WPD의 평활 창과 피크 창 길이는 원문을 아직 확인하지 못했다(ACM 유료).**
  - 이 계획의 0.2초·0.2초는 출발값이다. 원문을 확인하면 Task 3의 기본값만 바꾼다.

## 설계 검증 (Python 시제품, 커밋하지 않음)

이 계획의 알고리즘을 Python으로 똑같이 짜서 다음 결과를 확인했다. 아래 '기대값'이 테스트에 들어간다.
- 합성 신호는 테스트와 같은 선형 합동 난수를 쓴다.
- 실제 세션은 `20261109-213324-groundTruth`(15분 47초, 손에 들고 걷기 약 7분 + 실내 정지)다.

| 입력 | 제안판 `adaptive` | 기준판 `brajdic` | 정답 |
|---|---|---|---|
| 2Hz 보행 30초 | 59 | 59 | 60 |
| 1.5Hz 보행 30초 | 44 | 44 | 45 |
| 2.4Hz 보행 30초 | 71 | 70 | 72 |
| 2Hz 보행 30초, 50Hz 입력 | 59 | 59 | 60 |
| 15초 보행 + 7초 공백 + 15초 보행 | 58 | 58 | 60 |
| 4초 보행(8걸음) × 3, 사이 3초 정지 | 24 | 27 | 24 |
| 2초 보행(4걸음) 한 번 | 0 (N=5 미만) | 5 | 4 |
| 정지 20초 | 0, 첫 사건 990ms 정지 | 0 | 0 |
| 버스 흉내 60초(엔진 12·17Hz + 0.3Hz 흔들림) | 0, 상태는 기타 움직임만 | 52 | 0 |
| 실제 세션 | 887 | 952 | OS 걸음 센서 875 |

## Global Constraints

- 작업 브랜치는 `steps`다(`replay`에서 갈라짐. `replay`는 PR #34로 리뷰 중). 다른 브랜치를 만들지 않는다.
- 커밋에 `Co-Authored-By`, `Claude-Session` 같은 AI 트레일러를 넣지 않는다. push 전에 `git log --format=%B origin/replay..HEAD | grep -iE "co-authored|claude"`가 빈 결과인지 확인한다.
- `packages/footstep_core`는 Flutter에 의존하지 않는다. 런타임 의존성은 `path`와 `args`뿐이고, 개발 의존성은 `test`와 `lints`다.
- 패키지 안의 시각은 모두 `int` UTC epoch 밀리초(`tMs`)이고, 시간 길이도 밀리초(`...Ms`)다.
  - 패키지 로직에서 `DateTime.now()`나 난수를 쓰지 않는다(재생 결과가 항상 같아야 한다).
  - 테스트의 합성 잡음은 `test/detectors/synthetic.dart`의 선형 합동 수열만 쓴다(`dart:math`의 `Random` 금지). 설계 검증과 같은 수열이어야 한다.
- 실측 사실: 가속도는 약 100Hz로 들어온다. 감지기는 표본 간격을 가정하지 않고 20ms 격자(`MagnitudeGrid`)로 다시 표본화한다.
- 걸음 감지기 id는 설계 문서 5-4 그대로다: `os`, `brajdic`, `adaptive`.
- 출발 파라미터는 아래 값을 그대로 쓴다. 최종값은 예비용(pilot) 세션으로만 정한다(설계 5-2). 이 계획에서는 조정하지 않는다.
  - 흔들림: 0.8초 창 가속도 크기 표준편차 0.6 m/s²
  - 자기상관: 봉우리 0.4, 창 3초, 지연 0.24~1.3초
  - 연속 확인: N = 5
  - 적응형 임계값: Tmin = −0.588 m/s²(0.94g를 0 중심으로 바꾼 값), Tmax = 직전 두 Pmax 합 ÷ 6, 첫 Tmax = 1.0
  - 걸음 대역: 0.7~3Hz. 대역 흔들림 하한 0.3 m/s²
  - 걸음 사이 최대 간격: 1.5초. 최소 간격: 걸음 주기 × 0.6
  - WPD: 평활 0.2초, 피크 반창 0.2초
- 수집한 세션 데이터(`research/data/`)와 결과는 커밋하지 않는다.
- 코드 주석은 한국어로 '왜'를 적는다.
- 패키지 테스트·분석은 `packages/footstep_core/`에서 `dart test`, `dart analyze`로 한다. `flutter analyze`는 이 PC에서 경로 문제로 죽는다.

## 파일 구조

```
packages/footstep_core/
  lib/src/model/readings.dart              + MarkReading (Task 1)
  lib/src/session/session_reader.dart      + SessionData.marks, marks.csv 읽기 (Task 1)
  lib/src/detectors/signal.dart            MagnitudeGrid, Biquad, RecentValues, mean, stdDev, autocorrelationPeak (Task 2)
  lib/src/replay/accel_batches.dart        accelBatches — 재생기에서 꺼낸 공용 묶기 (Task 2)
  lib/src/detectors/step_timeline.dart     StepTimeline 인터페이스 (Task 3)
  lib/src/detectors/step_detector.dart     + params (Task 3)
  lib/src/detectors/os_step_detector.dart  + StepTimeline, params (Task 3)
  lib/src/detectors/brajdic_detector.dart  논문 기준판 (Task 3)
  lib/src/detectors/adaptive_peak_finder.dart  적응형 임계값 후보 찾기 (Task 4)
  lib/src/detectors/adaptive_step_detector.dart 제안판 (Task 5)
  lib/src/params.dart                      ParamReader — 정책·감지기 목록 공용 (Task 6)
  lib/src/detectors/detector_registry.dart os·brajdic·adaptive + 파라미터 (Task 6)
  lib/src/cli/key_values.dart              parseKeyValues (Task 6)
  lib/src/steps/step_run.dart              runDetector, StepRun, StateChange (Task 7)
  lib/src/steps/steps_output.dart          StepsSchema, 구간 계산, writeStepsOutput (Task 7)
  lib/src/cli/steps_cli.dart               runStepsCli (Task 7)
  bin/steps.dart                           dart run footstep_core:steps (Task 7)
  test/detectors/synthetic.dart            합성 신호·묶어 넣기 도우미 (Task 3, 테스트가 아님)
docs/research/steps-guide.md               걸음 감지 실행·걸음 세기 기록 안내 (Task 8)
```

수정하는 기존 파일:
- `replay_engine.dart`: 묶기 공용화(Task 2), `detectorParams`(Task 6)
- `replay_result.dart`: `detectorParams`(Task 6)
- `policy_registry.dart`: `ParamReader` 사용(Task 6)
- `replay_cli.dart`: `--detector-param`(Task 6)
- `lib/footstep_core.dart`: export 추가(Task 3·5·7). `signal.dart`·`accel_batches.dart`·`params.dart`·`key_values.dart`는 패키지 내부용이라 export하지 않는다(테스트는 `package:footstep_core/src/...`로 가져온다).
- `docs/research/replay-guide.md`, 설계 문서 5-2(Task 8)

---

### Task 1: 관찰 표시(marks.csv) 읽기

**Files:**
- Modify: `packages/footstep_core/lib/src/model/readings.dart`
- Modify: `packages/footstep_core/lib/src/session/session_reader.dart`
- Test: `packages/footstep_core/test/session/session_reader_test.dart`

**Interfaces:**
- Consumes: `SessionSchema.marksFile`(`marks.csv`), `csvRecords`, `splitCsvLine`(R2)
- Produces:
  - `class MarkReading({required int tMs, required String kind, required String value})`
  - 상수 `MarkReading.countStart = 'count_start'`, `countEnd = 'count_end'`, `board = 'board'`, `alight = 'alight'`
  - `SessionData.marks`(`List<MarkReading>`, 기본 `const []`, 시각순)

- [ ] **Step 1: 실패하는 테스트 작성**

`test/session/session_reader_test.dart`의 `main()` 안, 마지막 테스트 뒤에 더한다:

```dart
  test('관찰 표시(marks.csv)를 시각순으로 읽고, 따옴표 안 쉼표와 빈 값을 지킨다', () async {
    write('marks.csv', [
      't_ms,kind,value',
      '61000,count_end,100',
      '1000,count_start,',
      '70000,note,"버스, 앞자리"',
      'broken',
    ]);
    write('gps.csv', [
      't_ms,fix_t_ms,lat,lng,accuracy_m,speed_mps,bearing_deg,altitude_m',
      '5000,4990,37.5,127.0,5.0,0,0,30',
    ]);

    final data = await readSession(session);

    expect(data.marks.map((m) => (m.tMs, m.kind, m.value)), [
      (1000, MarkReading.countStart, ''),
      (61000, MarkReading.countEnd, '100'),
      (70000, 'note', '버스, 앞자리'),
    ]);
    expect(data.skippedRows, 1);
    // 관찰 표시는 사람이 누른 시각이라 세션 시작·끝(센서 기록 범위)을 바꾸지 않는다.
    expect(data.startMs, 5000);
    expect(data.endMs, 5000);
  });
```

- [ ] **Step 2: 실패 확인**

Run (`packages/footstep_core/`에서): `dart test test/session/session_reader_test.dart`
Expected: 컴파일 오류(`MarkReading`, `marks`가 없음)

- [ ] **Step 3: 구현**

`lib/src/model/readings.dart` 맨 끝에 더한다:

```dart
/// marks.csv의 행 하나(설계 4-2 관찰 표시). kind는 arrive·depart·board·alight·count_start·count_end·carry·note다.
class MarkReading {
  const MarkReading({required this.tMs, required this.kind, required this.value});

  static const countStart = 'count_start';
  static const countEnd = 'count_end';
  static const board = 'board';
  static const alight = 'alight';

  final int tMs;
  final String kind;

  /// count_end면 직접 센 걸음 수, board면 탈것 종류, arrive면 장소 이름이다. 없으면 빈 문자열이다.
  final String value;
}
```

`lib/src/session/session_reader.dart`:

1. `SessionData` 생성자에 `this.marks = const [],`를 `this.battery = const [],` 다음 줄에 더하고, 필드를 더한다(`battery` 필드 다음):

```dart
  /// 관찰 표시(설계 4-2). 사람이 누른 시각이라 [startMs]·[endMs]에는 넣지 않는다 — 재생 범위는 센서 기록이 정한다.
  final List<MarkReading> marks;
```

2. `readSession`에서 `battery`를 읽는 줄 다음에 더한다:

```dart
  final marks = await load(SessionSchema.marksFile, _parseMark, (MarkReading m) => m.tMs);
```

그리고 `return SessionData(...)`에 `marks: marks,`를 `battery: battery,` 다음에 더한다.

3. 파일 맨 끝에 파서를 더한다:

```dart
MarkReading? _parseMark(List<String> f) {
  if (f.length < 2) return null;
  final t = int.tryParse(f[0]);
  final kind = f[1];
  if (t == null || kind.isEmpty) return null;
  return MarkReading(tMs: t, kind: kind, value: f.length > 2 ? f[2] : '');
}
```

- [ ] **Step 4: 통과 확인**

Run: `dart test test/session/session_reader_test.dart` → PASS. 이어서 `dart test`(전체)와 `dart analyze` → 모두 통과, 분석 0건.

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core/lib/src/model/readings.dart packages/footstep_core/lib/src/session/session_reader.dart packages/footstep_core/test/session/session_reader_test.dart
git commit -m "feat(footstep_core): 세션의 관찰 표시(marks.csv)를 읽는다"
```

---

### Task 2: 신호 도구와 가속도 묶기 공용화

**Files:**
- Create: `packages/footstep_core/lib/src/detectors/signal.dart`
- Create: `packages/footstep_core/lib/src/replay/accel_batches.dart`
- Modify: `packages/footstep_core/lib/src/replay/replay_engine.dart`(`_accelBatches` 메서드)
- Test: `packages/footstep_core/test/detectors/signal_test.dart`
- Test: `packages/footstep_core/test/replay/accel_batches_test.dart`

**Interfaces:**
- Consumes: `AccelReading`(R2)
- Produces (`signal.dart`, 패키지 내부용이라 export하지 않는다):
  - `const gridStepMs = 20`
  - `class GridSample({required int tMs, required double magnitude, bool afterGap = false})`
  - `class MagnitudeGrid({int stepMs = gridStepMs, int maxGapMs = 200})`, `List<GridSample> add(AccelReading reading)`
  - `class Biquad`, `factory Biquad.lowPass(double cutoffHz, double sampleHz)`, `factory Biquad.highPass(double cutoffHz, double sampleHz)`, `double filter(double x, {required double steadyOutput})`
  - `class RecentValues(int capacity)`: `add(double)`, `clear()`, `toList()`, `length`, `isFull`, `capacity`
  - `double mean(Iterable<double>)`, `double stdDev(Iterable<double>)`(모표준편차, 비면 0)
  - `({double r, int lag})? autocorrelationPeak(List<double> window, int minLag, int maxLag)`
- Produces (`accel_batches.dart`): `Iterable<List<AccelReading>> accelBatches(List<AccelReading> accel, int batchMs)`. 재생기의 기존 묶기 규칙과 같다.

- [ ] **Step 1: 실패하는 테스트 작성**

`test/detectors/signal_test.dart`:

```dart
import 'dart:math' as math;

import 'package:footstep_core/footstep_core.dart';
import 'package:footstep_core/src/detectors/signal.dart';
import 'package:test/test.dart';

AccelReading reading(int tMs, double magnitude) => AccelReading(tMs: tMs, x: 0, y: magnitude, z: 0);

void main() {
  group('MagnitudeGrid', () {
    test('20ms 칸 안의 표본은 크기의 평균이 되고, 칸은 다음 칸 표본이 와야 확정된다', () {
      final grid = MagnitudeGrid();
      expect(grid.add(const AccelReading(tMs: 0, x: 3, y: 4, z: 0)), isEmpty); // 크기 5
      expect(grid.add(reading(10, 7)), isEmpty);
      final out = grid.add(reading(20, 1));
      expect(out.map((s) => (s.tMs, s.magnitude, s.afterGap)), [(0, 6.0, false)]);
    });

    test('짧은 빈 칸은 직전 값으로 메운다', () {
      final grid = MagnitudeGrid()
        ..add(reading(0, 2))
        ..add(reading(10, 4));
      final out = grid.add(reading(70, 9));
      expect(out.map((s) => (s.tMs, s.magnitude)), [(0, 3.0), (20, 3.0), (40, 3.0)]);
    });

    test('200ms보다 긴 공백은 메우지 않고, 공백 뒤 첫 칸에 afterGap을 단다', () {
      final grid = MagnitudeGrid()..add(reading(0, 2));
      expect(grid.add(reading(500, 4)).map((s) => s.tMs), [0]);
      final out = grid.add(reading(520, 6));
      expect(out.map((s) => (s.tMs, s.magnitude, s.afterGap)), [(500, 4.0, true)]);
    });
  });

  group('Biquad', () {
    double amplitudeAfterSettling(Biquad filter, double hz) {
      var peak = 0.0;
      for (var i = 0; i < 500; i++) {
        final y = filter.filter(math.sin(2 * math.pi * hz * i / 50), steadyOutput: 0);
        if (i >= 250) peak = math.max(peak, y.abs());
      }
      return peak;
    }

    test('저역 통과(3Hz)는 일정한 입력을 그대로 내고, 걸음 박자는 남기고 빠른 진동은 줄인다', () {
      final steady = Biquad.lowPass(3, 50);
      for (var i = 0; i < 20; i++) {
        expect(steady.filter(9.81, steadyOutput: 9.81), closeTo(9.81, 1e-9));
      }
      expect(amplitudeAfterSettling(Biquad.lowPass(3, 50), 1), greaterThan(0.95));
      expect(amplitudeAfterSettling(Biquad.lowPass(3, 50), 10), lessThan(0.15));
    });

    test('고역 통과(0.7Hz)는 일정한 입력을 0으로 만들고, 느린 흔들림은 줄이고 걸음 박자는 남긴다', () {
      final steady = Biquad.highPass(0.7, 50);
      for (var i = 0; i < 20; i++) {
        expect(steady.filter(9.81, steadyOutput: 0), closeTo(0, 1e-9));
      }
      expect(amplitudeAfterSettling(Biquad.highPass(0.7, 50), 0.2), lessThan(0.15));
      expect(amplitudeAfterSettling(Biquad.highPass(0.7, 50), 2), greaterThan(0.95));
    });
  });

  test('stdDev는 모표준편차이고 비면 0이다', () {
    expect(stdDev([1, 2, 3, 4]), closeTo(1.1180, 1e-4));
    expect(stdDev(const []), 0);
    expect(mean([1, 2, 3, 4]), 2.5);
  });

  test('RecentValues는 최근 값만 남긴다', () {
    final values = RecentValues(3);
    for (final v in [1.0, 2.0, 3.0, 4.0]) {
      values.add(v);
    }
    expect(values.toList(), [2.0, 3.0, 4.0]);
    expect(values.isFull, isTrue);
    values.clear();
    expect(values.length, 0);
    expect(values.isFull, isFalse);
  });

  group('autocorrelationPeak', () {
    test('2Hz 사인은 0.5초(25표본) 지연에서 봉우리가 1에 가깝다', () {
      final w = [for (var i = 0; i < 150; i++) math.sin(2 * math.pi * 2 * i / 50)];
      final peak = autocorrelationPeak(w, 12, 65)!;
      expect(peak.lag, 25);
      expect(peak.r, greaterThan(0.95));
    });

    test('느린 흔들림(0.2Hz)은 지연이 커질수록 상관이 줄기만 해서 봉우리가 없다', () {
      final w = [for (var i = 0; i < 150; i++) math.sin(2 * math.pi * 0.2 * i / 50)];
      expect(autocorrelationPeak(w, 12, 65), isNull);
    });

    test('창이 지연 범위보다 짧으면 null이다', () {
      expect(autocorrelationPeak(List.filled(60, 1.0), 12, 65), isNull);
    });
  });
}
```

`test/replay/accel_batches_test.dart`:

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:footstep_core/src/replay/accel_batches.dart';
import 'package:test/test.dart';

void main() {
  test('묶음 길이만큼 시간이 지나면 새 묶음을 시작한다', () {
    final readings = [
      for (var t = 0; t <= 2500; t += 10) AccelReading(tMs: t, x: 0, y: 9.8, z: 0),
    ];
    final batches = accelBatches(readings, 1000).toList();
    expect(batches.map((b) => (b.first.tMs, b.last.tMs)), [(0, 990), (1000, 1990), (2000, 2500)]);
  });

  test('빈 목록이면 묶음이 없다', () {
    expect(accelBatches(const [], 1000), isEmpty);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `dart test test/detectors/signal_test.dart test/replay/accel_batches_test.dart`
Expected: 컴파일 오류(파일 없음)

- [ ] **Step 3: 구현**

`lib/src/detectors/signal.dart`:

```dart
import 'dart:collection';
import 'dart:math' as math;

import '../model/readings.dart';

/// 걸음 감지기가 쓰는 격자 간격(ms, 50Hz). 걸음 신호(약 1~3Hz)를 다루기에 충분하고, 100Hz 기기와 50Hz
/// 기기에서 같은 파라미터가 같은 뜻을 갖게 한다.
const gridStepMs = 20;

/// 격자 표본 하나. [afterGap]이면 바로 앞에 메우지 않은 큰 공백이 있었다.
class GridSample {
  const GridSample({required this.tMs, required this.magnitude, this.afterGap = false});

  final int tMs;
  final double magnitude;
  final bool afterGap;
}

/// 가속도 크기(√(x²+y²+z²), 폰 방향과 무관)를 [stepMs] 격자로 다시 표본화한다.
/// - 기기마다 표본 간격이 다르고 들쭉날쭉해서(Galaxy S23은 약 10ms), 창 길이를 시간으로 정한 파라미터가
///   기기와 무관하게 같은 뜻이 되게 한다.
/// - 칸 안의 표본은 평균한다. 칸보다 빠른 진동(엔진 등)이 낮은 주파수로 접혀 들어오는 것을 줄인다.
/// - [maxGapMs] 이하의 빈 칸은 직전 값으로 메우고, 그보다 긴 공백(서비스 재시작 등)은 메우지 않고 표시만 한다.
class MagnitudeGrid {
  MagnitudeGrid({this.stepMs = gridStepMs, this.maxGapMs = 200});

  final int stepMs;
  final int maxGapMs;

  int? _bin;
  double _sum = 0;
  int _count = 0;
  bool _gapBefore = false;

  /// [reading]을 넣고, 이번에 확정된 격자 표본을 돌려준다. 칸은 다음 칸의 표본이 들어와야 확정된다.
  List<GridSample> add(AccelReading reading) {
    final magnitude =
        math.sqrt(reading.x * reading.x + reading.y * reading.y + reading.z * reading.z);
    final bin = reading.tMs - reading.tMs % stepMs;
    final out = <GridSample>[];
    final current = _bin;
    if (current == null) {
      _bin = bin;
    } else if (bin > current) {
      final value = _sum / _count;
      out.add(GridSample(tMs: current, magnitude: value, afterGap: _gapBefore));
      _gapBefore = bin - current > maxGapMs;
      if (!_gapBefore) {
        for (var t = current + stepMs; t < bin; t += stepMs) {
          out.add(GridSample(tMs: t, magnitude: value));
        }
      }
      _bin = bin;
      _sum = 0;
      _count = 0;
    }
    // 시각이 거꾸로 온 표본(bin < current)은 지금 칸에 더한다. 세션 읽기가 정렬하므로 드물다.
    _sum += magnitude;
    _count++;
    return out;
  }
}

/// 2차 버터워스 필터(쌍선형 변환). 걸음 대역만 남기는 데 쓴다.
class Biquad {
  Biquad._(this._b0, this._b1, this._b2, this._a1, this._a2);

  factory Biquad.lowPass(double cutoffHz, double sampleHz) {
    final k = math.tan(math.pi * cutoffHz / sampleHz);
    final norm = 1 / (1 + k * math.sqrt2 + k * k);
    final b0 = k * k * norm;
    return Biquad._(b0, 2 * b0, b0, 2 * (k * k - 1) * norm, (1 - k * math.sqrt2 + k * k) * norm);
  }

  factory Biquad.highPass(double cutoffHz, double sampleHz) {
    final k = math.tan(math.pi * cutoffHz / sampleHz);
    final norm = 1 / (1 + k * math.sqrt2 + k * k);
    return Biquad._(
        norm, -2 * norm, norm, 2 * (k * k - 1) * norm, (1 - k * math.sqrt2 + k * k) * norm);
  }

  final double _b0;
  final double _b1;
  final double _b2;
  final double _a1;
  final double _a2;

  double _x1 = 0;
  double _x2 = 0;
  double _y1 = 0;
  double _y2 = 0;
  bool _started = false;

  /// 첫 입력에서는 필터가 이미 그 값에 오래 머물러 있던 것처럼 시작한다([steadyOutput]은 그때의 출력:
  /// 저역 통과는 입력 그대로, 고역 통과는 0). 0에서 시작하면 중력(약 9.8)이 계단처럼 들어와 첫 몇 초에
  /// 가짜 봉우리가 생긴다.
  double filter(double x, {required double steadyOutput}) {
    if (!_started) {
      _x1 = x;
      _x2 = x;
      _y1 = steadyOutput;
      _y2 = steadyOutput;
      _started = true;
    }
    final y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }
}

/// 최근 [capacity]개 값을 담는 창.
class RecentValues {
  RecentValues(this.capacity);

  final int capacity;
  final _values = ListQueue<double>();

  int get length => _values.length;

  bool get isFull => _values.length >= capacity;

  void add(double value) {
    _values.addLast(value);
    if (_values.length > capacity) _values.removeFirst();
  }

  void clear() => _values.clear();

  List<double> toList() => _values.toList(growable: false);
}

double mean(Iterable<double> values) {
  var sum = 0.0;
  var n = 0;
  for (final v in values) {
    sum += v;
    n++;
  }
  return n == 0 ? 0 : sum / n;
}

/// 모표준편차. 비어 있으면 0이다.
double stdDev(Iterable<double> values) {
  final list = values.toList(growable: false);
  if (list.isEmpty) return 0;
  final m = mean(list);
  var sum = 0.0;
  for (final v in list) {
    sum += (v - m) * (v - m);
  }
  return math.sqrt(sum / list.length);
}

/// 정규화 자기상관이 지연 [minLag]~[maxLag](표본 수)에서 봉우리(양옆보다 높은 점)를 이루는 곳 중 가장 높은 것.
/// 봉우리만 보는 이유: 느린 흔들림(버스의 좌우 흔들림)은 지연이 짧을수록 상관이 높아서, 범위 안 최댓값만 보면
/// '박자'로 오인된다. 걸음은 걸음 주기 지연에서 봉우리가 생긴다. 봉우리가 없거나 창이 짧으면 null이다.
({double r, int lag})? autocorrelationPeak(List<double> window, int minLag, int maxLag) {
  if (minLag < 2 || window.length <= maxLag + 2) return null;

  double corr(int lag) {
    final n = window.length - lag;
    var meanA = 0.0;
    var meanB = 0.0;
    for (var i = 0; i < n; i++) {
      meanA += window[i];
      meanB += window[i + lag];
    }
    meanA /= n;
    meanB /= n;
    var cross = 0.0;
    var varA = 0.0;
    var varB = 0.0;
    for (var i = 0; i < n; i++) {
      final a = window[i] - meanA;
      final b = window[i + lag] - meanB;
      cross += a * b;
      varA += a * a;
      varB += b * b;
    }
    final den = math.sqrt(varA * varB);
    return den > 0 ? cross / den : 0;
  }

  final r = {for (var lag = minLag - 1; lag <= maxLag + 1; lag++) lag: corr(lag)};
  ({double r, int lag})? best;
  for (var lag = minLag; lag <= maxLag; lag++) {
    final value = r[lag]!;
    if (value >= r[lag - 1]! && value > r[lag + 1]! && (best == null || value > best.r)) {
      best = (r: value, lag: lag);
    }
  }
  return best;
}
```

`lib/src/replay/accel_batches.dart`:

```dart
import '../model/readings.dart';

/// 가속도를 [batchMs] 길이 묶음으로 나눈다. 재생기와 걸음 감지 평가가 같은 묶음을 써야 두 결과에서 감지기가
/// 똑같이 동작한다(감지기는 묶음 끝 시각을 시계로 쓴다).
Iterable<List<AccelReading>> accelBatches(List<AccelReading> accel, int batchMs) sync* {
  var batch = <AccelReading>[];
  int? windowStart;
  for (final reading in accel) {
    final start = windowStart ??= reading.tMs;
    if (reading.tMs - start >= batchMs && batch.isNotEmpty) {
      yield batch;
      batch = <AccelReading>[];
      windowStart = reading.tMs;
    }
    batch.add(reading);
  }
  if (batch.isNotEmpty) yield batch;
}
```

`lib/src/replay/replay_engine.dart`:
- 맨 위 import 목록에 `import 'accel_batches.dart';`를 더한다.
- `_buildTimeline()`의 `..._accelBatches(),` 줄을 다음으로 바꾼다:

```dart
      for (final batch in accelBatches(data.accel, config.accelBatchMs)) _AccelBatch(batch),
```

- `Iterable<_AccelBatch> _accelBatches() sync* { ... }` 메서드 전체를 지운다(같은 규칙을 `accelBatches`가 맡는다).

- [ ] **Step 4: 통과 확인**

Run: `dart test test/detectors/signal_test.dart test/replay/accel_batches_test.dart` → PASS. 이어서 `dart test`(전체, 재생기 테스트가 그대로 통과해야 한다)와 `dart analyze` → 0건.

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core/lib/src/detectors/signal.dart packages/footstep_core/lib/src/replay/accel_batches.dart packages/footstep_core/lib/src/replay/replay_engine.dart packages/footstep_core/test/detectors/signal_test.dart packages/footstep_core/test/replay/accel_batches_test.dart
git commit -m "feat(footstep_core): 걸음 감지용 신호 도구를 더하고 가속도 묶기를 공용으로 뺀다"
```

---

### Task 3: 걸음 시각 인터페이스 + 논문 기준판 감지기(`brajdic`)

**Files:**
- Create: `packages/footstep_core/lib/src/detectors/step_timeline.dart`
- Create: `packages/footstep_core/lib/src/detectors/brajdic_detector.dart`
- Modify: `packages/footstep_core/lib/src/detectors/step_detector.dart`(`params` 추가)
- Modify: `packages/footstep_core/lib/src/detectors/os_step_detector.dart`(`StepTimeline`, `params`)
- Modify: `packages/footstep_core/lib/footstep_core.dart`(export 2줄)
- Create: `packages/footstep_core/test/detectors/synthetic.dart`(테스트 도우미, `_test`로 끝나지 않으므로 그 자체는 실행되지 않는다)
- Test: `packages/footstep_core/test/detectors/brajdic_detector_test.dart`
- Test: `packages/footstep_core/test/detectors/os_step_detector_test.dart`(테스트 1개 추가)

**Interfaces:**
- Consumes: `MagnitudeGrid`, `GridSample`, `RecentValues`, `mean`, `stdDev`, `gridStepMs`(Task 2), `accelBatches`(Task 2, 테스트 도우미에서)
- Produces:
  - `abstract interface class StepTimeline { List<int> takeStepTimes(); }`
  - `StepDetector`에 `Map<String, Object> get params;`
  - `OsStepDetector`가 `StepTimeline`을 구현한다. `params`는 `{'walking_window_s': 4.0}`(기본값일 때)이다.
  - `class BrajdicDetector({double stdThreshold = 0.6, int smoothMs = 200, int peakHalfMs = 200}) implements StepDetector, StepTimeline`
    - `id == 'brajdic'`
    - `params == {'std_th': 0.6, 'smooth_s': 0.2, 'peak_half_s': 0.2}`
    - `cadenceHz`는 늘 null이다
  - 테스트 도우미(`test/detectors/synthetic.dart`):
    - 합성 신호: `lcg`, `walk`, `still`, `bus`, `stopAndGo`, `shortBurst`, `gapWalk`
    - 감지기에 넣기: `feed`

- [ ] **Step 1: 테스트 도우미 작성**

`test/detectors/synthetic.dart`:

```dart
import 'dart:math' as math;

import 'package:footstep_core/footstep_core.dart';
import 'package:footstep_core/src/replay/accel_batches.dart';

/// 결정적 난수(선형 합동). 설계 검증에 쓴 Python 시제품과 같은 수열이어야 기대값이 맞는다.
/// 그래서 dart:math의 Random을 쓰지 않는다.
Iterator<double> lcg(int seed) {
  Iterable<double> values() sync* {
    var state = seed;
    while (true) {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      yield state / 0x7fffffff;
    }
  }

  return values().iterator;
}

double _next(Iterator<double> it) {
  it.moveNext();
  return it.current;
}

AccelReading _magnitude(int tMs, double m) => AccelReading(tMs: tMs, x: 0, y: m, z: 0);

/// 보행 흉내: 중력 + [hz]로 출렁이는 사인 + 작은 잡음. 걸음 수 = 사인 주기 수다.
List<AccelReading> walk(int seconds,
    {double hz = 2, double amp = 3, int t0 = 0, int seed = 1, int sampleMs = 10}) {
  final noise = lcg(seed);
  final perSecond = 1000 ~/ sampleMs;
  return [
    for (var i = 0; i < seconds * perSecond; i++)
      _magnitude(t0 + i * sampleMs,
          9.81 + amp * math.sin(2 * math.pi * hz * i / perSecond) + 0.2 * (_next(noise) - 0.5)),
  ];
}

/// 책상 위 정지 흉내(100Hz): 중력 + 아주 작은 잡음.
List<AccelReading> still(int seconds, {int t0 = 0, int seed = 2}) {
  final noise = lcg(seed);
  return [
    for (var i = 0; i < seconds * 100; i++)
      _magnitude(t0 + i * 10, 9.81 + 0.05 * (_next(noise) - 0.5)),
  ];
}

/// 버스 흉내(100Hz): 엔진 진동(12·17.3Hz) + 0.3Hz 좌우 흔들림 + 잡음. 흔들림은 크지만 걸음 박자는 없다.
List<AccelReading> bus(int seconds, {int t0 = 0, int seed = 7}) {
  final noise = lcg(seed);
  return [
    for (var i = 0; i < seconds * 100; i++)
      _magnitude(
          t0 + i * 10,
          9.81 +
              1.5 *
                  (math.sin(2 * math.pi * 12 * i / 100) +
                      0.6 * math.sin(2 * math.pi * 17.3 * i / 100 + 1.0)) +
              0.5 * math.sin(2 * math.pi * 0.3 * i / 100) +
              0.3 * (_next(noise) - 0.5)),
  ];
}

/// 4초 보행(8걸음)을 3초 정지 사이사이에 세 번 — 끊어 걷기(이권희 외 2018의 실험 B와 같은 성격). 정답 24걸음.
List<AccelReading> stopAndGo() {
  final readings = <AccelReading>[];
  var t0 = 0;
  for (var k = 0; k < 3; k++) {
    readings.addAll(still(3, t0: t0, seed: 10 + k));
    t0 += 3000;
    readings.addAll(walk(4, t0: t0, seed: 20 + k));
    t0 += 4000;
  }
  readings.addAll(still(3, t0: t0, seed: 99));
  return readings;
}

/// 정지 3초 → 2초 보행(4걸음) → 정지 5초. 연속 N(5)걸음에 못 미치는 짧은 움직임이다.
List<AccelReading> shortBurst() => [
      ...still(3),
      ...walk(2, t0: 3000, seed: 5),
      ...still(5, t0: 5000, seed: 6),
    ];

/// 15초 보행 → 7초 기록 공백(서비스 재시작) → 15초 보행. 정답 60걸음.
List<AccelReading> gapWalk() => [...walk(15), ...walk(15, t0: 22000, seed: 2)];

/// 재생기와 같은 1초 묶음으로 감지기에 넣고, 나온 StepUpdate를 모은다.
List<StepUpdate> feed(StepDetector detector, List<AccelReading> readings) => [
      for (final batch in accelBatches(readings, 1000))
        if (detector.onAccel(batch.last.tMs, batch) case final update?) update,
    ];
```

- [ ] **Step 2: 실패하는 테스트 작성**

`test/detectors/brajdic_detector_test.dart`:

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

import 'synthetic.dart';

void main() {
  test('2Hz 보행 30초(60걸음)를 거의 그대로 센다', () {
    final detector = BrajdicDetector();
    final updates = feed(detector, walk(30));

    expect(detector.totalSteps, inInclusiveRange(58, 61));
    expect(updates.last.state, StepState.walking);
    expect(updates.last.cadenceHz, isNull);
    final times = detector.takeStepTimes();
    expect(times, hasLength(detector.totalSteps));
    expect(times, orderedEquals([...times]..sort()));
    expect(detector.takeStepTimes(), isEmpty); // 가져가면 비운다
  });

  test('걸음 빠르기가 달라도 센다(1.5Hz·2.4Hz)', () {
    final slow = BrajdicDetector();
    feed(slow, walk(30, hz: 1.5, seed: 3));
    expect(slow.totalSteps, inInclusiveRange(43, 46));
    final fast = BrajdicDetector();
    feed(fast, walk(30, hz: 2.4, seed: 4));
    expect(fast.totalSteps, inInclusiveRange(69, 73));
  });

  test('표본 간격이 달라도(50Hz 기기) 같은 결과다', () {
    final detector = BrajdicDetector();
    feed(detector, walk(30, sampleMs: 20));
    expect(detector.totalSteps, inInclusiveRange(58, 61));
  });

  test('기록 공백(7초) 건너편을 한 창에 섞지 않는다', () {
    final detector = BrajdicDetector();
    feed(detector, gapWalk());
    expect(detector.totalSteps, inInclusiveRange(56, 61));
  });

  test('정지면 0걸음이고, 0.8초 창이 찬 첫 묶음에서 정지를 한 번 알린다', () {
    final detector = BrajdicDetector();
    final updates = feed(detector, still(20));
    expect(updates, hasLength(1));
    expect(updates.single.tMs, 990);
    expect(updates.single.state, StepState.still);
    expect(detector.totalSteps, 0);
  });

  test('연속 확인이 없어 짧은 움직임도 센다(논문 방식 그대로)', () {
    final detector = BrajdicDetector();
    feed(detector, shortBurst());
    expect(detector.totalSteps, inInclusiveRange(3, 6));
  });

  test('기타 움직임을 구분하지 않아 버스 진동을 걸음으로 센다(제안판과 비교하려는 약점)', () {
    final detector = BrajdicDetector();
    final updates = feed(detector, bus(60));
    expect(detector.totalSteps, greaterThan(10));
    expect(updates.map((u) => u.state), isNot(contains(StepState.otherMotion)));
  });

  test('onFix는 마지막 측위 이후 걸음 수를 0으로 되돌리고, OS 걸음 읽기는 무시한다', () {
    final detector = BrajdicDetector();
    feed(detector, walk(10));
    final before = detector.totalSteps;
    detector.onFix();
    expect(detector.stepsSinceLastFix, 0);
    expect(detector.onOsStep(const OsStepReading(tMs: 1, kind: OsStepReading.count, value: '5')),
        isNull);
    expect(detector.totalSteps, before);
  });

  test('id와 파라미터', () {
    final detector = BrajdicDetector();
    expect(detector.id, 'brajdic');
    expect(detector.params, {'std_th': 0.6, 'smooth_s': 0.2, 'peak_half_s': 0.2});
  });
}
```

`test/detectors/os_step_detector_test.dart`의 `main()` 안 맨 끝에 더한다:

```dart
  test('늘어난 걸음은 읽은 시각으로 걸음 시각에 남고, 가져가면 비운다', () {
    final detector = OsStepDetector()
      ..onOsStep(count(1000, 100))
      ..onOsStep(count(2000, 103))
      ..onOsStep(count(3000, 105));

    expect(detector.takeStepTimes(), [2000, 2000, 2000, 3000, 3000]);
    expect(detector.takeStepTimes(), isEmpty);
    expect(detector.params, {'walking_window_s': 4.0});
  });
```

- [ ] **Step 3: 실패 확인**

Run: `dart test test/detectors/`
Expected: 컴파일 오류(`BrajdicDetector`, `takeStepTimes`, `params` 없음)

- [ ] **Step 4: 구현**

`lib/src/detectors/step_timeline.dart`:

```dart
/// 걸음마다 시각을 알려 주는 감지기. 걸음 감지 평가(steps.csv)에 쓴다. StepUpdate는 묶음 끝 시각에 나오고
/// 소급 카운트한 걸음도 그 시각에 더해지므로, 걸음 세기 구간 경계에서 개수를 정확히 나누려면 걸음 자체의
/// 시각이 필요하다.
abstract interface class StepTimeline {
  /// 마지막으로 부른 뒤 새로 센 걸음의 시각(소급분 포함). 부르면 비운다.
  List<int> takeStepTimes();
}
```

`lib/src/detectors/step_detector.dart`의 `String get id;` 다음 줄에 더한다:

```dart

  /// 결과 파일(summary.json·step_summary.json)에 남기는 파라미터. 같은 결과를 다시 만들 수 있게 한다.
  Map<String, Object> get params;
```

`lib/src/detectors/os_step_detector.dart`:
- import에 `import 'step_timeline.dart';`를 더한다.
- `class OsStepDetector implements StepDetector {`를 `class OsStepDetector implements StepDetector, StepTimeline {`로 바꾼다.
- `bool _announced = false;` 필드 다음에 더한다:

```dart

  final _stepTimes = <int>[];

  @override
  Map<String, Object> get params => {'walking_window_s': walkingWindowMs / 1000};
```

- `onOsStep`의 `} else if (total > _total) {` 블록 첫 줄(`_total = total;`) 앞에 더한다:

```dart
        // OS는 걸음을 몇 개씩 묶어 늦게 알린다. 묶인 걸음은 모두 읽은 시각에 둔다.
        _stepTimes.addAll(List.filled(total - _total, reading.tMs));
```

- `onFix` 다음에 더한다:

```dart
  @override
  List<int> takeStepTimes() {
    final times = List<int>.of(_stepTimes);
    _stepTimes.clear();
    return times;
  }
```

`lib/src/detectors/brajdic_detector.dart`:

```dart
import 'dart:collection';
import 'dart:math' as math;

import '../events/policy_event.dart';
import '../model/readings.dart';
import 'signal.dart';
import 'step_detector.dart';
import 'step_timeline.dart';

/// 논문 기준판 걸음 감지기(Brajdic & Harle, UbiComp 2013의 추천 조합, 설계 5-2).
/// - 보행 판정 STD_TH: 가속도 크기의 0.8초 창 표준편차가 [stdThreshold]보다 크면 보행이다.
/// - 걸음 세기 WPD: 크기를 [smoothMs] 이동 평균으로 다듬고, 앞뒤 [peakHalfMs] 안에서 가장 큰 점을 걸음으로 센다.
///   그 순간 보행 판정이 참일 때만 센다.
/// 논문에는 기타 움직임(탈것) 구분이 없어서 이 감지기도 정지·보행만 낸다. 그래서 버스 진동을 걸음으로 셀 수 있고,
/// 그 점이 제안판과 비교하려는 지점이다. 평활·피크 창 길이는 출발값이다(원문 확인 후 바꿀 수 있다).
class BrajdicDetector implements StepDetector, StepTimeline {
  BrajdicDetector({this.stdThreshold = 0.6, this.smoothMs = 200, this.peakHalfMs = 200});

  final double stdThreshold;
  final int smoothMs;
  final int peakHalfMs;

  static const _stdWindowMs = 800;

  final _grid = MagnitudeGrid();
  final _raw = RecentValues(_stdWindowMs ~/ gridStepMs);
  late final _smoothing = RecentValues(math.max(1, (smoothMs / gridStepMs).round()));
  late final int _half = math.max(1, (peakHalfMs / gridStepMs).round());
  final _smoothed = ListQueue<({int tMs, double value})>();
  final _stepTimes = <int>[];

  int _total = 0;
  int _totalAtLastFix = 0;
  StepState _state = StepState.still;
  bool _announced = false;

  @override
  String get id => 'brajdic';

  @override
  Map<String, Object> get params =>
      {'std_th': stdThreshold, 'smooth_s': smoothMs / 1000, 'peak_half_s': peakHalfMs / 1000};

  @override
  StepState get state => _state;

  @override
  int get totalSteps => _total;

  @override
  int get stepsSinceLastFix => _total - _totalAtLastFix;

  @override
  StepUpdate? onAccel(int tMs, List<AccelReading> batch) {
    final before = _total;
    for (final reading in batch) {
      for (final sample in _grid.add(reading)) {
        _addSample(sample);
      }
    }
    // 0.8초 창이 차기 전의 '정지'는 관측이 아니라 기본값이라 알리지 않는다.
    if (!_raw.isFull) return null;
    final next = stdDev(_raw.toList()) > stdThreshold ? StepState.walking : StepState.still;
    if (_announced && next == _state && _total == before) return null;
    _announced = true;
    _state = next;
    return StepUpdate(
      tMs: tMs,
      state: _state,
      totalSteps: _total,
      stepsSinceLastFix: stepsSinceLastFix,
    );
  }

  /// 가속도만 쓰는 방식이라 OS 걸음 센서 값은 쓰지 않는다.
  @override
  StepUpdate? onOsStep(OsStepReading reading) => null;

  @override
  void onFix() => _totalAtLastFix = _total;

  @override
  List<int> takeStepTimes() {
    final times = List<int>.of(_stepTimes);
    _stepTimes.clear();
    return times;
  }

  void _addSample(GridSample sample) {
    if (sample.afterGap) {
      // 공백(서비스 재시작 등) 건너편 표본을 한 창에 섞으면 가짜 흔들림과 봉우리가 생긴다.
      _raw.clear();
      _smoothing.clear();
      _smoothed.clear();
    }
    _raw.add(sample.magnitude);
    _smoothing.add(sample.magnitude);
    _smoothed.addLast((tMs: sample.tMs, value: mean(_smoothing.toList())));
    if (_smoothed.length > 2 * _half + 1) _smoothed.removeFirst();
    if (_smoothed.length < 2 * _half + 1) return;

    final window = _smoothed.toList(growable: false);
    final center = window[_half];
    for (var i = 0; i < window.length; i++) {
      // 평평한 꼭대기를 한 번만 세려고 왼쪽은 '더 작아야', 오른쪽은 '크지 않아야' 봉우리로 본다.
      if (i < _half && window[i].value >= center.value) return;
      if (i > _half && window[i].value > center.value) return;
    }
    // 봉우리가 확정된 순간의 0.8초 창으로 보행 여부를 본다(STD_TH).
    if (_raw.isFull && stdDev(_raw.toList()) > stdThreshold) {
      _total++;
      _stepTimes.add(center.tMs);
    }
  }
}
```

`lib/footstep_core.dart`의 export 목록에 더한다(알파벳 순서를 지킨다):

```dart
export 'src/detectors/brajdic_detector.dart';
export 'src/detectors/step_timeline.dart';
```

- [ ] **Step 5: 통과 확인**

Run: `dart test test/detectors/` → PASS.

**기대값이 위 '설계 검증' 표와 다르면 파라미터를 바꾸지 말고 멈춰서 보고한다(DONE_WITH_CONCERNS).** 숫자를 함께 적는다.

이어서 `dart test`(전체)와 `dart analyze` → 0건.

- [ ] **Step 6: 커밋**

```bash
git add packages/footstep_core/lib/src/detectors/ packages/footstep_core/lib/footstep_core.dart packages/footstep_core/test/detectors/
git commit -m "feat(footstep_core): 논문 기준판 걸음 감지기와 걸음 시각 인터페이스를 추가한다"
```

---

### Task 4: 적응형 임계값 걸음 후보 찾기

**Files:**
- Create: `packages/footstep_core/lib/src/detectors/adaptive_peak_finder.dart`
- Test: `packages/footstep_core/test/detectors/adaptive_peak_finder_test.dart`

**Interfaces:**
- Consumes: 없음(입력은 0 중심 걸음 대역 신호, m/s²)
- Produces: `class AdaptivePeakFinder({double minThreshold = -0.588, double initialMaxThreshold = 1.0})`
  - `int? add(int tMs, double value)`: 후보가 확정되면 그 봉우리 시각을 돌려준다.
  - `double get maxThreshold`
  - `void reset()`

- [ ] **Step 1: 실패하는 테스트 작성**

`test/detectors/adaptive_peak_finder_test.dart`:

```dart
import 'dart:math' as math;

import 'package:footstep_core/src/detectors/adaptive_peak_finder.dart';
import 'package:test/test.dart';

void main() {
  /// 50Hz(20ms)로 2Hz 사인을 5초 넣고 확정된 봉우리 시각을 모은다.
  List<int> feedSine(AdaptivePeakFinder finder, {required double amplitude, double offset = 0}) => [
        for (var i = 0; i < 250; i++)
          if (finder.add(i * 20, offset + amplitude * math.sin(2 * math.pi * 2 * i * 20 / 1000))
              case final peakMs?)
            peakMs,
      ];

  test('Tmax를 넘고 Tmin 아래로 내려갔다가 0으로 돌아오면 봉우리 시각 하나를 확정한다', () {
    // 마지막 주기(4620ms 봉우리)는 5초 안에 0으로 돌아오지 않아 아직 확정되지 않는다.
    expect(feedSine(AdaptivePeakFinder(), amplitude: 2),
        [120, 620, 1120, 1620, 2120, 2620, 3120, 3620, 4120]);
  });

  test('Tmax는 직전 두 봉우리 평균의 1/3로 바뀐다(이권희 외 2018 식 (4))', () {
    final finder = AdaptivePeakFinder();
    feedSine(finder, amplitude: 2);
    expect(finder.maxThreshold, closeTo(0.665, 0.001));
  });

  test('Tmax(처음 1.0)를 넘지 못하는 작은 흔들림은 후보가 아니다', () {
    expect(feedSine(AdaptivePeakFinder(), amplitude: 0.5), isEmpty);
  });

  test('Tmin 아래로 내려가지 않으면(골짜기 없음) 확정하지 않는다', () {
    expect(feedSine(AdaptivePeakFinder(), amplitude: 1, offset: 1.5), isEmpty);
  });

  test('reset은 Tmax를 처음 값으로 되돌린다', () {
    final finder = AdaptivePeakFinder();
    feedSine(finder, amplitude: 2);
    finder.reset();
    expect(finder.maxThreshold, 1.0);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `dart test test/detectors/adaptive_peak_finder_test.dart`
Expected: 컴파일 오류(파일 없음)

- [ ] **Step 3: 구현**

`lib/src/detectors/adaptive_peak_finder.dart`:

```dart
/// 적응형 임계값 걸음 후보 찾기(이권희·김광현·오종택, JIIBC 2018, 식 (4)). 신호는 걸음 대역만 남긴 0 중심
/// 가속도 크기(m/s²)다.
/// 1. 최대 임계값(Tmax)을 넘으면 봉우리를 찾기 시작한다.
/// 2. 최소 임계값(Tmin) 아래로 내려갈 때까지 가장 높은 값(Pmax)과 그 시각을 기억한다.
/// 3. 신호가 다시 0 이상으로 올라오면 걸음 후보 하나로 확정하고, Tmax를 직전 두 Pmax 평균의 1/3로 바꾼다.
/// 휴대 위치나 걸음 세기마다 봉우리 크기가 달라도 임계값이 따라간다. 봉우리 사이에 골짜기(Tmin 아래)를 요구하므로
/// 한 걸음 안의 작은 굴곡을 두 번 세지 않는다.
class AdaptivePeakFinder {
  AdaptivePeakFinder({this.minThreshold = -0.588, this.initialMaxThreshold = 1.0})
      : _maxThreshold = initialMaxThreshold;

  /// Tmin. 논문은 중력 단위 0.94(정지 1.0 기준 −0.06g)로 고정한다. 0 중심 m/s²로 바꾸면 −0.06 × 9.80665다.
  final double minThreshold;

  /// 첫 두 봉우리 전의 Tmax. 논문은 '임의 값'으로 정했다. 실제 세션의 보행 봉우리(약 3~5 m/s²)의 1/3 근처다.
  final double initialMaxThreshold;

  double _maxThreshold;
  _Phase _phase = _Phase.waiting;
  double _peak = 0;
  int _peakMs = 0;
  double? _previousPeak;

  double get maxThreshold => _maxThreshold;

  /// 표본 하나를 넣는다. 걸음 후보가 확정되면 그 봉우리 시각을 돌려준다.
  int? add(int tMs, double value) {
    switch (_phase) {
      case _Phase.waiting:
        if (value > _maxThreshold) {
          _phase = _Phase.peak;
          _peak = value;
          _peakMs = tMs;
        }
      case _Phase.peak:
        if (value > _peak) {
          _peak = value;
          _peakMs = tMs;
        }
        if (value < minThreshold) _phase = _Phase.valley;
      case _Phase.valley:
        if (value >= 0) {
          _phase = _Phase.waiting;
          final previous = _previousPeak;
          // 식 (4): Tmax = 1/3 × (두 Pmax의 평균) = (Pmax(i) + Pmax(i−1)) / 6
          if (previous != null) _maxThreshold = (previous + _peak) / 6;
          _previousPeak = _peak;
          return _peakMs;
        }
    }
    return null;
  }

  /// 기록 공백 뒤에는 봉우리 크기 기억을 버리고 처음부터 찾는다.
  void reset() {
    _phase = _Phase.waiting;
    _previousPeak = null;
    _maxThreshold = initialMaxThreshold;
  }
}

enum _Phase { waiting, peak, valley }
```

- [ ] **Step 4: 통과 확인**

Run: `dart test test/detectors/adaptive_peak_finder_test.dart` → PASS. 이어서 `dart analyze` → 0건.

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core/lib/src/detectors/adaptive_peak_finder.dart packages/footstep_core/test/detectors/adaptive_peak_finder_test.dart
git commit -m "feat(footstep_core): 적응형 임계값 걸음 후보 찾기를 추가한다"
```

---

### Task 5: 제안 걸음 감지기(`adaptive`)

**Files:**
- Create: `packages/footstep_core/lib/src/detectors/adaptive_step_detector.dart`
- Modify: `packages/footstep_core/lib/footstep_core.dart`(export 1줄)
- Test: `packages/footstep_core/test/detectors/adaptive_step_detector_test.dart`

**Interfaces:**
- Consumes:
  - Task 2: `MagnitudeGrid`, `GridSample`, `Biquad`, `RecentValues`, `stdDev`, `autocorrelationPeak`, `gridStepMs`
  - Task 4: `AdaptivePeakFinder`
  - Task 3: `StepTimeline`, `synthetic.dart` 도우미
- Produces:
  - `class AdaptiveStepDetector({double shakeThreshold = 0.6, double bandShakeThreshold = 0.3, double rhythmThreshold = 0.4, int confirmSteps = 5, int maxStepGapMs = 1500}) implements StepDetector, StepTimeline`
  - `id == 'adaptive'`
  - `params == {'std_th': 0.6, 'band_std_th': 0.3, 'ac_th': 0.4, 'n_confirm': 5, 'max_gap_s': 1.5}`
  - 보행일 때 `cadenceHz`는 1000 ÷ 걸음 주기(ms)다. 보행이 아니면 null이다.

- [ ] **Step 1: 실패하는 테스트 작성**

`test/detectors/adaptive_step_detector_test.dart`:

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

import 'synthetic.dart';

void main() {
  test('2Hz 보행 30초(60걸음)를 세고, 보행 상태와 걸음 빠르기(2Hz)를 알린다', () {
    final detector = AdaptiveStepDetector();
    final updates = feed(detector, walk(30));

    expect(detector.totalSteps, inInclusiveRange(58, 61));
    expect(updates.last.state, StepState.walking);
    expect(updates.last.cadenceHz, closeTo(2.0, 0.1));
    final times = detector.takeStepTimes();
    expect(times, hasLength(detector.totalSteps));
    expect(times, orderedEquals([...times]..sort()));
  });

  test('연속 N(5)걸음을 확인한 뒤 기다리던 걸음을 소급해 센다', () {
    final detector = AdaptiveStepDetector();
    final updates = feed(detector, walk(30));
    final first = updates.firstWhere((u) => u.totalSteps > 0);

    expect(first.state, StepState.walking);
    expect(first.totalSteps, greaterThanOrEqualTo(5));
    // 소급분이라 첫 걸음 시각은 그 사건보다 이르다.
    expect(detector.takeStepTimes().first, lessThan(first.tMs - 2000));
  });

  test('걸음 빠르기가 달라도 센다(1.5Hz·2.4Hz)', () {
    final slow = AdaptiveStepDetector();
    feed(slow, walk(30, hz: 1.5, seed: 3));
    expect(slow.totalSteps, inInclusiveRange(43, 46));
    final fast = AdaptiveStepDetector();
    feed(fast, walk(30, hz: 2.4, seed: 4));
    expect(fast.totalSteps, inInclusiveRange(70, 73));
  });

  test('끊어 걷기(8걸음 × 3)를 센다', () {
    final detector = AdaptiveStepDetector();
    feed(detector, stopAndGo());
    expect(detector.totalSteps, inInclusiveRange(22, 25));
  });

  test('연속 N걸음에 못 미치는 짧은 움직임(4걸음)은 세지 않는다', () {
    final detector = AdaptiveStepDetector();
    feed(detector, shortBurst());
    expect(detector.totalSteps, 0);
  });

  test('버스 진동은 흔들림만 있고 박자가 없어 기타 움직임이고 0걸음이다', () {
    final detector = AdaptiveStepDetector();
    final updates = feed(detector, bus(60));
    expect(detector.totalSteps, 0);
    expect(updates.map((u) => u.state).toSet(), {StepState.otherMotion});
  });

  test('정지면 0걸음이고, 0.8초 창이 찬 첫 묶음에서 정지를 한 번 알린다', () {
    final detector = AdaptiveStepDetector();
    final updates = feed(detector, still(20));
    expect(updates, hasLength(1));
    expect(updates.single.tMs, 990);
    expect(updates.single.state, StepState.still);
    expect(updates.single.cadenceHz, isNull);
  });

  test('표본 간격이 달라도(50Hz 기기) 같은 결과다', () {
    final detector = AdaptiveStepDetector();
    feed(detector, walk(30, sampleMs: 20));
    expect(detector.totalSteps, inInclusiveRange(58, 61));
  });

  test('기록 공백(7초) 뒤에는 처음부터 다시 확인한다', () {
    final detector = AdaptiveStepDetector();
    feed(detector, gapWalk());
    expect(detector.totalSteps, inInclusiveRange(56, 61));
  });

  test('onFix는 마지막 측위 이후 걸음 수를 0으로 되돌리고, OS 걸음 읽기는 무시한다', () {
    final detector = AdaptiveStepDetector();
    feed(detector, walk(10));
    detector.onFix();
    expect(detector.stepsSinceLastFix, 0);
    expect(detector.onOsStep(const OsStepReading(tMs: 1, kind: OsStepReading.count, value: '5')),
        isNull);
  });

  test('id와 파라미터', () {
    final detector = AdaptiveStepDetector();
    expect(detector.id, 'adaptive');
    expect(detector.params,
        {'std_th': 0.6, 'band_std_th': 0.3, 'ac_th': 0.4, 'n_confirm': 5, 'max_gap_s': 1.5});
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `dart test test/detectors/adaptive_step_detector_test.dart`
Expected: 컴파일 오류(`AdaptiveStepDetector` 없음)

- [ ] **Step 3: 구현**

`lib/src/detectors/adaptive_step_detector.dart`:

```dart
import '../events/policy_event.dart';
import '../model/readings.dart';
import 'adaptive_peak_finder.dart';
import 'signal.dart';
import 'step_detector.dart';
import 'step_timeline.dart';

/// 제안 걸음 감지기(설계 5-2, 연구 자료 4-1).
/// 1. 가속도 크기를 20ms 격자로 다시 표본화하고, 걸음 대역(0.7~3Hz)만 남긴다.
/// 2. 흔들림(0.8초 창 크기 표준편차)이 작으면 정지다.
/// 3. 흔들리는데 박자(3초 창 정규화 자기상관의 봉우리)가 있으면 보행, 없으면 기타 움직임(탈것·폰 만지기)이다.
/// 4. 적응형 임계값(이권희 외 2018)으로 걸음 후보를 찾고, 걸음 주기의 0.6배보다 가까운 후보는 버린다.
/// 5. 연속 N걸음이 모이고 보행이면 그 걸음들을 소급해 센다. 확인된 뒤에는 걸음이 이어지는 동안 바로 센다.
/// 버스 진동처럼 흔들림만 있고 박자가 없는 움직임에서는 확인이 일어나지 않아 걸음을 세지 않는다.
class AdaptiveStepDetector implements StepDetector, StepTimeline {
  AdaptiveStepDetector({
    this.shakeThreshold = 0.6,
    this.bandShakeThreshold = 0.3,
    this.rhythmThreshold = 0.4,
    this.confirmSteps = 5,
    this.maxStepGapMs = 1500,
  }) {
    _restart();
  }

  /// 정지와 움직임을 가르는 0.8초 창 표준편차(m/s²). Brajdic & Harle의 STD_TH 값이다.
  final double shakeThreshold;

  /// 걸음 대역 신호의 0.8초 표준편차 하한(m/s²). 엔진 진동처럼 걸음 대역 밖에서만 흔들리면 박자를 보지 않는다.
  final double bandShakeThreshold;

  /// 박자로 인정하는 자기상관 봉우리 높이(Brajdic & Harle 0.4).
  final double rhythmThreshold;

  /// 소급 카운트 전에 모아야 하는 연속 걸음 수 N(연구 자료 4-1의 5~6 중 5).
  final int confirmSteps;

  /// 이보다 벌어지면 걸음이 끊긴 것으로 본다.
  final int maxStepGapMs;

  static const _lowCutHz = 0.7;
  static const _highCutHz = 3.0;
  static const _shakeWindowMs = 800;
  static const _rhythmWindowMs = 3000;

  /// 자기상관을 보는 지연 범위. 위쪽은 두 걸음(한 보)까지다. 주머니에 넣으면 왼발·오른발 모양이 달라 한 보
  /// 지연의 상관이 더 높게 나온다.
  static const _minLag = 240 ~/ gridStepMs;
  static const _maxLag = 1300 ~/ gridStepMs;

  /// 이보다 긴 봉우리 지연은 한 보(두 걸음)로 보고 걸음 주기를 절반으로 잡는다.
  static const _stepLagLimitMs = 800;
  static const _minIntervalFraction = 0.6;
  static const _defaultPeriodMs = 500.0;

  final _grid = MagnitudeGrid();
  final _shake = RecentValues(_shakeWindowMs ~/ gridStepMs);
  final _band = RecentValues(_rhythmWindowMs ~/ gridStepMs);
  final _peaks = AdaptivePeakFinder();
  late Biquad _lowPass;
  late Biquad _highPass;

  /// 확인을 기다리는 걸음 후보 시각. 최근 2N개까지만 둔다 — 박자 판정(3초 창)이 늦게 서는 동안의 걸음은
  /// 살리되, 오래 이어진 박자 없는 흔들림이 한꺼번에 걸음으로 바뀌지 않게 한다.
  final _pending = <int>[];
  final _stepTimes = <int>[];
  bool _confirmed = false;
  int? _lastStepMs;
  double _periodMs = _defaultPeriodMs;

  int _total = 0;
  int _totalAtLastFix = 0;
  StepState _state = StepState.still;
  bool _announced = false;

  @override
  String get id => 'adaptive';

  @override
  Map<String, Object> get params => {
        'std_th': shakeThreshold,
        'band_std_th': bandShakeThreshold,
        'ac_th': rhythmThreshold,
        'n_confirm': confirmSteps,
        'max_gap_s': maxStepGapMs / 1000,
      };

  @override
  StepState get state => _state;

  @override
  int get totalSteps => _total;

  @override
  int get stepsSinceLastFix => _total - _totalAtLastFix;

  @override
  StepUpdate? onAccel(int tMs, List<AccelReading> batch) {
    final before = _total;
    for (final reading in batch) {
      for (final sample in _grid.add(reading)) {
        _addSample(sample);
      }
    }
    // 0.8초 창이 차기 전의 '정지'는 관측이 아니라 기본값이라 알리지 않는다.
    if (!_shake.isFull) return null;

    final shake = stdDev(_shake.toList());
    var rhythm = -1.0;
    if (shake > shakeThreshold && _band.isFull) {
      final band = _band.toList();
      if (stdDev(band.sublist(band.length - _shake.capacity)) >= bandShakeThreshold) {
        final peak = autocorrelationPeak(band, _minLag, _maxLag);
        if (peak != null) {
          rhythm = peak.r;
          final lagMs = peak.lag * gridStepMs;
          _periodMs = lagMs <= _stepLagLimitMs ? lagMs.toDouble() : lagMs / 2;
        }
      }
    }
    final next = shake <= shakeThreshold
        ? StepState.still
        : rhythm >= rhythmThreshold
            ? StepState.walking
            : StepState.otherMotion;

    if (!_confirmed &&
        _pending.length >= confirmSteps &&
        next == StepState.walking &&
        tMs - _pending.last <= maxStepGapMs) {
      // 박자 있는 보행 안에서 연속 N걸음이 모였다 — 기다리던 걸음을 소급해 센다.
      _count(_pending);
      _lastStepMs = _pending.last;
      _pending.clear();
      _confirmed = true;
    }

    if (_announced && next == _state && _total == before) return null;
    _announced = true;
    _state = next;
    return StepUpdate(
      tMs: tMs,
      state: _state,
      totalSteps: _total,
      stepsSinceLastFix: stepsSinceLastFix,
      cadenceHz: _state == StepState.walking ? 1000 / _periodMs : null,
    );
  }

  /// 가속도만 쓰는 방식이라 OS 걸음 센서 값은 쓰지 않는다(배터리 실험에서 OS 센서판과 비교한다).
  @override
  StepUpdate? onOsStep(OsStepReading reading) => null;

  @override
  void onFix() => _totalAtLastFix = _total;

  @override
  List<int> takeStepTimes() {
    final times = List<int>.of(_stepTimes);
    _stepTimes.clear();
    return times;
  }

  void _addSample(GridSample sample) {
    if (sample.afterGap) _restart();
    _shake.add(sample.magnitude);
    final low = _lowPass.filter(sample.magnitude, steadyOutput: sample.magnitude);
    final band = _highPass.filter(low, steadyOutput: 0);
    _band.add(band);
    final peakMs = _peaks.add(sample.tMs, band);
    if (peakMs != null) _onCandidate(peakMs);
  }

  void _onCandidate(int tMs) {
    final previous = _pending.isNotEmpty ? _pending.last : _lastStepMs;
    // 걸음 주기보다 한참 가까운 후보는 한 걸음 안의 굴곡이다.
    if (previous != null && tMs - previous < _minIntervalFraction * _periodMs) return;
    final last = _lastStepMs;
    if (_confirmed && last != null && tMs - last <= maxStepGapMs) {
      _count([tMs]);
      _lastStepMs = tMs;
      return;
    }
    _confirmed = false;
    if (_pending.isNotEmpty && tMs - _pending.last > maxStepGapMs) _pending.clear();
    _pending.add(tMs);
    if (_pending.length > 2 * confirmSteps) _pending.removeAt(0);
  }

  void _count(List<int> times) {
    _stepTimes.addAll(times);
    _total += times.length;
  }

  /// 처음이나 기록 공백 뒤: 창·필터·후보를 비운다. 걸음 수와 마지막 걸음 시각은 이어 간다.
  void _restart() {
    _lowPass = Biquad.lowPass(_highCutHz, 1000 / gridStepMs);
    _highPass = Biquad.highPass(_lowCutHz, 1000 / gridStepMs);
    _shake.clear();
    _band.clear();
    _peaks.reset();
    _pending.clear();
    _confirmed = false;
  }
}
```

`lib/footstep_core.dart`의 export 목록에 더한다(알파벳 순서):

```dart
export 'src/detectors/adaptive_step_detector.dart';
```

- [ ] **Step 4: 통과 확인**

Run: `dart test test/detectors/adaptive_step_detector_test.dart` → PASS.

**기대값이 '설계 검증' 표와 다르면 파라미터나 알고리즘을 바꾸지 말고 멈춰서 보고한다(DONE_WITH_CONCERNS).** 숫자를 함께 적는다.

이어서 `dart test`(전체)와 `dart analyze` → 0건.

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core/lib/src/detectors/adaptive_step_detector.dart packages/footstep_core/lib/footstep_core.dart packages/footstep_core/test/detectors/adaptive_step_detector_test.dart
git commit -m "feat(footstep_core): 제안 걸음 감지기(흔들림·박자 판정과 연속 걸음 소급 카운트)를 추가한다"
```

---

### Task 6: 감지기 목록·파라미터와 재생기 연결

**Files:**
- Create: `packages/footstep_core/lib/src/params.dart`
- Create: `packages/footstep_core/lib/src/cli/key_values.dart`
- Modify: `packages/footstep_core/lib/src/policies/policy_registry.dart`(전체 교체)
- Modify: `packages/footstep_core/lib/src/detectors/detector_registry.dart`(전체 교체)
- Modify: `packages/footstep_core/lib/src/replay/replay_result.dart`
- Modify: `packages/footstep_core/lib/src/replay/replay_engine.dart`
- Modify: `packages/footstep_core/lib/src/cli/replay_cli.dart`
- Test:
  - `packages/footstep_core/test/registry_test.dart`(마지막 테스트를 바꾼다)
  - `packages/footstep_core/test/cli/key_values_test.dart`(새 파일)
  - `packages/footstep_core/test/cli/replay_cli_test.dart`(테스트 추가)

**Interfaces:**
- Consumes: `OsStepDetector`, `BrajdicDetector`(Task 3), `AdaptiveStepDetector`(Task 5)
- Produces:
  - `class ParamReader(String owner, Map<String, String> params)`
    - `allowOnly(Set<String>)`
    - `double positive(String key, double fallback)`
    - `int positiveInt(String key, int fallback)`
  - `const detectorIds = ['os', 'brajdic', 'adaptive']`
  - `StepDetector createDetector(String id, [Map<String, String> params = const {}])`. 파라미터는 다음과 같다.
    - `brajdic`: `std_th`, `smooth_s`, `peak_half_s`
    - `adaptive`: `std_th`, `band_std_th`, `ac_th`, `n_confirm`, `max_gap_s`
  - `Map<String, String> parseKeyValues(Iterable<String> pairs)`(형식이 틀리면 `FormatException`)
  - `ReplaySummary.detectorParams`(기본 `const {}`)
    - summary.json의 키는 `detector_params`이고, `detector_id` 바로 뒤에 둔다.
  - 재생 CLI의 `--detector-param k=v`(여러 번)

- [ ] **Step 1: 실패하는 테스트 작성**

`test/registry_test.dart`의 마지막 테스트(`'걸음 감지기 id로 감지기를 만든다'`)를 통째로 다음 두 테스트로 바꾼다:

```dart
  test('설계 문서 5-4의 걸음 감지기 id로 감지기를 만든다', () {
    expect(detectorIds, ['os', 'brajdic', 'adaptive']);
    for (final id in detectorIds) {
      expect(createDetector(id).id, id);
    }
    expect(createDetector('brajdic', {'std_th': '0.8', 'smooth_s': '0.1'}).params,
        {'std_th': 0.8, 'smooth_s': 0.1, 'peak_half_s': 0.2});
    expect(createDetector('adaptive', {'n_confirm': '6', 'ac_th': '0.5'}).params,
        {'std_th': 0.6, 'band_std_th': 0.3, 'ac_th': 0.5, 'n_confirm': 6, 'max_gap_s': 1.5});
  });

  test('모르는 감지기·파라미터·잘못된 숫자는 ArgumentError다', () {
    expect(() => createDetector('nope'), throwsArgumentError);
    expect(() => createDetector('os', {'std_th': '0.6'}), throwsArgumentError);
    expect(() => createDetector('adaptive', {'n_confirm': '2.5'}), throwsArgumentError);
    expect(() => createDetector('adaptive', {'n_confirm': '0'}), throwsArgumentError);
    expect(() => createDetector('brajdic', {'std_th': 'NaN'}), throwsArgumentError);
  });
```

`test/cli/key_values_test.dart`:

```dart
import 'package:footstep_core/src/cli/key_values.dart';
import 'package:test/test.dart';

void main() {
  test('k=v 목록을 맵으로 바꾸고, 값에는 =가 더 있어도 된다', () {
    expect(parseKeyValues(['a=1', 'b=x=y', 'c=']), {'a': '1', 'b': 'x=y', 'c': ''});
  });

  test('=가 없거나 키가 비면 FormatException이다', () {
    expect(() => parseKeyValues(['abc']), throwsFormatException);
    expect(() => parseKeyValues(['=1']), throwsFormatException);
  });
}
```

`test/cli/replay_cli_test.dart`의 `main()` 안 맨 끝에 더한다:

```dart
  test('--detector와 --detector-param이 재생과 summary.json에 들어간다', () async {
    final outDir = p.join(root.path, 'out3');
    final code = await runReplayCli([
      '--session', session.path, '--policy', 'still_suppress', '--detector', 'adaptive',
      '--detector-param', 'n_confirm=6', '--out', outDir,
    ], out: out, err: err);

    expect(code, 0, reason: err.toString());
    final summary =
        jsonDecode(File(p.join(outDir, 'summary.json')).readAsStringSync()) as Map<String, Object?>;
    expect(summary['detector_id'], 'adaptive');
    expect((summary['detector_params'] as Map)['n_confirm'], 6);
  });

  test('--detector-param 형식이 틀리거나 모르는 파라미터면 64를 돌려준다', () async {
    for (final bad in ['n_confirm', 'nope=1']) {
      final code = await runReplayCli([
        '--session', session.path, '--policy', 'fixed_1m', '--detector', 'adaptive',
        '--detector-param', bad, '--out', p.join(root.path, 'o'),
      ], out: StringBuffer(), err: err);
      expect(code, 64, reason: '--detector-param $bad');
    }
  });
```

- [ ] **Step 2: 실패 확인**

Run: `dart test test/registry_test.dart test/cli/`
Expected: 실패. `detectorIds`가 `['os']`이고, `key_values.dart`가 없고, `--detector-param`도 아직 모른다.

- [ ] **Step 3: 구현**

`lib/src/params.dart`:

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
}
```

`lib/src/policies/policy_registry.dart` 전체:

```dart
import '../params.dart';
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
      reader.allowOnly(const {'interval_s'});
      return StillSuppressPolicy(intervalMs: (reader.positive('interval_s', 60) * 1000).round());
    case 'activity_gated':
      reader.allowOnly(const {});
      return ActivityGatedPolicy();
    default:
      throw ArgumentError('알 수 없는 정책: $id (가능: ${policyIds.join(', ')})');
  }
}
```

`lib/src/detectors/detector_registry.dart` 전체:

```dart
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
      reader.allowOnly(const {'std_th', 'smooth_s', 'peak_half_s'});
      return BrajdicDetector(
        stdThreshold: reader.positive('std_th', 0.6),
        smoothMs: (reader.positive('smooth_s', 0.2) * 1000).round(),
        peakHalfMs: (reader.positive('peak_half_s', 0.2) * 1000).round(),
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
```

`lib/src/cli/key_values.dart`:

```dart
/// CLI의 `k=v` 목록을 맵으로 바꾼다. '='가 없거나 키가 비면 FormatException이다(값은 비어도 되고 '='를 더 담아도 된다).
Map<String, String> parseKeyValues(Iterable<String> pairs) {
  final result = <String, String>{};
  for (final pair in pairs) {
    final i = pair.indexOf('=');
    if (i <= 0) throw FormatException('k=v 형식이어야 합니다: $pair');
    result[pair.substring(0, i)] = pair.substring(i + 1);
  }
  return result;
}
```

`lib/src/replay/replay_result.dart`의 `ReplaySummary`:
- 생성자에서 `required this.detectorId,` 다음 줄에 `this.detectorParams = const {},`를 더한다.
- `final String detectorId;` 다음에 더한다:

```dart

  /// 걸음 감지기 파라미터. 감지기 파라미터를 바꿔 가며 재생한 결과를 구분하려고 남긴다.
  final Map<String, Object> detectorParams;
```

- `toJson()`에서 `'detector_id': detectorId,` 다음 줄에 `'detector_params': detectorParams,`를 더한다.

`lib/src/replay/replay_engine.dart`: `ReplaySummary(...)`를 만드는 곳의 `detectorId: detector.id,` 다음 줄에 `detectorParams: detector.params,`를 더한다.

`lib/src/cli/replay_cli.dart`:
- import에 `import 'key_values.dart';`를 더한다.
- `_usage`를 바꾼다:

```dart
const _usage = '사용법: dart run footstep_core:replay --session <세션 폴더> --policy <정책 id> '
    '--out <결과 폴더> [--param k=v ...] [--detector os|brajdic|adaptive] '
    '[--detector-param k=v ...] [--ttff 초]';
```

- 파서의 `..addOption('detector', ...)` 다음 줄에 더한다:

```dart
    ..addMultiOption('detector-param',
        help: '걸음 감지기 파라미터 k=v (여러 번 줄 수 있다)', splitCommas: false)
```

- `final params = <String, String>{};`부터 그 `for` 루프 끝까지를 다음으로 바꾼다:

```dart
  final Map<String, String> params;
  final Map<String, String> detectorParams;
  try {
    params = parseKeyValues(args.multiOption('param'));
    detectorParams = parseKeyValues(args.multiOption('detector-param'));
  } on FormatException catch (e) {
    return usageError(e.message);
  }
```

- `detector = createDetector(args.option('detector')!);`를 `detector = createDetector(args.option('detector')!, detectorParams);`로 바꾼다.

- [ ] **Step 4: 통과 확인**

Run: `dart test`(전체) → PASS. 정책 목록 테스트도 그대로 통과해야 한다(오류 문구 형식이 같다). `dart analyze` → 0건.

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core/lib/ packages/footstep_core/test/
git commit -m "feat(footstep_core): 재생기에서 논문 기준판·제안판 감지기와 감지기 파라미터를 고른다"
```

---

### Task 7: 걸음 감지 실행기와 `steps` CLI

**Files:**
- Create: `packages/footstep_core/lib/src/steps/step_run.dart`
- Create: `packages/footstep_core/lib/src/steps/steps_output.dart`
- Create: `packages/footstep_core/lib/src/cli/steps_cli.dart`
- Create: `packages/footstep_core/bin/steps.dart`
- Modify: `packages/footstep_core/lib/footstep_core.dart`(export 2줄)
- Test: `packages/footstep_core/test/steps/step_run_test.dart`
- Test: `packages/footstep_core/test/steps/steps_output_test.dart`
- Test: `packages/footstep_core/test/cli/steps_cli_test.dart`

**Interfaces:**
- Consumes:
  - Task 1: `SessionData`(`marks` 포함), `MarkReading`
  - Task 2: `accelBatches`
  - Task 3: `StepTimeline`
  - Task 6: `createDetector`, `detectorIds`, `parseKeyValues`
  - R2: `readSession`, `formatCsvField`
- Produces:
  - `class StateChange({required int tMs, required StepState state, double? cadenceHz})`
  - `class StepRun({sessionId, detectorId, detectorParams, startMs, endMs, stepTimes, states})` + `int get totalSteps`
  - `StepRun runDetector(SessionData data, StepDetector detector, {int accelBatchMs = 1000})`
    - 기록이 없거나 `accelBatchMs <= 0`이면 `ArgumentError`
  - `abstract final class StepsSchema`
    - `stepsFile = 'steps.csv'`, `stepsHeader = ['t_ms', 'total_steps']`
    - `statesFile = 'step_states.csv'`, `statesHeader = ['t_ms', 'state', 'cadence_hz']`
    - `summaryFile = 'step_summary.json'`
  - `class CountInterval({startMs, endMs, manualSteps (int?), detectedSteps})` + `double? get errorPct`
  - `class VehicleInterval({boardMs, alightMs, kind, detectedSteps})`
  - `List<CountInterval> countIntervals(List<MarkReading> marks, List<int> stepTimes)`
  - `List<VehicleInterval> vehicleIntervals(List<MarkReading> marks, List<int> stepTimes)`
  - `Map<String, double> stateSeconds(StepRun run)`(키 `unknown`, `still`, `walking`, `otherMotion`)
  - `Map<String, Object?> stepSummary(StepRun run, List<MarkReading> marks)`
  - `Future<void> writeStepsOutput(StepRun run, List<MarkReading> marks, Directory outDir)`
  - `Future<int> runStepsCli(List<String> arguments, {StringSink? out, StringSink? err})`
    - 종료 코드: 0 성공, 64 사용법 오류, 65 기록 없는 세션, 66 세션 폴더 없음

- [ ] **Step 1: 실패하는 테스트 작성**

`test/steps/step_run_test.dart`:

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

OsStepReading count(int tMs, int value) =>
    OsStepReading(tMs: tMs, kind: OsStepReading.count, value: '$value');

/// 걸음 시각을 모르는 감지기 흉내: 가속도 묶음마다 2걸음씩 늘었다고 알리고, 부른 순서를 남긴다.
class _CountOnly implements StepDetector {
  final calls = <String>[];
  int _total = 0;

  @override
  String get id => 'count_only';

  @override
  Map<String, Object> get params => const {};

  @override
  StepState get state => StepState.walking;

  @override
  int get totalSteps => _total;

  @override
  int get stepsSinceLastFix => _total;

  @override
  StepUpdate? onAccel(int tMs, List<AccelReading> batch) {
    calls.add('accel@$tMs');
    _total += 2;
    return StepUpdate(
        tMs: tMs, state: StepState.walking, totalSteps: _total, stepsSinceLastFix: _total);
  }

  @override
  StepUpdate? onOsStep(OsStepReading reading) {
    calls.add('os@${reading.tMs}');
    return null;
  }

  @override
  void onFix() {}
}

void main() {
  final stillAccel = [for (var t = 0; t <= 4990; t += 10) AccelReading(tMs: t, x: 0, y: 9.81, z: 0)];

  test('가속도 묶음과 OS 걸음을 시각순으로 넣고, 걸음 시각과 상태 변화를 모은다', () {
    final data = SessionData(
      sessionId: 's1',
      accel: stillAccel,
      osSteps: [count(1000, 100), count(2000, 103), count(3000, 105)],
    );

    final run = runDetector(data, OsStepDetector());

    expect(run.sessionId, 's1');
    expect(run.detectorId, 'os');
    expect(run.startMs, 0);
    expect(run.endMs, 4990);
    expect(run.stepTimes, [2000, 2000, 2000, 3000, 3000]);
    expect(run.totalSteps, 5);
    expect(run.states.map((s) => (s.tMs, s.state)),
        [(1000, StepState.still), (2000, StepState.walking)]);
  });

  test('걸음 시각을 모르는 감지기는 늘어난 걸음을 알린 시각에 두고, 같은 시각은 가속도 묶음이 먼저다', () {
    final detector = _CountOnly();
    final data = SessionData(
      sessionId: 's2',
      accel: [for (var t = 0; t <= 2000; t += 10) AccelReading(tMs: t, x: 0, y: 9.81, z: 0)],
      osSteps: [count(990, 1)],
    );

    final run = runDetector(data, detector);

    expect(detector.calls, ['accel@990', 'os@990', 'accel@1990', 'accel@2000']);
    expect(run.stepTimes, [990, 990, 1990, 1990, 2000, 2000]);
    expect(run.states.map((s) => s.tMs), [990]); // 상태가 바뀔 때만 남는다
  });

  test('기록이 없는 세션이나 0 이하 묶음 길이는 ArgumentError다', () {
    expect(() => runDetector(const SessionData(sessionId: 'empty'), OsStepDetector()),
        throwsArgumentError);
    expect(
        () => runDetector(SessionData(sessionId: 's', accel: stillAccel), OsStepDetector(),
            accelBatchMs: 0),
        throwsArgumentError);
  });
}
```

`test/steps/steps_output_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:footstep_core/footstep_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

MarkReading mark(int tMs, String kind, [String value = '']) =>
    MarkReading(tMs: tMs, kind: kind, value: value);

void main() {
  final marks = [
    mark(1000, MarkReading.countStart),
    mark(11000, MarkReading.countEnd, '10'),
    mark(12000, MarkReading.countStart),
    mark(15000, MarkReading.countEnd), // 센 수를 안 적었다
    mark(20000, MarkReading.board, 'bus'),
    mark(30000, MarkReading.alight),
    mark(40000, MarkReading.board, 'subway'), // 내리기 전에 세션이 끝났다
  ];
  const steps = [500, 1000, 5000, 11000, 12500, 25000];

  test('걸음 세기 구간은 count_start~count_end(양 끝 포함)이고, 센 수가 있으면 오차(%)를 낸다', () {
    final intervals = countIntervals(marks, steps);

    expect(intervals.map((c) => (c.startMs, c.endMs, c.manualSteps, c.detectedSteps)), [
      (1000, 11000, 10, 3),
      (12000, 15000, null, 1),
    ]);
    expect(intervals.first.errorPct, closeTo(-70.0, 1e-9));
    expect(intervals.last.errorPct, isNull);
  });

  test('탈것 구간은 board~alight이고, 내리지 않은 탑승은 넣지 않는다', () {
    final intervals = vehicleIntervals(marks, steps);
    expect(intervals.map((v) => (v.boardMs, v.alightMs, v.kind, v.detectedSteps)),
        [(20000, 30000, 'bus', 1)]);
  });

  test('steps.csv·step_states.csv·step_summary.json을 쓴다', () async {
    final root = await Directory.systemTemp.createTemp('steps_output_test');
    addTearDown(() => root.delete(recursive: true));
    const run = StepRun(
      sessionId: 's1',
      detectorId: 'adaptive',
      detectorParams: {'n_confirm': 5},
      startMs: 0,
      endMs: 40000,
      stepTimes: steps,
      states: [
        StateChange(tMs: 2000, state: StepState.still),
        StateChange(tMs: 10000, state: StepState.walking, cadenceHz: 2.0),
      ],
    );
    final out = Directory(p.join(root.path, 'nested', 'out'));

    await writeStepsOutput(run, marks, out);

    expect(File(p.join(out.path, StepsSchema.stepsFile)).readAsLinesSync(),
        ['t_ms,total_steps', '500,1', '1000,2', '5000,3', '11000,4', '12500,5', '25000,6']);
    expect(File(p.join(out.path, StepsSchema.statesFile)).readAsLinesSync(),
        ['t_ms,state,cadence_hz', '2000,still,', '10000,walking,2.0']);
    final summary = jsonDecode(File(p.join(out.path, StepsSchema.summaryFile)).readAsStringSync())
        as Map<String, Object?>;
    expect(summary['detector_id'], 'adaptive');
    expect(summary['detector_params'], {'n_confirm': 5});
    expect(summary['total_steps'], 6);
    expect(summary['state_seconds'],
        {'unknown': 2.0, 'still': 8.0, 'walking': 30.0, 'otherMotion': 0.0});
    expect((summary['count_intervals'] as List).first,
        {'start_ms': 1000, 'end_ms': 11000, 'manual_steps': 10, 'detected_steps': 3, 'error_pct': -70.0});
    expect((summary['vehicle_intervals'] as List).single,
        {'board_ms': 20000, 'alight_ms': 30000, 'kind': 'bus', 'detected_steps': 1});
  });
}
```

`test/cli/steps_cli_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:footstep_core/src/cli/steps_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../detectors/synthetic.dart';

void main() {
  late Directory root;
  late Directory session;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('steps_cli_test');
    session = Directory(p.join(root.path, 'mini-groundTruth'))..createSync();
    final rows = [for (final r in walk(10)) '${r.tMs},${r.x},${r.y},${r.z}'];
    File(p.join(session.path, 'accel.csv')).writeAsStringSync('t_ms,x,y,z\n${rows.join('\n')}\n');
    File(p.join(session.path, 'marks.csv'))
        .writeAsStringSync('t_ms,kind,value\n0,count_start,\n9990,count_end,20\n');
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() async => root.delete(recursive: true));

  test('감지기를 돌려 결과 파일을 쓰고 한 줄 요약을 출력한다', () async {
    final outDir = p.join(root.path, 'out');
    final code = await runStepsCli(
        ['--session', session.path, '--detector', 'adaptive', '--out', outDir],
        out: out, err: err);

    expect(code, 0, reason: err.toString());
    expect(out.toString(), contains('adaptive steps='));
    expect(File(p.join(outDir, 'steps.csv')).readAsLinesSync().length, greaterThan(10));
    final summary =
        jsonDecode(File(p.join(outDir, 'step_summary.json')).readAsStringSync()) as Map<String, Object?>;
    expect((summary['count_intervals'] as List).single['manual_steps'], 20);
  });

  test('--detector-param이 감지기에 들어간다', () async {
    final outDir = p.join(root.path, 'out2');
    final code = await runStepsCli([
      '--session', session.path, '--detector', 'adaptive', '--detector-param', 'n_confirm=6',
      '--out', outDir,
    ], out: out, err: err);

    expect(code, 0, reason: err.toString());
    final summary =
        jsonDecode(File(p.join(outDir, 'step_summary.json')).readAsStringSync()) as Map<String, Object?>;
    expect((summary['detector_params'] as Map)['n_confirm'], 6);
  });

  test('필수 옵션이 없거나, 모르는 감지기·틀린 파라미터면 64를 돌려준다', () async {
    expect(await runStepsCli(const [], out: out, err: err), 64);
    expect(err.toString(), contains('사용법'));
    for (final args in [
      ['--detector', 'nope'],
      ['--detector', 'adaptive', '--detector-param', 'n_confirm'],
      ['--detector', 'os', '--detector-param', 'n_confirm=6'],
    ]) {
      final code = await runStepsCli(
          ['--session', session.path, ...args, '--out', p.join(root.path, 'o')],
          out: StringBuffer(), err: StringBuffer());
      expect(code, 64, reason: args.join(' '));
    }
  });

  test('세션 폴더가 없으면 66, 기록이 없는 폴더면 65다', () async {
    expect(
        await runStepsCli([
          '--session', p.join(root.path, 'missing'), '--detector', 'os', '--out', p.join(root.path, 'o'),
        ], out: out, err: err),
        66);
    final empty = Directory(p.join(root.path, 'empty'))..createSync();
    expect(
        await runStepsCli(['--session', empty.path, '--detector', 'os', '--out', p.join(root.path, 'o')],
            out: out, err: err),
        65);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `dart test test/steps/ test/cli/steps_cli_test.dart`
Expected: 컴파일 오류(파일 없음)

- [ ] **Step 3: 구현**

`lib/src/steps/step_run.dart`:

```dart
import '../detectors/step_detector.dart';
import '../detectors/step_timeline.dart';
import '../events/policy_event.dart';
import '../replay/accel_batches.dart';
import '../session/session_reader.dart';

/// 감지기 상태가 바뀐 순간(첫 분류 포함).
class StateChange {
  const StateChange({required this.tMs, required this.state, this.cadenceHz});

  final int tMs;
  final StepState state;
  final double? cadenceHz;
}

/// 걸음 감지기 하나를 정책 없이 세션에 돌린 결과. 걸음 감지 평가(설계 7-2)의 입력이다.
class StepRun {
  const StepRun({
    required this.sessionId,
    required this.detectorId,
    required this.detectorParams,
    required this.startMs,
    required this.endMs,
    required this.stepTimes,
    required this.states,
  });

  final String sessionId;
  final String detectorId;
  final Map<String, Object> detectorParams;
  final int startMs;
  final int endMs;

  /// 센 걸음마다 그 걸음의 시각(오름차순).
  final List<int> stepTimes;

  /// 상태가 바뀐 순간들(시각순).
  final List<StateChange> states;

  int get totalSteps => stepTimes.length;
}

/// [data]의 가속도 묶음과 OS 걸음을 시각순으로 [detector]에 넣는다. 묶는 규칙과 같은 시각의 순서(가속도 묶음
/// 먼저)는 재생기와 같다 — 재생 결과와 걸음 평가가 같은 감지기 동작을 보게 한다.
StepRun runDetector(SessionData data, StepDetector detector, {int accelBatchMs = 1000}) {
  final start = data.startMs;
  final end = data.endMs;
  if (start == null || end == null) {
    throw ArgumentError('기록이 없는 세션입니다: ${data.sessionId}');
  }
  if (accelBatchMs <= 0) throw ArgumentError('accelBatchMs는 양수여야 합니다: $accelBatchMs');

  final batches = accelBatches(data.accel, accelBatchMs).toList();
  final osSteps = data.osSteps;
  final stepTimes = <int>[];
  final states = <StateChange>[];
  var lastTotal = 0;

  void handle(StepUpdate? update) {
    if (detector case final StepTimeline timeline) {
      stepTimes.addAll(timeline.takeStepTimes());
    } else if (update != null && update.totalSteps > lastTotal) {
      // 걸음 시각을 모르는 감지기는 늘어난 걸음을 알린 시각에 둔다.
      stepTimes.addAll(List.filled(update.totalSteps - lastTotal, update.tMs));
    }
    if (update == null) return;
    lastTotal = update.totalSteps;
    if (states.isEmpty || states.last.state != update.state) {
      states.add(StateChange(tMs: update.tMs, state: update.state, cadenceHz: update.cadenceHz));
    }
  }

  var i = 0;
  var j = 0;
  while (i < batches.length || j < osSteps.length) {
    final takeBatch =
        j >= osSteps.length || (i < batches.length && batches[i].last.tMs <= osSteps[j].tMs);
    if (takeBatch) {
      final batch = batches[i++];
      handle(detector.onAccel(batch.last.tMs, batch));
    } else {
      handle(detector.onOsStep(osSteps[j++]));
    }
  }
  stepTimes.sort();

  return StepRun(
    sessionId: data.sessionId,
    detectorId: detector.id,
    detectorParams: detector.params,
    startMs: start,
    endMs: end,
    stepTimes: stepTimes,
    states: states,
  );
}
```

`lib/src/steps/steps_output.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../events/policy_event.dart';
import '../model/readings.dart';
import '../session/csv.dart';
import 'step_run.dart';

/// 걸음 감지 결과 파일 이름과 헤더. R6 분석이 같은 이름을 읽는다.
abstract final class StepsSchema {
  static const stepsFile = 'steps.csv';
  static const stepsHeader = ['t_ms', 'total_steps'];
  static const statesFile = 'step_states.csv';
  static const statesHeader = ['t_ms', 'state', 'cadence_hz'];
  static const summaryFile = 'step_summary.json';
}

/// 걸음 세기 구간 하나(count_start~count_end, 양 끝 포함)와 직접 센 걸음 수.
class CountInterval {
  const CountInterval({
    required this.startMs,
    required this.endMs,
    required this.manualSteps,
    required this.detectedSteps,
  });

  final int startMs;
  final int endMs;

  /// count_end에 적은 수. 안 적었으면 null이다.
  final int? manualSteps;
  final int detectedSteps;

  /// (감지 − 직접 센 수) ÷ 직접 센 수 × 100. 센 수가 없거나 0이면 null이다.
  double? get errorPct {
    final manual = manualSteps;
    if (manual == null || manual == 0) return null;
    return (detectedSteps - manual) / manual * 100;
  }
}

/// 탈것 구간 하나(board~alight). 정답 걸음 수는 0이다(설계 7-2).
class VehicleInterval {
  const VehicleInterval({
    required this.boardMs,
    required this.alightMs,
    required this.kind,
    required this.detectedSteps,
  });

  final int boardMs;
  final int alightMs;

  /// board의 값(bus·subway·vehicle).
  final String kind;
  final int detectedSteps;
}

int _stepsBetween(List<int> stepTimes, int fromMs, int toMs) =>
    stepTimes.where((t) => t >= fromMs && t <= toMs).length;

/// count_start 다음의 count_end를 짝지어 구간을 만든다. count_end 전에 count_start를 또 누르면 나중 것을 쓴다.
List<CountInterval> countIntervals(List<MarkReading> marks, List<int> stepTimes) {
  final intervals = <CountInterval>[];
  int? start;
  for (final mark in marks) {
    if (mark.kind == MarkReading.countStart) {
      start = mark.tMs;
    } else if (mark.kind == MarkReading.countEnd) {
      final from = start;
      if (from == null) continue;
      intervals.add(CountInterval(
        startMs: from,
        endMs: mark.tMs,
        manualSteps: int.tryParse(mark.value.trim()),
        detectedSteps: _stepsBetween(stepTimes, from, mark.tMs),
      ));
      start = null;
    }
  }
  return intervals;
}

/// board 다음의 alight를 짝지어 구간을 만든다. 내리기 전에 세션이 끝난 탑승은 넣지 않는다(끝을 모른다).
List<VehicleInterval> vehicleIntervals(List<MarkReading> marks, List<int> stepTimes) {
  final intervals = <VehicleInterval>[];
  MarkReading? boarded;
  for (final mark in marks) {
    if (mark.kind == MarkReading.board) {
      boarded = mark;
    } else if (mark.kind == MarkReading.alight) {
      final from = boarded;
      if (from == null) continue;
      intervals.add(VehicleInterval(
        boardMs: from.tMs,
        alightMs: mark.tMs,
        kind: from.value,
        detectedSteps: _stepsBetween(stepTimes, from.tMs, mark.tMs),
      ));
      boarded = null;
    }
  }
  return intervals;
}

/// 상태별로 머문 시간(초). 첫 분류 전은 unknown이다.
Map<String, double> stateSeconds(StepRun run) {
  final seconds = <String, double>{
    'unknown': 0,
    for (final state in StepState.values) state.name: 0,
  };
  final states = run.states;
  final firstMs = states.isEmpty ? run.endMs : states.first.tMs;
  seconds['unknown'] = (firstMs - run.startMs) / 1000;
  for (var k = 0; k < states.length; k++) {
    final untilMs = k + 1 < states.length ? states[k + 1].tMs : run.endMs;
    final name = states[k].state.name;
    seconds[name] = seconds[name]! + (untilMs - states[k].tMs) / 1000;
  }
  return seconds;
}

Map<String, Object?> stepSummary(StepRun run, List<MarkReading> marks) => {
      'session_id': run.sessionId,
      'detector_id': run.detectorId,
      'detector_params': run.detectorParams,
      'start_ms': run.startMs,
      'end_ms': run.endMs,
      'duration_s': (run.endMs - run.startMs) / 1000,
      'total_steps': run.totalSteps,
      'state_seconds': stateSeconds(run),
      'count_intervals': [
        for (final c in countIntervals(marks, run.stepTimes))
          {
            'start_ms': c.startMs,
            'end_ms': c.endMs,
            'manual_steps': c.manualSteps,
            'detected_steps': c.detectedSteps,
            'error_pct': c.errorPct,
          },
      ],
      'vehicle_intervals': [
        for (final v in vehicleIntervals(marks, run.stepTimes))
          {
            'board_ms': v.boardMs,
            'alight_ms': v.alightMs,
            'kind': v.kind,
            'detected_steps': v.detectedSteps,
          },
      ],
    };

/// [outDir]에 steps.csv·step_states.csv·step_summary.json을 쓴다(폴더가 없으면 만든다).
Future<void> writeStepsOutput(StepRun run, List<MarkReading> marks, Directory outDir) async {
  await outDir.create(recursive: true);

  String csv(List<String> header, Iterable<List<Object?>> rows) {
    final buffer = StringBuffer()..writeln(header.join(','));
    for (final row in rows) {
      buffer.writeln(row.map(formatCsvField).join(','));
    }
    return buffer.toString();
  }

  await File(p.join(outDir.path, StepsSchema.stepsFile)).writeAsString(csv(
    StepsSchema.stepsHeader,
    [for (var k = 0; k < run.stepTimes.length; k++) [run.stepTimes[k], k + 1]],
  ));
  await File(p.join(outDir.path, StepsSchema.statesFile)).writeAsString(csv(
    StepsSchema.statesHeader,
    [for (final s in run.states) [s.tMs, s.state.name, s.cadenceHz]],
  ));
  await File(p.join(outDir.path, StepsSchema.summaryFile))
      .writeAsString(const JsonEncoder.withIndent('  ').convert(stepSummary(run, marks)));
}
```

`lib/src/cli/steps_cli.dart`:

```dart
import 'dart:io';

import 'package:args/args.dart';

import '../detectors/detector_registry.dart';
import '../detectors/step_detector.dart';
import '../session/session_reader.dart';
import '../steps/step_run.dart';
import '../steps/steps_output.dart';
import 'key_values.dart';

const _usage = '사용법: dart run footstep_core:steps --session <세션 폴더> '
    '--detector os|brajdic|adaptive --out <결과 폴더> [--detector-param k=v ...]';

/// 걸음 감지 CLI. 감지기 하나만 세션에 돌려 걸음 시각·상태·걸음 세기 구간을 쓴다.
/// 종료 코드는 재생기와 같다: 0 성공, 64 사용법 오류, 65 기록 없는 세션, 66 세션 폴더 없음.
Future<int> runStepsCli(List<String> arguments, {StringSink? out, StringSink? err}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final parser = ArgParser()
    ..addOption('session', help: 'R1 세션 폴더')
    ..addOption('detector', help: '걸음 감지기 (${detectorIds.join(', ')})')
    ..addMultiOption('detector-param',
        help: '걸음 감지기 파라미터 k=v (여러 번 줄 수 있다)', splitCommas: false)
    ..addOption('out', help: '결과 폴더(steps.csv, step_states.csv, step_summary.json)');

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
  final detectorId = args.option('detector');
  final outPath = args.option('out');
  if (sessionPath == null || detectorId == null || outPath == null) {
    return usageError('--session, --detector, --out은 꼭 줘야 합니다.');
  }

  final StepDetector detector;
  try {
    detector = createDetector(detectorId, parseKeyValues(args.multiOption('detector-param')));
  } on FormatException catch (e) {
    return usageError(e.message);
  } on ArgumentError catch (e) {
    return usageError('${e.message}');
  }

  final sessionDir = Directory(sessionPath);
  if (!await sessionDir.exists()) {
    stderrSink.writeln('세션 폴더가 없습니다: $sessionPath');
    return 66;
  }
  final data = await readSession(sessionDir);

  final StepRun run;
  try {
    run = runDetector(data, detector);
  } on ArgumentError catch (e) {
    stderrSink.writeln('${e.message}');
    return 65;
  }

  await writeStepsOutput(run, data.marks, Directory(outPath));
  final seconds = stateSeconds(run);
  String s(String key) => seconds[key]!.toStringAsFixed(0);
  stdoutSink.writeln('${run.detectorId} steps=${run.totalSteps} walking=${s('walking')}s '
      'still=${s('still')}s other=${s('otherMotion')}s '
      'count_intervals=${countIntervals(data.marks, run.stepTimes).length} '
      'vehicle_intervals=${vehicleIntervals(data.marks, run.stepTimes).length} '
      'skipped_rows=${data.skippedRows} -> $outPath');
  return 0;
}
```

`bin/steps.dart`:

```dart
import 'dart:io';

import 'package:footstep_core/src/cli/steps_cli.dart';

/// `dart run footstep_core:steps ...` (packages/footstep_core/에서). 사용법은 docs/research/steps-guide.md.
Future<void> main(List<String> arguments) async {
  exitCode = await runStepsCli(arguments);
}
```

`lib/footstep_core.dart`의 export 목록에 더한다(알파벳 순서):

```dart
export 'src/steps/step_run.dart';
export 'src/steps/steps_output.dart';
```

- [ ] **Step 4: 통과 확인**

Run: `dart test test/steps/ test/cli/steps_cli_test.dart` → PASS. 이어서 `dart test`(전체)와 `dart analyze` → 0건.

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core/lib/ packages/footstep_core/bin/steps.dart packages/footstep_core/test/
git commit -m "feat(footstep_core): 걸음 감지기만 세션에 돌려 걸음 시각과 구간 오차를 쓰는 CLI를 추가한다"
```

---

### Task 8: 실제 세션 확인 + 안내 문서

**Files:**
- Create: `docs/research/steps-guide.md`
- Modify: `docs/research/replay-guide.md`
- Modify: `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md`(5-2 표, 5-4 아래 한 줄)

**Interfaces:**
- Consumes: Task 1~7 전체
- Produces: 문서만(코드 변경 없음)

- [ ] **Step 1: 실제 세션으로 확인**

로컬에 R1 세션 `research/data/sessions/20261109-213324-groundTruth`가 있으면 다음을 돌린다(Bash, `packages/footstep_core/`에서). 결과는 임시 폴더에 쓰고 지운다.

```bash
S=../../research/data/sessions/20261109-213324-groundTruth
O="$(mktemp -d)"
if [ -d "$S" ]; then
  for D in os brajdic adaptive; do
    dart run footstep_core:steps --session "$S" --detector "$D" --out "$O/steps-$D"
  done
  for D in brajdic adaptive; do
    dart run footstep_core:replay --session "$S" --policy still_suppress --detector "$D" --out "$O/replay-$D"
  done
else
  echo "세션 없음 — 건너뜀"
fi
rm -rf "$O"
```

Expected (세션이 있을 때): 다섯 줄 모두 종료 코드 0이고, 걸음 수는 다음 범위다(설계 검증 표).
- `os`: steps=875
- `adaptive`: steps 860~915
- `brajdic`: steps 900~1000
- `adaptive`의 walking 시간이 300~500초다(이 세션의 걷기는 약 7분).

출력 다섯 줄을 태스크 보고서에 그대로 붙인다. **범위를 벗어나면 멈추고 보고한다.**

- [ ] **Step 2: 앱 쪽이 그대로인지 확인**

`app/`에서 `flutter test`와 `dart analyze`를 돌린다. 앱은 `footstep_core`의 세션 계약만 쓰므로 그대로 통과해야 한다.

- [ ] **Step 3: 안내 문서 작성**

`docs/research/steps-guide.md`:

````markdown
# 걸음 감지 실행 안내 (R3)

R1 세션의 가속도·OS 걸음으로 걸음 감지기를 PC에서 돌려 걸음 시각·상태를 파일로 만든다. 직접 센 걸음 수(`count_start`~`count_end`)와 비교한 오차도 함께 낸다. 설계는 `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md` 5-2·7-2.

## 감지기

| id | 방식 |
|---|---|
| `os` | OS 걸음 센서(전용 저전력 칩). 최근 4초 안에 누적값이 늘었거나 OS 상태가 walking이면 보행 |
| `brajdic` | 논문 기준판(Brajdic & Harle 2013). 0.8초 표준편차 > 0.6이면 보행, 다듬은 크기의 창 봉우리를 걸음으로 센다. 탈것을 구분하지 않는다 |
| `adaptive` | 제안판. 걸음 대역(0.7~3Hz) + 흔들림·박자(자기상관 봉우리) 판정 + 적응형 임계값(이권희 외 2018) + 연속 5걸음 확인 후 소급 카운트. 흔들림만 있고 박자가 없으면 기타 움직임 |

## 실행

`packages/footstep_core/`에서:

```bash
dart run footstep_core:steps --session <세션 폴더> --detector os|brajdic|adaptive --out <결과 폴더> \
    [--detector-param k=v ...]
```

예: `dart run footstep_core:steps --session ../../research/data/sessions/20261109-213324-groundTruth --detector adaptive --out ../../research/results/steps/s1-adaptive`

재생기에서도 같은 감지기를 고른다: `dart run footstep_core:replay ... --detector adaptive [--detector-param n_confirm=6]`

## 파라미터 (`--detector-param`)

| 감지기 | 이름 | 기본값 | 뜻 |
|---|---|---|---|
| `brajdic` | `std_th` | 0.6 | 보행 판정 표준편차(m/s², 0.8초 창) |
| `brajdic` | `smooth_s` | 0.2 | 이동 평균 길이(초) — 출발값, 논문 원문 확인 필요 |
| `brajdic` | `peak_half_s` | 0.2 | 봉우리 판정 반창(초) — 출발값, 논문 원문 확인 필요 |
| `adaptive` | `std_th` | 0.6 | 정지/움직임 표준편차(m/s²) |
| `adaptive` | `band_std_th` | 0.3 | 걸음 대역 흔들림 하한(m/s²) |
| `adaptive` | `ac_th` | 0.4 | 박자로 보는 자기상관 봉우리 |
| `adaptive` | `n_confirm` | 5 | 소급 카운트 전 연속 걸음 수 |
| `adaptive` | `max_gap_s` | 1.5 | 이보다 벌어지면 걸음이 끊긴 것 |

**최종값은 예비용(pilot) 세션으로만 정한다.** 평가용(eval) 세션을 보고 파라미터를 고르면 결과가 부풀려진다(설계 7-1).

## 결과 파일

- `steps.csv`: `t_ms,total_steps` — 센 걸음마다 한 줄(소급 카운트한 걸음도 그 걸음의 시각)
- `step_states.csv`: `t_ms,state,cadence_hz` — 상태가 바뀐 순간(`still`·`walking`·`otherMotion`)
- `step_summary.json`: 감지기·파라미터, 총 걸음, 상태별 시간(초), 걸음 세기 구간별 직접 센 수·감지 수·오차(%), 탈것 구간(`board`~`alight`)의 가짜 걸음 수

## 평가용 기록 남기는 법 (실험 화면)

- **걸음 세기:** '걸음 세기 시작'을 누르고 100~300걸음을 직접 세며 걷는다. '걸음 세기 끝'에 센 수를 적는다. 휴대 위치(손·주머니·가방)를 바꿔 가며 세션마다 몇 구간씩 넣는다.
- **탈것:** 버스·지하철을 탈 때 '탑승', 내릴 때 '하차'를 누른다. 그 구간의 정답 걸음 수는 0이다.
- **휴대 위치:** 바꿀 때마다 '휴대 위치'를 남긴다. 결과를 위치별로 나눠 보고한다.

## 해석할 때 주의

- OS 걸음 센서는 걸음을 몇 개씩 묶어 늦게 알린다. 구간 경계 근처 걸음은 실제보다 늦은 시각으로 남는다.
- `adaptive`는 연속 5걸음 미만의 짧은 움직임을 세지 않는다(설계 의도). 4걸음 이하로 끊기는 구간이 많으면 과소 계수가 된다.
- 손으로 폰을 규칙적으로 흔드는 동작처럼, 흔들림이 걸음 대역 안에서 박자를 가지면 걸음으로 셀 수 있다(확장 과제: DePedo).
- 결과 폴더(`research/results/`)와 세션(`research/data/`)은 커밋하지 않는다.
````

`docs/research/replay-guide.md`:
- '실행' 절 코드 블록의 둘째 줄 `  [--param k=v ...] [--detector os] [--ttff 초]`를 다음으로 바꾼다:

```
  [--param k=v ...] [--detector os|brajdic|adaptive] [--detector-param k=v ...] [--ttff 초]
```

- 그 아래 `예: ...` 줄 다음에 빈 줄을 두고 다음 문단을 더한다:

```markdown
걸음 감지기는 `--detector`로 고른다(기본 `os`). `--detector-param k=v`로 감지기 파라미터를 바꾸면 summary.json의 `detector_params`에 남는다. 감지기 목록과 파라미터는 `docs/research/steps-guide.md`에 있다.
```

설계 문서 5-2 표에서 `BrajdicDetector`, `AdaptiveStepDetector` 두 행을 다음으로 바꾼다.

```markdown
| `BrajdicDetector` (`brajdic`) | 논문 기준판. 보행 판정은 STD_TH(0.8초 창, 표준편차 0.6), 걸음 검출은 WPD(이동 평균 0.2초, 봉우리 반창 0.2초 — 출발값). 기타 움직임은 구분하지 않는다. |
| `AdaptiveStepDetector` (`adaptive`) | 제안판. 20ms 격자 → 걸음 대역(0.7~3Hz) → 흔들림(0.8초 표준편차 0.6, 대역 0.3) + 박자(3초 창 자기상관 **봉우리** 0.4) 판정 → 적응형 임계값 피크(이권희 외 2018 식 (4), Tmin −0.588) → 걸음 주기 0.6배 최소 간격 → 연속 5걸음 확인 후 소급 카운트. 흔들림은 있는데 박자가 없으면 기타 움직임. |
```

5-4의 마지막 줄(`- 같은 입력과 같은 파라미터에는 항상 같은 출력이 나온다.`) 다음 줄에 더한다.

```markdown
- 걸음 감지만 따로 볼 때는 `dart run footstep_core:steps --session <dir> --detector <id> --out <dir>`가 `steps.csv`·`step_states.csv`·`step_summary.json`을 쓴다(R3, 안내 `docs/research/steps-guide.md`).
```

- [ ] **Step 4: 커밋**

```bash
git add docs/research/steps-guide.md docs/research/replay-guide.md docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md
git commit -m "docs: 걸음 감지 실행 안내를 추가하고 설계 문서에 감지기 세부를 적는다"
```

- [ ] **Step 5: 마무리 확인**

- `packages/footstep_core/`에서 `dart test`(전체)와 `dart analyze` → 통과, 0건
- `git status`에 `research/`와 결과 폴더가 없다
- `git log --format=%B origin/replay..HEAD | grep -iE "co-authored|claude"`가 빈 결과다
