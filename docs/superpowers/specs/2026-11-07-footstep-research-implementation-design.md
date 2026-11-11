# 발걸음 배터리–정확도 연구 구현 설계

- 작성일: 2026-11-07
- 상태: 설계 승인, 구현 계획(R1~R7) 작성 전
- 연구 계획 요약(교수님용 1쪽): `docs/presentation/research-summary-onepager.html`
- 연구 주제·방법 종합(팀 자료): 바탕화면 `종설/중간 이후 아이디어/종설_연구주제_연구방법.md`

## 1. 목적과 범위

중간발표 심사평("외부 API 조합 수준, 공학적 기여 없음")에 따라 발걸음 기록 기능 하나를 연구형으로 고도화한다.

**연구 질문:** 경로 오차와 '들른 곳' 검출을 정해 둔 수준으로 지키면서, 위치 수집에 드는 배터리를 얼마나 줄일 수 있는가?

이 문서는 그 연구를 실제로 구현하는 설계다. 다루는 것은 다음 네 가지다.

1. 실험 데이터를 모으는 **기록 앱(로거)**
2. 걸음 감지(모듈 A)·적응형 수집(모듈 B)·머문 곳 묶기(모듈 C-1)를 담은 **공용 Dart 패키지와 PC 재생기**
3. 지도 매칭(모듈 C-2) **서버 API**와 **Python 분석**
4. 연구 결과를 앱 기능으로 넣는 **제품 반영**(국내 여행, 여행 기간 기록, 날짜별 보기)

**범위 밖:** 해외 매핑(한국 이동을 해외 도로에 재현), 서버 배포, 채팅 푸시. 기록 좌표의 서버 동기화도 하지 않는다.

## 2. 결정 기록

| # | 결정 | 이유 |
|---|---|---|
| D1 | 모듈 담당 팀원이 각자 구현한다. 담당자는 아직 정하지 않았고, 조영진이 대부분 맡을 수도 있다. | 계획서는 누가 맡든 따라 할 수 있고 Claude가 태스크 단위로 실행할 수 있는 형식으로 쓴다. |
| D2 | 모듈 A·B는 **순수 Dart 패키지**로 짠다. 앱과 PC 재생이 같은 코드를 쓴다. | 재생 실험 결과와 실기기 동작이 어긋나지 않는다. 같은 로직을 두 언어로 짜지 않는다. |
| D3 | 머문 곳 묶기는 Dart 패키지에, 지도 매칭은 Spring 서버(Java)에 둔다. | 앱의 날짜별 화면과 PC 평가가 같은 구현을 쓴다. OSRM은 서버 뒤에 있다. |
| D4 | 로거는 본 앱 안의 숨은 실험 화면으로 만든다. 기록 서비스 하나에 모드 셋을 둔다. | 포그라운드 서비스·권한·DB를 한 번만 만든다. 실험한 코드가 곧 제품 코드다. |
| D5 | 정책은 **사건을 받아 할 일을 돌려주는** 형태로 짠다. 정책은 시계·GPS를 직접 다루지 않는다. | 폰 실행기와 재생 실행기를 갈아 끼울 수 있다. 미래 정보 차단이 구조적으로 보장된다. 정지 중에 실제로 쉬므로 배터리 실험이 의미 있다. |
| D6 | 상용 방식 비교는 구글 활동 인식 API 연동 방식 하나로 한다. 논문 방식(EnTracked·RAPS, Galeana-Zapién, Zhuang)도 함께 비교한다. | 상용 앱의 내부 알고리즘은 공개돼 있지 않다. 공개 문서로 확인되는 대표 원리만 재현한다. |
| D7 | 걸음 감지에는 HMM을 쓰지 않는다. 지도 매칭에는 HMM을 쓴다. | 걸음 감지 HMM은 폰에서 50Hz 연속 계산 부담이 크다. 지도 매칭은 하루치 드문 점을 서버에서 한 번만 처리한다. |
| D8 | 실험은 폰 1대로 한다. 갤럭시 워치 같은 별도 장비는 쓰지 않는다. | 팀 여건. 배터리 실험은 같은 폰으로 방식을 바꿔 반복한다. |

## 3. 전체 구조

### 3-1. 저장소 배치

```
packages/footstep_core/   새 순수 Dart 패키지 (Flutter 의존 없음)
  lib/src/events/         사건·할 일 타입
  lib/src/detectors/      모듈 A 걸음 감지기
  lib/src/policies/       수집 정책 (기준 정책 + 제안 정책)
  lib/src/stays/          모듈 C-1 머문 곳 묶기
  lib/src/replay/         재생 실행기, CSV 입출력
  bin/replay.dart         PC 재생 CLI
app/                      path 의존으로 footstep_core 사용. 기록 서비스, 실험 화면, 여행 기록, 날짜별 보기
server/.../route/         모듈 C-2 경로 복원 API
research/analysis/        Python 지표·그래프 (pytest 포함)
research/sessions.yaml    세션 목록과 예비용/평가용 구분
research/data/            수집 로그 (.gitignore — 커밋 금지)
research/results/         분석 결과 CSV·그림 (.gitignore, 최종본만 보고서에 첨부)
```

