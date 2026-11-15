# R5 머문 곳 묶기·경로 복원 API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 재생기가 남긴 드문 점으로 머문 곳을 묶어 `stays.csv`를 쓰고(모듈 C-1), 서버에 경로 복원 API `POST /api/route/reconstruct`를 더한다(모듈 C-2). 제안은 두 가지다. 머문 곳의 도착·출발을 걸음 감지기의 정지 구간으로 잡고, 맵 매칭 HMM의 전이 확률에 걸음 수 × 보폭을 쓴다(`hmm_steps`). R3에서 남긴 `fixes.csv` `steps_since_prev` 누락도 고친다.

**Architecture:**
- 패키지(`packages/footstep_core`)
  - `lib/src/stays/`의 `detectStays`는 순수 함수다. 점 목록과 정지 구간을 받아 머문 곳을 돌려준다. 재생기와 R7 날짜별 보기가 같은 함수를 쓴다.
  - 재생기는 정책을 돌린 그 감지기의 상태 변화를 모아 정지 구간을 만들고, 끝에 머문 곳을 묶어 `stays.csv`를 쓴다.
  - 재생기는 끝에 걸음 시각(`StepTimeline`)으로 측위 사이 걸음 수를 다시 센다. 정책이 받은 값은 그대로라 미래 정보 차단은 깨지지 않는다.
- 서버(`server/.../route/`)
  - `ReconstructController` → `RouteReconstructionService`(머문 곳 → 공백 → 도보/탈것 → 방법별 연결) → 방법별 `Reconstructor`(straight·nearest·osrm_match·osrm_match_radius·hmm_steps).
  - `Reconstructor`는 빈이 아니다. 서비스가 생성자에서 `OsrmClient` 하나로 만든다. 그래서 테스트는 가짜 `OsrmClient`(격자 도로망) 하나로 서비스 전체를 돌린다.
  - `OsrmClient`에 `nearestCandidates`·`table`·반경/시각 `match`를 default 메서드로 더한다. 기존 `/snap`·해외 매핑 동작은 그대로다.
  - 실패는 예외가 아니라 직선 조각 + `fallback: true`다(기존 OsrmClient의 "실패 = 빈 결과" 규칙을 응답까지 잇는다).

**Tech Stack:**
- Dart 3.13.2(footstep_core) — 의존성 변화 없음
- Spring Boot 3.5.3, Java 21(server) — 의존성 변화 없음
- OSRM `osrm/osrm-backend`(도보 프로필, `osrm/docker-compose.yml`, 포트 5001)

**설계 문서·근거:**
- `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md`
  - 5-4: 재생기 출력(`stays.csv`)
  - 5-6: 머문 곳 묶기(모듈 C-1)
  - 6장: 경로 복원 API(모듈 C-2)
  - 7장: R6가 쓰는 R5 출력(머문 곳 F1, 복원 방법별 경로 오차)
- Li, Zheng, Zhang, Chen, Xie, Ma, "Mining User Similarity Based on Location History", ACM GIS 2008
  - 머문 곳 정의: 기준점에서 반경 안의 연속한 점, 도착 = 첫 점, 출발 = 마지막 점, 중심 = 평균, 머문 시간 ≥ 임계값
- Newson & Krumm, "Hidden Markov Map Matching Through Noise and Sparseness", ACM SIGSPATIAL GIS 2009 — https://www.microsoft.com/en-us/research/wp-content/uploads/2016/12/map-matching-ACM-GIS-camera-ready.pdf
  - 3.1절: 방사 확률(식 1, 가우시안), 200m 밖 후보 버림
  - 3.2절: 전이 확률(식 2·3, |직선거리 − 도로 경로거리|의 지수분포)
  - 4.2절: break 조건(도로 경로가 직선보다 2000m 이상 길면 확률 0)과 처리
  - 5.2절: σ_z = 1.4826 median|z − x|(이들 데이터 4.07m), β = median|직선 − 도로| / ln 2(식 5·6). 성능을 최대로 하는 값 찾기는 후속 과제로 남김
- OSRM HTTP API(`docs/http.md`): `/match`의 `radiuses`는 "GPS 정확도의 표준편차"(기본 5m), `timestamps`는 늘어나는 초. `/table`의 `annotations=distance`, 길 없는 칸은 null. `/nearest`의 `number`
- OSRM `map_matching.cpp`: `MATCHING_BETA = 10`, `MAX_DISTANCE_DELTA = 2000` — hmm_steps의 β 기본값과 전이 상한의 근거

## 설계 검증 (임시 작업 폴더, 커밋하지 않음)

이 계획의 코드는 `policy` 브랜치(da2d7af)에서 갈라 둔 임시 작업 폴더에서 먼저 그대로 짜서 검증했다.
- 패키지: `dart test` 214개 통과, `dart analyze` 0건
- 서버: `./gradlew test` 308개 통과(route 패키지 50개). Testcontainers 테스트가 있어 Docker Desktop이 켜져 있어야 한다.
- 태스크마다 그 태스크까지의 코드만 놓고 테스트가 통과하는 것도 확인했다.

아래 실제 세션 재생 값이 Task 8의 확인 기준이다. 세션은 `20261109-213324-groundTruth`(15분 47초, 손에 들고 걷기 약 7분 + 실내 정지 약 6분, ttff 0)다. 측위 횟수·GPS 켜짐은 R4 표와 같다(정책 동작은 바뀌지 않았다).

| 정책 | 감지기 | 파라미터 | 측위 | GPS 켜짐 | 머문 곳 | steps_since_prev 합(고치기 전 → 후) |
|---|---|---|---|---|---|---|
| `hourly` | os | — | 1 | 1초 | 0 | 0 → 0 |
| `fixed_1m` | os | — | 16 | 7초 | 0 | 875 → 875 |
| `fixed_5m` | os | — | 4 | 2초 | 0 | 875 → 875 |
| `fixed_5m` | os | `--stay-param use_still=false` | 4 | 2초 | 1 | 875 → 875 |
| `continuous_10m` | os | — | 53 | 947초 | 0 | 867 → 867 |
| `still_suppress` | os | — | 11 | 4초 | 0 | 875 → 875 |
| `step_budget` | os | — | 18 | 8초 | 0 | 875 → 875 |
| `step_budget` | adaptive | — | 16 | 9초 | 0 | 857 → **871** |
| `step_budget` | brajdic | — | 17 | 10초 | 0 | 915 → 915 (8행 바뀜) |
| `step_budget` | adaptive | `--stay-param use_still=false` | 16 | 9초 | 0 | 857 → **871** |
| `step_budget` | adaptive | `--param e_m=25` | 35 | 24초 | 0 | 843 → **871** |

- 실제로 머문 곳(실내 정지)이 6분이라 기본 T=10분에서는 0곳이 맞다.
- `fixed_5m` + `use_still=false`의 1곳은 거짓 머문 곳이다. 걷던 점(300초, 출발점에서 107m) 하나와 실내 점(600·900초) 두 개가 서로 100m 안이라 딱 10분으로 묶였다. 제안 방식은 정지 구간(약 590초~끝)으로 재 6분이라 걸러 낸다.
- `adaptive`는 걷기 시작 몇 초 안의 측위에서 소급 카운트한 걸음이 빠졌다(합 857 → 871). 871은 R3의 `steps` CLI가 센 전체 걸음 수와 같다. `os`는 한 행도 바뀌지 않고, `brajdic`는 측위 경계 근처 걸음이 옆 행으로 옮겨 합은 같다.

**검증 중에 정한 설계 하나 — 정지 구간이 머문 시간을 정한다.**
- 처음에는 무리의 첫 점·마지막 점이 정지 구간 안일 때만 그 구간 끝까지 늘렸다(점만으로 잰 시간을 넓히기만 함).
- 실제 세션 `fixed_5m`에서 위의 거짓 머문 곳이 그대로 남았다. 무리의 첫 점이 걷던 점이라 늘릴 것도 줄일 것도 없었기 때문이다.
- 그래서 무리 안에 정지 구간의 점이 있으면 첫 정지 구간 시작 ~ 마지막 정지 구간 끝을 머문 시간으로 쓰고, 그 밖의 점(걸어 들어오고 떠나며 찍힌 점)은 중심에서도 뺀다. 정지 구간 안의 점이 없으면 Li 외(2008) 그대로다.

## Global Constraints

- 작업 브랜치는 `route`다. `policy`(R4, PR #37 리뷰 중)에서 갈라진다. 다른 브랜치를 만들지 않는다.
- 커밋에 `Co-Authored-By`, `Claude-Session` 같은 AI 트레일러를 넣지 않는다. push 전에 `git log --format=%B policy..HEAD | grep -iE "co-authored|claude"`가 빈 결과인지 확인한다.
- `packages/footstep_core`는 Flutter에 의존하지 않는다. 런타임 의존성은 `path`와 `args`뿐이고, 개발 의존성은 `test`와 `lints`다. 이 계획은 의존성을 바꾸지 않는다.
- 패키지 안의 시각은 모두 `int` UTC epoch 밀리초다. 패키지 로직에서 `DateTime.now()`나 난수를 쓰지 않는다.
- 머문 곳 묶기 값
  - `radius_m` 100, `min_stay_s` 600, `use_still` true(CLI `--stay-param`, summary.json `stay_params`)
  - 반경은 무리의 첫 점(기준점)에서 잰다. 기록 끝까지 머문 무리도 머문 곳이다.
  - `stays.csv`: `arrive_ms,leave_ms,lat,lng,n_points`
- 경로 복원 값
  - 점 최대 2000개, 머문 곳 최대 500개, 국가 KR 고정, `method`를 빼면 `osrm_match_radius`
  - 공백 10분(앞 점의 끝 시각 → 다음 점 시각)
  - `osrm_match_radius` 반경 = 정확도를 5~50m로 맞춤(없으면 5m), 시각 = 초(같은 초면 1초 밀어 늘어나게)
  - `nearest`·`hmm_steps` 후보 반경 200m, `hmm_steps` 후보 5개(1m 안은 같은 후보)
  - `hmm_steps` 기본값 β 10m, σ 하한 5m, 보폭 0.75m, `useSteps` true. 전이 차이 2000m 이상은 불가능
  - 구간 종류는 도착하는 점의 `state`가 `vehicle`이면 `vehicle`, 아니면 `walk`. 공백은 `estimated`
  - 응답 구간에는 `fallback`(true·false)이 늘 있다
- 서버 프로덕션 코드(`server/src/main/**`)에는 Spring 개념을 처음 배우는 사람을 위한 한국어 설명 주석을 단다(CLAUDE.md). 테스트에는 적용하지 않는다.
- 테스트·분석은 다음 명령으로 한다.
  - 패키지(`packages/footstep_core/`): `dart test`, `dart analyze`
  - 서버(`server/`, Git Bash): `./gradlew test`. 전체 실행에는 Docker Desktop이 켜져 있어야 한다(Testcontainers). 태스크 중간에는 `./gradlew test --tests 'com.travelfootsteps.route.*'`로 빠르게 본다.
  - 앱은 이 계획에서 건드리지 않는다. `flutter analyze`는 이 PC에서 죽으므로 쓰지 않는다.
- 수집한 세션 데이터(`research/data/`)와 결과는 커밋하지 않는다. 비밀정보(`firebase-service-account.json`, `.env`)도 커밋하지 않는다.
- 코드 주석은 한국어로 '왜'를 적는다.

## 파일 구조

```
packages/footstep_core/
  lib/src/stays/stay_detector.dart       StayParams, createStayParams, TimeSpan, Stay, stillSpans, detectStays (Task 1)
  lib/footstep_core.dart                 export 1줄 (Task 1)
  lib/src/replay/replay_engine.dart      steps_since_prev 다시 세기 (Task 2), 상태 변화 모으기·머문 곳 (Task 3)
  lib/src/replay/replay_result.dart      ReplayResult.stays, ReplaySummary.stayParams·stayCount (Task 3)
  lib/src/replay/replay_output.dart      stays.csv (Task 3)
  lib/src/cli/replay_cli.dart            --stay-param (Task 3)
server/src/main/java/com/travelfootsteps/route/
  OsrmClient.java, HttpOsrmClient.java   nearestCandidates, table, 반경·시각 match (Task 4)
  Waypoint.java, HmmOptions.java, Reconstructor.java, HmmStepsReconstructor.java   (Task 5)
  ReconstructMethod.java, SegmentKind.java, TrackPoint.java, StayInput.java, ReconstructRequest.java,
  RouteSegment.java, ReconstructResponse.java, StraightReconstructor.java, NearestReconstructor.java,
  OsrmMatchReconstructor.java, RouteReconstructionService.java   (Task 6)
  ReconstructController.java             (Task 7)
server/src/test/java/com/travelfootsteps/route/
  HttpOsrmClientTest.java (Task 4), GridOsrm.java·HmmStepsReconstructorTest.java (Task 5),
  RouteReconstructionServiceTest.java (Task 6), ReconstructControllerTest.java (Task 7)
docs/research/route-guide.md             경로 복원 안내 (Task 8)
docs/research/replay-guide.md            --stay-param, stays.csv (Task 8)
```

---

### Task 1: 머문 곳 묶기 모듈 (모듈 C-1)

**Files:**
- Create: `packages/footstep_core/lib/src/stays/stay_detector.dart`
- Modify: `packages/footstep_core/lib/footstep_core.dart`(export 1줄)
- Test: `packages/footstep_core/test/stays/stay_detector_test.dart`

**Interfaces:**
- Consumes: R2의 `Fix`, `haversineMeters`, `ParamReader`, R3의 `StateChange`(`lib/src/steps/step_run.dart`), `StepState`
- Produces:
  - `StayParams({double radiusM = 100, int minDurationMs = 600000, bool useStillIntervals = true})`, `params` → `{'radius_m': 100.0, 'min_stay_s': 600.0, 'use_still': true}`, `check()`(0 이하면 ArgumentError)
  - `StayParams createStayParams([Map<String, String> params])` — 키 `radius_m`·`min_stay_s`·`use_still`
  - `TimeSpan(int startMs, int endMs)`(양 끝 포함, `contains`, 값 비교)
  - `Stay({arriveMs, leaveMs, lat, lng, nPoints})`, `durationMs`
  - `List<TimeSpan> stillSpans(List<StateChange> states, int endMs)`
  - `List<Stay> detectStays(List<Fix> points, {List<TimeSpan> stillSpans = const [], StayParams params = const StayParams()})`

- [ ] **Step 1: 실패하는 테스트 작성**

`packages/footstep_core/test/stays/stay_detector_test.dart`:

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

/// 위도 1도 = 111,195m(geo.dart의 지구 반지름 기준).
const _degPerMeter = 1 / 111195.08;

/// [minute]분에 기준 위치에서 북쪽으로 [northM]m인 점.
Fix at(double minute, double northM) => Fix(
      tMs: (minute * 60000).round(),
      lat: 37.5 + northM * _degPerMeter,
      lng: 127.0,
      accuracyM: 5,
    );

TimeSpan minutes(double from, double to) => TimeSpan((from * 60000).round(), (to * 60000).round());

void main() {
  group('점만으로 묶기 (Li 외 2008)', () {
    const pointsOnly = StayParams(useStillIntervals: false);

    test('10분 넘게 머문 두 곳을 도착·출발 시각과 함께 찾는다', () {
      // A에서 0~12분(±10m 흔들림), 13~15분 이동, B(북쪽 1200m)에서 16~28분, 29분에 떠난다.
      final points = [
        for (var m = 0; m <= 12; m++) at(m.toDouble(), m.isEven ? 10 : -10),
        at(13, 300),
        at(14, 600),
        at(15, 900),
        for (var m = 16; m <= 28; m++) at(m.toDouble(), 1200 + (m.isEven ? 5 : -5)),
        at(29, 1500),
      ];

      final stays = detectStays(points, params: pointsOnly);

      expect(stays.map((s) => (s.arriveMs, s.leaveMs, s.nPoints)), [
        (0, 12 * 60000, 13),
        (16 * 60000, 28 * 60000, 13),
      ]);
      expect(haversineMeters(stays[0].lat, stays[0].lng, 37.5, 127.0), lessThan(2));
      expect(haversineMeters(stays[1].lat, stays[1].lng, 37.5 + 1200 * _degPerMeter, 127.0), lessThan(2));
    });

    test('머문 시간이 10분에 못 미치면 머문 곳이 아니다', () {
      final points = [for (var m = 0; m <= 9; m++) at(m.toDouble(), 0), at(10, 500)];

      expect(detectStays(points, params: pointsOnly), isEmpty);
    });

    test('기준점(첫 점)에서 반경 밖의 점이 나오면 무리가 끝난다', () {
      // 0~10분은 기준점에서 99m 안, 11분은 101m — 무리는 0~10분(10분)이다.
      final points = [for (var m = 0; m <= 10; m++) at(m.toDouble(), m * 9.9), at(11, 101)];

      final stay = detectStays(points, params: pointsOnly).single;
      expect((stay.arriveMs, stay.leaveMs, stay.nPoints), (0, 10 * 60000, 11));
    });

    test('기록 끝까지 머문 무리도 머문 곳이다', () {
      final points = [for (var m = 0; m <= 11; m++) at(m.toDouble(), 0)];

      final stay = detectStays(points, params: pointsOnly).single;
      expect((stay.arriveMs, stay.leaveMs), (0, 11 * 60000));
    });

    test('정지 구간을 줘도 쓰지 않는다', () {
      final points = [at(0, -300), at(5, 0), at(10, 0), at(15, 300)];

      expect(detectStays(points, stillSpans: [minutes(1.5, 13)], params: pointsOnly), isEmpty);
    });
  });

  group('걸음 감지기 정지 구간으로 시각 잡기 (제안)', () {
    test('5분마다 잰 점 두 개뿐이어도 정지 구간으로 도착·출발 시각을 잡는다', () {
      // 1.5분에 도착해 13분에 떠났다. 점은 5분·10분 두 개라 점 사이는 5분뿐이다.
      final points = [at(0, -300), at(5, 0), at(10, 3), at(15, 300)];

      final stay = detectStays(points, stillSpans: [minutes(1.5, 13)]).single;

      expect((stay.arriveMs, stay.leaveMs, stay.nPoints), (90000, 13 * 60000, 2));
      expect(haversineMeters(stay.lat, stay.lng, 37.5 + 1.5 * _degPerMeter, 127.0), lessThan(0.1));
    });

    test('점 하나라도 정지 구간이 길면 머문 곳이다(1시간 주기 측위)', () {
      final points = [at(0, -3000), at(60, 0), at(120, 3000)];

      final stay = detectStays(points, stillSpans: [minutes(40, 80)]).single;
      expect((stay.arriveMs, stay.leaveMs, stay.nPoints), (40 * 60000, 80 * 60000, 1));
    });

    test('정지 구간이 이웃 점보다 앞서 시작하면 걸음 없이 옮겨 온 것이라 도착은 점 시각이다', () {
      // OS 센서판은 버스 안에서도 정지다. 0분 점(2km 남쪽)부터 이미 정지였으니 언제 도착했는지 모른다.
      final points = [at(0, -2000), at(5, 0), at(10, 0), at(15, 0), at(20, 300)];

      final stay = detectStays(points, stillSpans: [minutes(-1, 17)]).single;
      expect((stay.arriveMs, stay.leaveMs, stay.nPoints), (5 * 60000, 17 * 60000, 3));
    });

    test('정지 구간이 다음 점 뒤까지 이어지면 출발은 점 시각이다', () {
      final points = [at(0, -300), at(5, 0), at(16, 0), at(20, 3000)];

      final stay = detectStays(points, stillSpans: [minutes(1, 25)]).single;
      expect((stay.arriveMs, stay.leaveMs), (60000, 16 * 60000));
    });

    test('반경 안에 걸어 들어오며 찍힌 점은 머문 곳에 넣지 않고 정지 구간 시작을 도착으로 쓴다', () {
      // 0분 점은 60m 남쪽에서 걸어오던 중(정지 구간 밖)이다. 1분에 멈춰 11분에 떠났다.
      final points = [at(0, -60), at(5, 0), at(9, 0), at(15, 300)];

      final stay = detectStays(points, stillSpans: [minutes(1, 11)]).single;
      expect((stay.arriveMs, stay.leaveMs, stay.nPoints), (60000, 11 * 60000, 2));
      expect(haversineMeters(stay.lat, stay.lng, 37.5, 127.0), lessThan(0.1));
    });

    test('걷다 찍힌 점이 정지 점들과 반경 안에 묶여도 머문 시간은 정지 구간으로 잰다', () {
      // 5분 점은 걷는 중(90m 북쪽), 9.5분에 멈춰 기록 끝(15.8분)까지 있었다. 점만으로는 5~15분이 10분이라
      // 머문 곳이 되지만, 실제로 머문 시간은 6.3분이다(실제 세션 fixed_5m 재생에서 본 경우).
      final points = [at(0, -400), at(5, 90), at(10, 0), at(15, 5)];
      final spans = [minutes(9.5, 15.8)];

      expect(detectStays(points, stillSpans: spans), isEmpty);
      expect(detectStays(points, stillSpans: spans, params: const StayParams(useStillIntervals: false))
          .map((s) => (s.arriveMs, s.leaveMs, s.nPoints)), [(5 * 60000, 15 * 60000, 3)]);
    });
  });

  test('걸음 감지기 상태 변화에서 정지 구간을 뽑는다(마지막 상태는 끝 시각까지)', () {
    final states = [
      const StateChange(tMs: 0, state: StepState.still),
      const StateChange(tMs: 1000, state: StepState.walking),
      const StateChange(tMs: 5000, state: StepState.still),
      const StateChange(tMs: 9000, state: StepState.otherMotion),
      const StateChange(tMs: 12000, state: StepState.still),
    ];

    expect(stillSpans(states, 20000),
        [const TimeSpan(0, 1000), const TimeSpan(5000, 9000), const TimeSpan(12000, 20000)]);
    expect(stillSpans(const [], 20000), isEmpty);
  });

  group('설정과 입력 검증', () {
    test('CLI 파라미터로 설정을 만든다', () {
      expect(createStayParams().params, {'radius_m': 100.0, 'min_stay_s': 600.0, 'use_still': true});
      expect(createStayParams({'radius_m': '50', 'min_stay_s': '300', 'use_still': 'false'}).params,
          {'radius_m': 50.0, 'min_stay_s': 300.0, 'use_still': false});
      expect(() => createStayParams({'radius': '50'}), throwsArgumentError);
      expect(() => createStayParams({'min_stay_s': '0'}), throwsArgumentError);
    });

    test('시각순이 아닌 점이나 0 이하의 반경·시간은 ArgumentError다', () {
      expect(() => detectStays([at(1, 0), at(0, 0)]), throwsArgumentError);
      expect(() => detectStays([at(0, 0)], params: const StayParams(radiusM: 0)), throwsArgumentError);
      expect(() => detectStays([at(0, 0)], params: const StayParams(minDurationMs: 0)), throwsArgumentError);
    });

    test('점이 없으면 머문 곳도 없다', () {
      expect(detectStays(const []), isEmpty);
    });
  });
}
```

- [ ] **Step 2: 실패 확인**

Run (`packages/footstep_core/`에서): `dart test test/stays/`

Expected: FAIL. `detectStays`·`StayParams`·`TimeSpan`이 없어 컴파일되지 않는다.

- [ ] **Step 3: 구현**

`packages/footstep_core/lib/src/stays/stay_detector.dart`:

```dart
import '../events/policy_event.dart';
import '../geo.dart';
import '../model/fix.dart';
import '../params.dart';
import '../steps/step_run.dart';

/// 머문 곳 묶기 설정(설계 5-6). 기본값은 Li 외(2008)의 반경 100m, 10분이다.
class StayParams {
  const StayParams({this.radiusM = 100, this.minDurationMs = 600000, this.useStillIntervals = true});

  /// 첫 점(기준점)에서 이 거리(m) 안에 이어진 점들을 한 곳으로 본다.
  final double radiusM;

  /// 이보다 오래 머물러야 머문 곳이다.
  final int minDurationMs;

  /// 걸음 감지기의 정지 구간으로 도착·출발 시각을 잡는다(제안). false면 점만으로 묶는다(Li 외 2008, 절제 실험).
  final bool useStillIntervals;

  /// summary.json의 stay_params. 이름은 CLI `--stay-param`과 같다.
  Map<String, Object> get params =>
      {'radius_m': radiusM, 'min_stay_s': minDurationMs / 1000, 'use_still': useStillIntervals};

  /// 반경·시간이 양수가 아니면 ArgumentError다 — 0이면 모든 점이 따로 놀거나 모든 점이 머문 곳이 된다.
  void check() {
    if (!radiusM.isFinite || radiusM <= 0) throw ArgumentError('radiusM은 양수여야 합니다: $radiusM');
    if (minDurationMs <= 0) throw ArgumentError('minDurationMs는 양수여야 합니다: $minDurationMs');
  }
}

/// CLI의 `--stay-param k=v`로 설정을 만든다. 모르는 키나 잘못된 값은 ArgumentError다.
StayParams createStayParams([Map<String, String> params = const {}]) {
  final reader = ParamReader('머문 곳 묶기', params)..allowOnly(const {'radius_m', 'min_stay_s', 'use_still'});
  return StayParams(
    radiusM: reader.positive('radius_m', 100),
    minDurationMs: (reader.positive('min_stay_s', 600) * 1000).round(),
    useStillIntervals: reader.flag('use_still', true),
  );
}

/// 시각 구간 [startMs, endMs](양 끝 포함).
class TimeSpan {
  const TimeSpan(this.startMs, this.endMs);

  final int startMs;
  final int endMs;

  bool contains(int tMs) => tMs >= startMs && tMs <= endMs;

  @override
  bool operator ==(Object other) => other is TimeSpan && other.startMs == startMs && other.endMs == endMs;

  @override
  int get hashCode => Object.hash(startMs, endMs);

  @override
  String toString() => 'TimeSpan($startMs, $endMs)';
}

/// 머문 곳 하나(stays.csv의 행).
class Stay {
  const Stay({
    required this.arriveMs,
    required this.leaveMs,
    required this.lat,
    required this.lng,
    required this.nPoints,
  });

  final int arriveMs;
  final int leaveMs;

  /// 묶인 점들의 평균 위치.
  final double lat;
  final double lng;

  /// 묶인 점 수.
  final int nPoints;

  int get durationMs => leaveMs - arriveMs;
}

/// 걸음 감지기 상태 변화에서 정지 구간을 뽑는다. 마지막 상태는 [endMs]까지 이어진 것으로 본다.
/// [states]는 상태가 바뀐 순간만 담은 시각순 목록이다(StepRun.states와 같은 규칙).
List<TimeSpan> stillSpans(List<StateChange> states, int endMs) => [
      for (var k = 0; k < states.length; k++)
        if (states[k].state == StepState.still)
          TimeSpan(states[k].tMs, k + 1 < states.length ? states[k + 1].tMs : endMs),
    ];

/// 머문 곳 묶기(모듈 C-1, 설계 5-6).
///
/// 점 묶기는 Li 외(2008)의 정의를 따른다. 기준점 p_i에서 [StayParams.radiusM] 안에 이어진 점 p_i..p_j를 한 무리로
/// 보고, 도착 p_i·출발 p_j 시각 사이가 [StayParams.minDurationMs] 이상이면 머문 곳이다. 중심은 무리의 평균,
/// 다음 기준점은 p_(j+1)이다. 못 미치면 기준점을 하나 옮긴다. 기록 끝까지 머문 무리도 머문 곳으로 친다.
///
/// 제안([StayParams.useStillIntervals]): 무리에 걸음 감지기 정지 구간 안의 점이 있으면, 그 첫 점이 든 정지 구간의
/// 시작을 도착, 마지막 점이 든 정지 구간의 끝을 출발로 쓴다. 점이 드물어도(예: 5분마다 측위) 머문 시간을 알 수
/// 있고, 걸어오거나 떠나며 반경 안에 찍힌 점은 머문 시간에 넣지 않는다. 머문 곳의 점은 도착~출발 사이의 점이다.
/// 정지 구간이 이웃 점보다 먼저 시작하거나 늦게 끝나면 걸음 없이 옮겨 온 것(OS 센서판의 버스 등)이라 정지 구간이
/// 도착·출발을 알려 주지 않으므로 그쪽은 점 시각을 쓴다. 정지 구간 안의 점이 하나도 없으면 Li 외(2008) 그대로다.
///
/// [points]와 [stillSpans]는 시각순이어야 하고, 정지 구간은 서로 겹치지 않아야 한다.
List<Stay> detectStays(
  List<Fix> points, {
  List<TimeSpan> stillSpans = const [],
  StayParams params = const StayParams(),
}) {
  params.check();
  for (var k = 1; k < points.length; k++) {
    if (points[k].tMs < points[k - 1].tMs) throw ArgumentError('점이 시각순이 아닙니다: ${points[k].tMs}');
  }
  final spans = params.useStillIntervals ? stillSpans : const <TimeSpan>[];

  final stays = <Stay>[];
  var i = 0;
  while (i < points.length) {
    final anchor = points[i];
    var j = i;
    while (j + 1 < points.length &&
        haversineMeters(anchor.lat, anchor.lng, points[j + 1].lat, points[j + 1].lng) <= params.radiusM) {
      j++;
    }

    // 무리에서 정지 구간 안에 든 첫 점(first)과 마지막 점(last).
    var first = -1;
    var last = -1;
    for (var k = i; k <= j && spans.isNotEmpty; k++) {
      if (_spanContaining(spans, points[k].tMs) != null) {
        if (first < 0) first = k;
        last = k;
      }
    }

    var from = i;
    var to = j;
    var arriveMs = points[i].tMs;
    var leaveMs = points[j].tMs;
    if (first >= 0) {
      from = first;
      to = last;
      final arriveSpan = _spanContaining(spans, points[first].tMs)!;
      arriveMs = first == 0 || arriveSpan.startMs > points[first - 1].tMs
          ? arriveSpan.startMs
          : points[first].tMs;
      final leaveSpan = _spanContaining(spans, points[last].tMs)!;
      leaveMs = last + 1 == points.length || leaveSpan.endMs < points[last + 1].tMs
          ? leaveSpan.endMs
          : points[last].tMs;
    }

    if (leaveMs - arriveMs >= params.minDurationMs) {
      var lat = 0.0;
      var lng = 0.0;
      for (var k = from; k <= to; k++) {
        lat += points[k].lat;
        lng += points[k].lng;
      }
      final n = to - from + 1;
      stays.add(Stay(arriveMs: arriveMs, leaveMs: leaveMs, lat: lat / n, lng: lng / n, nPoints: n));
      i = j + 1;
    } else {
      i++;
    }
  }
  return stays;
}

/// [tMs]를 품은 정지 구간. 구간은 시각순이고 겹치지 않으므로 시작 시각으로 이진 탐색한다.
TimeSpan? _spanContaining(List<TimeSpan> spans, int tMs) {
  var low = 0;
  var high = spans.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (spans[mid].startMs <= tMs) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  // low는 시작이 tMs보다 늦은 첫 구간이다. 그 앞 구간이 tMs를 품는지 본다.
  if (low == 0) return null;
  final span = spans[low - 1];
  return span.contains(tMs) ? span : null;
}
```

`packages/footstep_core/lib/footstep_core.dart`에서 다음 부분을

```dart
export 'src/session/session_schema.dart';
export 'src/steps/step_run.dart';
```

다음으로 바꾼다:

```dart
export 'src/session/session_schema.dart';
export 'src/stays/stay_detector.dart';
export 'src/steps/step_run.dart';
```

- [ ] **Step 4: 통과 확인**

Run: `dart test`(전체)와 `dart analyze` → 모두 통과(206개), 0건.

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core/lib/src/stays/stay_detector.dart packages/footstep_core/lib/footstep_core.dart packages/footstep_core/test/stays/stay_detector_test.dart
git commit -m "feat(footstep_core): 머문 곳 묶기(Li 외 2008)와 걸음 감지기 정지 구간으로 도착·출발을 잡는 제안 방식을 더한다"
```

---

### Task 2: 재생기가 `steps_since_prev`를 걸음 시각으로 다시 센다 (R3 후속)

R3에서 남긴 문제다. 제안판 감지기(`adaptive`)는 연속 5걸음을 확인한 뒤 앞 걸음을 소급해 센다. 걷기 시작하고 몇 초 안에 측위하면, 그 앞 걸음은 감지기 안에서 '측위 이전 몫'으로 늦게 셈해져 어느 `fixes.csv` 행에도 남지 않았다. 정책이 받는 `stepsSinceLastFix`는 맞으므로 그대로 두고, 재생이 끝난 뒤 결과 파일만 걸음 시각으로 다시 센다. `hmm_steps`(Task 5)가 이 열을 걸은 거리로 쓴다.

**Files:**
- Modify: `packages/footstep_core/lib/src/replay/replay_engine.dart`
- Test: `packages/footstep_core/test/replay/replay_engine_test.dart`

**Interfaces:**
- Consumes: R3의 `StepTimeline.takeStepTimes()`, `runDetector`, 테스트 도우미 `test/detectors/synthetic.dart`의 `walk`
- Produces: `ReplayResult.fixes[i].stepsSincePrev` = 직전 측위 시각 이상 ~ 이 측위 시각 미만의 걸음 수(첫 측위는 처음부터). 걸음 시각을 모르는 감지기는 측위 때 알린 값 그대로

- [ ] **Step 1: 실패하는 테스트 작성**

`test/replay/replay_engine_test.dart`에서

다음 부분을

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

/// 정해 둔 할 일을 돌려주고 받은 사건을 모으는 시험용 정책.
```

다음으로 바꾼다:

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

import '../detectors/synthetic.dart';

/// 걸음 시각을 모르는 감지기 흉내: 가속도 묶음마다 3걸음씩 늘었다고 알린다.
class _NoTimeline implements StepDetector {
  int _total = 0;
  int _atFix = 0;

  @override
  String get id => 'no_timeline';

  @override
  Map<String, Object> get params => const {};

  @override
  StepState get state => StepState.walking;

  @override
  int get totalSteps => _total;

  @override
  int get stepsSinceLastFix => _total - _atFix;

  @override
  StepUpdate? onAccel(int tMs, List<AccelReading> batch) {
    _total += 3;
    return StepUpdate(
        tMs: tMs, state: StepState.walking, totalSteps: _total, stepsSinceLastFix: stepsSinceLastFix);
  }

  @override
  StepUpdate? onOsStep(OsStepReading reading) => null;

  @override
  void onFix() => _atFix = _total;
}

/// 정해 둔 할 일을 돌려주고 받은 사건을 모으는 시험용 정책.
```

그리고 다음 부분을

```dart
  test('1분 고정 주기로 10분을 재생하면 측위 11번(0분~10분)이다', () {
```

다음으로 바꾼다:

```dart
  test('제안판 감지기가 연속 걸음을 확인하기 전에 측위해도 그 앞 걸음이 steps_since_prev에 남는다', () {
    // 걷기 시작 2초 만에 측위한다. 제안판은 박자 창(3초)이 차고 연속 5걸음을 확인한 뒤 앞 걸음을 소급해 센다.
    final policy = _Scripted(
      startActions: [const WakeAt(tMs: 2000, tag: 'a'), const WakeAt(tMs: 10000, tag: 'b')],
      onWake: {'a': [const RequestFix()], 'b': [const RequestFix()]},
    );
    final data = SessionData(sessionId: 'walk', fixes: everySecond(0, 20000), accel: walk(20));

    final result = replaySession(data, policy, AdaptiveStepDetector());

    // 같은 감지기를 정책 없이 돌려 얻은 걸음 시각으로 구간마다 센 값과 같아야 한다.
    final times = runDetector(data, AdaptiveStepDetector()).stepTimes;
    final beforeFirst = times.where((t) => t < 2000).length;
    expect(beforeFirst, greaterThan(0));
    expect(result.fixes.map((f) => f.tMs), [2000, 10000]);
    expect(result.fixes.map((f) => f.stepsSincePrev),
        [beforeFirst, times.where((t) => t >= 2000 && t < 10000).length]);
  });

  test('걸음 시각을 모르는 감지기는 측위 때 알린 걸음 수를 그대로 쓴다', () {
    final policy = _Scripted(
      startActions: [const WakeAt(tMs: 2500, tag: 'a')],
      onWake: {'a': [const RequestFix()]},
    );
    final data = session(
      fixes: everySecond(0, 5000),
      accel: [for (var t = 0; t <= 5000; t += 10) AccelReading(tMs: t, x: 0, y: 9.81, z: 0)],
    );

    final result = replaySession(data, policy, _NoTimeline());

    // 3초 응답 전에 끝난 묶음(0.99·1.99·2.99초) 세 개 × 3걸음.
    expect(result.fixes.single.stepsSincePrev, 9);
  });

  test('1분 고정 주기로 10분을 재생하면 측위 11번(0분~10분)이다', () {
```

- [ ] **Step 2: 실패 확인**

Run: `dart test test/replay/replay_engine_test.dart`

Expected: FAIL 1개. `제안판 감지기가 연속 걸음을 확인하기 전에 측위해도…`가 `Expected: [4, 16]`, `Actual: [0, 15]`로 실패한다(첫 측위 앞 4걸음이 사라지고, 측위 경계 걸음 하나가 다음 구간으로 밀렸다). 나머지는 통과한다.

- [ ] **Step 3: 구현**

`lib/src/replay/replay_engine.dart`에서

다음 부분을

```dart
import '../detectors/step_detector.dart';
import '../events/policy_action.dart';
```

다음으로 바꾼다:

```dart
import '../detectors/step_detector.dart';
import '../detectors/step_timeline.dart';
import '../events/policy_action.dart';
```

그리고 다음 부분을

```dart
    return ReplayResult(
      fixes: List.unmodifiable(_fixes),
```

다음으로 바꾼다:

```dart
    return ReplayResult(
      fixes: List.unmodifiable(_recountSteps(_fixes)),
```

그리고 다음 부분을

```dart
  String _stateLabel() {
    if (policy case ReportsState(:final stateLabel)) return stateLabel;
    return detector.state.name;
  }
```

다음으로 바꾼다:

```dart
  String _stateLabel() {
    if (policy case ReportsState(:final stateLabel)) return stateLabel;
    return detector.state.name;
  }

  /// fixes.csv의 steps_since_prev를 걸음 시각으로 다시 센다: 직전 측위 시각 이상 ~ 이 측위 시각 미만의 걸음 수.
  ///
  /// 정책에 알린 stepsSinceLastFix는 그 순간까지 센 걸음뿐이다. 제안판 감지기는 연속 5걸음을 확인한 뒤 앞선 걸음을
  /// 소급해 세므로, 걷기 시작하고 몇 초 안에 측위하면 그 앞 걸음은 측위 이전 몫으로 늦게 셈해져 어느 행에도
  /// 남지 않았다. 정책은 미래를 보면 안 되므로 그대로 두고, 결과 파일만 재생이 끝난 뒤 바로잡는다. 걸음 시각을
  /// 모르는 감지기는 알린 값을 그대로 쓴다.
  List<FixRecord> _recountSteps(List<FixRecord> fixes) {
    if (detector case final StepTimeline timeline) {
      final times = timeline.takeStepTimes()..sort();
      final recounted = <FixRecord>[];
      var next = 0;
      for (final record in fixes) {
        final from = next;
        while (next < times.length && times[next] < record.tMs) {
          next++;
        }
        recounted.add(FixRecord(
          fix: record.fix,
          stepsSincePrev: next - from,
          state: record.state,
          kind: record.kind,
        ));
      }
      return recounted;
    }
    return fixes;
  }
```

- [ ] **Step 4: 통과 확인**

Run: `dart test`(전체)와 `dart analyze` → 모두 통과(208개), 0건.

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core/lib/src/replay/replay_engine.dart packages/footstep_core/test/replay/replay_engine_test.dart
git commit -m "fix(footstep_core): 재생기가 steps_since_prev를 걸음 시각으로 다시 세어 소급 카운트한 걸음을 잃지 않는다"
```

---

### Task 3: 재생기가 머문 곳을 묶어 `stays.csv`를 쓴다

**Files:**
- Modify: `packages/footstep_core/lib/src/replay/replay_engine.dart`(전체 교체)
- Modify: `packages/footstep_core/lib/src/replay/replay_result.dart`(전체 교체)
- Modify: `packages/footstep_core/lib/src/replay/replay_output.dart`(전체 교체)
- Modify: `packages/footstep_core/lib/src/cli/replay_cli.dart`(전체 교체)
- Test: `packages/footstep_core/test/replay/replay_engine_test.dart`, `test/replay/replay_output_test.dart`, `test/cli/replay_cli_test.dart`(모두 전체 교체)

**Interfaces:**
- Consumes: Task 1의 `StayParams`·`createStayParams`·`stillSpans`·`detectStays`·`Stay`, Task 2의 다시 센 측위 기록
- Produces:
  - `ReplayConfig({int ttffMs = 0, int accelBatchMs = 1000, StayParams stays = const StayParams()})` — `replaySession`이 시작 전에 `stays.check()`
  - `ReplayResult({fixes, actions, List<Stay> stays = const [], summary})`
  - `ReplaySummary`에 `Map<String, Object> stayParams = const {}`, `int stayCount = 0` → summary.json `stay_params`, `stays`
  - `ReplaySchema.staysFile = 'stays.csv'`, `staysHeader = ['arrive_ms', 'leave_ms', 'lat', 'lng', 'n_points']`
  - CLI `--stay-param k=v`(여러 번), 한 줄 요약에 `stays=N`

재생기는 정책에 넘기는 `StepUpdate`마다 감지기 상태가 바뀌었으면 `StateChange`로 모은다(걸음 CLI `step_states.csv`와 같은 규칙). 재생이 끝나면 그 정지 구간과 다시 센 측위 점으로 머문 곳을 묶는다. 감지기는 정책을 돌린 바로 그 감지기라 따로 다시 돌리지 않는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`packages/footstep_core/test/replay/replay_engine_test.dart` 전체(Task 2의 테스트 + 머문 곳 그룹, summary 키, 설정 검증):

```dart
import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

import '../detectors/synthetic.dart';

/// 걸음 시각을 모르는 감지기 흉내: 가속도 묶음마다 3걸음씩 늘었다고 알린다.
class _NoTimeline implements StepDetector {
  int _total = 0;
  int _atFix = 0;

  @override
  String get id => 'no_timeline';

  @override
  Map<String, Object> get params => const {};

  @override
  StepState get state => StepState.walking;

  @override
  int get totalSteps => _total;

  @override
  int get stepsSinceLastFix => _total - _atFix;

  @override
  StepUpdate? onAccel(int tMs, List<AccelReading> batch) {
    _total += 3;
    return StepUpdate(
        tMs: tMs, state: StepState.walking, totalSteps: _total, stepsSinceLastFix: stepsSinceLastFix);
  }

  @override
  StepUpdate? onOsStep(OsStepReading reading) => null;

  @override
  void onFix() => _atFix = _total;
}

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
    // 첫 OS 걸음 읽기(0ms)에서 정지로 시작했음을 알리고, 걸음이 늘면 보행, 4초 넘게 멈추면 다시 정지다.
    expect(updates.map((u) => (u.tMs, u.state)),
        [(0, StepState.still), (1000, StepState.walking), (5990, StepState.still)]);
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

  test('제안판 감지기가 연속 걸음을 확인하기 전에 측위해도 그 앞 걸음이 steps_since_prev에 남는다', () {
    // 걷기 시작 2초 만에 측위한다. 제안판은 박자 창(3초)이 차고 연속 5걸음을 확인한 뒤 앞 걸음을 소급해 센다.
    final policy = _Scripted(
      startActions: [const WakeAt(tMs: 2000, tag: 'a'), const WakeAt(tMs: 10000, tag: 'b')],
      onWake: {'a': [const RequestFix()], 'b': [const RequestFix()]},
    );
    final data = SessionData(sessionId: 'walk', fixes: everySecond(0, 20000), accel: walk(20));

    final result = replaySession(data, policy, AdaptiveStepDetector());

    // 같은 감지기를 정책 없이 돌려 얻은 걸음 시각으로 구간마다 센 값과 같아야 한다.
    final times = runDetector(data, AdaptiveStepDetector()).stepTimes;
    final beforeFirst = times.where((t) => t < 2000).length;
    expect(beforeFirst, greaterThan(0));
    expect(result.fixes.map((f) => f.tMs), [2000, 10000]);
    expect(result.fixes.map((f) => f.stepsSincePrev),
        [beforeFirst, times.where((t) => t >= 2000 && t < 10000).length]);
  });

  test('걸음 시각을 모르는 감지기는 측위 때 알린 걸음 수를 그대로 쓴다', () {
    final policy = _Scripted(
      startActions: [const WakeAt(tMs: 2500, tag: 'a')],
      onWake: {'a': [const RequestFix()]},
    );
    final data = session(
      fixes: everySecond(0, 5000),
      accel: [for (var t = 0; t <= 5000; t += 10) AccelReading(tMs: t, x: 0, y: 9.81, z: 0)],
    );

    final result = replaySession(data, policy, _NoTimeline());

    // 3초 응답 전에 끝난 묶음(0.99·1.99·2.99초) 세 개 × 3걸음.
    expect(result.fixes.single.stepsSincePrev, 9);
  });

  group('머문 곳', () {
    // 2분 동안 남쪽 168m에서 걸어와(1.4m/s) A에서 11분 머문 뒤(2~13분), 북쪽으로 2분 걸어간다(15분에 168m).
    // OS 걸음 읽기는 1초마다이고, 걷는 동안 초당 2걸음씩 는다.
    const degPerMeter = 1 / 111195.08;
    double northAt(int s) => s <= 120 ? (s - 120) * 1.4 : (s <= 780 ? 0 : (s - 780) * 1.4);
    final data = SessionData(
      sessionId: 'stay',
      fixes: [
        for (var s = 0; s <= 900; s++) gps(s * 1000, lat: 37.5 + northAt(s) * degPerMeter),
      ],
      osSteps: [
        for (var s = 0; s <= 900; s++)
          count(s * 1000, s <= 120 ? 2 * s : (s <= 780 ? 240 : 240 + 2 * (s - 780))),
      ],
    );
    FixedIntervalPolicy every5m() => FixedIntervalPolicy(id: 'fixed_5m', intervalMs: 300000);

    test('5분마다 잰 점 두 개뿐이어도 감지기 정지 구간으로 머문 곳과 도착·출발 시각을 잡는다', () {
      final result = replaySession(data, every5m(), OsStepDetector());

      expect(result.fixes.map((f) => f.tMs), [0, 300000, 600000, 900000]);
      final stay = result.stays.single;
      // 마지막 걸음(120초) 4초 뒤 다음 읽기(125초)에 정지, 781초에 걸음이 다시 늘어 보행이다.
      expect((stay.arriveMs, stay.leaveMs, stay.nPoints), (125000, 781000, 2));
      expect(haversineMeters(stay.lat, stay.lng, 37.5, 127.0), lessThan(0.5));
      expect(result.summary.toJson()['stays'], 1);
    });

    test('점만으로 묶으면(use_still=false) 두 점 사이 5분이라 머문 곳이 아니다', () {
      final result = replaySession(data, every5m(), OsStepDetector(),
          config: const ReplayConfig(stays: StayParams(useStillIntervals: false)));

      expect(result.stays, isEmpty);
      expect(result.summary.toJson()['stay_params'],
          {'radius_m': 100.0, 'min_stay_s': 600.0, 'use_still': false});
    });
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
    expect(json['gps_on_s'], 0.0); // ttff 0이면 켜자마자 응답이 와 켜진 시간이 없다
    expect(json['fix_requests'], 13);
    expect(json['fix_successes'], 13);
    expect(json['fix_failures'], 0);
    // 한 시간 내내 같은 자리라 측위 13개가 머문 곳 하나로 묶인다.
    expect(json['stay_params'], {'radius_m': 100.0, 'min_stay_s': 600.0, 'use_still': true});
    expect(json['stays'], 1);
  });

  test('기록이 없는 세션은 ArgumentError다', () {
    expect(() => replaySession(session(), _Scripted(), OsStepDetector()), throwsArgumentError);
  });

  test('연속 측위가 세션 끝까지 켜져 있으면 켜진 시간이 끝 시각까지 센다', () {
    // continuous_10m 기준선의 GPS 켜짐 시간은 이 경로로만 잡힌다.
    final policy = _Scripted(startActions: [const StartContinuous(intervalMs: 1000)]);

    final result = replaySession(session(fixes: everySecond(0, 10000)), policy, OsStepDetector());

    expect(result.summary.gpsOnMs, 10000);
    expect(result.summary.continuousFixes, 11);
  });

  test('응답을 기다리는 중의 RequestFix는 무시한다', () {
    final policy = _Scripted(
      startActions: [const WakeAt(tMs: 2500, tag: 'a')],
      onWake: {'a': [const RequestFix(), const RequestFix()]},
    );

    final result = replaySession(session(fixes: everySecond(0, 10000)), policy, OsStepDetector(),
        config: const ReplayConfig(ttffMs: 2000));

    expect(result.summary.fixRequests, 1);
    expect(result.summary.fixSuccesses, 1);
    expect(result.fixes, hasLength(1));
    expect(policy.events.whereType<FixResult>(), hasLength(1));
    expect(result.summary.gpsOnMs, 2500); // 켜진 시간도 한 번만 센다
    // 무시된 요청도 actions에는 정책이 낸 그대로 남는다.
    expect(result.actions.where((a) => a.action is RequestFix), hasLength(2));
  });

  test('연속 측위 중 StartContinuous를 또 내면 스트림을 새로 시작하고 켜진 시간은 겹쳐 세지 않는다', () {
    final policy = _Scripted(
      startActions: [
        const StartContinuous(intervalMs: 1000, distanceFilterM: 1000),
        const WakeAt(tMs: 5000, tag: 'restart'),
        const WakeAt(tMs: 10000, tag: 'stop'),
      ],
      onWake: {
        'restart': [const StartContinuous(intervalMs: 1000, distanceFilterM: 1000)],
        'stop': [const StopContinuous()],
      },
    );

    // 같은 자리라 1000m 거리 필터에 걸려 첫 점 말고는 나오지 않는다 — 다시 시작하면 첫 점이 또 나온다.
    final result = replaySession(session(fixes: everySecond(0, 20000)), policy, OsStepDetector());

    expect(result.fixes.map((f) => f.tMs), [0, 5000]);
    expect(result.summary.continuousFixes, 2);
    expect(result.summary.gpsOnMs, 10000);
  });

  test('정지로 시작한 세션에서 still_suppress는 주기 측위를 건너뛴다', () {
    // 5분 동안 걸음 수가 그대로다. 첫 OS 걸음 읽기에서 정지가 알려지면, 시작 때와 첫 정지 확인(1분) 때만
    // 측위하고 두 번째 연속 정지 확인부터 건너뛴다(Zhuang 외 2010). 확인 측위(5분)는 세션 끝(5분) 뒤라 없다.
    final data = session(
      fixes: everySecond(0, 300000),
      osSteps: [count(0, 700), count(150000, 700), count(300000, 700)],
    );

    final result = replaySession(data, StillSuppressPolicy(), OsStepDetector());

    expect(result.summary.fixRequests, 2);
    expect(result.fixes.map((f) => f.tMs), [0, 60000]);
    expect(result.fixes.map((f) => f.state), ['still', 'still']);
    // 비교: 고정 주기는 같은 세션에서 6번(0~5분) 측위한다.
    final fixed = replaySession(
        data, FixedIntervalPolicy(id: 'fixed_1m', intervalMs: 60000), OsStepDetector());
    expect(fixed.summary.fixRequests, 6);
  });

  group('재생 설정 검증', () {
    final data = session(fixes: everySecond(0, 10000));

    test('음수 ttffMs는 ArgumentError다', () {
      expect(
          () => replaySession(data, _Scripted(), OsStepDetector(),
              config: const ReplayConfig(ttffMs: -1)),
          throwsArgumentError);
    });

    test('0 이하의 accelBatchMs는 ArgumentError다', () {
      for (final bad in [0, -1000]) {
        expect(
            () => replaySession(data, _Scripted(), OsStepDetector(),
                config: ReplayConfig(accelBatchMs: bad)),
            throwsArgumentError,
            reason: 'accelBatchMs=$bad');
      }
    });

    test('0 이하의 머문 곳 반경·시간은 재생 전에 ArgumentError다', () {
      for (final bad in [const StayParams(radiusM: 0), const StayParams(minDurationMs: -1)]) {
        expect(() => replaySession(data, _Scripted(), OsStepDetector(), config: ReplayConfig(stays: bad)),
            throwsArgumentError);
      }
    });
  });
}
```

`packages/footstep_core/test/replay/replay_output_test.dart` 전체:

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

  test('fixes.csv·actions.csv·stays.csv·summary.json을 설계 문서 5-4·5-6 형식으로 쓴다', () async {
    const fix = Fix(tMs: 1000, lat: 37.5665, lng: 126.978, accuracyM: 4.5);
    const result = ReplayResult(
      fixes: [FixRecord(fix: fix, stepsSincePrev: 12, state: 'walking', kind: 'single')],
      actions: [
        ActionRecord(tMs: 0, action: RequestFix()),
        ActionRecord(tMs: 0, action: WakeAt(tMs: 60000, tag: 'tick')),
      ],
      stays: [Stay(arriveMs: 60000, leaveMs: 720000, lat: 37.5651, lng: 126.9895, nPoints: 3)],
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
        stayParams: {'radius_m': 100.0, 'min_stay_s': 600.0, 'use_still': true},
        stayCount: 1,
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
    expect(File(p.join(out.path, 'stays.csv')).readAsLinesSync(), [
      'arrive_ms,leave_ms,lat,lng,n_points',
      '60000,720000,37.5651,126.9895,3',
    ]);
    final summary =
        jsonDecode(File(p.join(out.path, 'summary.json')).readAsStringSync()) as Map<String, Object?>;
    expect(summary['policy_id'], 'fixed_1m');
    expect(summary['total_fixes'], 1);
    expect(summary['gps_on_s'], 1.0);
    expect(summary['stays'], 1);
    expect(summary['stay_params'], {'radius_m': 100.0, 'min_stay_s': 600.0, 'use_still': true});
  });

  test('머문 곳이 없어도 stays.csv는 헤더 한 줄로 쓴다', () async {
    const result = ReplayResult(
      fixes: [],
      actions: [],
      summary: ReplaySummary(
        sessionId: 's2',
        policyId: 'hourly',
        policyParams: {'interval_s': 3600},
        detectorId: 'os',
        ttffMs: 0,
        startMs: 0,
        endMs: 1000,
        fixRequests: 0,
        fixSuccesses: 0,
        fixFailures: 0,
        continuousFixes: 0,
        gpsOnMs: 0,
      ),
    );

    await writeReplayOutput(result, root);

    expect(File(p.join(root.path, 'stays.csv')).readAsLinesSync(), ['arrive_ms,leave_ms,lat,lng,n_points']);
  });
}
```