수집 로그에는 팀원의 실제 이동 경로가 들어 있다. 저장소에 올리지 않고 팀 드라이브로 공유한다.

### 3-2. 데이터 흐름

```
[정확도 실험]
폰(정답 기록 모드) → 세션 폴더(CSV) → adb pull 또는 zip 공유 → research/data/sessions/<id>/
  → dart run footstep_core:replay  (정책 × 설정마다 '남았을 GPS 점'과 머문 곳)
  → 로컬 서버 POST /api/route/reconstruct  (local 프로필, 로컬 OSRM)
  → Python 분석  (1초 정답 경로·관찰 표시와 비교 → 지표·그래프)

[배터리 실험]
폰(정책 실행 모드, 한 방식만) → 배터리 로그 + batterystats → Python 분석

[제품]
폰(여행 기록 모드, 제안 정책) → 로컬 DB(RoutePoints) → 날짜별 화면 → 서버 복원
```

### 3-3. 구현 계획서 구성

계획서는 `docs/superpowers/plans/`에 하나씩 만든다. 진행 방식은 기존 계획서와 같다(`superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`).

| | 계획서 | 선행 조건 | 목표 |
|---|---|---|---|
| R1 | 기록 서비스 + 로거(정답 기록 모드) + 내보내기 | 없음 — 최우선 | 1주차 (11/9~) |
| R2 | 공용 패키지 뼈대 + 재생기 + 기준 정책 + OS 걸음 감지기(기준 정책 재생에 필요) | 없음 (R1과 병행) | 1주차 |
| R3 | 모듈 A 걸음 감지(논문 기준판·제안판) | R2, R1 데이터 | 2주차 |
| R4 | 모듈 B 제안 정책 + 폰 실행기 + 정책 실행 모드(배터리 실험) | R2, R3 인터페이스 | 2주차 |
| R5 | 모듈 C 머문 곳 묶기 + 서버 복원 API | R2 | 2주차 |
| R6 | Python 분석 (+ 선택: 위치공유 전송량) | R1 데이터, R2·R5 출력 | 2~3주차 |
| R7 | 제품 반영: 국내 여행, 여행 기간 기록, 날짜별 보기 | R1 서비스, R4, R5 | 3주차 |

3주차에는 배터리 반복 측정과 R7을 함께 진행한다. 4주차에는 결과를 정리하고 발표를 준비한다.

**대체 경로:** R3의 제안 걸음 감지가 늦어지면 OS 걸음 센서판으로 바꾼다. R5의 HMM이 늦어지면 `osrm_match_radius`로 바꾼다. 어느 쪽이든 연구 질문(수집 정책)의 결과는 나온다.

## 4. R1 — 기록 서비스와 로거

### 4-1. 기록 서비스