`packages/footstep_core/test/cli/replay_cli_test.dart` 전체:

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
    expect(out.toString(), contains('stays=0')); // 같은 자리 2분은 10분에 못 미친다
    expect(File(p.join(outDir, 'fixes.csv')).readAsLinesSync(), hasLength(4)); // 헤더 + 0·60·120초
    expect(File(p.join(outDir, 'actions.csv')).existsSync(), isTrue);
    expect(File(p.join(outDir, 'stays.csv')).readAsLinesSync(), ['arrive_ms,leave_ms,lat,lng,n_points']);
  });

  test('--stay-param이 머문 곳 묶기와 summary.json에 들어간다', () async {
    final outDir = p.join(root.path, 'out4');
    final code = await runReplayCli([
      '--session', session.path, '--policy', 'fixed_1m',
      '--stay-param', 'min_stay_s=60', '--stay-param', 'use_still=false', '--out', outDir,
    ], out: out, err: err);

    expect(code, 0, reason: err.toString());
    expect(File(p.join(outDir, 'stays.csv')).readAsLinesSync(),
        ['arrive_ms,leave_ms,lat,lng,n_points', '0,120000,37.5,127.0,3']);
    final summary =
        jsonDecode(File(p.join(outDir, 'summary.json')).readAsStringSync()) as Map<String, Object?>;
    expect(summary['stay_params'], {'radius_m': 100.0, 'min_stay_s': 60.0, 'use_still': false});
    expect(summary['stays'], 1);
  });

  test('--stay-param 형식이 틀리거나 모르는 키·잘못된 값이면 64를 돌려준다', () async {
    for (final bad in ['radius_m', 'radius=50', 'min_stay_s=0', 'use_still=maybe']) {
      final code = await runReplayCli([
        '--session', session.path, '--policy', 'fixed_1m', '--stay-param', bad, '--out', p.join(root.path, 'o'),
      ], out: StringBuffer(), err: err);
      expect(code, 64, reason: '--stay-param $bad');
    }
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

  test('--ttff가 NaN·Infinity·음수면 64를 돌려준다', () async {
    for (final bad in ['NaN', 'Infinity', '-1']) {
      final code = await runReplayCli([
        '--session', session.path, '--policy', 'fixed_1m', '--ttff', bad, '--out', p.join(root.path, 'o'),
      ], out: StringBuffer(), err: err);
      expect(code, 64, reason: '--ttff $bad');
    }
    expect(err.toString(), contains('--ttff'));
  });

  test('--param 형식이 틀리면 64를 돌려준다', () async {
    final code = await runReplayCli([
      '--session', session.path, '--policy', 'time_speed', '--param', 'e_m', '--out', p.join(root.path, 'o'),
    ], out: out, err: err);
    expect(code, 64);
  });

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
}
```

- [ ] **Step 2: 실패 확인**

Run: `dart test test/replay/ test/cli/replay_cli_test.dart`

Expected: FAIL. `ReplayConfig`에 `stays`, `ReplayResult`에 `stays`, `ReplaySummary`에 `stayParams`가 없어 컴파일되지 않는다.

- [ ] **Step 3: 구현**

`packages/footstep_core/lib/src/replay/replay_engine.dart` 전체:

```dart
import 'dart:math' as math;

import '../detectors/step_detector.dart';
import '../detectors/step_timeline.dart';
import '../events/policy_action.dart';
import '../events/policy_event.dart';
import '../geo.dart';
import '../model/fix.dart';
import '../model/readings.dart';
import '../policies/collection_policy.dart';
import '../session/session_reader.dart';
import '../stays/stay_detector.dart';
import '../steps/step_run.dart';
import 'accel_batches.dart';
import 'replay_result.dart';

/// 재생 설정(설계 5-4).
class ReplayConfig {
  const ReplayConfig({this.ttffMs = 0, this.accelBatchMs = 1000, this.stays = const StayParams()});

  /// GPS를 켠 뒤 첫 위치가 나오기까지 걸린다고 가정하는 시간. 기록은 GPS가 계속 켜져 있던 값이라
  /// '켜자마자 위치가 나온다'고 가정하게 되는 약점을 0·5·10초로 바꿔 가며 줄인다.
  final int ttffMs;

  /// 가속도를 걸음 감지기에 넘기는 묶음 길이. 표본 간격은 기기마다 다르다(Galaxy S23은 약 10ms).
  final int accelBatchMs;

  /// 재생이 끝난 뒤 남은 점으로 머문 곳을 묶는 설정(설계 5-6).
  final StayParams stays;
}

/// 세션 기록으로 정책을 재생한다. 정책은 요청한 시각 이후의 정보만 받으므로 미래 정보를 쓸 수 없고,
/// 같은 입력이면 항상 같은 결과가 나온다(설계 5-4).
ReplayResult replaySession(
  SessionData data,
  CollectionPolicy policy,
  StepDetector detector, {
  ReplayConfig config = const ReplayConfig(),
}) {
  // 음수 ttff는 응답이 과거로 예약돼 시계가 거꾸로 가고 GPS 켜짐 시간이 음수가 된다. 묶음 길이가 0 이하면
  // 가속도 묶음이 만들어지지 않거나 표본마다 쪼개진다. 조용히 틀린 결과를 내느니 바로 알린다.
  if (config.ttffMs < 0) throw ArgumentError('ttffMs는 0 이상이어야 합니다: ${config.ttffMs}');
  if (config.accelBatchMs <= 0) {
    throw ArgumentError('accelBatchMs는 양수여야 합니다: ${config.accelBatchMs}');
  }
  config.stays.check();
  return _Replay(data, policy, detector, config).run();
}

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

  /// 걸음 감지기 상태가 바뀐 순간들. 머문 곳 묶기가 정지 구간으로 쓴다(걸음 CLI의 step_states.csv와 같은 규칙).
  final _stepStates = <StateChange>[];

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
      } else if (external != null) {
        if (external.tMs > end) break;
        _nowMs = external.tMs;
        next++;
        _handleExternal(external);
      }
    }

    // 끝 시각에 켜져 있거나 응답을 기다리는 중이면 끝 시각까지 GPS가 켜져 있던 것으로 센다.
    if (_continuous != null) _gpsOnMs += end - _continuousSinceMs;
    final pending = _pendingFix;
    if (pending != null) _gpsOnMs += end - pending.requestMs;

    final fixes = _recountSteps(_fixes);
    final stays = detectStays(
      [for (final record in fixes) record.fix],
      stillSpans: stillSpans(_stepStates, end),
      params: config.stays,
    );
    return ReplayResult(
      fixes: List.unmodifiable(fixes),
      actions: List.unmodifiable(_actions),
      stays: List.unmodifiable(stays),
      summary: ReplaySummary(
        sessionId: data.sessionId,
        policyId: policy.id,
        policyParams: policy.params,
        detectorId: detector.id,
        detectorParams: detector.params,
        ttffMs: config.ttffMs,
        startMs: start,
        endMs: end,
        fixRequests: _fixRequests,
        fixSuccesses: _fixSuccesses,
        fixFailures: _fixFailures,
        continuousFixes: _continuousFixes,
        gpsOnMs: _gpsOnMs,
        stayParams: config.stays.params,
        stayCount: stays.length,
      ),
    );
  }

  PolicyContext _ctx() => PolicyContext(nowMs: _nowMs, lastFix: _lastFix);

  List<_External> _buildTimeline() {
    final items = <_External>[
      for (final fix in data.fixes) _GpsRow(fix),
      for (final batch in accelBatches(data.accel, config.accelBatchMs)) _AccelBatch(batch),
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

  /// fixes.csv의 steps_since_prev를 걸음 시각으로 다시 센다: 직전 측위 시각 이상 ~ 이 측위 시각 미만의 걸음 수.
  ///
  /// 정책에 알린 stepsSinceLastFix는 그 순간까지 센 걸음뿐이다. 제안판 감지기는 연속 5걸음을 확인한 뒤 앞선 걸음을
  /// 소급해 세므로, 걷기 시작하고 몇 초 안에 측위하면 그 앞 걸음은 측위 이전 몫으로 늦게 셈해져 어느 행에도
  /// 남지 않았다. 정책은 미래를 보면 안 되므로 그대로 두고, 결과 파일만 재생이 끝난 뒤 바로잡는다. 걸음 시각을
  /// 모르는 감지기는 알린 값을 그대로 쓴다.
  List<FixRecord> _recountSteps(List<FixRecord> fixes) {
    if (detector case final StepTimeline timeline) {
      final times = timeline.takeStepTimes()..sort();
      final recounted = <FixRecord>[];
      var next = 0;
      for (final record in fixes) {
        final from = next;
        while (next < times.length && times[next] < record.tMs) {
          next++;
        }
        recounted.add(FixRecord(
          fix: record.fix,
          stepsSincePrev: next - from,
          state: record.state,
          kind: record.kind,
        ));
      }
      return recounted;
    }
    return fixes;
  }

  void _deliverStep(StepUpdate? update) {
    if (update == null) return;
    if (_stepStates.isEmpty || _stepStates.last.state != update.state) {
      _stepStates.add(StateChange(tMs: update.tMs, state: update.state, cadenceHz: update.cadenceHz));
    }
    _deliver(update);
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

`packages/footstep_core/lib/src/replay/replay_result.dart` 전체:

```dart
import '../events/policy_action.dart';
import '../model/fix.dart';
import '../stays/stay_detector.dart';

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
    this.detectorParams = const {},
    required this.ttffMs,
    required this.startMs,
    required this.endMs,
    required this.fixRequests,
    required this.fixSuccesses,
    required this.fixFailures,
    required this.continuousFixes,
    required this.gpsOnMs,
    this.stayParams = const {},
    this.stayCount = 0,
  });

  final String sessionId;
  final String policyId;
  final Map<String, Object> policyParams;
  final String detectorId;

  /// 걸음 감지기 파라미터. 감지기 파라미터를 바꿔 가며 재생한 결과를 구분하려고 남긴다.
  final Map<String, Object> detectorParams;
  final int ttffMs;
  final int startMs;
  final int endMs;
  final int fixRequests;
  final int fixSuccesses;
  final int fixFailures;
  final int continuousFixes;

  /// 추정 GPS 켜짐 시간. 단발은 요청~응답, 연속은 켠 때~끈 때.
  final int gpsOnMs;

  /// 머문 곳 묶기 설정(StayParams.params)과 찾은 머문 곳 수.
  final Map<String, Object> stayParams;
  final int stayCount;

  int get durationMs => endMs - startMs;

  int get totalFixes => fixSuccesses + continuousFixes;

  double get fixesPerHour => durationMs == 0 ? 0 : totalFixes / (durationMs / 3600000);

  Map<String, Object?> toJson() => {
        'session_id': sessionId,
        'policy_id': policyId,
        'policy_params': policyParams,
        'detector_id': detectorId,
        'detector_params': detectorParams,
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
        'stay_params': stayParams,
        'stays': stayCount,
      };
}

class ReplayResult {
  const ReplayResult({
    required this.fixes,
    required this.actions,
    this.stays = const [],
    required this.summary,
  });

  final List<FixRecord> fixes;
  final List<ActionRecord> actions;

  /// 남은 점으로 묶은 머문 곳(stays.csv).
  final List<Stay> stays;
  final ReplaySummary summary;
}
```

`packages/footstep_core/lib/src/replay/replay_output.dart` 전체:

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

  static const staysFile = 'stays.csv';
  static const staysHeader = ['arrive_ms', 'leave_ms', 'lat', 'lng', 'n_points'];

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
  await File(p.join(outDir.path, ReplaySchema.staysFile)).writeAsString(
    csv(ReplaySchema.staysHeader, [
      for (final s in result.stays) [s.arriveMs, s.leaveMs, s.lat, s.lng, s.nPoints],
    ]),
    flush: true,
  );
  await File(p.join(outDir.path, ReplaySchema.summaryFile)).writeAsString(
    const JsonEncoder.withIndent('  ').convert(result.summary.toJson()),
    flush: true,
  );
}
```

`packages/footstep_core/lib/src/cli/replay_cli.dart` 전체:

```dart
import 'dart:io';

import 'package:args/args.dart';

import '../detectors/detector_registry.dart';
import '../detectors/step_detector.dart';
import 'key_values.dart';
import '../policies/collection_policy.dart';
import '../policies/policy_registry.dart';
import '../replay/replay_engine.dart';
import '../replay/replay_output.dart';
import '../replay/replay_result.dart';
import '../session/session_reader.dart';
import '../stays/stay_detector.dart';

const _usage = '사용법: dart run footstep_core:replay --session <세션 폴더> --policy <정책 id> '
    '--out <결과 폴더> [--param k=v ...] [--detector os|brajdic|adaptive] '
    '[--detector-param k=v ...] [--ttff 초] [--stay-param k=v ...]';

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
    ..addMultiOption('detector-param',
        help: '걸음 감지기 파라미터 k=v (여러 번 줄 수 있다)', splitCommas: false)
    ..addOption('ttff', defaultsTo: '0', help: '측위 지연(초): 0·5·10')
    ..addMultiOption('stay-param',
        help: '머문 곳 묶기 k=v: radius_m(100), min_stay_s(600), use_still(true)', splitCommas: false)
    ..addOption('out', help: '결과 폴더(fixes.csv, actions.csv, stays.csv, summary.json)');

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
  if (ttffSeconds == null || !ttffSeconds.isFinite || ttffSeconds < 0) return usageError('--ttff는 0 이상의 초여야 합니다.');

  final Map<String, String> params;
  final Map<String, String> detectorParams;
  final Map<String, String> stayParams;
  try {
    params = parseKeyValues(args.multiOption('param'));
    detectorParams = parseKeyValues(args.multiOption('detector-param'));
    stayParams = parseKeyValues(args.multiOption('stay-param'));
  } on FormatException catch (e) {
    return usageError(e.message);
  }

  late final CollectionPolicy policy;
  late final StepDetector detector;
  late final StayParams stays;
  try {
    policy = createPolicy(policyId, params);
    detector = createDetector(args.option('detector')!, detectorParams);
    stays = createStayParams(stayParams);
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
        config: ReplayConfig(ttffMs: (ttffSeconds * 1000).round(), stays: stays));
  } on ArgumentError catch (e) {
    stderrSink.writeln('${e.message}');
    return 65;
  }

  await writeReplayOutput(result, Directory(outPath));
  final s = result.summary;
  stdoutSink.writeln('${s.policyId} fixes=${s.totalFixes} requests=${s.fixRequests} '
      'failures=${s.fixFailures} gps_on=${(s.gpsOnMs / 1000).toStringAsFixed(0)}s '
      'fixes/h=${s.fixesPerHour.toStringAsFixed(1)} stays=${s.stayCount} '
      'skipped_rows=${data.skippedRows} -> $outPath');
  return 0;
}
```

- [ ] **Step 4: 통과 확인**

Run: `dart test`(전체)와 `dart analyze` → 모두 통과(214개), 0건.

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core/lib/src/replay packages/footstep_core/lib/src/cli/replay_cli.dart packages/footstep_core/test/replay packages/footstep_core/test/cli/replay_cli_test.dart
git commit -m "feat(footstep_core): 재생기가 남은 점으로 머문 곳을 묶어 stays.csv를 쓰고 --stay-param을 받는다"
```

---

### Task 4: OSRM 클라이언트에 후보 여러 개·거리표·반경/시각 매칭을 더한다

**Files:**
- Modify: `server/src/main/java/com/travelfootsteps/route/OsrmClient.java`(전체 교체)
- Modify: `server/src/main/java/com/travelfootsteps/route/HttpOsrmClient.java`(전체 교체)
- Test: `server/src/test/java/com/travelfootsteps/route/HttpOsrmClientTest.java`(전체 교체 — 기존 테스트 8개 + 새 테스트 6개)

**Interfaces:**
- Consumes: 기존 `OsrmProperties`, `GeoPoint`
- Produces(`OsrmClient`의 default 메서드, 기본 구현은 빈 결과):
  - `List<GeoPoint> nearestCandidates(String country, GeoPoint point, int number, double maxDistanceMeters)` — `GET /nearest/v1/{profile}/{lng,lat}?number=N`, 기준거리 밖은 뺌, 가까운 순
  - `List<List<Double>> table(String country, List<GeoPoint> sources, List<GeoPoint> destinations)` — `GET /table/v1/{profile}/{출발들;도착들}?sources=0;..&destinations=..&annotations=distance`, `[i][j]` m, 길 없으면 null, 실패나 표 모양이 다르면 빈 리스트
  - `List<GeoPoint> match(String country, List<GeoPoint> points, List<Double> radiuses, List<Long> timestamps)` — null이면 그 옵션을 안 보냄, 개수가 점과 다르면 빈 리스트, 100점마다 1점 겹쳐 나눠 보냄(반경·시각도 같은 경계)
  - 기존 `match(country, points)`는 새 `match`에 30m 반경을 넣어 부른다 — URL이 `radiuses=30;30;…`로 그대로다

`OsrmClient`에 추상 메서드가 아니라 default 메서드로 더하는 이유: `StubOsrmClient`(test 프로필)와 `OverseasWalkServiceTest`의 가짜를 고치지 않아도 되고, 기본 구현(빈 결과)이 인터페이스의 실패 규칙과 같다.

- [ ] **Step 1: 실패하는 테스트 작성**

`server/src/test/java/com/travelfootsteps/route/HttpOsrmClientTest.java` 전체:

```java
package com.travelfootsteps.route;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.ExpectedCount;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.startsWith;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

// OSRM 응답 해석(lon,lat → lat,lng 뒤집기)과 "실패는 예외가 아니라 빈 결과" 정책을 검증한다.
class HttpOsrmClientTest {

    private static final OsrmProperties PROPS =
            new OsrmProperties("foot", Map.of("JP", "http://jp.osrm:5002/", "KR", ""));

    private final RestClient.Builder builder = RestClient.builder();
    private final MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    private final HttpOsrmClient client = new HttpOsrmClient(builder.build(), PROPS);

    @Test
    void nearest는_도로_위_좌표를_lat_lng_순서로_돌려준다() {
        server.expect(requestTo("http://jp.osrm:5002/nearest/v1/foot/139.7671000,35.6812000"))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"code":"Ok","waypoints":[{"distance":12.5,"location":[139.7672,35.6811]}]}
                        """, MediaType.APPLICATION_JSON));

        Optional<GeoPoint> snapped = client.nearest("JP", new GeoPoint(35.6812, 139.7671), 50);

        assertThat(snapped).contains(new GeoPoint(35.6811, 139.7672));
    }

    @Test
    void nearest는_도로가_기준거리보다_멀면_비어_있다() {
        server.expect(requestTo("http://jp.osrm:5002/nearest/v1/foot/139.7671000,35.6812000"))
                .andRespond(withSuccess("""
                        {"code":"Ok","waypoints":[{"distance":80.0,"location":[139.7672,35.6811]}]}
                        """, MediaType.APPLICATION_JSON));

        assertThat(client.nearest("JP", new GeoPoint(35.6812, 139.7671), 50)).isEmpty();
    }

    @Test
    void route는_GeoJSON_좌표를_lat_lng으로_뒤집어_돌려준다() {
        server.expect(requestTo("http://jp.osrm:5002/route/v1/foot/139.7000000,35.6000000;139.7100000,35.6100000"
                        + "?overview=full&geometries=geojson"))
                .andRespond(withSuccess("""
                        {"code":"Ok","routes":[{"geometry":{"coordinates":[[139.7,35.6],[139.705,35.605]]}}]}
                        """, MediaType.APPLICATION_JSON));

        List<GeoPoint> route = client.route("JP", new GeoPoint(35.6, 139.7), new GeoPoint(35.61, 139.71));

        assertThat(route).containsExactly(new GeoPoint(35.6, 139.7), new GeoPoint(35.605, 139.705));
    }

    @Test
    void OSRM이_NoRoute_400이나_서버오류를_주면_예외_없이_빈_결과다() {
        server.expect(requestTo(org.hamcrest.Matchers.containsString("/route/v1/")))
                .andRespond(withStatus(HttpStatus.BAD_REQUEST).contentType(MediaType.APPLICATION_JSON)
                        .body("{\"code\":\"NoRoute\"}"));
        server.expect(requestTo(org.hamcrest.Matchers.containsString("/route/v1/")))
                .andRespond(withServerError());

        GeoPoint a = new GeoPoint(35.6, 139.7);
        GeoPoint b = new GeoPoint(35.61, 139.71);
        assertThat(client.route("JP", a, b)).isEmpty();
        assertThat(client.route("JP", a, b)).isEmpty();
    }

    @Test
    void 주소가_없거나_모르는_국가면_호출하지_않고_빈_결과다() {
        GeoPoint a = new GeoPoint(35.6, 139.7);

        assertThat(client.route("KR", a, a)).isEmpty();
        assertThat(client.route("XX", a, a)).isEmpty();
        assertThat(client.nearest("KR", a, 50)).isEmpty();
        assertThat(client.match("KR", List.of(a, a))).isEmpty();
        server.verify(); // 기대한 요청이 하나도 없으므로 실제 호출이 있었다면 여기서 실패한다
    }

    @Test
    void match는_OSRM_좌표_한계를_넘는_궤적을_나눠_보내고_결과를_이어_붙인다() {
        // 앱은 10m 간격으로 좌표를 쌓으므로 1km가 넘는 평범한 경로도 100점을 넘는다.
        // 앞 100점만 보내고 그 결과를 "전체 경로"로 돌려주면 뒷부분이 통째로 사라진다.
        List<GeoPoint> trace = new ArrayList<>();
        for (int i = 0; i < 150; i++) {
            trace.add(new GeoPoint(35.0 + i * 0.0001, 139.0 + i * 0.0001));
        }

        server.expect(ExpectedCount.times(2), requestTo(startsWith("http://jp.osrm:5002/match/v1/foot/")))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"code":"Ok","matchings":[{"geometry":{"coordinates":[[139.0,35.0],[139.1,35.1]]}}]}
                        """, MediaType.APPLICATION_JSON));

        List<GeoPoint> matched = client.match("JP", trace);

        server.verify();
        // 두 구간이 좌표 1점을 공유하므로 이어 붙일 때 중복 하나를 떼어낸다: 2 + (2 - 1).
        assertThat(matched).hasSize(3);
    }

    @Test
    void match는_점마다_30m_탐색_반경을_보내_도로에서_조금_벗어난_GPS도_붙인다() {
        // OSRM 기본 반경(약 5m)에서는 도로에서 조금만 벗어난 점이 하나만 있어도 NoMatch로 거절돼
        // 서버가 원본 좌표를 돌려주고, 앱 지도에는 도로를 무시한 직선이 그려진다.
        server.expect(requestTo(containsString("radiuses=30;30;30")))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"code":"Ok","matchings":[{"geometry":{"coordinates":[[139.0,35.0],[139.1,35.1]]}}]}
                        """, MediaType.APPLICATION_JSON));

        List<GeoPoint> matched = client.match("JP", List.of(
                new GeoPoint(35.0, 139.0), new GeoPoint(35.05, 139.05), new GeoPoint(35.1, 139.1)));

        server.verify();
        assertThat(matched).hasSize(2);
    }

    @Test
    void nearestCandidates는_number개를_요청하고_기준거리_안의_점만_가까운_순으로_돌려준다() {
        server.expect(requestTo("http://jp.osrm:5002/nearest/v1/foot/139.7671000,35.6812000?number=5"))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"code":"Ok","waypoints":[
                          {"distance":3.0,"location":[139.7672,35.6811]},
                          {"distance":40.0,"location":[139.7675,35.6815]},
                          {"distance":250.0,"location":[139.7700,35.6830]}]}
                        """, MediaType.APPLICATION_JSON));

        List<GeoPoint> candidates = client.nearestCandidates("JP", new GeoPoint(35.6812, 139.7671), 5, 200);

        assertThat(candidates).containsExactly(new GeoPoint(35.6811, 139.7672), new GeoPoint(35.6815, 139.7675));
    }

    @Test
    void table은_출발점과_도착점을_번호로_나눠_거리표를_받고_길이_없는_칸은_null이다() {
        server.expect(requestTo("http://jp.osrm:5002/table/v1/foot/"
                        + "139.0000000,35.0000000;139.0010000,35.0000000;139.0020000,35.0000000;139.0030000,35.0000000"
                        + "?sources=0;1&destinations=2;3&annotations=distance"))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"code":"Ok","distances":[[10.5,null],[20,30.25]]}
                        """, MediaType.APPLICATION_JSON));

        List<List<Double>> table = client.table("JP",
                List.of(new GeoPoint(35.0, 139.0), new GeoPoint(35.0, 139.001)),
                List.of(new GeoPoint(35.0, 139.002), new GeoPoint(35.0, 139.003)));

        assertThat(table).hasSize(2);
        assertThat(table.get(0)).containsExactly(10.5, null);
        assertThat(table.get(1)).containsExactly(20.0, 30.25);
    }

    @Test
    void table은_OSRM이_실패하거나_표_모양이_다르면_빈_결과다() {
        server.expect(requestTo(startsWith("http://jp.osrm:5002/table/v1/foot/")))
                .andRespond(withStatus(HttpStatus.BAD_REQUEST).contentType(MediaType.APPLICATION_JSON)
                        .body("{\"code\":\"InvalidQuery\"}"));
        server.expect(requestTo(startsWith("http://jp.osrm:5002/table/v1/foot/")))
                .andRespond(withSuccess("{\"code\":\"Ok\",\"distances\":[[1.0]]}", MediaType.APPLICATION_JSON));

        List<GeoPoint> two = List.of(new GeoPoint(35.0, 139.0), new GeoPoint(35.0, 139.001));
        assertThat(client.table("JP", two, two)).isEmpty();
        assertThat(client.table("JP", two, two)).isEmpty();
    }

    @Test
    void match에_점마다_반경과_시각을_넘기면_radiuses와_timestamps로_보낸다() {
        server.expect(requestTo(containsString("radiuses=5;12.5;50&timestamps=100;160;220")))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"code":"Ok","matchings":[{"geometry":{"coordinates":[[139.0,35.0],[139.1,35.1]]}}]}
                        """, MediaType.APPLICATION_JSON));

        List<GeoPoint> matched = client.match("JP",
                List.of(new GeoPoint(35.0, 139.0), new GeoPoint(35.05, 139.05), new GeoPoint(35.1, 139.1)),
                List.of(5.0, 12.5, 50.0), List.of(100L, 160L, 220L));

        server.verify();
        assertThat(matched).hasSize(2);
    }

    @Test
    void match에_반경과_시각이_없으면_OSRM_기본값을_쓰도록_옵션을_보내지_않는다() {
        server.expect(requestTo("http://jp.osrm:5002/match/v1/foot/139.0000000,35.0000000;139.1000000,35.1000000"
                        + "?overview=full&geometries=geojson"))
                .andRespond(withSuccess("""
                        {"code":"Ok","matchings":[{"geometry":{"coordinates":[[139.0,35.0],[139.1,35.1]]}}]}
                        """, MediaType.APPLICATION_JSON));

        List<GeoPoint> matched = client.match("JP",
                List.of(new GeoPoint(35.0, 139.0), new GeoPoint(35.1, 139.1)), null, null);

        server.verify();
        assertThat(matched).hasSize(2);
    }

    @Test
    void match에_반경이나_시각의_개수가_점과_다르면_호출하지_않고_빈_결과다() {
        List<GeoPoint> two = List.of(new GeoPoint(35.0, 139.0), new GeoPoint(35.1, 139.1));

        assertThat(client.match("JP", two, List.of(5.0), null)).isEmpty();
        assertThat(client.match("JP", two, null, List.of(1L, 2L, 3L))).isEmpty();
        server.verify();
    }

    @Test
    void match는_OSRM이_궤적을_여러_matching으로_나눠_주면_전부_이어_붙인다() {
        // GPS가 끊기거나 튀는 구간이 있으면 OSRM은 궤적을 matching 여러 개로 쪼개 돌려준다.
        // 첫 번째만 쓰면 그 뒤의 이동 경로가 통째로 사라진다.
        server.expect(requestTo(startsWith("http://jp.osrm:5002/match/v1/foot/")))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"code":"Ok","matchings":[
                          {"geometry":{"coordinates":[[139.0,35.0],[139.1,35.1]]}},
                          {"geometry":{"coordinates":[[139.2,35.2],[139.3,35.3]]}}
                        ]}
                        """, MediaType.APPLICATION_JSON));

        List<GeoPoint> matched = client.match("JP",
                List.of(new GeoPoint(35.0, 139.0), new GeoPoint(35.3, 139.3)));

        server.verify();
        assertThat(matched).containsExactly(
                new GeoPoint(35.0, 139.0), new GeoPoint(35.1, 139.1),
                new GeoPoint(35.2, 139.2), new GeoPoint(35.3, 139.3));
    }
}
```

- [ ] **Step 2: 실패 확인**

Run (`server/`에서, Git Bash): `./gradlew test --tests 'com.travelfootsteps.route.HttpOsrmClientTest'`

Expected: FAIL. `nearestCandidates`·`table`·인자 4개짜리 `match`가 없어 컴파일되지 않는다.

- [ ] **Step 3: 구현**

`server/src/main/java/com/travelfootsteps/route/OsrmClient.java` 전체:

```java
package com.travelfootsteps.route;

import java.util.List;
import java.util.Optional;

// OSRM 호출을 인터페이스 뒤에 둔다 — PlacesClient와 같은 이유로, 컨트롤러/알고리즘 테스트가
// 실제 OSRM 서버 없이 이 인터페이스의 가짜 구현만으로 돌 수 있게 하기 위함이다.
//
// 모든 메서드는 OSRM이 꺼져 있거나 응답이 이상한 경우에도 예외를 던지지 않고 빈 결과
// (Optional.empty / 빈 리스트)를 돌려준다. 앱은 "실패 = ok:false"로 받아 다음 트리거에서
// 더 긴 구간으로 재시도하므로(overseas_mapping_page.dart), 502 같은 에러로 바꿀 이유가 없다.
//
// 아래쪽 세 메서드(경로 복원용, 설계 2026-11-07 6장)는 default 메서드다. default는 자바 문법으로,
// 인터페이스가 기본 구현을 갖게 해 이미 이 인터페이스를 구현한 클래스(테스트용 StubOsrmClient 등)를
// 고치지 않아도 컴파일되게 한다. 기본 구현은 "지원 안 함 = 빈 결과"라서 위의 실패 규칙과 같고,
// 경로 복원은 빈 결과를 받으면 직선으로 대신 채운다. 진짜 구현은 HttpOsrmClient가 덮어쓴다.
public interface OsrmClient {

    /** point에서 maxDistanceMeters 안에 도로가 있으면 도로 위로 붙인 좌표를 돌려준다. */
    Optional<GeoPoint> nearest(String country, GeoPoint point, double maxDistanceMeters);

    /** from에서 to까지의 경로 좌표. 경로가 없으면 빈 리스트. */
    List<GeoPoint> route(String country, GeoPoint from, GeoPoint to);

    /** 좌표열을 도로 위 경로로 재정렬(Map Matching). 실패하면 빈 리스트. */
    List<GeoPoint> match(String country, List<GeoPoint> points);

    /**
     * point에서 가까운 도로 위 점을 가까운 순으로 최대 number개(OSRM /nearest?number=N). maxDistanceMeters보다
     * 먼 점은 뺀다. OSRM은 양방향 도로의 두 방향을 같은 위치로 두 번 줄 수 있다. 실패하면 빈 리스트.
     */
    default List<GeoPoint> nearestCandidates(String country, GeoPoint point, int number, double maxDistanceMeters) {
        return List.of();
    }

    /**
     * sources[i]에서 destinations[j]까지 도로 경로 거리(m) 표(OSRM /table, annotations=distance).
     * 길이 없는 칸은 null이고, 호출이 실패하면 빈 리스트다.
     */
    default List<List<Double>> table(String country, List<GeoPoint> sources, List<GeoPoint> destinations) {
        return List.of();
    }

    /**
     * 점마다 GPS 표준편차(radiuses, m)와 시각(timestamps, 초)을 함께 넘기는 Map Matching. 둘 다 points와 길이가
     * 같아야 하고, null이면 그 옵션을 보내지 않는다(OSRM 기본 반경 5m). 실패하면 빈 리스트.
     */
    default List<GeoPoint> match(String country, List<GeoPoint> points, List<Double> radiuses, List<Long> timestamps) {
        return List.of();
    }
}
```

`server/src/main/java/com/travelfootsteps/route/HttpOsrmClient.java` 전체:

```java
package com.travelfootsteps.route;

import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Profile;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.math.BigDecimal;
import java.net.URI;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.stream.Collectors;
import java.util.stream.IntStream;
import java.util.stream.Stream;

// OsrmClient의 진짜 구현체(자체 호스팅 OSRM HTTP API). GooglePlacesClient와 같은 이유로
// @Profile("!test") — 테스트 프로필에서는 support.StubOsrmClient가 이 자리를 채운다.
@Component
@Profile("!test")
public class HttpOsrmClient implements OsrmClient {

    // 한 요청에 OSRM /route를 최대 8번 보내므로(OverseasWalkService) 한 호출이 오래 걸리면
    // 앱 쪽 10초 타임아웃을 금방 넘긴다. 호출당 5초로 끊는다(mock 서버와 같은 값).
    private static final Duration TIMEOUT = Duration.ofSeconds(5);
    // OSRM /match는 좌표가 너무 많으면 거부한다. mock 서버와 같은 상한.
    private static final int MAX_MATCH_POINTS = 100;
    // 점마다 도로를 찾는 반경(m). OSRM 기본값(약 5m)에서는 도로에서 조금만 벗어난 점이 하나만 있어도
    // NoMatch가 되어 원본 좌표가 그대로 돌아간다. 휴대폰 GPS 오차(보통 5~20m)보다 넉넉하게 잡되,
    // 너무 크면 나란한 옆 도로로 잘못 붙을 수 있어 30m로 한다.
    private static final int MATCH_RADIUS_METERS = 30;

    private final RestClient restClient;
    private final OsrmProperties properties;

    // 스프링이 주입하는 RestClient.Builder는 호출마다 새로 만들어지는 prototype이라 여기서
    // requestFactory를 바꿔도 다른 클라이언트에 영향이 없다.
    @Autowired
    public HttpOsrmClient(RestClient.Builder builder, OsrmProperties properties) {
        this(builder.requestFactory(timeoutFactory()).build(), properties);
    }

    // 테스트가 MockRestServiceServer에 묶은 RestClient를 직접 넘기기 위한 생성자.
    HttpOsrmClient(RestClient restClient, OsrmProperties properties) {
        this.restClient = restClient;
        this.properties = properties;
    }

    private static SimpleClientHttpRequestFactory timeoutFactory() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(TIMEOUT);
        factory.setReadTimeout(TIMEOUT);
        return factory;
    }

    @Override
    public Optional<GeoPoint> nearest(String country, GeoPoint point, double maxDistanceMeters) {
        String baseUrl = properties.baseUrl(country);
        if (baseUrl.isEmpty()) return Optional.empty();

        JsonNode data = get(baseUrl + "/nearest/v1/" + properties.profile() + "/" + lngLat(point));
        if (data == null || !"Ok".equals(data.path("code").asText())) return Optional.empty();

        JsonNode waypoint = data.path("waypoints").path(0);
        if (waypoint.isMissingNode() || waypoint.path("distance").asDouble(Double.MAX_VALUE) > maxDistanceMeters) {
            return Optional.empty();
        }
        return Optional.of(new GeoPoint(waypoint.path("location").path(1).asDouble(),
                waypoint.path("location").path(0).asDouble()));
    }

    @Override
    public List<GeoPoint> route(String country, GeoPoint from, GeoPoint to) {
        String baseUrl = properties.baseUrl(country);
        if (baseUrl.isEmpty()) return List.of();

        JsonNode data = get(baseUrl + "/route/v1/" + properties.profile() + "/"
                + lngLat(from) + ";" + lngLat(to) + "?overview=full&geometries=geojson");
        if (data == null || !"Ok".equals(data.path("code").asText())) return List.of();

        return geometry(data.path("routes").path(0).path("geometry"));
    }

    // 실시간 경로 스냅(/api/route/snap)이 쓰는 기존 방식: 모든 점에 30m 반경을 보낸다.
    @Override
    public List<GeoPoint> match(String country, List<GeoPoint> points) {
        return match(country, points, Collections.nCopies(points.size(), (double) MATCH_RADIUS_METERS), null);
    }

    // OSRM /match는 한 번에 받는 좌표 수가 제한돼 있다(osrm-routed --max-matching-size).
    // 컨트롤러는 500점까지 받는데 앱은 10m 간격으로 좌표를 쌓으므로, 1km가 넘는 평범한
    // 경로도 이 한계를 넘는다. 앞 100점만 보내고 그 결과를 "전체 경로"라고 돌려주면
    // 뒷부분이 통째로 사라지므로, 구간을 나눠 호출하고 결과를 이어 붙인다.
    // 반경·시각은 점과 짝이라 같은 경계로 함께 자른다.
    @Override
    public List<GeoPoint> match(String country, List<GeoPoint> points, List<Double> radiuses, List<Long> timestamps) {
        String baseUrl = properties.baseUrl(country);
        if (baseUrl.isEmpty() || points.size() < 2) return List.of();
        if ((radiuses != null && radiuses.size() != points.size())
                || (timestamps != null && timestamps.size() != points.size())) {
            return List.of();
        }

        List<GeoPoint> out = new ArrayList<>();
        // 구간 경계에서 선이 끊기지 않게 좌표 1점을 겹쳐서 자른다(그래서 step은 한계 - 1).
        for (int start = 0; start < points.size() - 1; start += MAX_MATCH_POINTS - 1) {
            int end = Math.min(start + MAX_MATCH_POINTS, points.size());
            List<GeoPoint> matched = matchChunk(baseUrl, points.subList(start, end),
                    radiuses == null ? null : radiuses.subList(start, end),
                    timestamps == null ? null : timestamps.subList(start, end));
            // 한 구간이라도 실패하면 전체를 실패로 다룬다 — 일부만 그리면 "성공했지만
            // 엉뚱한 경로"가 되어, 호출자가 원본 좌표로 폴백할 기회를 잃는다.
            if (matched.isEmpty()) return List.of();
            // 겹쳐 보낸 좌표 때문에 앞 구간의 끝과 이 구간의 시작이 같은 지점이다.
            out.addAll(out.isEmpty() ? matched : matched.subList(1, matched.size()));
        }
        return out;
    }

    @Override
    public List<GeoPoint> nearestCandidates(String country, GeoPoint point, int number, double maxDistanceMeters) {
        String baseUrl = properties.baseUrl(country);
        if (baseUrl.isEmpty() || number < 1) return List.of();

        JsonNode data = get(baseUrl + "/nearest/v1/" + properties.profile() + "/" + lngLat(point)
                + "?number=" + number);
        if (data == null || !"Ok".equals(data.path("code").asText())) return List.of();

        List<GeoPoint> out = new ArrayList<>();
        for (JsonNode waypoint : data.path("waypoints")) {
            if (waypoint.path("distance").asDouble(Double.MAX_VALUE) > maxDistanceMeters) continue;
            out.add(new GeoPoint(waypoint.path("location").path(1).asDouble(),
                    waypoint.path("location").path(0).asDouble()));
        }
        return out;
    }

    // 좌표 목록에 출발점들을 먼저, 도착점들을 뒤에 넣고 sources·destinations 번호로 나눈다.
    @Override
    public List<List<Double>> table(String country, List<GeoPoint> sources, List<GeoPoint> destinations) {
        String baseUrl = properties.baseUrl(country);
        if (baseUrl.isEmpty() || sources.isEmpty() || destinations.isEmpty()) return List.of();

        String coords = Stream.concat(sources.stream(), destinations.stream())
                .map(HttpOsrmClient::lngLat).collect(Collectors.joining(";"));
        String sourceIndexes = IntStream.range(0, sources.size()).mapToObj(String::valueOf)
                .collect(Collectors.joining(";"));
        String destinationIndexes = IntStream.range(sources.size(), sources.size() + destinations.size())
                .mapToObj(String::valueOf).collect(Collectors.joining(";"));
        JsonNode data = get(baseUrl + "/table/v1/" + properties.profile() + "/" + coords
                + "?sources=" + sourceIndexes + "&destinations=" + destinationIndexes + "&annotations=distance");
        if (data == null || !"Ok".equals(data.path("code").asText())) return List.of();

        JsonNode rows = data.path("distances");
        if (rows.size() != sources.size()) return List.of();
        List<List<Double>> out = new ArrayList<>();
        for (JsonNode row : rows) {
            if (row.size() != destinations.size()) return List.of();
            List<Double> cells = new ArrayList<>();
            // 길이 없는 칸은 JSON null이다 — 0으로 읽지 않도록 null로 둔다.
            row.forEach(cell -> cells.add(cell.isNumber() ? cell.asDouble() : null));
            out.add(cells);
        }
        return out;
    }

    private List<GeoPoint> matchChunk(String baseUrl, List<GeoPoint> chunk, List<Double> radiuses, List<Long> timestamps) {
        if (chunk.size() < 2) return List.of();
        String coords = chunk.stream().map(HttpOsrmClient::lngLat).collect(Collectors.joining(";"));
        StringBuilder url = new StringBuilder(baseUrl + "/match/v1/" + properties.profile() + "/" + coords
                + "?overview=full&geometries=geojson");
        if (radiuses != null) {
            url.append("&radiuses=").append(radiuses.stream().map(HttpOsrmClient::meters)
                    .collect(Collectors.joining(";")));
        }
        if (timestamps != null) {
            url.append("&timestamps=").append(timestamps.stream().map(String::valueOf)
                    .collect(Collectors.joining(";")));
        }
        JsonNode data = get(url.toString());
        if (data == null || !"Ok".equals(data.path("code").asText())) return List.of();

        // GPS가 끊기거나 튀는 구간이 있으면 OSRM은 궤적을 matching 여러 개로 쪼개 돌려준다.
        // 첫 번째만 쓰면 그 뒤의 경로가 통째로 사라지므로 전부 순서대로 이어 붙인다.
        List<GeoPoint> out = new ArrayList<>();
        for (JsonNode matching : data.path("matchings")) {
            out.addAll(geometry(matching.path("geometry")));
        }
        return out;
    }

    // 실패(연결 거부, 타임아웃, 4xx/5xx, JSON 아님)는 전부 null로 바꾼다 — OsrmClient 주석 참고.
    // OSRM은 도로를 못 찾았을 때도 HTTP 400에 {"code":"NoRoute"}를 주므로 정상적인 경우다.
    private JsonNode get(String url) {
        try {
            return restClient.get().uri(URI.create(url)).retrieve()
                    .onStatus(status -> true, (request, response) -> { })
                    .body(JsonNode.class);
        } catch (RestClientException e) {
            return null;
        }
    }

    // OSRM은 lon,lat 순서를 쓴다(Google과 반대). 소수 7자리면 약 1cm 정밀도다.
    private static String lngLat(GeoPoint p) {
        return String.format(Locale.ROOT, "%.7f,%.7f", p.lng(), p.lat());
    }

    // 30.0은 "30", 12.5는 "12.5"로 쓴다 — 기존 스냅 요청 URL(radiuses=30;30;...)을 그대로 지킨다.
    private static String meters(double value) {
        return BigDecimal.valueOf(value).stripTrailingZeros().toPlainString();
    }

    // GeoJSON LineString은 [lng, lat] 순서다 — 우리 응답 스키마({lat, lng})로 뒤집는다.
    private static List<GeoPoint> geometry(JsonNode geometry) {
        List<GeoPoint> out = new ArrayList<>();
        for (JsonNode c : geometry.path("coordinates")) {
            out.add(new GeoPoint(c.path(1).asDouble(), c.path(0).asDouble()));
        }
        return out;
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `./gradlew test --tests 'com.travelfootsteps.route.*'` → 통과(27개). 기존 `RouteControllerTest`·`OverseasWalkServiceTest`도 그대로 통과한다.

- [ ] **Step 5: 커밋**

```bash
git add server/src/main/java/com/travelfootsteps/route/OsrmClient.java server/src/main/java/com/travelfootsteps/route/HttpOsrmClient.java server/src/test/java/com/travelfootsteps/route/HttpOsrmClientTest.java
git commit -m "feat(server): OSRM 클라이언트에 후보 여러 개 nearest, 거리표 table, 반경·시각을 넘기는 match를 더한다"
```

---

### Task 5: 걸음 수로 전이 확률을 정하는 HMM 맵 매칭 `hmm_steps`

**Files:**
- Create: `server/src/main/java/com/travelfootsteps/route/Waypoint.java`
- Create: `server/src/main/java/com/travelfootsteps/route/HmmOptions.java`
- Create: `server/src/main/java/com/travelfootsteps/route/Reconstructor.java`
- Create: `server/src/main/java/com/travelfootsteps/route/HmmStepsReconstructor.java`
- Test: `server/src/test/java/com/travelfootsteps/route/GridOsrm.java`(격자 도로망 가짜 OSRM, Task 6도 쓴다)
- Test: `server/src/test/java/com/travelfootsteps/route/HmmStepsReconstructorTest.java`

**Interfaces:**
- Consumes: Task 4의 `OsrmClient.nearestCandidates`·`table`·`route`, 기존 `GeoMath.haversine`
- Produces:
  - `record Waypoint(long startT, long endT, GeoPoint point, Double accuracy, Integer stepsSincePrev, String state)`, `isVehicle()`
  - `record HmmOptions(Double betaM, Double sigmaMinM, Double strideM, Boolean useSteps)`, `DEFAULTS`(10, 5, 0.75, true), `static HmmOptions orDefaults(HmmOptions)`
  - `interface Reconstructor { List<Piece> reconstruct(String country, List<Waypoint> run, HmmOptions options); record Piece(List<GeoPoint> coords, boolean fallback) { static Piece straight(List<Waypoint>) } static List<GeoPoint> points(List<Waypoint>) }`
  - `class HmmStepsReconstructor(OsrmClient)` — 상수 `CANDIDATES = 5`, `CANDIDATE_RADIUS_M = 200`, `MAX_DISTANCE_DELTA_M = 2000`, `SAME_CANDIDATE_M = 1.0`; `static double walkedDistance(Waypoint previous, Waypoint current, HmmOptions o)`
  - 테스트용 `GridOsrm`: 가로 길 y = 0·100·200m, 세로 길 x = 0·100·200·300m, `at(x, y)`, `x(p)`, `y(p)`, `failing`, `lastRadiuses`·`lastTimestamps`·`matchCalls`

`Waypoint`·`Reconstructor`·`HmmStepsReconstructor`는 패키지 안에서만 쓰므로 `public`이 아니다.

- [ ] **Step 1: 실패하는 테스트 작성**

`server/src/test/java/com/travelfootsteps/route/GridOsrm.java`:

```java
package com.travelfootsteps.route;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;