- `flutter_foreground_task`로 `foregroundServiceType="location"` 포그라운드 서비스를 띄운다. 매니페스트에 `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `ACTIVITY_RECOGNITION`, `WAKE_LOCK`을 추가한다.
- 서비스 작업은 별도 isolate의 `TaskHandler`에서 돈다.
- 모드는 시작할 때 하나만 고르고, 두 모드를 동시에 돌리지 않는다. 배터리 측정이 오염되기 때문이다.

| 모드 | 하는 일 | 만드는 계획서 |
|---|---|---|
| `groundTruth` | 모든 센서를 최대 빈도로 저장 | R1 |
| `policy` | 고른 정책 하나만 실행, 측위 결과와 배터리만 저장 | R4 |
| `trip` | 여행 기간에 제안 정책 실행, RoutePoints에 저장 | R7 |

- 기록 중에는 부분 wake lock을 유지한다. 모든 모드와 정책이 같은 조건에서 돌게 하기 위해서다(10장 위험 3).

### 4-2. 정답 기록 모드가 쓰는 파일

세션 폴더: `Android/data/<applicationId>/files/sessions/<yyyyMMdd-HHmmss>-<mode>/`

모든 파일의 첫 열 `t_ms`는 **같은 시계**(기록 시각, UTC 밀리초)다. CSV는 헤더 행을 포함한다.

| 파일 | 열 | 수단(후보) |
|---|---|---|
| `gps.csv` | `t_ms,fix_t_ms,lat,lng,accuracy_m,speed_mps,bearing_deg,altitude_m` | geolocator, interval 1초, distanceFilter 0, high |
| `accel.csv` | `t_ms,x,y,z` (m/s², 중력 포함). `t_ms`는 센서 이벤트 시각이고, 기록 시각과 10초 넘게 차이 나면 기록 시각을 쓴다 | sensors_plus, 약 50Hz (20ms) |
| `os_steps.csv` | `t_ms,kind,value` — `kind`는 `count`(value = 부팅 후 누적 걸음 수) 또는 `status`(value = `walking`·`stopped`·`unknown`, OS 보행 상태) | pedometer |
| `activity.csv` | `t_ms,type,confidence` — `type`은 `STILL`·`WALKING`·`RUNNING`·`ON_BICYCLE`·`IN_VEHICLE`·`UNKNOWN` | flutter_activity_recognition |
| `battery.csv` | `t_ms,charge_uah,current_ua,level_pct,temp_c,plugged` (30초마다) | 앱 안의 작은 Kotlin 플러그인 (BatteryManager) |
| `marks.csv` | `t_ms,kind,value` (아래 표) | 실험 화면 버튼 + 알림 버튼 |
| `meta.json` | `sessionId, mode, deviceModel, androidSdk, appVersion, startedAt, endedAt, carryInitial, policy(정책 모드일 때), note` | — |

**관찰 표시(`marks.csv`)**

| kind | value | 입력 위치 |
|---|---|---|
| `arrive` / `depart` | 장소 이름(선택, 알림 버튼으로 누르면 빈 값) | 화면, 알림 |
| `board` / `alight` | `board`는 `bus` · `subway` · `vehicle`(알림 버튼으로 눌러 종류 미지정), `alight`는 빈 값 | 화면, 알림 |
| `count_start` / `count_end` | `count_end`일 때 직접 센 걸음 수 | 화면 |
| `carry` | `hand` · `pocket` · `bag` | 화면 |
| `note` | 자유 메모 | 화면 |

- Android 알림 버튼은 최대 3개라서 버튼 두 개를 토글로 쓴다. '도착'을 누르면 '출발'로, '탑승'을 누르면 '하차'로 바뀐다. 화면에서 남긴 표시도 같은 상태를 바꾼다.
- 파일은 버퍼에 모아 5초마다 쓴다. 서비스가 끝나면 모두 쓰고 닫는다. 비정상 종료 때도 직전까지는 남는다. 2시간 세션이면 약 20MB다.
- 센서 하나가 실패해도 나머지는 계속 기록한다. 실패는 `meta.json`의 `errors` 배열에 시각과 함께 남긴다.

### 4-3. 실험 화면과 내보내기

- 발걸음 탭 세계지도 아래의 '방문 국가 … 총 걸음' 문구를 길게 누르면 `/footsteps/lab`이 열린다(발걸음 탭에는 앱바 제목이 없다). 일반 사용자 화면에는 노출하지 않는다.
- 실험 화면에서 할 수 있는 일:
  - 모드·정책 선택, 시작·종료
  - 실시간 값 확인: 최근 GPS 정확도, 걸음 수, 배터리 전하량, 경과 시간
  - 관찰 표시 버튼
  - 세션 목록(크기, 시간)
- 내보내기는 두 가지다. `adb pull /sdcard/Android/data/<applicationId>/files/sessions/`와, 세션을 zip으로 묶어 Android 공유 창으로 보내는 기능(`share_plus`)이다.

### 4-4. 첫 태스크: 실기기 점검

화면을 만들기 전에 실험에 쓸 폰에서 다음을 확인한다.

- 위 후보 패키지들이 서비스 isolate 안에서 화면을 끈 채 10분 동안 값을 내는가
- 행 수와 시각 간격이 정상인가
- 이 기종이 배터리 전하량(`BATTERY_PROPERTY_CHARGE_COUNTER`)을 지원하는가

안 되는 센서는 Kotlin 코드(플러그인)로 바꾼다. 전하량을 지원하지 않으면 배터리 %와 GPS 사용 시간으로 대신 보고한다.

### 4-5. 테스트

- 단위 테스트: CSV 쓰기(헤더, 버퍼 비우기), 관찰 표시 기록, 세션 메타 생성, 세션 폴더 이름
- 실기기 점검표: 화면 끄고 10분, 파일별 행 수·시각 간격, 알림 버튼 동작

## 5. R2~R4 — 공용 패키지 `footstep_core`

### 5-1. 사건과 할 일

```dart
sealed class PolicyEvent { DateTime get at; }
//   StepUpdate(state: still|walking|otherMotion, totalSteps, stepsSinceLastFix, cadenceHz)
//   ActivityUpdate(type, confidence)
//   FixResult(fix?: Fix, failure?: FixFailure)        // RequestFix에 대한 응답
//   ContinuousFix(fix)                                // 연속 측위 중 들어오는 값
//   Wakeup(tag)                                       // WakeAt으로 예약한 시각
//   BatteryLevel(pct)