/**
 * 격자 도로망을 흉내 내는 가짜 OSRM. 가로 길 y = 0·100·200m(x 0~300), 세로 길 x = 0·100·200·300m(y 0~200).
 * 좌표는 (37.5, 127.0)을 원점으로 한 동쪽 x·북쪽 y 미터다. failing이면 모든 호출이 실패(빈 결과)다.
 * 진짜 OSRM처럼 교차로에서는 두 길의 같은 위치를 후보로 두 번 준다.
 */
class GridOsrm implements OsrmClient {

    static final double LAT0 = 37.5;
    static final double LNG0 = 127.0;
    static final double M_PER_DEG = 6371000.0 * Math.PI / 180;
    static final double[] ROWS = {0, 100, 200};
    static final double[] COLS = {0, 100, 200, 300};

    final boolean failing;
    List<Double> lastRadiuses;
    List<Long> lastTimestamps;
    int matchCalls;

    GridOsrm() {
        this(false);
    }

    GridOsrm(boolean failing) {
        this.failing = failing;
    }

    static GeoPoint at(double x, double y) {
        return new GeoPoint(LAT0 + y / M_PER_DEG, LNG0 + x / (M_PER_DEG * Math.cos(Math.toRadians(LAT0))));
    }

    static double x(GeoPoint p) {
        return (p.lng() - LNG0) * M_PER_DEG * Math.cos(Math.toRadians(LAT0));
    }

    static double y(GeoPoint p) {
        return (p.lat() - LAT0) * M_PER_DEG;
    }

    @Override
    public Optional<GeoPoint> nearest(String country, GeoPoint point, double maxDistanceMeters) {
        return nearestCandidates(country, point, 1, maxDistanceMeters).stream().findFirst();
    }

    @Override
    public List<GeoPoint> nearestCandidates(String country, GeoPoint point, int number, double maxDistanceMeters) {
        if (failing) return List.of();
        double px = x(point);
        double py = y(point);
        List<double[]> found = new ArrayList<>();   // {x, y, 거리}
        for (double row : ROWS) {
            double sx = Math.max(0, Math.min(300, px));
            found.add(new double[] {sx, row, Math.hypot(px - sx, py - row)});
        }
        for (double col : COLS) {
            double sy = Math.max(0, Math.min(200, py));
            found.add(new double[] {col, sy, Math.hypot(px - col, py - sy)});
        }
        return found.stream()
                .sorted(Comparator.comparingDouble(f -> f[2]))
                .filter(f -> f[2] <= maxDistanceMeters)
                .limit(number)
                .map(f -> at(f[0], f[1]))
                .toList();
    }

    @Override
    public List<List<Double>> table(String country, List<GeoPoint> sources, List<GeoPoint> destinations) {
        if (failing) return List.of();
        List<List<Double>> out = new ArrayList<>();
        for (GeoPoint s : sources) {
            List<Double> row = new ArrayList<>();
            for (GeoPoint d : destinations) row.add(shortest(s, d).length);
            out.add(row);
        }
        return out;
    }

    @Override
    public List<GeoPoint> route(String country, GeoPoint from, GeoPoint to) {
        if (failing) return List.of();
        Path path = shortest(from, to);
        List<GeoPoint> out = new ArrayList<>();
        for (double[] c : path.corners) {
            GeoPoint p = at(c[0], c[1]);
            if (out.isEmpty() || GeoMath.haversine(out.get(out.size() - 1), p) > 0.01) out.add(p);
        }
        return out;
    }

    @Override
    public List<GeoPoint> match(String country, List<GeoPoint> points) {
        return match(country, points, null, null);
    }

    @Override
    public List<GeoPoint> match(String country, List<GeoPoint> points, List<Double> radiuses, List<Long> timestamps) {
        matchCalls++;
        lastRadiuses = radiuses;
        lastTimestamps = timestamps;
        return failing ? List.of() : points;
    }

    private record Path(Double length, List<double[]> corners) {
    }

    // 두 점이 놓인 길(가로·세로)의 모든 조합 중 가장 짧은 길. 격자라 갈아탈 교차로만 고르면 된다.
    private static Path shortest(GeoPoint from, GeoPoint to) {
        double ax = x(from), ay = y(from), bx = x(to), by = y(to);
        Path best = new Path(null, List.of());
        for (boolean aRow : new boolean[] {true, false}) {
            for (boolean bRow : new boolean[] {true, false}) {
                if (!onStreet(ax, ay, aRow) || !onStreet(bx, by, bRow)) continue;
                List<Path> options = new ArrayList<>();
                if (aRow && bRow) {
                    if (Math.abs(ay - by) < 0.01) options.add(path(ax, ay, bx, by));
                    for (double col : COLS) {
                        options.add(path(ax, ay, col, ay, col, by, bx, by));
                    }
                } else if (!aRow && !bRow) {
                    if (Math.abs(ax - bx) < 0.01) options.add(path(ax, ay, bx, by));
                    for (double row : ROWS) {
                        options.add(path(ax, ay, ax, row, bx, row, bx, by));
                    }
                } else if (aRow) {
                    options.add(path(ax, ay, bx, ay, bx, by));
                } else {
                    options.add(path(ax, ay, ax, by, bx, by));
                }
                for (Path p : options) {
                    if (best.length == null || p.length < best.length - 1e-9) best = p;
                }
            }
        }
        return best;
    }

    private static boolean onStreet(double px, double py, boolean row) {
        if (row) {
            for (double r : ROWS) if (Math.abs(py - r) < 0.01 && px > -0.01 && px < 300.01) return true;
        } else {
            for (double c : COLS) if (Math.abs(px - c) < 0.01 && py > -0.01 && py < 200.01) return true;
        }
        return false;
    }

    private static Path path(double... xy) {
        List<double[]> corners = new ArrayList<>();
        double length = 0;
        for (int i = 0; i < xy.length; i += 2) {
            if (i > 0) length += Math.abs(xy[i] - xy[i - 2]) + Math.abs(xy[i + 1] - xy[i - 1]);
            corners.add(new double[] {xy[i], xy[i + 1]});
        }
        return new Path(length, corners);
    }
}
```

`server/src/test/java/com/travelfootsteps/route/HmmStepsReconstructorTest.java`:

```java
package com.travelfootsteps.route;

import org.junit.jupiter.api.Test;

import java.util.List;

import static com.travelfootsteps.route.GridOsrm.at;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

// 격자 도로망(GridOsrm)에서 HMM이 정답 후보를 고르는지 본다. 좌표는 격자 원점에서 동쪽·북쪽 미터다.
class HmmStepsReconstructorTest {

    private static final HmmOptions BASIC = new HmmOptions(null, null, null, false);

    private static Waypoint point(long seconds, double x, double y, Double accuracy, Integer steps) {
        return new Waypoint(seconds * 1000, seconds * 1000, at(x, y), accuracy, steps, "walking");
    }

    private static void assertAt(GeoPoint p, double x, double y) {
        assertThat(GridOsrm.x(p)).isCloseTo(x, within(0.5));
        assertThat(GridOsrm.y(p)).isCloseTo(y, within(0.5));
    }

    @Test
    void 걸음_수로_실제_걸은_거리를_알아_꺾인_길의_후보를_고른다() {
        // (0,0)에서 동쪽 100m, 북쪽 40m를 걸어(140m, 187걸음) (100,40)에 있었다. 두 번째 측위는 오차 40m로
        // 블록 안 (60,40)에 찍혀 (60,0)과 (100,40)이 똑같이 40m 거리다.
        List<Waypoint> run = List.of(point(0, 0, 0, 5.0, null), point(100, 60, 40, 40.0, 187));
        HmmStepsReconstructor hmm = new HmmStepsReconstructor(new GridOsrm());

        Reconstructor.Piece piece = hmm.reconstruct("KR", run, HmmOptions.DEFAULTS).get(0);

        assertThat(piece.fallback()).isFalse();
        assertAt(piece.coords().get(0), 0, 0);
        assertAt(piece.coords().get(1), 100, 0); // 모퉁이를 돌아
        assertAt(piece.coords().get(piece.coords().size() - 1), 100, 40);
    }

    @Test
    void 직선거리를_쓰는_기본_HMM은_같은_점에서_가까운_길로_잘못_간다() {
        // 직선거리(72m)는 (60,0)까지의 도로 거리(60m)와 더 가깝다 — 걸음 정보 없이는 꺾인 길을 놓친다.
        List<Waypoint> run = List.of(point(0, 0, 0, 5.0, null), point(100, 60, 40, 40.0, 187));
        HmmStepsReconstructor hmm = new HmmStepsReconstructor(new GridOsrm());

        Reconstructor.Piece piece = hmm.reconstruct("KR", run, BASIC).get(0);

        assertAt(piece.coords().get(piece.coords().size() - 1), 60, 0);
    }

    @Test
    void 잡음이_있어도_걷는_내내_같은_길의_후보를_고른다() {
        // y=0 길을 따라 50m(67걸음)마다 측위, 남북으로 ±20m 흔들린다. x=100·200처럼 세로 길 위에 찍힌 점도
        // 그 길로 꺾었다 돌아오는 것보다 y=0에 머무는 쪽이 걸음 수와 맞는다.
        double[] noise = {5, -12, 20, -18, 10, -15, 12};
        List<Waypoint> run = new java.util.ArrayList<>();
        for (int k = 0; k < noise.length; k++) {
            run.add(point(40L * k, 50.0 * k, noise[k], 15.0, k == 0 ? null : 67));
        }
        HmmStepsReconstructor hmm = new HmmStepsReconstructor(new GridOsrm());

        List<Reconstructor.Piece> pieces = hmm.reconstruct("KR", run, HmmOptions.DEFAULTS);

        assertThat(pieces).hasSize(1);
        assertThat(pieces.get(0).fallback()).isFalse();
        for (GeoPoint p : pieces.get(0).coords()) assertThat(GridOsrm.y(p)).isCloseTo(0, within(0.5));
        assertAt(pieces.get(0).coords().get(0), 0, 0);
        assertAt(pieces.get(0).coords().get(pieces.get(0).coords().size() - 1), 300, 0);
    }

    @Test
    void 반경_200m_안에_도로가_없는_점에서_사슬이_끊기고_그_양옆만_직선_fallback이다() {
        List<Waypoint> run = List.of(
                point(0, 0, 0, 5.0, null),
                point(80, 100, 0, 5.0, 133),
                point(160, 100, -500, 5.0, 133),   // 도로에서 500m — 후보 없음
                point(240, 200, 0, 5.0, 133),
                point(320, 300, 0, 5.0, 133));
        HmmStepsReconstructor hmm = new HmmStepsReconstructor(new GridOsrm());

        List<Reconstructor.Piece> pieces = hmm.reconstruct("KR", run, HmmOptions.DEFAULTS);

        assertThat(pieces).extracting(Reconstructor.Piece::fallback).containsExactly(false, true, false);
        assertThat(pieces.get(1).coords()).hasSize(3);
        assertAt(pieces.get(1).coords().get(0), 100, 0);
        assertAt(pieces.get(1).coords().get(1), 100, -500);
        assertAt(pieces.get(1).coords().get(2), 200, 0);
    }

    @Test
    void OSRM이_꺼져_있으면_받은_점을_직선으로_이은_fallback_한_조각이다() {
        List<Waypoint> run = List.of(point(0, 0, 0, 5.0, null), point(60, 60, 40, 40.0, 100));
        HmmStepsReconstructor hmm = new HmmStepsReconstructor(new GridOsrm(true));

        List<Reconstructor.Piece> pieces = hmm.reconstruct("KR", run, HmmOptions.DEFAULTS);

        assertThat(pieces).hasSize(1);
        assertThat(pieces.get(0).fallback()).isTrue();
        assertThat(pieces.get(0).coords()).containsExactly(run.get(0).point(), run.get(1).point());
    }

    @Test
    void 걸은_거리는_걸음_수와_보폭이고_걸음을_모르거나_탈것이면_직선거리다() {
        Waypoint a = point(0, 0, 0, 5.0, null);
        Waypoint walked = point(60, 60, 80, 5.0, 200);
        Waypoint vehicle = new Waypoint(60_000, 60_000, at(60, 80), 5.0, 200, "vehicle");
        Waypoint unknown = point(60, 60, 80, 5.0, null);

        assertThat(HmmStepsReconstructor.walkedDistance(a, walked, HmmOptions.DEFAULTS)).isCloseTo(150, within(1e-9));
        assertThat(HmmStepsReconstructor.walkedDistance(a, vehicle, HmmOptions.DEFAULTS)).isCloseTo(100, within(0.1));
        assertThat(HmmStepsReconstructor.walkedDistance(a, unknown, HmmOptions.DEFAULTS)).isCloseTo(100, within(0.1));
        assertThat(HmmStepsReconstructor.walkedDistance(a, walked, BASIC)).isCloseTo(100, within(0.1));
    }
}
```

첫 두 테스트의 수(β 10m, σ = 정확도): 두 번째 점 (60,40)은 (60,0)·(100,40)과 똑같이 40m라 방사 확률이 같다. 걸은 거리 140.25m(187걸음)로 보면 (100,40)까지 도로 거리 140m가 맞아 −0.03, (60,0)은 60m라 −8.0이다. 직선거리 72.1m로 보면 거꾸로 (60,0)이 −1.2, (100,40)이 −6.8이다.

- [ ] **Step 2: 실패 확인**

Run: `./gradlew test --tests 'com.travelfootsteps.route.HmmStepsReconstructorTest'`

Expected: FAIL. `Waypoint`·`HmmOptions`·`HmmStepsReconstructor`가 없어 컴파일되지 않는다.

- [ ] **Step 3: 구현**

`server/src/main/java/com/travelfootsteps/route/Waypoint.java`:

```java
package com.travelfootsteps.route;

// 복원 안에서 쓰는 지나간 점 하나. 측위 점이면 startT = endT이고, 머문 곳이면 그 중심이 [도착, 출발]을 차지한다.
// 공백은 앞 점의 endT와 다음 점의 startT 사이로 잰다 — 머문 시간 자체를 공백으로 보지 않기 위해서다.
//  - accuracy       : 정확도(m). 모르면 null
//  - stepsSincePrev : 직전 점 이후 걸음 수. 모르면 null
//  - state          : 측위 때 정책 상태(still·walking·otherMotion·vehicle·unknown). 모르면 null
record Waypoint(long startT, long endT, GeoPoint point, Double accuracy, Integer stepsSincePrev, String state) {

    boolean isVehicle() {
        return "vehicle".equals(state);
    }
}
```

`server/src/main/java/com/travelfootsteps/route/HmmOptions.java`:

```java
package com.travelfootsteps.route;

import jakarta.validation.constraints.Positive;

// hmm_steps의 조정값(설계 6-3). 요청에서 빠진 값은 아래 기본값을 쓴다. R6가 예비용 세션으로 β와 σ 하한을 정할 때
// 서버를 다시 빌드하지 않고 요청마다 바꿔 볼 수 있게 요청 값으로 받는다.
//  - betaM     : 전이 확률 exp(-|도로 경로거리 - 걸은 거리| / β)의 β(m)
//  - sigmaMinM : 방사 확률 가우시안의 σ 하한(m). σ = max(점 정확도, 하한)
//  - strideM   : 걸은 거리 = 걸음 수 × 보폭
//  - useSteps  : false면 걸은 거리 대신 두 점의 직선거리(Newson & Krumm 원래 식, 절제 실험)
public record HmmOptions(
        @Positive Double betaM,
        @Positive Double sigmaMinM,
        @Positive Double strideM,
        Boolean useSteps
) {
    // 조정 전 기본값. β 10m는 OSRM 자체 맵 매칭의 기본값(MATCHING_BETA)과 같아 osrm_match_radius와 같은 β로
    // 견줄 수 있다. σ 하한 5m는 설계 6-3과 OSRM 기본 GPS 정밀도다. 둘 다 R6에서 예비용 세션으로 다시 정한다.
    static final double DEFAULT_BETA_M = 10.0;
    static final double DEFAULT_SIGMA_MIN_M = 5.0;
    static final double DEFAULT_STRIDE_M = 0.75;

    static final HmmOptions DEFAULTS =
            new HmmOptions(DEFAULT_BETA_M, DEFAULT_SIGMA_MIN_M, DEFAULT_STRIDE_M, true);

    /** 빠진 값을 기본값으로 채운다. options가 null이면 기본값 전체다. */
    static HmmOptions orDefaults(HmmOptions options) {
        if (options == null) return DEFAULTS;
        return new HmmOptions(
                options.betaM() != null ? options.betaM() : DEFAULT_BETA_M,
                options.sigmaMinM() != null ? options.sigmaMinM() : DEFAULT_SIGMA_MIN_M,
                options.strideM() != null ? options.strideM() : DEFAULT_STRIDE_M,
                options.useSteps() != null ? options.useSteps() : Boolean.TRUE);
    }
}
```

`server/src/main/java/com/travelfootsteps/route/Reconstructor.java`:

```java
package com.travelfootsteps.route;

import java.util.List;

// 복원 방법 하나(설계 6-2 표의 한 행). 공백 없이 이어진 같은 종류(도보·탈것)의 점 2개 이상을 받아 경로 조각을 낸다.
// 조각마다 fallback 여부가 다를 수 있어(예: HMM이 끊긴 곳만 직선) 목록으로 돌려준다. 실패를 예외로 알리지 않고
// 직선 조각(fallback=true)으로 돌려준다 — OsrmClient와 같은 "실패 = 빈 결과" 규칙을 응답까지 이어 간다.
interface Reconstructor {

    List<Piece> reconstruct(String country, List<Waypoint> run, HmmOptions options);

    record Piece(List<GeoPoint> coords, boolean fallback) {

        /** 받은 점을 그대로 직선으로 잇는 대체 조각. */
        static Piece straight(List<Waypoint> run) {
            return new Piece(points(run), true);
        }
    }

    static List<GeoPoint> points(List<Waypoint> run) {
        return run.stream().map(Waypoint::point).toList();
    }
}
```

`server/src/main/java/com/travelfootsteps/route/HmmStepsReconstructor.java`:

```java
package com.travelfootsteps.route;

import java.util.ArrayList;
import java.util.List;

/**
 * hmm_steps: 걸음 수로 전이 확률을 정하는 은닉 마르코프 모델 맵 매칭(설계 6-3, 제안).
 *
 * <p>틀은 Newson & Krumm, "Hidden Markov Map Matching Through Noise and Sparseness"(ACM GIS 2009)를 따른다.
 * <ul>
 *   <li>후보: 점마다 OSRM /nearest로 200m(원문 3.1절) 안의 도로 위 점 최대 5개.</li>
 *   <li>방사 확률(원문 식 1): 점과 후보 사이 거리의 가우시안. σ = max(점 정확도, σ 하한). 같은 점의 후보끼리만
 *       비교되므로 정규화 상수는 빼고 로그 값 -0.5(d/σ)²만 쓴다.</li>
 *   <li>전이 확률(원문 식 2): exp(-|도로 경로거리 - 걸은 거리| / β). 원문은 걸은 거리 자리에 두 점의 직선거리를
 *       쓴다. 제안은 걸음 수 × 보폭을 쓴다 — 점이 드물어 길이 꺾여도 실제로 걸은 거리를 안다. 걸음 정보가 없거나
 *       탈것이면 원문대로 직선거리다. 도로 경로거리는 연속한 두 점의 후보 쌍을 OSRM /table로 한 번에 구한다.</li>
 *   <li>차이가 2000m 이상인 전이는 불가능으로 본다(원문 4.2절, OSRM MAX_DISTANCE_DELTA).</li>
 *   <li>비터비로 가장 그럴듯한 후보 순서를 고르고, 고른 후보 사이를 OSRM /route로 잇는다.</li>
 * </ul>
 * 후보가 없는 점이나 모든 전이가 불가능한 곳에서는 사슬이 끊긴다(원문 4.2절의 break). 원문은 끊긴 곳 양옆 점을
 * 지워 가며 다시 이어 보지만, 여기서는 끊긴 곳만 직선(fallback)으로 잇고 양쪽을 따로 매칭한다.
 */
class HmmStepsReconstructor implements Reconstructor {

    static final int CANDIDATES = 5;
    static final double CANDIDATE_RADIUS_M = 200;
    static final double MAX_DISTANCE_DELTA_M = 2000;
    // OSRM은 양방향 도로의 두 방향을 같은 위치로 두 번 준다. 이보다 가까운 후보는 하나로 본다.
    static final double SAME_CANDIDATE_M = 1.0;

    private final OsrmClient osrmClient;

    HmmStepsReconstructor(OsrmClient osrmClient) {
        this.osrmClient = osrmClient;
    }

    @Override
    public List<Piece> reconstruct(String country, List<Waypoint> run, HmmOptions options) {
        HmmOptions o = HmmOptions.orDefaults(options);
        int n = run.size();
        List<List<GeoPoint>> candidates = new ArrayList<>();
        for (Waypoint w : run) {
            candidates.add(distinct(osrmClient.nearestCandidates(country, w.point(), CANDIDATES, CANDIDATE_RADIUS_M)));
        }

        // chosen[t]: 고른 후보(없으면 null), chain[t]: 사슬 번호(-1이면 후보 없음).
        GeoPoint[] chosen = new GeoPoint[n];
        int[] chain = new int[n];
        int chains = 0;
        int chainStart = -1;
        double[] score = null;
        List<int[]> back = new ArrayList<>();

        for (int t = 0; t < n; t++) {
            List<GeoPoint> cands = candidates.get(t);
            if (cands.isEmpty()) {
                if (chainStart >= 0) backtrack(chainStart, t - 1, score, back, candidates, chosen, chain, chains++);
                chainStart = -1;
                chain[t] = -1;
                continue;
            }
            double[] emission = emissions(run.get(t), cands, o);
            if (chainStart < 0) {
                chainStart = t;
                score = emission;
                back = new ArrayList<>();
                back.add(null);
                continue;
            }

            List<GeoPoint> previous = candidates.get(t - 1);
            List<List<Double>> table = osrmClient.table(country, previous, cands);
            double walked = walkedDistance(run.get(t - 1), run.get(t), o);
            double[] next = new double[cands.size()];
            int[] from = new int[cands.size()];
            boolean reachable = false;
            for (int j = 0; j < cands.size(); j++) {
                double best = Double.NEGATIVE_INFINITY;
                int arg = -1;
                for (int i = 0; i < previous.size() && !table.isEmpty(); i++) {
                    Double route = table.get(i).get(j);
                    if (route == null || score[i] == Double.NEGATIVE_INFINITY) continue;
                    double diff = Math.abs(route - walked);
                    if (diff >= MAX_DISTANCE_DELTA_M) continue;
                    double s = score[i] - diff / o.betaM();
                    if (s > best) {
                        best = s;
                        arg = i;
                    }
                }
                next[j] = arg < 0 ? Double.NEGATIVE_INFINITY : best + emission[j];
                from[j] = arg;
                reachable |= arg >= 0;
            }
            if (!reachable) {
                // 어느 후보로도 건너갈 수 없다(OSRM /table 실패 포함) — 여기서 사슬을 끊고 새로 시작한다.
                backtrack(chainStart, t - 1, score, back, candidates, chosen, chain, chains++);
                chainStart = t;
                score = emission;
                back = new ArrayList<>();
                back.add(null);
                continue;
            }
            score = next;
            back.add(from);
        }
        if (chainStart >= 0) backtrack(chainStart, n - 1, score, back, candidates, chosen, chain, chains);

        return pieces(country, run, chosen, chain);
    }

    /** 걸은 거리: 걸음 수 × 보폭. 걸음을 모르거나 탈것이거나 절제 실험(useSteps=false)이면 두 점의 직선거리. */
    static double walkedDistance(Waypoint previous, Waypoint current, HmmOptions o) {
        if (o.useSteps() && current.stepsSincePrev() != null && !current.isVehicle()) {
            return current.stepsSincePrev() * o.strideM();
        }
        return GeoMath.haversine(previous.point(), current.point());
    }

    private static double[] emissions(Waypoint w, List<GeoPoint> cands, HmmOptions o) {
        double sigma = Math.max(w.accuracy() != null ? w.accuracy() : o.sigmaMinM(), o.sigmaMinM());
        double[] out = new double[cands.size()];
        for (int j = 0; j < cands.size(); j++) {
            double d = GeoMath.haversine(w.point(), cands.get(j)) / sigma;
            out[j] = -0.5 * d * d;
        }
        return out;
    }

    private static List<GeoPoint> distinct(List<GeoPoint> raw) {
        List<GeoPoint> out = new ArrayList<>();
        for (GeoPoint p : raw) {
            if (out.stream().noneMatch(q -> GeoMath.haversine(p, q) < SAME_CANDIDATE_M)) out.add(p);
        }
        return out;
    }

    /** 사슬의 마지막 단계에서 점수가 가장 높은 후보부터 거꾸로 따라가며 고른다. 같은 점수면 가까운 후보가 먼저다. */
    private static void backtrack(int start, int end, double[] lastScore, List<int[]> back,
                                  List<List<GeoPoint>> candidates, GeoPoint[] chosen, int[] chain, int chainNo) {
        int best = 0;
        for (int j = 1; j < lastScore.length; j++) {
            if (lastScore[j] > lastScore[best]) best = j;
        }
        for (int t = end; t >= start; t--) {
            chosen[t] = candidates.get(t).get(best);
            chain[t] = chainNo;
            if (t > start) best = back.get(t - start)[best];
        }
    }

    /** 같은 사슬 안의 이웃은 /route로, 끊긴 곳은 직선(fallback)으로 잇고, fallback이 같은 다리끼리 한 조각으로 묶는다. */
    private List<Piece> pieces(String country, List<Waypoint> run, GeoPoint[] chosen, int[] chain) {
        List<Piece> out = new ArrayList<>();
        List<GeoPoint> coords = new ArrayList<>();
        boolean fallback = false;
        for (int t = 0; t + 1 < run.size(); t++) {
            GeoPoint a = chosen[t] != null ? chosen[t] : run.get(t).point();
            GeoPoint b = chosen[t + 1] != null ? chosen[t + 1] : run.get(t + 1).point();
            List<GeoPoint> leg;
            boolean legFallback;
            if (chain[t] >= 0 && chain[t] == chain[t + 1]) {
                List<GeoPoint> route = GeoMath.haversine(a, b) < SAME_CANDIDATE_M ? List.of(a, b)
                        : osrmClient.route(country, a, b);
                legFallback = route.isEmpty();
                leg = legFallback ? List.of(a, b) : route;
            } else {
                legFallback = true;
                leg = List.of(a, b);
            }
            if (!coords.isEmpty() && legFallback != fallback) {
                out.add(new Piece(coords, fallback));
                coords = new ArrayList<>(List.of(coords.get(coords.size() - 1)));
            }
            fallback = legFallback;
            append(coords, leg);
        }
        out.add(new Piece(coords, fallback));
        return out;
    }