sealed class PolicyAction {}
//   RequestFix(timeout: 15s)
//   StartContinuous(interval, distanceFilterM)
//   StopContinuous()
//   WakeAt(at, tag)

abstract class CollectionPolicy {
  String get id;                                       // 예: 'step_budget_e50'
  List<PolicyAction> onStart(PolicyContext ctx);
  List<PolicyAction> onEvent(PolicyEvent e, PolicyContext ctx);   // ctx.now = 현재 시각
}
```

- 정책은 순수 Dart 객체다. 타이머, 파일, 플랫폼 API를 쓰지 않는다.
- 실행기(재생 또는 폰)가 할 일을 실제 동작으로 바꾸고, 결과를 다시 사건으로 넣는다.

### 5-2. 걸음 감지기 (모듈 A, R3)

```dart
abstract class StepDetector {
  StepUpdate? onAccel(AccelBatch batch);   // 약 1초 분량 묶음
  StepUpdate? onOsStep(OsStepSample s);
  void onFix();                            // stepsSinceLastFix를 0으로
}
```

| 구현 | 내용 |
|---|---|
| `OsStepDetector` | OS 누적 걸음 수(`count`)를 센다. 최근 4초 안에 누적 값이 늘었거나 OS 상태가 `walking`이면 보행, 아니면 정지. 기타 움직임은 구분하지 않는다. |
| `BrajdicDetector` (`brajdic`) | 논문 기준판. 보행 판정은 STD_TH(0.8초 창, 표준편차 0.6, 논문 표 3), 걸음 검출은 WPD(중심 이동 평균 0.31초, 봉우리 창 0.59초, 논문 표 4). 기타 움직임은 구분하지 않는다. |
| `AdaptiveStepDetector` (`adaptive`) | 제안판. 20ms 격자 → 걸음 대역(0.7~3Hz) → 흔들림(0.8초 표준편차 0.6, 대역 0.3) + 박자(3초 창 자기상관 **봉우리** 0.4) 판정 → 적응형 임계값 피크(이권희 외 2018 식 (4), Tmin −0.588) → 걸음 주기 0.6배 최소 간격 → 연속 5걸음 확인 후 소급 카운트, 그 뒤로는 보행 상태일 때만 바로 센다. 흔들림은 있는데 박자가 없으면 기타 움직임이고, 박자 창이 차기 전에는 판정하지 않는다. |

파라미터의 출발값은 연구 자료 4-1절을 따른다. 최종값은 예비용 세션으로만 정한다.

### 5-3. 수집 정책 (R2 기준 정책, R4 제안 정책)

| id | 방식 | 계획서 |
|---|---|---|
| `hourly` | 60분마다 `RequestFix` (현재 앱 WorkManager 방식) | R2 |
| `continuous_10m` | 시작부터 `StartContinuous(distanceFilter 10m)` (현재 앱 실시간 경로) | R2 |
| `fixed_30s` · `fixed_1m` · `fixed_5m` | 고정 주기 `RequestFix` | R2 |
| `speed_adaptive` | Galeana-Zapién 외(2014): 마지막 측위 속도 구간에 따라 다음 간격을 정한다 | R2 |
| `time_speed` | EnTracked·RAPS: `마지막 오차 + 속도 × 경과 시간 > E`가 되는 시각에 측위 | R2 |
| `still_suppress` | Zhuang 외(2010): 고정 1분 주기이되, 걸음 감지기의 `StepUpdate.state`가 정지면 측위를 건너뛴다 | R2 |
| `activity_gated` | 상용 방식: 활동 인식이 `STILL`이면 `StopContinuous`, 움직임이면 `StartContinuous(10m)` | R2 |
| `step_budget` | 제안 (아래) | R4 |

**`step_budget` 규칙 (파라미터: E = 25·50·100m, 보폭 0.75m, 걸음 감지기 종류)**

| 상태 | 동작 |
|---|---|
| 보행 | `마지막 측위 오차 + stepsSinceLastFix × 보폭 > E`이면 `RequestFix` |
| 정지 | 정지가 시작될 때 한 번 측위하고(머문 곳 위치) 이후 측위하지 않는다. 대신 5분마다 확인 측위를 한다. 걸음 없이 움직이는 경우(버스)를 놓치지 않기 위한 안전장치다. |
| 기타 움직임 | 확인 측위 두 번으로 속도를 본다. 시속 12km 이상이면 탈것 상태로 보고 `time_speed` 규칙으로 측위한다. 걸음이 다시 나오면 보행으로 돌아간다. |
| 측위 실패 반복 | 시도 간격을 30초 → 1분 → 2분 → 최대 5분으로 늘린다 (지하철·실내) |
| 배터리 20% 미만 | E를 2배로 키운다 |

절제 실험용 스위치:
- `useSteps=false`: 걸음 수 대신 경과 시간 × 1.4m/s로 계산
- `suppressStill=false`: 정지 억제 끄기
- `vehicleProbe=false`: 탈것 확인 측위 끄기

### 5-4. 재생 실행기 (R2)

```
dart run footstep_core:replay --session <dir> --policy <id> [--param k=v ...]
    [--detector os|brajdic|adaptive] [--ttff 0|5|10] --out <dir>