    // 다리의 첫 점이 앞 다리의 끝과 같은 자리면 한 번만 넣는다.
    private static void append(List<GeoPoint> coords, List<GeoPoint> leg) {
        int skip = !coords.isEmpty() && GeoMath.haversine(coords.get(coords.size() - 1), leg.get(0)) < 0.5 ? 1 : 0;
        coords.addAll(leg.subList(skip, leg.size()));
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `./gradlew test --tests 'com.travelfootsteps.route.*'` → 통과(33개).

확인 하나 더(검증 때 한 것): `walkedDistance`의 첫 `if`를 `if (false)`로 바꾸면(늘 직선거리) 테스트 3개가 실패해야 한다. 확인한 뒤 되돌린다.

- [ ] **Step 5: 커밋**

```bash
git add server/src/main/java/com/travelfootsteps/route/Waypoint.java server/src/main/java/com/travelfootsteps/route/HmmOptions.java server/src/main/java/com/travelfootsteps/route/Reconstructor.java server/src/main/java/com/travelfootsteps/route/HmmStepsReconstructor.java server/src/test/java/com/travelfootsteps/route/GridOsrm.java server/src/test/java/com/travelfootsteps/route/HmmStepsReconstructorTest.java
git commit -m "feat(server): 걸음 수로 전이 확률을 정하는 HMM 맵 매칭 hmm_steps를 더한다"
```

---

### Task 6: 경로 복원 서비스와 기준 방법들

**Files:**
- Create: `server/src/main/java/com/travelfootsteps/route/ReconstructMethod.java`
- Create: `server/src/main/java/com/travelfootsteps/route/SegmentKind.java`
- Create: `server/src/main/java/com/travelfootsteps/route/TrackPoint.java`
- Create: `server/src/main/java/com/travelfootsteps/route/StayInput.java`
- Create: `server/src/main/java/com/travelfootsteps/route/ReconstructRequest.java`
- Create: `server/src/main/java/com/travelfootsteps/route/RouteSegment.java`
- Create: `server/src/main/java/com/travelfootsteps/route/ReconstructResponse.java`
- Create: `server/src/main/java/com/travelfootsteps/route/StraightReconstructor.java`
- Create: `server/src/main/java/com/travelfootsteps/route/NearestReconstructor.java`
- Create: `server/src/main/java/com/travelfootsteps/route/OsrmMatchReconstructor.java`
- Create: `server/src/main/java/com/travelfootsteps/route/RouteReconstructionService.java`
- Test: `server/src/test/java/com/travelfootsteps/route/RouteReconstructionServiceTest.java`

**Interfaces:**
- Consumes: Task 4의 `OsrmClient`, Task 5의 `Waypoint`·`HmmOptions`·`Reconstructor`·`HmmStepsReconstructor`·`GridOsrm`
- Produces:
  - `enum ReconstructMethod { STRAIGHT, NEAREST, OSRM_MATCH, OSRM_MATCH_RADIUS, HMM_STEPS }` — JSON 이름 `straight`·`nearest`·`osrm_match`·`osrm_match_radius`·`hmm_steps`, 모르면 IllegalArgumentException(→ 400)
  - `enum SegmentKind { WALK, VEHICLE, ESTIMATED }` — JSON `walk`·`vehicle`·`estimated`
  - `record TrackPoint(Long t, Double lat, Double lng, Double accuracy, Integer stepsSincePrev, String state)`
  - `record StayInput(Long arrive, Long leave, Double lat, Double lng)`, `isOrdered()`
  - `record ReconstructRequest(ReconstructMethod method, List<TrackPoint> points, List<StayInput> stays, HmmOptions hmm)` — 점 ≤ 2000, 머문 곳 ≤ 500
  - `record RouteSegment(SegmentKind kind, List<GeoPoint> coords, boolean fallback)`, `record ReconstructResponse(ReconstructMethod method, List<RouteSegment> segments)`
  - `@Service RouteReconstructionService(OsrmClient)`: `ReconstructResponse reconstruct(ReconstructRequest)`, `static List<Waypoint> waypoints(List<TrackPoint>, List<StayInput>)`, `static List<List<Waypoint>> splitAtGaps(List<Waypoint>)`, 상수 `COUNTRY = "KR"`, `GAP_MS = 600000`
  - `OsrmMatchReconstructor.radiuses(run)`·`timestamps(run)`

- [ ] **Step 1: 실패하는 테스트 작성**

`server/src/test/java/com/travelfootsteps/route/RouteReconstructionServiceTest.java`:

```java
package com.travelfootsteps.route;

import org.junit.jupiter.api.Test;

import java.util.List;

import static com.travelfootsteps.route.GridOsrm.at;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

// 처리 순서(머문 곳 → 공백 → 방법별 연결)와 실패 시 직선 대체를 격자 도로망 가짜 OSRM으로 본다.
class RouteReconstructionServiceTest {

    private static TrackPoint p(long seconds, double x, double y, Integer steps, String state) {
        GeoPoint g = at(x, y);
        return new TrackPoint(seconds * 1000, g.lat(), g.lng(), 5.0, steps, state);
    }

    private static TrackPoint walking(long seconds, double x, double y) {
        return p(seconds, x, y, 100, "walking");
    }

    private static ReconstructRequest request(ReconstructMethod method, List<TrackPoint> points, List<StayInput> stays) {
        return new ReconstructRequest(method, points, stays, null);
    }

    private static void assertAt(GeoPoint p, double x, double y) {
        assertThat(GridOsrm.x(p)).isCloseTo(x, within(0.5));
        assertThat(GridOsrm.y(p)).isCloseTo(y, within(0.5));
    }

    @Test
    void 머문_곳_안의_점은_중심_하나로_바뀌고_머문_시간은_공백으로_보지_않는다() {
        GeoPoint center = at(100, 0);
        List<TrackPoint> points = List.of(
                walking(0, 0, 0), walking(60, 50, 3),
                walking(200, 100, 5), walking(700, 98, 4), walking(1300, 103, 2),   // 머문 곳 안
                walking(1560, 150, 0), walking(1620, 200, 0));
        StayInput stay = new StayInput(120_000L, 1_500_000L, center.lat(), center.lng());
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm());

        ReconstructResponse response = service.reconstruct(request(ReconstructMethod.STRAIGHT, points, List.of(stay)));

        RouteSegment walk = response.segments().get(0);
        assertThat(response.segments()).hasSize(1); // 23분을 머물렀어도 머문 뒤 60초 만에 다음 점이라 공백이 아니다
        assertThat(walk.kind()).isEqualTo(SegmentKind.WALK);
        assertThat(walk.coords()).hasSize(5);
        assertThat(walk.coords().get(2)).isEqualTo(center);
    }

    @Test
    void 머문_곳의_중심은_그_안에_처음_든_점의_걸음_수와_상태를_이어받는다() {
        List<TrackPoint> points = List.of(walking(0, 0, 0), p(200, 100, 5, 40, "still"), p(900, 100, 4, 0, "still"));
        StayInput stay = new StayInput(120_000L, 1_000_000L, at(100, 0).lat(), at(100, 0).lng());

        List<Waypoint> waypoints = RouteReconstructionService.waypoints(points, List.of(stay));

        assertThat(waypoints).hasSize(2);
        Waypoint center = waypoints.get(1);
        assertThat(center.startT()).isEqualTo(120_000L);
        assertThat(center.endT()).isEqualTo(1_000_000L);
        assertThat(center.stepsSincePrev()).isEqualTo(40);
        assertThat(center.state()).isEqualTo("still");
    }

    @Test
    void 십분_넘게_비면_자르고_공백_양_끝을_최단경로로_이어_estimated로_표시한다() {
        List<TrackPoint> points = List.of(walking(0, 0, 0), walking(60, 100, 0), walking(900, 200, 100), walking(960, 300, 100));
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm());

        List<RouteSegment> segments = service.reconstruct(request(ReconstructMethod.STRAIGHT, points, List.of())).segments();

        assertThat(segments).extracting(RouteSegment::kind)
                .containsExactly(SegmentKind.WALK, SegmentKind.ESTIMATED, SegmentKind.WALK);
        RouteSegment gap = segments.get(1);
        assertThat(gap.fallback()).isFalse();
        assertAt(gap.coords().get(0), 100, 0);
        assertAt(gap.coords().get(gap.coords().size() - 1), 200, 100);
        assertThat(GeoMath.polylineLength(gap.coords())).isCloseTo(200, within(0.5)); // 격자 최단경로
    }

    @Test
    void 십분이_안_되는_공백은_자르지_않는다() {
        List<TrackPoint> points = List.of(walking(0, 0, 0), walking(599, 100, 0));
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm());

        assertThat(service.reconstruct(request(ReconstructMethod.STRAIGHT, points, List.of())).segments())
                .extracting(RouteSegment::kind).containsExactly(SegmentKind.WALK);
    }

    @Test
    void 탈것_상태로_도착한_점까지는_vehicle_구간으로_나눈다() {
        List<TrackPoint> points = List.of(walking(0, 0, 0), walking(60, 100, 0),
                p(120, 200, 0, null, "vehicle"), p(180, 300, 0, null, "vehicle"), walking(240, 300, 100));
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm());

        List<RouteSegment> segments = service.reconstruct(request(ReconstructMethod.STRAIGHT, points, List.of())).segments();

        assertThat(segments).extracting(RouteSegment::kind)
                .containsExactly(SegmentKind.WALK, SegmentKind.VEHICLE, SegmentKind.WALK);
        assertThat(segments.get(1).coords()).hasSize(3); // 100 → 200 → 300, 경계 점은 양쪽 구간이 함께 쓴다
    }

    @Test
    void OSRM이_꺼져_있으면_방법마다_직선으로_대신하고_fallback을_붙인다() {
        List<TrackPoint> points = List.of(walking(0, 0, 0), walking(60, 60, 40), walking(900, 200, 100), walking(960, 300, 100));
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm(true));

        for (ReconstructMethod method : List.of(ReconstructMethod.NEAREST, ReconstructMethod.OSRM_MATCH,
                ReconstructMethod.OSRM_MATCH_RADIUS, ReconstructMethod.HMM_STEPS)) {
            List<RouteSegment> segments = service.reconstruct(request(method, points, List.of())).segments();

            assertThat(segments).as(method.wireName()).extracting(RouteSegment::fallback).containsOnly(true);
            assertThat(segments.get(0).coords()).as(method.wireName())
                    .containsExactly(at(0, 0), at(60, 40));
            assertThat(segments.get(1).kind()).isEqualTo(SegmentKind.ESTIMATED);
            assertThat(segments.get(1).coords()).hasSize(2); // 공백도 /route 대신 직선
        }
        assertThat(service.reconstruct(request(ReconstructMethod.STRAIGHT, points, List.of())).segments().get(0)
                .fallback()).isFalse();
    }

    @Test
    void nearest는_점마다_가장_가까운_도로에_붙여_직선으로_잇는다() {
        List<TrackPoint> points = List.of(walking(0, 0, 3), walking(60, 50, 15), walking(120, 100, -4));
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm());

        RouteSegment segment = service.reconstruct(request(ReconstructMethod.NEAREST, points, List.of())).segments().get(0);

        assertThat(segment.fallback()).isFalse();
        assertAt(segment.coords().get(1), 50, 0);
    }

    @Test
    void osrm_match_radius는_정확도를_5에서_50m로_맞춘_반경과_늘어나는_초_단위_시각을_넘긴다() {
        GeoPoint a = at(0, 0);
        List<TrackPoint> points = List.of(
                new TrackPoint(1_000L, a.lat(), a.lng(), 3.0, null, null),
                new TrackPoint(1_500L, a.lat(), a.lng(), 12.5, null, null),   // 같은 초 → 1초 민다
                new TrackPoint(61_000L, a.lat(), a.lng(), 80.0, null, null),
                new TrackPoint(121_000L, a.lat(), a.lng(), null, null, null));
        GridOsrm osrm = new GridOsrm();
        RouteReconstructionService service = new RouteReconstructionService(osrm);

        service.reconstruct(request(ReconstructMethod.OSRM_MATCH_RADIUS, points, List.of()));
        assertThat(osrm.lastRadiuses).containsExactly(5.0, 12.5, 50.0, 5.0);
        assertThat(osrm.lastTimestamps).containsExactly(1L, 2L, 61L, 121L);

        service.reconstruct(request(ReconstructMethod.OSRM_MATCH, points, List.of()));
        assertThat(osrm.lastRadiuses).isNull(); // OSRM 기본값(5m)
        assertThat(osrm.lastTimestamps).isNull();
    }

    @Test
    void method를_빼면_앱_기본값_osrm_match_radius로_복원한다() {
        GridOsrm osrm = new GridOsrm();
        RouteReconstructionService service = new RouteReconstructionService(osrm);

        ReconstructResponse response = service.reconstruct(request(null, List.of(walking(0, 0, 0), walking(60, 100, 0)), null));

        assertThat(response.method()).isEqualTo(ReconstructMethod.OSRM_MATCH_RADIUS);
        assertThat(osrm.matchCalls).isEqualTo(1);
    }

    @Test
    void 점이_하나면_좌표_하나짜리_구간이고_없으면_빈_목록이다() {
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm());

        assertThat(service.reconstruct(request(ReconstructMethod.HMM_STEPS, List.of(walking(0, 50, 0)), List.of()))
                .segments()).singleElement().satisfies(s -> assertThat(s.coords()).hasSize(1));
        assertThat(service.reconstruct(request(ReconstructMethod.HMM_STEPS, List.of(), List.of())).segments()).isEmpty();
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `./gradlew test --tests 'com.travelfootsteps.route.RouteReconstructionServiceTest'`

Expected: FAIL. `TrackPoint`·`ReconstructRequest`·`RouteReconstructionService` 등이 없어 컴파일되지 않는다.

- [ ] **Step 3: 구현**

`ReconstructMethod.java`:

```java
package com.travelfootsteps.route;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

// 경로 복원 방법(설계 2026-11-07 6-2 표). JSON에서는 소문자 이름(osrm_match_radius 등)으로 주고받는다.
// @JsonValue는 Jackson(스프링이 JSON 변환에 쓰는 라이브러리)이 이 enum을 JSON으로 쓸 때 쓰는 값을,
// @JsonCreator는 JSON 문자열에서 enum을 만들 때 부르는 메서드를 정한다. 모르는 이름이면 예외가 나고,
// 스프링 MVC가 그것을 "요청 본문을 읽을 수 없음"으로 받아 400 Bad Request로 돌려준다.
public enum ReconstructMethod {
    STRAIGHT("straight"),
    NEAREST("nearest"),
    OSRM_MATCH("osrm_match"),
    OSRM_MATCH_RADIUS("osrm_match_radius"),
    HMM_STEPS("hmm_steps");

    private final String wireName;

    ReconstructMethod(String wireName) {
        this.wireName = wireName;
    }

    @JsonValue
    public String wireName() {
        return wireName;
    }

    @JsonCreator
    public static ReconstructMethod from(String value) {
        for (ReconstructMethod method : values()) {
            if (method.wireName.equals(value)) return method;
        }
        throw new IllegalArgumentException("알 수 없는 복원 방법: " + value);
    }
}
```

`SegmentKind.java`:

```java
package com.travelfootsteps.route;

import com.fasterxml.jackson.annotation.JsonValue;

// 복원한 구간의 종류(설계 6-1). estimated는 GPS가 없던 10분 이상의 공백(지하철 등)을 최단경로로 이은 것이다.
// @JsonValue: 응답 JSON에 이 enum을 소문자 이름으로 쓴다.
public enum SegmentKind {
    WALK("walk"),
    VEHICLE("vehicle"),
    ESTIMATED("estimated");

    private final String wireName;

    SegmentKind(String wireName) {
        this.wireName = wireName;
    }

    @JsonValue
    public String wireName() {
        return wireName;
    }
}
```

`TrackPoint.java`:

```java
package com.travelfootsteps.route;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.PositiveOrZero;

// 복원 요청의 측위 점 하나(재생기 fixes.csv의 한 행, 앱 RoutePoints의 한 행과 같은 내용).
// 이 레코드의 애너테이션은 Bean Validation 규칙이다. 컨트롤러 파라미터에 @Valid가 붙어 있으면 스프링이
// 요청 JSON을 이 객체로 바꾼 직후 규칙을 검사하고, 어기면 컨트롤러 메서드를 부르지 않고 400을 돌려준다.
// 필수 값은 박싱 타입(Long, Double)에 @NotNull을 붙인다 — 기본형(long)은 값이 빠지면 0으로 조용히 채워진다.
//  - t              : 측위 시각(UTC epoch 밀리초)
//  - accuracy       : 정확도(m). 모르면 null(5m로 본다)
//  - stepsSincePrev : 직전 점 이후 걸음 수. 모르면 null
//  - state          : 측위 때 정책 상태. step_budget은 시작 직후 unknown을 쓴다
public record TrackPoint(
        @NotNull Long t,
        @NotNull @DecimalMin("-90") @DecimalMax("90") Double lat,
        @NotNull @DecimalMin("-180") @DecimalMax("180") Double lng,
        @PositiveOrZero Double accuracy,
        @PositiveOrZero Integer stepsSincePrev,
        @Pattern(regexp = "still|walking|otherMotion|vehicle|unknown") String state
) {
}
```

`StayInput.java`:

```java
package com.travelfootsteps.route;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;

// 복원 요청의 머문 곳 하나(재생기 stays.csv의 한 행). 이 시간 범위 안의 점은 중심 하나로 바뀐다(설계 6-2의 1).
public record StayInput(
        @NotNull Long arrive,
        @NotNull Long leave,
        @NotNull @DecimalMin("-90") @DecimalMax("90") Double lat,
        @NotNull @DecimalMin("-180") @DecimalMax("180") Double lng
) {
    // @AssertTrue: Bean Validation이 이 메서드를 "ordered"라는 속성으로 보고 true인지 검사한다.
    // 필드 하나가 아니라 두 필드의 관계(도착 ≤ 출발)를 검사할 때 쓴다.
    @AssertTrue(message = "arrive는 leave보다 늦을 수 없다")
    public boolean isOrdered() {
        return arrive == null || leave == null || arrive <= leave;
    }
}
```

`ReconstructRequest.java`:

```java
package com.travelfootsteps.route;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.List;

// POST /api/route/reconstruct 요청(설계 2026-11-07 6-1). 앱(R7 날짜별 보기)과 R6 분석이 쓰는 계약이다.
// 점은 하루치 드문 점 기준 2000개까지 받는다 — 점마다 OSRM을 여러 번 부르므로 한 요청의 계산량을 묶어 둔다.
// List<@Valid TrackPoint>처럼 타입 인자에 붙인 @Valid는 목록의 원소마다 규칙을 검사하라는 뜻이다.
//  - method : 빠지면 앱 기본값 osrm_match_radius
//  - stays  : 빠지면 머문 곳 없음
//  - hmm    : hmm_steps 조정값. 빠지면 기본값
public record ReconstructRequest(
        ReconstructMethod method,
        @NotNull @Size(max = 2000) List<@NotNull @Valid TrackPoint> points,
        @Size(max = 500) List<@NotNull @Valid StayInput> stays,
        @Valid HmmOptions hmm
) {
}
```

`RouteSegment.java`:

```java
package com.travelfootsteps.route;

import java.util.List;

// 복원한 경로의 구간 하나. fallback=true면 OSRM이 꺼져 있거나 매칭에 실패해 직선으로 대신 채운 구간이다
// (앱은 "도로 맞춤을 못 했어요"라고 안내한다, 설계 9-4).
public record RouteSegment(SegmentKind kind, List<GeoPoint> coords, boolean fallback) {
}
```

`ReconstructResponse.java`:

```java
package com.travelfootsteps.route;

import java.util.List;

// POST /api/route/reconstruct 응답. method는 실제로 쓴 방법이다(요청에서 빠졌으면 기본값).
public record ReconstructResponse(ReconstructMethod method, List<RouteSegment> segments) {
}
```

`StraightReconstructor.java`:

```java
package com.travelfootsteps.route;

import java.util.List;

// straight: 점을 직선으로 잇는다. 다른 방법과 비교하는 가장 단순한 기준선이다.
class StraightReconstructor implements Reconstructor {

    @Override
    public List<Piece> reconstruct(String country, List<Waypoint> run, HmmOptions options) {
        return List.of(new Piece(Reconstructor.points(run), false));
    }
}
```

`NearestReconstructor.java`:

```java
package com.travelfootsteps.route;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

// nearest: 점마다 OSRM /nearest로 가장 가까운 도로에 붙인 뒤 직선으로 잇는다. 이웃 점과의 관계를 보지 않는
// 단순한 비교 기준이다. 반경 안에 도로가 없는 점은 원래 자리에 두고, 하나도 못 붙이면(OSRM 꺼짐 등) 대체 조각이다.
class NearestReconstructor implements Reconstructor {

    // hmm_steps의 후보 반경과 같다(Newson & Krumm 2009 3.1절의 200m).
    static final double SNAP_RADIUS_M = 200;

    private final OsrmClient osrmClient;

    NearestReconstructor(OsrmClient osrmClient) {
        this.osrmClient = osrmClient;
    }

    @Override
    public List<Piece> reconstruct(String country, List<Waypoint> run, HmmOptions options) {
        List<GeoPoint> coords = new ArrayList<>();
        boolean snappedAny = false;
        for (Waypoint waypoint : run) {
            Optional<GeoPoint> snapped = osrmClient.nearest(country, waypoint.point(), SNAP_RADIUS_M);
            snappedAny |= snapped.isPresent();
            coords.add(snapped.orElse(waypoint.point()));
        }
        return List.of(snappedAny ? new Piece(coords, false) : Piece.straight(run));
    }
}
```

`OsrmMatchReconstructor.java`:

```java
package com.travelfootsteps.route;

import java.util.ArrayList;
import java.util.List;

// osrm_match / osrm_match_radius: OSRM /match(OSRM 자체의 Newson & Krumm식 HMM)로 잇는다.
//  - withRadius=false(osrm_match): OSRM 기본값(GPS 표준편차 5m)만 쓴다.
//  - withRadius=true(osrm_match_radius, 앱 기본값): 점마다 정확도를 5~50m로 맞춘 radiuses와 시각(timestamps)을 넘긴다.
// 실패(빈 결과)하면 직선 대체 조각이다.
class OsrmMatchReconstructor implements Reconstructor {

    static final double MIN_RADIUS_M = 5;
    static final double MAX_RADIUS_M = 50;

    private final OsrmClient osrmClient;
    private final boolean withRadius;

    OsrmMatchReconstructor(OsrmClient osrmClient, boolean withRadius) {
        this.osrmClient = osrmClient;
        this.withRadius = withRadius;
    }

    @Override
    public List<Piece> reconstruct(String country, List<Waypoint> run, HmmOptions options) {
        List<GeoPoint> points = Reconstructor.points(run);
        List<GeoPoint> matched = withRadius
                ? osrmClient.match(country, points, radiuses(run), timestamps(run))
                : osrmClient.match(country, points, null, null);
        return List.of(matched.isEmpty() ? Piece.straight(run) : new Piece(matched, false));
    }

    // 정확도를 모르면 OSRM 기본값(5m)으로 본다. 50m보다 크게 주면 엉뚱한 먼 도로까지 후보가 된다(검색 반경은 3배).
    static List<Double> radiuses(List<Waypoint> run) {
        return run.stream()
                .map(w -> w.accuracy() == null ? MIN_RADIUS_M
                        : Math.max(MIN_RADIUS_M, Math.min(MAX_RADIUS_M, w.accuracy())))
                .toList();
    }

    // OSRM은 초 단위 시각이 늘어나기만 해야 한다. 1초 안에 찍힌 점이 같은 초가 되지 않게 1초씩 밀어 준다.
    // 머문 곳은 도착 시각을 쓴다.
    static List<Long> timestamps(List<Waypoint> run) {
        List<Long> out = new ArrayList<>();
        long previous = Long.MIN_VALUE;
        for (Waypoint waypoint : run) {
            long seconds = Math.floorDiv(waypoint.startT(), 1000L);
            if (previous != Long.MIN_VALUE && seconds <= previous) seconds = previous + 1;
            out.add(seconds);
            previous = seconds;
        }
        return out;
    }
}
```

`RouteReconstructionService.java`:

```java
package com.travelfootsteps.route;

import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;

/**
 * 드문 측위 점과 머문 곳으로 하루 경로를 복원한다(설계 2026-11-07 6장, 모듈 C-2).
 *
 * <p>@Service: 스프링이 시작할 때 이 클래스의 객체를 하나 만들어(빈) 컨테이너에 넣고, 필요한 곳(ReconstructController)에
 * 넣어 준다. 생성자가 하나뿐이면 스프링이 그 생성자의 파라미터(OsrmClient)에 맞는 빈을 찾아 자동으로 넘긴다 —
 * 실행 중에는 HttpOsrmClient, test 프로필에서는 StubOsrmClient다. 방법별 Reconstructor는 이 서비스만 쓰는 보통
 * 객체라 빈으로 만들지 않고 여기서 직접 만든다. 그래서 테스트는 가짜 OsrmClient 하나로 서비스 전체를 만든다.
 *
 * <p>처리 순서(설계 6-2):
 * <ol>
 *   <li>머문 곳 시간 범위 안의 점을 그 머문 곳 중심 하나로 바꾼다.</li>
 *   <li>10분 이상의 공백(측위 실패·걸음 없는 이동)에서 자르고, 공백 양 끝은 /route로 이어 estimated로 표시한다.</li>
 *   <li>남은 구간을 도보·탈것으로 나눠 요청한 방법으로 잇는다. 실패한 조각은 직선 + fallback이다.</li>
 * </ol>
 */
@Service
public class RouteReconstructionService {

    // 대상 국가는 KR 고정이다(설계 6-1). 해외 이동은 연구 범위 밖이다.
    static final String COUNTRY = "KR";
    static final long GAP_MS = 10 * 60 * 1000L;

    private final OsrmClient osrmClient;
    private final Map<ReconstructMethod, Reconstructor> reconstructors = new EnumMap<>(ReconstructMethod.class);

    public RouteReconstructionService(OsrmClient osrmClient) {
        this.osrmClient = osrmClient;
        reconstructors.put(ReconstructMethod.STRAIGHT, new StraightReconstructor());
        reconstructors.put(ReconstructMethod.NEAREST, new NearestReconstructor(osrmClient));
        reconstructors.put(ReconstructMethod.OSRM_MATCH, new OsrmMatchReconstructor(osrmClient, false));
        reconstructors.put(ReconstructMethod.OSRM_MATCH_RADIUS, new OsrmMatchReconstructor(osrmClient, true));
        reconstructors.put(ReconstructMethod.HMM_STEPS, new HmmStepsReconstructor(osrmClient));
    }

    public ReconstructResponse reconstruct(ReconstructRequest request) {
        ReconstructMethod method = request.method() != null ? request.method() : ReconstructMethod.OSRM_MATCH_RADIUS;
        HmmOptions options = HmmOptions.orDefaults(request.hmm());
        List<Waypoint> waypoints = waypoints(request.points(), request.stays() != null ? request.stays() : List.of());

        List<RouteSegment> segments = new ArrayList<>();
        if (waypoints.size() == 1) {
            // 점 하나뿐인 날도 어디 있었는지는 보여 줄 수 있게 좌표 하나짜리 구간으로 돌려준다.
            segments.add(new RouteSegment(SegmentKind.WALK, List.of(waypoints.get(0).point()), false));
            return new ReconstructResponse(method, segments);
        }

        GeoPoint previousEnd = null;
        for (List<Waypoint> run : splitAtGaps(waypoints)) {
            List<RouteSegment> runSegments = reconstructRun(method, run, options);
            GeoPoint start = runSegments.isEmpty() ? run.get(0).point() : runSegments.get(0).coords().get(0);
            if (previousEnd != null) segments.add(estimated(previousEnd, start));
            segments.addAll(runSegments);
            previousEnd = runSegments.isEmpty() ? run.get(run.size() - 1).point() : lastCoord(runSegments);
        }
        return new ReconstructResponse(method, segments);
    }

    /** 1단계: 점을 시각순으로 놓고, 머문 곳 범위 안의 점은 빼고 머문 곳마다 중심 하나를 넣는다. */
    static List<Waypoint> waypoints(List<TrackPoint> points, List<StayInput> stays) {
        List<StayInput> sortedStays = stays.stream().sorted(Comparator.comparing(StayInput::arrive)).toList();
        // 머문 곳에 처음 든 점. 머문 곳 중심이 그 점의 '직전 이후 걸음 수'와 상태를 이어받는다(걸어 들어온 몫).
        TrackPoint[] firstInside = new TrackPoint[sortedStays.size()];

        List<Waypoint> out = new ArrayList<>();
        for (TrackPoint p : points.stream().sorted(Comparator.comparing(TrackPoint::t)).toList()) {
            int stay = stayContaining(sortedStays, p.t());
            if (stay < 0) {
                out.add(new Waypoint(p.t(), p.t(), new GeoPoint(p.lat(), p.lng()),
                        p.accuracy(), p.stepsSincePrev(), p.state()));
            } else if (firstInside[stay] == null) {
                firstInside[stay] = p;
            }
        }
        for (int k = 0; k < sortedStays.size(); k++) {
            StayInput s = sortedStays.get(k);
            TrackPoint first = firstInside[k];
            out.add(new Waypoint(s.arrive(), s.leave(), new GeoPoint(s.lat(), s.lng()), null,
                    first == null ? null : first.stepsSincePrev(), first == null ? null : first.state()));
        }
        // List.sort는 안정 정렬이라 시각이 같으면 넣은 순서(측위 점, 머문 곳)를 지킨다.
        out.sort(Comparator.comparingLong(Waypoint::startT));
        return out;
    }

    private static int stayContaining(List<StayInput> stays, long t) {
        for (int k = 0; k < stays.size(); k++) {
            if (stays.get(k).arrive() <= t && t <= stays.get(k).leave()) return k;
        }
        return -1;
    }

    /** 2단계: 앞 점이 끝난 뒤 다음 점까지 10분 이상 비면 자른다. */
    static List<List<Waypoint>> splitAtGaps(List<Waypoint> waypoints) {
        List<List<Waypoint>> runs = new ArrayList<>();
        List<Waypoint> current = new ArrayList<>();
        for (Waypoint w : waypoints) {
            if (!current.isEmpty() && w.startT() - current.get(current.size() - 1).endT() >= GAP_MS) {
                runs.add(current);
                current = new ArrayList<>();
            }
            current.add(w);
        }
        if (!current.isEmpty()) runs.add(current);
        return runs;
    }

    /** 3단계: 한 덩어리를 도보·탈것으로 나눠 잇는다. 점 사이의 종류는 도착하는 점의 상태로 정한다. */
    private List<RouteSegment> reconstructRun(ReconstructMethod method, List<Waypoint> run, HmmOptions options) {
        Reconstructor reconstructor = reconstructors.get(method);
        List<RouteSegment> out = new ArrayList<>();
        int from = 0;
        while (from < run.size() - 1) {
            SegmentKind kind = kindOf(run.get(from + 1));
            int to = from + 1;
            while (to + 1 < run.size() && kindOf(run.get(to + 1)) == kind) to++;
            for (Reconstructor.Piece piece : reconstructor.reconstruct(COUNTRY, run.subList(from, to + 1), options)) {
                out.add(new RouteSegment(kind, piece.coords(), piece.fallback()));
            }
            from = to;
        }
        return out;
    }

    private static SegmentKind kindOf(Waypoint arriving) {
        return arriving.isVehicle() ? SegmentKind.VEHICLE : SegmentKind.WALK;
    }

    private RouteSegment estimated(GeoPoint from, GeoPoint to) {
        List<GeoPoint> route = osrmClient.route(COUNTRY, from, to);
        return route.isEmpty()
                ? new RouteSegment(SegmentKind.ESTIMATED, List.of(from, to), true)
                : new RouteSegment(SegmentKind.ESTIMATED, route, false);
    }

    private static GeoPoint lastCoord(List<RouteSegment> segments) {
        List<GeoPoint> coords = segments.get(segments.size() - 1).coords();
        return coords.get(coords.size() - 1);
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `./gradlew test --tests 'com.travelfootsteps.route.*'` → 통과(43개).

- [ ] **Step 5: 커밋**

```bash
git add server/src/main/java/com/travelfootsteps/route server/src/test/java/com/travelfootsteps/route/RouteReconstructionServiceTest.java
git commit -m "feat(server): 머문 곳·공백·도보/탈것을 나눠 방법별로 잇는 경로 복원 서비스를 더한다"
```

---

### Task 7: `POST /api/route/reconstruct` 엔드포인트

**Files:**
- Create: `server/src/main/java/com/travelfootsteps/route/ReconstructController.java`
- Test: `server/src/test/java/com/travelfootsteps/route/ReconstructControllerTest.java`

**Interfaces:**
- Consumes: Task 6의 `RouteReconstructionService`·요청/응답 레코드, 기존 `SecurityConfig`(`/api/**` 인증), `StubTokenVerifier`
- Produces: `POST /api/route/reconstruct` — 200 + `ReconstructResponse`, 검증 실패 400, 토큰 없음 401

`SecurityConfig`는 바꾸지 않는다. `/api/route/reconstruct`는 `"/api/**".authenticated()`에 걸린다. R6 분석은 서버를 `local` 프로필로 띄워 `LocalDevTokenVerifier`의 더미 토큰 `dev-fake-token`을 쓴다(Task 8 안내).

- [ ] **Step 1: 실패하는 테스트 작성**

`server/src/test/java/com/travelfootsteps/route/ReconstructControllerTest.java`:

```java
package com.travelfootsteps.route;

import com.travelfootsteps.auth.SecurityConfig;
import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.util.stream.Collectors;
import java.util.stream.IntStream;

import static org.mockito.Mockito.mock;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

// 경로 복원 API의 JSON 계약(앱 R7·R6 분석)과 입력 검증·인증을 확인한다. RouteControllerTest와 같은 @WebMvcTest 슬라이스다.
// 서비스는 진짜를 쓰고 OsrmClient만 Mockito 가짜(모든 호출이 빈 결과 = OSRM 꺼짐)라 응답에 fallback이 붙는다.
@WebMvcTest(ReconstructController.class)
@ActiveProfiles("test")
@Import({SecurityConfig.class, ReconstructControllerTest.TestBeans.class})
class ReconstructControllerTest {

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register("valid-token", "uid-123");
            return stub;
        }

        @Bean
        RouteReconstructionService routeReconstructionService() {
            return new RouteReconstructionService(mock(OsrmClient.class));
        }
    }

    @Autowired MockMvc mockMvc;

    private static String points(int count) {
        return IntStream.range(0, count)
                .mapToObj(i -> "{\"t\":" + (1762480000000L + i * 30000L) + ",\"lat\":" + (37.5665 + i * 0.0001)
                        + ",\"lng\":126.978,\"accuracy\":8.0,\"stepsSincePrev\":40,\"state\":\"walking\"}")
                .collect(Collectors.joining(",", "[", "]"));
    }

    private ResultActions send(String body) throws Exception {
        return mockMvc.perform(post("/api/route/reconstruct")
                .header("Authorization", "Bearer valid-token")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body));
    }

    @Test
    void 복원_응답은_method와_구간의_kind_coords_fallback을_담는다() throws Exception {
        send("""
                {"method":"hmm_steps",
                 "points":[{"t":1762480000000,"lat":37.5665,"lng":126.9780,"accuracy":8.0,"stepsSincePrev":null,"state":"walking"},
                           {"t":1762480060000,"lat":37.5670,"lng":126.9785,"accuracy":12.0,"stepsSincePrev":80,"state":"walking"}],
                 "stays":[],
                 "hmm":{"betaM":5.0}}""")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.method").value("hmm_steps"))
                .andExpect(jsonPath("$.segments[0].kind").value("walk"))
                .andExpect(jsonPath("$.segments[0].fallback").value(true))   // OSRM 가짜가 빈 결과
                .andExpect(jsonPath("$.segments[0].coords[0].lat").value(37.5665))
                .andExpect(jsonPath("$.segments[0].coords[1].lng").value(126.9785));
    }

    @Test
    void method를_빼면_앱_기본값_osrm_match_radius로_복원한다() throws Exception {
        send("{\"points\":" + points(2) + "}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.method").value("osrm_match_radius"))
                .andExpect(jsonPath("$.segments.length()").value(1));
    }

    @Test
    void 점은_2000개까지_받고_넘으면_400() throws Exception {
        send("{\"method\":\"straight\",\"points\":" + points(2000) + "}").andExpect(status().isOk());
        send("{\"method\":\"straight\",\"points\":" + points(2001) + "}").andExpect(status().isBadRequest());
    }

    @Test
    void 모르는_method나_state면_400() throws Exception {
        send("{\"method\":\"teleport\",\"points\":" + points(2) + "}").andExpect(status().isBadRequest());
        send("{\"method\":\"straight\",\"points\":[{\"t\":1,\"lat\":37.5,\"lng\":127.0,\"state\":\"flying\"}]}")
                .andExpect(status().isBadRequest());
    }

    @Test
    void 필수_값이_빠지거나_범위를_벗어나면_400() throws Exception {
        send("{\"method\":\"straight\"}").andExpect(status().isBadRequest());   // points 없음
        send("{\"points\":[{\"lat\":37.5,\"lng\":127.0}]}").andExpect(status().isBadRequest());   // t 없음
        send("{\"points\":[{\"t\":1,\"lat\":137.5,\"lng\":127.0}]}").andExpect(status().isBadRequest());
        send("{\"points\":[{\"t\":1,\"lat\":37.5,\"lng\":127.0,\"accuracy\":-1}]}").andExpect(status().isBadRequest());
        send("{\"points\":" + points(2) + ",\"hmm\":{\"betaM\":0}}").andExpect(status().isBadRequest());
    }

    @Test
    void 머문_곳의_도착이_출발보다_늦으면_400() throws Exception {
        send("{\"points\":" + points(2) + ",\"stays\":[{\"arrive\":2000,\"leave\":1000,\"lat\":37.5,\"lng\":127.0}]}")
                .andExpect(status().isBadRequest());
    }

    @Test
    void 토큰_없이_호출하면_401() throws Exception {
        mockMvc.perform(post("/api/route/reconstruct")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"points\":[]}"))
                .andExpect(status().isUnauthorized());
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `./gradlew test --tests 'com.travelfootsteps.route.ReconstructControllerTest'`

Expected: FAIL. `ReconstructController`가 없어 컴파일되지 않는다.

- [ ] **Step 3: 구현**

`server/src/main/java/com/travelfootsteps/route/ReconstructController.java`:

```java
package com.travelfootsteps.route;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

// 경로 복원 API(설계 2026-11-07 6장). 앱의 날짜별 보기(R7)와 R6 분석이 하루치 드문 점·머문 곳을 보내 복원 경로를 받는다.
// 기록 좌표는 저장하지 않고 응답만 만든다(설계 9-3).
//
// @RestController: 이 클래스가 HTTP 요청을 받는 컨트롤러이고, 메서드가 돌려준 객체를 JSON으로 바꿔 응답한다는 뜻이다.
// @RequestMapping("/api/route"): 이 클래스 메서드들의 공통 경로 앞부분이다. RouteController도 같은 앞부분을 쓰지만,
// 스프링은 전체 경로(+ HTTP 메서드)가 겹치지만 않으면 여러 컨트롤러에 나눠 둘 수 있다.
// 인증은 SecurityConfig의 "/api/**는 로그인 필요" 규칙이 컨트롤러보다 먼저 도는 필터에서 처리하므로 여기서는 모른다.
// @RequiredArgsConstructor(Lombok): final 필드를 받는 생성자를 만들어, 스프링이 그 생성자로 서비스 빈을 넣어 준다.
@RestController
@RequestMapping("/api/route")
@RequiredArgsConstructor
public class ReconstructController {

    private final RouteReconstructionService reconstructionService;

    // @RequestBody: 요청 본문 JSON을 ReconstructRequest로 바꾼다. @Valid: 바꾼 직후 그 안의 검증 규칙(점 2000개 상한,
    // 좌표 범위 등)을 검사해, 어기면 이 메서드를 부르지 않고 400 Bad Request로 끝낸다.
    @PostMapping("/reconstruct")
    public ReconstructResponse reconstruct(@RequestBody @Valid ReconstructRequest request) {
        return reconstructionService.reconstruct(request);
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `./gradlew test --tests 'com.travelfootsteps.route.*'` → 통과(50개). 이어서 Docker Desktop을 켜고 `./gradlew test`(전체) → 통과(308개).

- [ ] **Step 5: 커밋**

```bash
git add server/src/main/java/com/travelfootsteps/route/ReconstructController.java server/src/test/java/com/travelfootsteps/route/ReconstructControllerTest.java
git commit -m "feat(server): POST /api/route/reconstruct 엔드포인트와 요청 검증을 더한다"
```

---

### Task 8: 실제 세션 확인 + 문서

**Files:**
- Create: `docs/research/route-guide.md`
- Modify: `docs/research/replay-guide.md`(전체 교체)
- Modify: `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md`(5-4, 5-6, 6장)

**Interfaces:**
- Consumes: Task 1~7 전체
- Produces: 문서만

- [ ] **Step 1: 실제 세션으로 확인**

로컬에 R1 세션이 있으면 다음을 돌린다(Bash, `packages/footstep_core/`에서). 결과는 임시 폴더에 쓰고 지운다.

```bash
S=../../research/data/sessions/20261109-213324-groundTruth
O="$(mktemp -d)"
if [ -d "$S" ]; then
  while read -r P D X; do
    args="--policy $P --detector $D"; [ -n "$X" ] && args="$args $X"
    dart run footstep_core:replay --session "$S" $args --out "$O/x" | sed 's/ -> .*//'
    awk -F, 'NR>1 {s+=$5} END {print "  steps_since_prev 합", s+0}' "$O/x/fixes.csv"
  done <<'EOF'
hourly os
fixed_1m os
fixed_5m os
fixed_5m os --stay-param use_still=false
continuous_10m os
still_suppress os
step_budget os
step_budget adaptive
step_budget brajdic
step_budget adaptive --stay-param use_still=false
step_budget adaptive --param e_m=25
EOF
else
  echo "세션 없음 — 건너뜀"
fi
rm -rf "$O"
```

Expected (세션이 있을 때): 모든 줄의 종료 코드가 0이고, 측위·GPS 켜짐·`stays=`·걸음 합이 '설계 검증' 표의 '후' 값과 **같다**. 재생은 결정적이다. 출력을 태스크 보고서에 그대로 붙인다. 다르면 멈추고 보고한다.

로컬 OSRM(5001)과 Docker가 있으면 한 번 실제로 불러 본다(없으면 건너뛰고 보고한다):

```bash
cd ../../osrm && docker compose up -d osrm && cd ../server
OSRM_BASE_URL=http://localhost:5001 SPRING_PROFILES_ACTIVE=local SERVER_PORT=9090 ./gradlew bootRun
# 다른 터미널에서 route-guide.md 3절의 curl 예시 → 200, segments[0].fallback이 false인지 본다
```

`SERVER_PORT`는 `netsh interface ipv4 show excludedportrange protocol=tcp`로 예약 범위 밖인지 먼저 본다.

- [ ] **Step 2: 안내 문서 작성**

`docs/research/route-guide.md`:

````markdown
# 경로 복원 API 안내 (R5)

재생기가 남긴 드문 점(`fixes.csv`)과 머문 곳(`stays.csv`)을 도로 위 경로로 복원한다. 설계는 `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md` 6장이다. 앱의 날짜별 보기(R7)와 R6 분석이 같은 API를 쓴다.

## 1. 로컬 OSRM 띄우기

Docker Desktop을 켠 뒤 저장소 루트에서:

```bash
cd osrm
./setup.sh                 # 최초 1회 — 한국 OSM 데이터 다운로드 + 도보 프로필 전처리
docker compose up -d osrm  # http://localhost:5001
curl "http://localhost:5001/nearest/v1/foot/126.9780,37.5665?number=5"   # code: "Ok"면 정상
```

복원은 OSRM의 `/nearest`·`/table`·`/route`·`/match`를 쓴다. 도보 프로필이라 버스 구간은 걸을 수 있는 길로 이어진다(설계 10장 위험 5).

## 2. 서버를 local 프로필로 띄우기

`local` 프로필은 Firebase 없이 더미 토큰 `dev-fake-token`만 받는다(`LocalDevTokenVerifier`). PostgreSQL(5432)은 평소처럼 떠 있어야 한다.

```bash
cd server
OSRM_BASE_URL=http://localhost:5001 SPRING_PROFILES_ACTIVE=local SERVER_PORT=9090 ./gradlew bootRun
```

이 PC는 Windows가 포트 범위를 예약해 8080을 못 쓸 때가 있다. `netsh interface ipv4 show excludedportrange protocol=tcp`로 비어 있는 포트를 골라 `SERVER_PORT`에 넣는다.

## 3. 호출하기

```bash
curl -s -X POST http://localhost:9090/api/route/reconstruct \
  -H "Authorization: Bearer dev-fake-token" -H "Content-Type: application/json" \
  -d '{"method":"hmm_steps",
       "points":[{"t":1762480000000,"lat":37.5665,"lng":126.9780,"accuracy":8.0,"stepsSincePrev":null,"state":"walking"},
                 {"t":1762480060000,"lat":37.5670,"lng":126.9790,"accuracy":10.0,"stepsSincePrev":120,"state":"walking"}],
       "stays":[],
       "hmm":{"betaM":10,"sigmaMinM":5}}'
```

- `points`: `fixes.csv`의 행을 그대로 옮긴다(`t_ms`→`t`, `accuracy_m`→`accuracy`, `steps_since_prev`→`stepsSincePrev`, `state`). 최대 2000개, 대상 국가는 KR 고정이다.
- `stays`: `stays.csv`의 행(`arrive_ms`→`arrive`, `leave_ms`→`leave`, `lat`, `lng`). 최대 500개. 빼도 된다.
- `method`: 빼면 앱 기본값 `osrm_match_radius`다.
- 응답: `{"method": …, "segments": [{"kind": "walk|vehicle|estimated", "coords": [{"lat","lng"}…], "fallback": false}]}`

## 4. 복원 방법

| method | 내용 |
|---|---|
| `straight` | 점을 직선으로 잇는다 |
| `nearest` | 점마다 200m 안의 가장 가까운 도로에 붙인 뒤 직선으로 잇는다 |
| `osrm_match` | OSRM `/match` 기본값(GPS 표준편차 5m) |
| `osrm_match_radius` | `/match`에 점 정확도를 5~50m로 맞춘 `radiuses`와 초 단위 `timestamps`를 넘긴다(**앱 기본값**) |
| `hmm_steps` | **제안**. Newson & Krumm(2009) HMM의 전이 확률에 걸음 수 × 보폭을 쓴다. 후보는 200m 안의 도로 위 점 5개, 고른 후보 사이는 `/route`로 잇는다 |

처리 순서는 모든 방법이 같다.
1. 머문 곳 시간 범위 안의 점을 그 중심 하나로 바꾼다.
2. 앞 점(머문 곳이면 출발 시각)에서 다음 점까지 10분 이상 비면 자르고, 그 사이는 `/route`로 이어 `estimated`로 표시한다.
3. 나머지를 방법대로 잇는다. 탈것 상태(`state: vehicle`)로 도착한 점까지는 `vehicle`, 그 밖은 `walk` 구간이다.

OSRM이 꺼져 있거나 매칭에 실패한 조각은 직선으로 채우고 `fallback: true`를 붙인다. `hmm_steps`는 도로가 200m 안에 없는 점에서 끊긴 곳만 직선이다.

## 5. `hmm_steps` 조정값 (`hmm`)

| 이름 | 기본값 | 뜻 |
|---|---|---|
| `betaM` | 10 | 전이 확률 exp(−\|도로 경로거리 − 걸은 거리\| / β)의 β(m). OSRM 자체 맵 매칭의 기본값과 같다 |
| `sigmaMinM` | 5 | 방사 확률 σ의 하한(m). σ = max(점 정확도, 하한) |
| `strideM` | 0.75 | 걸은 거리 = 걸음 수 × 보폭 |
| `useSteps` | true | false면 걸은 거리 대신 두 점의 직선거리(Newson & Krumm 원래 식, 절제 실험) |

**β와 σ 하한은 R6에서 예비용(pilot) 세션으로만 정한다.** Newson & Krumm은 정답 경로에서 β = median\|직선거리 − 도로 경로거리\| / ln 2, σ = 1.4826 × median\|점 − 정답 도로 점\|로 추정했다(원문 식 5·6). 원문은 성능을 최대로 하는 값을 찾는 것을 후속 과제로 남겼다. 이 연구는 예비용 세션에서 β ∈ {2, 5, 10, 20, 50}m, σ 하한 ∈ {3, 5, 10}m를 격자로 바꿔 경로 오차 P95가 가장 작은 값을 고르고, 평가용 세션에는 그 값만 쓴다.

## 6. 해석할 때 주의

- `stepsSincePrev`는 재생기가 끝에 걸음 시각으로 다시 센 값이다. 폰 정책 실행 모드의 `fixes.csv`는 걷기 시작 몇 초 안의 측위에서 걸음 몇 개가 빠질 수 있다(R7에서 고친다).
- 도보 프로필이라 `vehicle` 구간도 걸을 수 있는 길로 이어진다. 탈것 구간 오차는 따로 보고한다.
- `osrm_match_radius`는 OSRM 기본 동작(시각 간격이 중앙값의 10배를 넘거나 전이가 불가능하면 궤적을 나눔)을 그대로 쓴다. 나뉜 조각은 직선으로 이어 붙는다.
- 복원 결과와 세션 데이터(`research/`)는 커밋하지 않는다.
````

`docs/research/replay-guide.md` 전체:

````markdown
# 재생기 사용 안내 (R2)

R1로 기록한 세션 폴더를 PC에서 재생해, 각 수집 방식이 '어떤 GPS 점을 남겼을지'를 파일로 만든다. 설계는
`docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md` 5-4절이다.

## 실행

`packages/footstep_core/`에서 실행한다.

```bash
dart run footstep_core:replay --session <세션 폴더> --policy <정책 id> --out <결과 폴더> \
  [--param k=v ...] [--detector os|brajdic|adaptive] [--detector-param k=v ...] [--ttff 초] \
  [--stay-param k=v ...]
```

예: `dart run footstep_core:replay --session ../../research/data/sessions/20261109-213324-groundTruth --policy time_speed --param e_m=25 --ttff 5 --out ../../research/results/replay/s1-time_speed-e25-ttff5`

걸음 감지기는 `--detector`로 고른다(기본 `os`). `--detector-param k=v`로 감지기 파라미터를 바꾸면 summary.json의 `detector_params`에 남는다. 감지기 목록과 파라미터는 `docs/research/steps-guide.md`에 있다.

## 정책

| id | 방식 | 파라미터 |
|---|---|---|
| `hourly` | 현재 앱 1시간 주기 | 없음 |
| `continuous_10m` | 현재 앱 실시간 경로(1초, 10m 필터) | 없음 |
| `fixed_30s` · `fixed_1m` · `fixed_5m` | 고정 주기 | 없음 |
| `speed_adaptive` | Galeana-Zapién 외(2014): 마지막 속도로 간격 조절(정지 2분, 보행 30초, 시속 9km 이상 10초) | 없음 |
| `time_speed` | EnTracked·RAPS: 마지막 오차 + 속도 × 시간 > E이면 측위(속도 하한 1.4m/s) | `e_m`(기본 50) |
| `still_suppress` | Zhuang 외(2010): 1분마다 확인, 직전·이번 확인이 모두 정지면 건너뜀, 억제 중에도 5분마다 확인 측위 | `interval_s`(기본 60), `verify_s`(기본 300) |
| `step_budget` | **제안**: 보행은 '오차 + 걸음 수 × 보폭 > E'일 때(최소 5초 간격), 정지는 30초 이어지면 한 번 + 5분 확인, 기타 움직임은 확인 측위 두 번으로 탈것(시속 12km 이상)이면 time_speed 규칙(감지기 정지와 측위상 한 자리가 2분, GPS가 흔들리면 E 안 5분 넘을 때만 정지로) | `e_m`(50), `stride_m`(0.75), `use_steps`·`suppress_still`·`vehicle_probe`(true, 절제 실험) |
| `activity_gated` | 상용 방식: 활동 인식 STILL이면 연속 측위 끔, 움직임이면 켬 | 없음 |

`time_speed`는 RAPS(Paek 외 2010)의 장소·시간대별 속도 이력과 가속도 활동 비율을 쓰지 않고, 마지막 측위 속도만 쓰는 단순화판이다. 보고서에 이 차이를 적는다. 같은 정책을 폰에서 돌리는 방법(배터리 실험)은 `docs/research/battery-experiment-guide.md`에 있다.

## 머문 곳 (`--stay-param`)

재생이 끝나면 남은 점(`fixes.csv`)으로 머문 곳을 묶어 `stays.csv`에 쓴다(설계 5-6, 모듈 C-1).

- 점 묶기는 Li 외(2008)다. 첫 점에서 반경 R 안에 이어진 점들이 T 이상 머물면 한 곳이다.
- 제안: 그 점들 중 걸음 감지기의 정지 구간에 든 점이 있으면, 첫 정지 구간의 시작을 도착, 마지막 정지 구간의 끝을 출발로 쓴다. 점이 드물어도(5분 주기 등) 머문 시간을 알고, 걸어 들어오거나 떠나며 반경 안에 찍힌 점은 빼고 잰다. 정지 구간이 이웃 점보다 먼저 시작하거나 늦게 끝나면(걸음 없이 옮겨 온 버스 등) 그쪽은 점 시각을 쓴다.

| 이름 | 기본값 | 뜻 |
|---|---|---|
| `radius_m` | 100 | 반경 R(m) |
| `min_stay_s` | 600 | 최소 머문 시간 T(초) |
| `use_still` | true | false면 점만으로 묶는다(Li 외 2008, 절제 실험) |

예: `--stay-param use_still=false --stay-param min_stay_s=300`

## 결과 파일

| 파일 | 내용 |
|---|---|
| `fixes.csv` | `t_ms,lat,lng,accuracy_m,steps_since_prev,state,kind` — 정책이 남긴 점. kind는 `single`(단발) 또는 `continuous`. `steps_since_prev`는 재생이 끝난 뒤 걸음 시각으로 다시 센 값(직전 측위 시각 이상 ~ 이 측위 시각 미만)이라, 연속 걸음을 확인한 뒤 소급해 센 걸음(`adaptive`)도 들어간다 |
| `actions.csv` | `t_ms,action,args` — 정책이 낸 할 일 전부. 이미 응답을 기다리는 중이라 무시된 `request_fix`도 그대로 남으므로, 측위 요청 수는 행 수가 아니라 `summary.json`의 `fix_requests`를 쓴다 |
| `stays.csv` | `arrive_ms,leave_ms,lat,lng,n_points` — 머문 곳. 중심은 도착~출발 사이 점의 평균, `n_points`는 그 점 수 |
| `summary.json` | 측위 요청·성공·실패 수, 연속 측위 점 수, 추정 GPS 켜짐 시간(`gps_on_s`), 시간당 점 수, 머문 곳 설정(`stay_params`)과 개수(`stays`) |

복원 경로는 이 `fixes.csv`·`stays.csv`를 서버 `POST /api/route/reconstruct`에 넣어 만든다(`docs/research/route-guide.md`).

## 해석할 때 주의

- 재생은 '켜자마자 위치가 나온다'를 가정한다. `--ttff 5`·`--ttff 10`으로 바꿔 가며 민감도를 본다.
- 실내에서 정지해 있으면 정답 GPS 자체가 약 7초 간격이다(실기기 점검). 그 구간의 단발 측위는 응답이 최대 7초 늦게 잡힌다.
- 점만으로 묶으면(`use_still=false`) 드문 점끼리 우연히 반경 안에 들어 머문 곳이 생길 수 있다. 실제 세션 `fixed_5m` 재생에서 걷던 점 하나와 실내 점 두 개가 딱 10분으로 묶였다(정지 구간으로 재면 6분).
- 쇼핑몰처럼 반경 안을 계속 걸어 다닌 곳에서 짧게 한 번 멈췄다면, 제안 방식은 그 짧은 정지만 머문 시간으로 잰다. 정지가 여러 번이면 첫 정지 시작~마지막 정지 끝이다.
- 결과 폴더(`research/results/`)와 세션(`research/data/`)은 커밋하지 않는다.
````

- [ ] **Step 3: 설계 문서 고치기**

`docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md`에서 차례로 바꾼다.

1. 다음 부분을

```markdown
  - `fixes.csv`: `t_ms,lat,lng,accuracy_m,steps_since_prev,state,kind(single|continuous)` — `state`는 측위 시점의 정책 상태(`still`·`walking`·`otherMotion`·`vehicle`)다. `vehicle`은 정책이 판단한 상태라 걸음 감지기 출력에는 없다.
```

다음으로 바꾼다:

```markdown
  - `fixes.csv`: `t_ms,lat,lng,accuracy_m,steps_since_prev,state,kind(single|continuous)` — `state`는 측위 시점의 정책 상태(`still`·`walking`·`otherMotion`·`vehicle`)다. `vehicle`은 정책이 판단한 상태라 걸음 감지기 출력에는 없다. `steps_since_prev`는 재생이 끝난 뒤 걸음 시각으로 다시 센다(직전 측위 시각 이상 ~ 이 측위 시각 미만). 정책이 받은 값은 그 순간까지 센 걸음뿐이라, 제안판 감지기가 연속 5걸음 확인 뒤 소급해 센 걸음이 빠졌다(R5에서 고침).
```

2. 다음 부분을

```markdown
- Li 외(2008): 연속한 점들이 반경 R(기본 100m) 안에 T(기본 10분) 이상 머물면 머문 곳 하나로 묶는다. 결과는 중심, 도착 시각, 출발 시각, 점 수다.
```

다음으로 바꾼다:

```markdown
- Li 외(2008): 연속한 점들이 반경 R(기본 100m) 안에 T(기본 10분) 이상 머물면 머문 곳 하나로 묶는다. 결과는 중심, 도착 시각, 출발 시각, 점 수다. 반경은 무리의 첫 점에서 잰다(원문 정의). 기록 끝까지 머문 무리도 머문 곳이다.
```

3. 다음 부분을

```markdown
- 비교·절제: 점만으로 묶는 방식(`useStillIntervals=false`)
- 출력 `stays.csv`: `arrive_ms,leave_ms,lat,lng,n_points`
```

다음으로 바꾼다:

```markdown
  - 무리 안에서 정지 구간에 든 첫 점의 구간 시작이 도착, 마지막 점의 구간 끝이 출발이다. 걸어 들어오거나 떠나며 반경 안에 찍힌 점은 머문 시간과 중심에서 뺀다.
  - 정지 구간이 이웃 점보다 먼저 시작하거나 늦게 끝나면 걸음 없이 옮겨 온 것(OS 센서판의 버스)이라 그쪽은 점 시각을 쓴다.
  - 정지 구간 안의 점이 없으면 Li 외(2008) 그대로다.
  - 재생기는 정책을 돌린 같은 감지기의 상태 변화(`step_states.csv`와 같은 규칙)로 정지 구간을 만든다.
- 비교·절제: 점만으로 묶는 방식(`useStillIntervals=false`, CLI `--stay-param use_still=false`)
- 출력 `stays.csv`: `arrive_ms,leave_ms,lat,lng,n_points`. `summary.json`에 `stay_params`와 `stays`(개수)를 더한다.
- R5 설계 검증: 실제 세션 `fixed_5m` 재생에서 점만으로는 걷던 점 하나와 실내 점 두 개가 딱 10분으로 묶였다(정지 구간으로 재면 6분이라 머문 곳이 아니다). 처음에는 무리의 첫·끝 점이 정지 구간에 있을 때만 늘렸는데, 이 경우를 걸러 내지 못해 위 규칙으로 바꿨다.
```

4. 다음 부분을

```markdown
- `state`: `still` · `walking` · `otherMotion` · `vehicle`. `stepsSincePrev`는 모를 때 null.
- 한 요청의 점은 최대 2000개(하루치 드문 점 기준)다. 대상 국가는 KR 고정이다.
```

다음으로 바꾼다:

```markdown
- `state`: `still` · `walking` · `otherMotion` · `vehicle` · `unknown`(step_budget 시작 직후). `stepsSincePrev`·`accuracy`·`state`는 모를 때 null.
- 한 요청의 점은 최대 2000개(하루치 드문 점 기준), 머문 곳은 최대 500개다. 대상 국가는 KR 고정이다.
- `method`를 빼면 앱 기본값 `osrm_match_radius`다. `hmm`(선택)은 `hmm_steps` 조정값 `{betaM, sigmaMinM, strideM, useSteps}`이고, 빠진 값은 기본값(10, 5, 0.75, true)이다.
```

5. 다음 부분을

```markdown
- `kind`: `walk` · `vehicle` · `estimated`. `estimated`는 GPS가 없던 구간(지하철 등)을 최단경로로 이은 것이다.
- OSRM이 꺼져 있거나 매칭에 실패하면 해당 구간을 `straight`로 대신 채운다. 응답 구간에는 `fallback: true`를 붙인다.
```

다음으로 바꾼다:

```markdown
- `kind`: `walk` · `vehicle` · `estimated`. `estimated`는 GPS가 없던 구간(지하철 등)을 최단경로로 이은 것이다. 점 사이의 종류는 도착하는 점의 `state`로 정한다(`vehicle`이면 탈것, 그 밖은 도보).
- OSRM이 꺼져 있거나 매칭에 실패하면 해당 구간을 `straight`로 대신 채운다. 응답 구간에는 `fallback: true`를 붙인다. `fallback`은 모든 구간에 늘 있다(성공이면 false).
- 점이 하나뿐이면 좌표 하나짜리 `walk` 구간 하나, 없으면 빈 목록이다.
```

6. 다음 부분을

```markdown
1. 머문 곳 시간 범위 안의 점을 그 머문 곳 중심 하나로 바꾼다.
2. 측위 실패나 걸음 없는 10분 이상의 공백에서 구간을 자른다. 공백 양 끝은 `/route`로 잇고 `estimated`로 표시한다.
3. 남은 구간마다 `method`로 잇는다.
```

다음으로 바꾼다:

```markdown
1. 머문 곳 시간 범위 안의 점을 그 머문 곳 중심 하나로 바꾼다. 중심은 [도착, 출발]을 차지하고, 그 안에 처음 든 점의 `stepsSincePrev`·`state`를 이어받는다. 안에 든 점이 없어도 중심을 넣는다.
2. 측위 실패나 걸음 없는 10분 이상의 공백에서 구간을 자른다. 공백은 앞 점(머문 곳이면 출발 시각)에서 다음 점까지로 잰다 — 머문 시간 자체는 공백이 아니다. 공백 양 끝은 `/route`로 잇고 `estimated`로 표시한다.
3. 남은 구간을 도보·탈것으로 나눠 `method`로 잇는다.
```

7. 다음 부분을

```markdown
- 후보: 점마다 `/nearest?number=5`로 반경 안의 도로 위 점 최대 5개
```

다음으로 바꾼다:

```markdown
- 후보: 점마다 `/nearest?number=5`로 반경 200m(Newson & Krumm 3.1절) 안의 도로 위 점 최대 5개. 1m 안의 같은 위치(양방향 도로)는 하나로 본다.
```

8. 다음 부분을

```markdown
  - 걸음 정보가 없으면(탈것 등) 두 점의 직선거리로 대신한다 (Newson & Krumm 원래 식)
```

다음으로 바꾼다:

```markdown
  - 걸음 정보가 없으면(탈것 등) 두 점의 직선거리로 대신한다 (Newson & Krumm 원래 식). `state`가 `vehicle`이어도 직선거리다.
```

9. 다음 부분을

```markdown
  - 도로 경로거리는 연속한 두 점의 후보 쌍에 대해 `/table`로 한 번에 구한다
```

다음으로 바꾼다:

```markdown
  - 도로 경로거리는 연속한 두 점의 후보 쌍에 대해 `/table`로 한 번에 구한다
  - 차이가 2000m 이상이면 불가능한 전이다(원문 4.2절, OSRM `MAX_DISTANCE_DELTA`)
```

10. 다음 부분을

```markdown
- β와 σ 하한은 예비용 세션으로 정한다.
```

다음으로 바꾼다:

```markdown
- 후보가 없는 점이나 모든 전이가 불가능한 곳에서 사슬이 끊긴다. 원문은 끊긴 곳 양옆 점을 지워 가며 다시 잇지만, 여기서는 끊긴 곳만 직선(`fallback: true`)으로 잇고 양쪽을 따로 매칭한다.
- β와 σ 하한은 예비용 세션으로 정한다. 조정 전 기본값은 β 10m(OSRM 자체 맵 매칭의 `MATCHING_BETA`와 같아 `osrm_match_radius`와 같은 β로 견준다), σ 하한 5m다. 요청의 `hmm`으로 바꿀 수 있어 서버를 다시 빌드하지 않고 격자 탐색한다(R6: β ∈ {2, 5, 10, 20, 50}, σ 하한 ∈ {3, 5, 10}, 경로 오차 P95 최소). Newson & Krumm은 정답 경로에서 β = median|직선거리 − 도로 경로거리| / ln 2로 추정했고(식 6), 성능을 최대로 하는 값 찾기는 후속 과제로 남겼다.
```

11. 다음 부분을

```markdown
- `server/.../route/`에 `ReconstructController`, `RouteReconstructionService`, 방법별 `Reconstructor` 구현을 둔다.
- 기존 `OsrmClient`에 `nearest`(후보 여러 개), `table`, `match`(반경·시각 옵션)를 추가한다.
```

다음으로 바꾼다:

```markdown
- `server/.../route/`에 `ReconstructController`, `RouteReconstructionService`, 방법별 `Reconstructor` 구현을 둔다. `Reconstructor`는 서비스만 쓰는 보통 객체라 빈으로 만들지 않고 서비스 생성자에서 만든다.
- 기존 `OsrmClient`에 `nearestCandidates`(후보 여러 개), `table`, `match`(반경·시각 옵션)를 default 메서드로 추가한다(기본 구현은 빈 결과 = 지원 안 함). 기존 `nearest`·`route`·`match`와 `/snap`·해외 매핑의 동작은 그대로다.
- 인증은 다른 `/api/**`와 같다(Firebase 토큰). R6 분석은 서버를 `local` 프로필로 띄워 더미 토큰 `dev-fake-token`으로 부른다(`docs/research/route-guide.md`).
```

- [ ] **Step 4: 커밋**

```bash
git add docs/research/route-guide.md docs/research/replay-guide.md docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md
git commit -m "docs: 경로 복원 안내를 추가하고 재생기 안내와 설계 문서에 머문 곳·복원 규칙을 적는다"
```

- [ ] **Step 5: 마무리 확인**

- `packages/footstep_core/`: `dart test`, `dart analyze` → 통과(214개), 0건
- `server/`: `./gradlew test` → 통과(308개)
- `git status`에 `research/`가 없다
- `git log --format=%B policy..HEAD | grep -iE "co-authored|claude"`가 빈 결과다

---

## R6·R7에 넘기는 것

- **R6 — β·σ 하한 정하기.** 예비용(pilot) 세션에서만 요청의 `hmm`을 β ∈ {2, 5, 10, 20, 50}m, σ 하한 ∈ {3, 5, 10}m로 바꿔 복원하고, 1초 정답(정확도 20m 이하)까지 거리 P95가 가장 작은 조합을 고른다. 평가용 세션에는 그 값만 쓴다. 지금 기본값(β 10m = OSRM `MATCHING_BETA`, σ 하한 5m)은 걸음 수·버스 탑승을 담은 예비 세션이 아직 없어 조정 전 값이다. 같은 방식으로 `--stay-param`(R, T)과 보폭(`strideM`)도 볼 수 있다.
- **R6 — 머문 곳 평가.** `stays.csv`를 `arrive`~`depart` 표시와 견준다(설계 7-2). 지금 세션들에는 10분 넘게 머문 정답 표시가 없어, 실내 체류(10분 이상)를 넣은 코스를 새로 모아야 한다.
- **R7 — 폰에서도 걸음 수 다시 세기.** 폰 실행기(`PolicyRunner`)는 측위 기록을 바로 파일·DB에 쓰므로 재생기처럼 끝에 다시 셀 수 없다. 걷기 시작 몇 초 안의 측위는 `steps_since_prev`가 몇 걸음 모자랄 수 있다. R7 여행 기록이 `hmm_steps`를 쓰려면, 소급 카운트된 걸음이 나올 때 직전 RoutePoint의 걸음 수를 고치거나 걸음 시각을 함께 남긴다.
- **R7 — 정지 구간 남기기.** 날짜별 보기의 머문 곳 마커를 제안 방식으로 그리려면 `detectStays`에 정지 구간이 필요하다. RoutePoints의 `state`만으로는 정지 시작·끝을 모르므로, 여행 기록이 감지기 상태 변화(시각·상태)를 함께 저장해야 한다.