```

- 세션 폴더의 CSV를 모두 읽어 시각순으로 합치고, 가상 시계로 사건을 흘려보낸다.
- 가속도와 OS 걸음은 걸음 감지기를 거쳐 `StepUpdate`로 바뀐다. 활동 인식은 `ActivityUpdate`로 들어간다.
- `RequestFix`가 시각 t에 오면 `t + ttff` 이후의 첫 `gps.csv` 행을 돌려준다. 제한 시간(15초) 안에 행이 없으면 실패다. 정책은 요청한 시각 이후의 정보만 받으므로 **미래 정보를 쓸 수 없다.**
- `StartContinuous`는 그 뒤의 `gps.csv` 행을 간격·거리 필터에 맞춰 흘려보낸다.
- 출력:
  - `fixes.csv`: `t_ms,lat,lng,accuracy_m,steps_since_prev,state,kind(single|continuous)` — `state`는 측위 시점의 정책 상태(`still`·`walking`·`otherMotion`·`vehicle`)다. `vehicle`은 정책이 판단한 상태라 걸음 감지기 출력에는 없다.
  - `actions.csv`: `t_ms,action,args`
  - `stays.csv`: 5-6
  - `summary.json`: 측위 횟수, 추정 GPS 켜짐 시간(단발 측위는 ttff + 응답 지연, 연속 측위는 켜진 시간), 정책 id와 파라미터
- 같은 입력과 같은 파라미터에는 항상 같은 출력이 나온다.
- 걸음 감지만 따로 볼 때는 `dart run footstep_core:steps --session <dir> --detector <id> --out <dir>`가 `steps.csv`·`step_states.csv`·`step_summary.json`을 쓴다(R3, 안내 `docs/research/steps-guide.md`).

### 5-5. 폰 실행기 (R4, R7에서 재사용)

- `RequestFix` → `Geolocator.getCurrentPosition(high, timeLimit)`
- `StartContinuous`·`StopContinuous` → `getPositionStream` 구독·해제
- `WakeAt` → 서비스 isolate의 타이머
- 센서 스트림 → 걸음 감지기 → 정책
- 화면이 꺼지면 타이머가 늦게 깰 수 있다. 예약 시각과 실제 깬 시각을 함께 로그에 남겨 지연을 보고한다.
- **정책 실행 모드(배터리 실험)**는 측위 결과와 `battery.csv`만 쓴다. 1초 GPS와 가속도 원본은 쓰지 않는다. 정답 기록을 같이 돌리면 배터리가 오염된다.

### 5-6. 머문 곳 묶기 (모듈 C-1, R5에서 구현, 패키지에 위치)

- Li 외(2008): 연속한 점들이 반경 R(기본 100m) 안에 T(기본 10분) 이상 머물면 머문 곳 하나로 묶는다. 결과는 중심, 도착 시각, 출발 시각, 점 수다.
- 제안: 걸음 감지기가 낸 정지 구간 시작·끝을 도착·출발 시각으로 쓴다. 점이 드물어도 머문 시간을 알 수 있다.
- 비교·절제: 점만으로 묶는 방식(`useStillIntervals=false`)
- 출력 `stays.csv`: `arrive_ms,leave_ms,lat,lng,n_points`

### 5-7. 테스트

- 정책: 사건을 순서대로 넣고 나오는 할 일을 확인한다. 예: 보행 53걸음째에 E=50 측위, 정지 5분 뒤 확인 측위, 실패가 반복될 때 간격이 늘어나는지
- 걸음 감지기: 합성 신호(2Hz 사인파 + 잡음 → 걸음 수, 버스 진동 흉내 → 0걸음)와 실제 짧은 기록
- 재생기: 작은 가짜 세션 폴더로 미래 정보 차단(ttff, 공백 구간 실패), 결정성(두 번 실행해 같은 출력)
- 머문 곳: 합성 궤적(10분 체류 2곳)으로 개수와 시각

## 6. R5 — 경로 복원 서버 API

### 6-1. `POST /api/route/reconstruct`

요청:

```json
{
  "method": "osrm_match_radius",
  "points": [
    {"t": 1762480000000, "lat": 37.5665, "lng": 126.9780, "accuracy": 8.0,
     "stepsSincePrev": 64, "state": "walking"}
  ],
  "stays": [
    {"arrive": 1762480600000, "leave": 1762481800000, "lat": 37.5651, "lng": 126.9895}
  ]
}
```

- `state`: `still` · `walking` · `otherMotion` · `vehicle`. `stepsSincePrev`는 모를 때 null.
- 한 요청의 점은 최대 2000개(하루치 드문 점 기준)다. 대상 국가는 KR 고정이다.

응답:

```json
{
  "method": "osrm_match_radius",
  "segments": [
    {"kind": "walk", "coords": [{"lat": 37.5665, "lng": 126.9780}]}
  ]
}
```

- `kind`: `walk` · `vehicle` · `estimated`. `estimated`는 GPS가 없던 구간(지하철 등)을 최단경로로 이은 것이다.
- OSRM이 꺼져 있거나 매칭에 실패하면 해당 구간을 `straight`로 대신 채운다. 응답 구간에는 `fallback: true`를 붙인다.

### 6-2. 처리 순서

1. 머문 곳 시간 범위 안의 점을 그 머문 곳 중심 하나로 바꾼다.
2. 측위 실패나 걸음 없는 10분 이상의 공백에서 구간을 자른다. 공백 양 끝은 `/route`로 잇고 `estimated`로 표시한다.
3. 남은 구간마다 `method`로 잇는다.

| method | 내용 |
|---|---|
| `straight` | 직선 연결 |
| `nearest` | 점마다 `/nearest`로 가장 가까운 도로에 붙인 뒤 직선 연결 |
| `osrm_match` | `/match` 기본값(반경 5m) |
| `osrm_match_radius` | `/match`에 `radiuses`(점 정확도를 5~50m로 맞춤)와 `timestamps`를 넘긴다. **앱 기본값(1차).** |
| `hmm_steps` | 제안 HMM (6-3) |

### 6-3. `hmm_steps` (Newson & Krumm 틀 + 걸음 거리 전이)

- 후보: 점마다 `/nearest?number=5`로 반경 안의 도로 위 점 최대 5개
- 방사 확률: 점과 후보 사이 거리의 가우시안. σ는 그 점의 정확도(최소 5m)
- 전이 확률: `exp(-|도로 경로거리 − 걸은 거리| / β)`
  - 걸은 거리 = `stepsSincePrev × 0.75m`
  - 걸음 정보가 없으면(탈것 등) 두 점의 직선거리로 대신한다 (Newson & Krumm 원래 식)
  - 도로 경로거리는 연속한 두 점의 후보 쌍에 대해 `/table`로 한 번에 구한다
- 비터비로 가장 그럴듯한 후보 순서를 고르고, 고른 후보 사이를 `/route`로 이어 좌표를 만든다.
- β와 σ 하한은 예비용 세션으로 정한다.
- 비교·절제: `hmm_steps`에서 걸은 거리 대신 직선거리를 쓰면 기본 HMM이 된다(`useSteps=false`).

### 6-4. 구현 위치와 테스트

- `server/.../route/`에 `ReconstructController`, `RouteReconstructionService`, 방법별 `Reconstructor` 구현을 둔다.
- 기존 `OsrmClient`에 `nearest`(후보 여러 개), `table`, `match`(반경·시각 옵션)를 추가한다.
- 서버 프로덕션 코드는 CLAUDE.md의 Spring 학습용 주석 규칙을 따른다.
- 테스트:
  - 가짜 `OsrmClient`와 격자 도로 합성 예제로 HMM이 정답 후보를 고르는지 확인한다.
  - 공백 구간이 `estimated`가 되는지, OSRM 실패 시 직선 대체와 `fallback: true`가 붙는지 확인한다.
  - `@WebMvcTest`로 요청·응답 계약과 점 개수 상한을 검증한다.

## 7. R6 — Python 분석

### 7-1. 세션 관리와 실행

- `research/sessions.yaml`에 세션 id, 코스, 휴대 위치, 용도(`pilot` 또는 `eval`)를 적는다.
- **평가용 세션은 파라미터를 정할 때 보지 않는다.**
- `python -m analysis.run --config research/experiments.yaml`이 정책·파라미터 조합마다 다음을 실행한다.
  1. 재생 CLI
  2. 로컬 서버 복원 호출(`local` 프로필, 로컬 OSRM)
  3. 지표 계산과 `research/results/` 저장

### 7-2. 지표

| 대상 | 지표 | 정답 |
|---|---|---|
| 수집·복원 | 1초 정답 점마다 복원 경로까지의 거리 평균·P95(m), 이동거리 오차(%), 시간당 측위 횟수, 추정 GPS 켜짐 시간 | `gps.csv` 중 정확도 20m 이하인 행. 도보·탈것 구간을 나눠 보고한다 (탈것 구간은 `board`~`alight`). |
| 머문 곳 | 정밀도·재현율·F1. 검출된 머문 곳이 정답과 시간이 50% 이상 겹치고 중심이 100m 이내면 일치 | `arrive`~`depart` 표시 |
| 걸음 감지 | 걸음 수 오차(%), 탈것 구간의 가짜 걸음 수, 보행 판정 정밀도·재현율, 첫 걸음까지 지연 | `count_start`~`count_end`의 센 걸음 수, 탑승 구간 = 0걸음, 머문 곳·탈것 밖 = 보행 |
| 배터리 | 시간당 mAh = 전하량 변화 ÷ 시간. 방식마다 3회 이상, 평균 ± 표준편차. GPS 사용 시간 | `battery.csv`, `dumpsys batterystats` 출력 파싱 |
| (선택) 위치공유 | 메시지 수와 받는 쪽 위치 오차: 현재 5초 고정 ↔ "상태 변화, 20m 이상 이동, 60초 경과 중 하나면 전송" | 1초 GPS |

### 7-3. 그래프

1. 배터리–오차 곡선 (가로: 시간당 측위 횟수 또는 mAh, 세로: 경로 오차 P95)
2. 방식별 시간당 mAh 막대 (실기기)
3. 머문 곳 F1 (오류 예산별)
4. 걸음 감지 방법별 오차와 탈것 구간 가짜 걸음 수
5. 복원 방법별 경로 오차 (같은 입력)

결과는 "같은 50m 오차에서 배터리 X% 감소"처럼 측정값 그대로 보고한다. 목표 수치는 미리 정하지 않는다.

### 7-4. 테스트

지표 함수마다 손으로 답을 계산할 수 있는 작은 합성 데이터로 pytest를 돌린다. 예: 직선 경로와 10m 평행 이동 경로 → 평균 오차 10m, 머문 곳 겹침 경계값.

## 8. 실험 절차

### 8-1. 정확도 실험 (재생)

- 코스: 한국 안에서 도보(골목·대로) + 실내 체류(10분 이상) + 버스 + 지하철을 섞은 60~120분 코스를 약 10회 수집한다.
- 휴대 위치는 손·주머니·가방 중 2곳 이상을 섞는다.
- 정답 기록 모드로 수집하고, 걸음 세기는 100~300걸음 구간을 세션마다 몇 개씩 넣는다.
- 예비용(파라미터 결정)과 평가용으로 나눈다.

### 8-2. 배터리 실험 (실기기)

- 대상은 네 방식이다: `continuous_10m`, 같은 품질의 고정 주기(재생 결과로 고름), `activity_gated`, `step_budget`(E=50). 여유가 있으면 `step_budget`의 걸음 감지기 두 가지(OS 센서판·제안판)를 모두 잰다.
- 같은 폰, 같은 코스에서 방식마다 3회 이상 반복한다. 방식 순서는 섞는다.
- 통제 조건:
  - 시작 배터리 80~90%, 충전기 분리
  - 화면 꺼짐, 같은 네트워크 설정
  - 다른 앱 종료, 정답 기록 모드는 끔
- 실행 전에 `adb shell dumpsys batterystats --reset`을 하고, 끝난 뒤 `adb shell dumpsys batterystats > <세션>/batterystats.txt`로 저장한다.

## 9. R7 — 제품 반영

### 9-1. 국내 여행

- **앱:**
  - 여행 만들기 국가 목록 맨 위에 '대한민국(국내 여행)'을 둔다(`homeCountry` 재사용).
  - 국내 여행은 여권 만료일 입력을 숨긴다.
  - 여행 상세에서는 비자 결과·준비 일정·체크리스트·지갑을 숨기고 발걸음 기록만 보여 준다.
  - 국내 여행에는 준비 일정 알람을 만들지 않는다.
- **서버:**
  - `countryIso2 = "KR"`이면 비자 판정을 건너뛴다. `verdict = "DOMESTIC"`으로 저장하고, 일정·준비물은 만들지 않는다.
  - refresh는 아무것도 하지 않고 현재 값을 돌려준다.
  - `passportExpiry`는 null을 허용한다(`V15` 마이그레이션, `CreateTripRequest`의 `@NotNull` 해제). KR이 아닌 여행은 여전히 필수로 검증한다.
  - 국가 목록 API(`/api/countries`)는 바꾸지 않는다.

### 9-2. 여행 기간 기록

시작은 항상 사용자가 앱을 연 순간이다. Android 14가 백그라운드에서 위치 포그라운드 서비스를 시작하는 것을 막기 때문이다.
1. 앱이 포그라운드로 올 때 오늘이 어떤 여행의 기간 안이면 기록 서비스를 `trip` 모드로 켠다.
2. 출발일 아침 8시에 로컬 알림을 보낸다. "오늘부터 ○○ 여행 발걸음을 기록합니다." 누르면 앱이 열리고 1번이 실행된다.
3. 여행 상세에 '기록 일시정지·재개' 버튼을 둔다. 일시정지 상태는 여행별로 로컬에 저장한다.

종료:
- 서비스가 깨어날 때마다 날짜를 확인한다. 귀국일 다음 날 0시(기기 현지 시각)가 지났거나 여행이 삭제됐으면 스스로 종료한다.
- 재부팅 후에는 자동으로 다시 켜지 않는다. 다음에 앱을 열 때 1번으로 다시 켜진다. 이 한계는 사용자 화면과 보고서에 적는다.

정책과 기존 동작:
- 정책은 `step_budget`(E=50m)으로 시작한다. E와 걸음 감지기 종류는 실험 결과로 확정한다.
- 기존 실시간 경로(`liveRouteProvider`)는 저장을 멈추고 화면 표시용으로만 남긴다. "앱이 켜져 있을 때마다 기록"하지 않는다.
- WorkManager 1시간 국가 체크인도 여행 기간에만 체크인한다. 작업은 등록해 두되, 여행 기간이 아니면 측위 없이 끝낸다.

판단 로직은 순수 함수 `shouldRecord(trips, now, pausedTripIds)`로 분리한다.

### 9-3. 저장

- 기존 `RoutePoints` 테이블에 null 허용 열 `trip_id`, `accuracy_m`, `steps_since_prev`, `state`를 추가한다(Drift 스키마 버전 올림). 세계지도·국가 지도는 수정 없이 계속 동작한다.
- 기록 좌표는 폰에만 둔다. 복원할 때만 서버로 보내고, 서버는 저장하지 않는다.
- 여행 삭제나 계정 변경 시 해당 여행의 좌표를 지운다. 기존 여행 기록 정리 로직(PR #32)과 같은 경로를 쓴다.

### 9-4. 날짜별 보기 (여행 상세 → 발걸음)

- 출발일부터 귀국일까지 날짜 칩을 두고, 고른 날의 지도를 보여 준다.
  - 복원 경로: `POST /api/route/reconstruct`, 기본 `method`. 결과는 (여행, 날짜, 마지막 점 시각)을 키로 메모리에 캐시한다. `estimated` 구간은 점선으로 그린다.
  - 머문 곳 마커: 도착 시각과 머문 시간
  - 그날의 걸음 수와 이동 거리
- 날짜는 기기 현지 날짜 기준으로 묶는다.
- 서버나 네트워크가 실패하면 직선 연결로 그리고 "도로 맞춤을 못 했어요"라고 안내한다.
- 권한(백그라운드 위치, 활동 인식, 알림)이 없으면 상단에 "기록이 꺼져 있어요" 배너와 설정 이동 버튼을 띄운다.
- 화면을 만들기 전에 Claude Design 와이어프레임 프로젝트를 확인한다.

### 9-5. 테스트

- 서버: KR 여행 생성 시 `DOMESTIC`과 일정·준비물 0개, KR이 아닌 여행의 여권 만료일 필수 검증, KR refresh가 아무것도 하지 않는지
- 앱 단위: `shouldRecord`의 날짜 경계(출발일 0시, 귀국일 23:59, 다음 날 0시), 일시정지, 겹치는 여행
- 앱 위젯: 국내 여행 상세의 섹션 숨김, 날짜별 묶음, 복원 실패 시 직선 표시

## 10. 위험과 대응

| # | 위험 | 대응 |
|---|---|---|
| 1 | 후보 패키지가 서비스 isolate에서 화면이 꺼진 채로 동작하지 않는다 | R1 첫 태스크 실기기 점검. 안 되는 센서는 Kotlin 플러그인으로 대체 |
| 2 | 실험 폰이 배터리 전하량을 지원하지 않는다 | 배터리 %와 batterystats GPS 사용 시간으로 대신 보고 |
| 3 | 화면이 꺼지면 타이머가 늦게 깬다 | 모든 방식을 부분 wake lock 조건에서 측정, 예약·실제 깬 시각 로그로 지연 보고, 보고서 한계에 명시 |
| 4 | 재생은 "켜자마자 정확한 위치"를 가정한다 | ttff 0·5·10초 민감도 분석, 실기기 배터리 실험으로 보완 |
| 5 | OSRM `foot` 프로필은 버스 경로를 잘 따라가지 못할 수 있다 | 탈것 구간은 따로 보고한다. 필요하면 탈것 구간만 `osrm_match_radius` 또는 `straight` 사용 |
| 6 | 4주 일정이 빠듯하다 | 3-3의 대체 경로. 핵심(R1·R2·R4·R6)을 먼저 끝낸다 |
| 7 | 1초 GPS 정답 자체에도 오차가 있다 | 정확도 20m 이하 행만 정답으로 쓰고, 이 한계를 보고서에 적는다 |
