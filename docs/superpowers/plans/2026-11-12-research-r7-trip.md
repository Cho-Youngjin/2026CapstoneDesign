# R7 제품 반영(국내 여행·여행 기간 기록·날짜별 보기) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 연구 결과를 앱 기능으로 넣는다(설계 9장). 대한민국을 고르면 비자 판정 없이 국내 여행(`DOMESTIC`)이 되고, 여행 기간에 앱을 열면 기록 서비스가 `trip` 모드로 켜져 제안 정책(`step_budget`, E = 50m)으로 발걸음을 RoutePoints에 남긴다. 여행 상세 → 발걸음에서 날짜별 복원 경로·머문 곳·걸음·이동 거리를 본다.

**Architecture:**
- 서버(`trip/`, `country/`, `batch/`)
  - V15가 country 표에 본국(KR) 행을 넣고 `trip.passport_expiry`의 NOT NULL을 푼다. 여행은 country 행을 가리켜야 하기 때문이다(외래 키).
  - `TripController`는 본국이면 판정·준비 일정·준비물을 건너뛰고 `DOMESTIC` 스냅샷만 저장한다. refresh는 아무것도 바꾸지 않고 지금 값을 돌려준다.
  - 목적지 목록(`GET /api/countries`)과 일일 공공데이터 수집은 본국을 뺀다. 목록 응답은 R7 전과 같다.
- 판단은 순수 함수 `shouldRecord(trips, now, pausedTripIds)` 하나다.
  - 기간 [출발일 0시, 귀국일 다음 날 0시)(기기 현지 시각) 안이고 일시정지하지 않은 여행 중 가장 늦게 출발한 것을 고른다.
- 세 isolate가 같은 상태를 본다: 화면, 기록 서비스, WorkManager.
  - 일정·일시정지·주인·출발일 알림 기록은 SharedPreferences의 JSON 값이다(`TripRecordingStore`).
  - 백그라운드 isolate는 읽기 전에 `reload`한다.
- 화면 쪽은 `TripRecordingCoordinator` 하나가 모든 작업을 한 줄로 세워 기록 서비스를 켜고 끈다.
  - 앱 셸: 시작·포그라운드 복귀에 `sync`, 서버 목록 도착에 `updateTrips`
  - 여행 상세: `setPaused`
  - 여행 삭제·없는 여행(404): `forgetTrip`
  - 계정 가드: `claimFor`
  - 비자 알람 정리(PR #32)와 같은 때에 부른다.
- 기록 서비스는 실험 모드와 같은 포그라운드 서비스·알림 채널을 쓰고, TaskHandler만 `TripRecordingTaskHandler`로 바꿔 붙인다.
  - `TripRecordingSession`이 끝낼 때를 정한다: 귀국 다음 날 0시, 삭제, 일시정지.
  - `TripRecorder`는 R4의 `PolicyRunner`로 정책을 돌려 위치를 RoutePoints에, 걸음 감지기 정지 구간을 `TripStillSpans`에 쓴다.
  - 정지 구간은 `PolicyRunner`에 더한 `onStepUpdate`로 재생기와 같은 규칙을 따른다.
- 날짜별 보기
  - Drift에서 그 여행의 점·정지 구간을 읽어 기기 현지 날짜로 묶는다.
  - 머문 곳은 footstep_core `detectStays`(R5)로, 경로는 `POST /api/route/reconstruct`(R5, 기본 방법)로 그린다.
  - 결과는 (여행, 날짜, 마지막 점 시각)을 키로 메모리에 캐시한다. 실패하면 직선으로 잇고 "도로 맞춤을 못 했어요"라고 안내한다.

**Tech Stack:**
- Flutter 3.47.2 / Dart 3.13.2(app)
  - flutter_riverpod 3, drift 2.35(스키마 3), flutter_foreground_task 11, flutter_local_notifications 22, permission_handler 13, shared_preferences 2.5, google_maps_flutter
  - 새 의존성 없음
- footstep_core(R2~R5): `PolicyRunner`에 선택 콜백 `onStepUpdate` 하나를 더한다. 의존성 변화 없음.
- Spring Boot 3.5.3 / Java 21(server), PostgreSQL 16 + Flyway(V15). 의존성 변화 없음.

**설계 문서·근거:**
- `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md`
  - 4-1: 기록 서비스 모드(`trip`), 부분 wake lock
  - 5-5: 폰 실행기(`PolicyRunner`) — R7 여행 기록이 같은 실행기를 쓴다
  - 5-6: 머문 곳 묶기(정지 구간으로 도착·출발)
  - 6-1: 복원 API 요청·응답, 점 2000개·머문 곳 500개 상한
  - 9장: R7 전체(9-1 국내 여행, 9-2 여행 기간 기록, 9-3 저장, 9-4 날짜별 보기, 9-5 테스트)
- R4 계획서 `2026-11-11-research-r4-policy.md`: `PolicyRunner`, `PolicyRecorder`, `PolicySensorNeeds`, 정책 실행 모드
- R5 계획서 `2026-11-12-research-r5-route.md`: `detectStays`, 복원 API, 'R6·R7에 넘기는 것'(정지 구간 남기기, 폰에서 걸음 수 다시 세기)
- PR #32(fix-feedback)의 정리 경로: `TripDeleter.delete`, `VisaResultPage`의 404 처리, `tripListProvider`의 `keepOnlyTrips`, `visaAlarmAccountGuardProvider`(알람 주인 uid)
- Android 개발자 문서
  - 'Restrictions on starting a foreground service from the background': Android 12+, 위치 타입은 Android 14에서 더 좁아졌다
  - 'Foreground service types — location': 앱 사용 중 위치 권한으로 화면에서 켠 서비스는 화면이 꺼져도 위치를 받는다

## 설계 검증 (임시 작업 폴더, 커밋하지 않음)

이 계획의 코드는 `analysis`(62d42d0)에서 갈라 둔 임시 작업 폴더에서 먼저 그대로 짜서 검증했다. 아래 코드 블록은 그 폴더의 최종 코드를 그대로 옮긴 것이다. 생성기로 `analysis`에서 태스크 순서대로 다시 적용해 같은 코드가 나오는 것도 확인했다.
- 앱: `flutter test` 814개 통과(시작 727), `dart analyze lib test` 0건
  - 태스크별 누적: Task 2 732 → Task 3 748 → Task 4 759 → Task 5 768 → Task 6 784 → Task 7 800 → Task 8 814
  - 태스크마다 그 태스크까지의 코드만 놓고 확인했다. 생성기가 `analysis`에 그 태스크까지 다시 적용한 별도 작업 폴더에서 전체 `flutter test`·`dart analyze lib test`를 돌려 이 숫자가 나왔다.
  - Task 4에서는 패키지 `dart test` 216개도 함께 돌렸다.
- 패키지(`packages/footstep_core`): `dart test` 216개 통과(시작 215), `dart analyze` 0건
- 서버: `./gradlew test` 333개 통과(시작 326). Testcontainers 테스트가 있어 Docker Desktop을 켜고 돌렸다.
- PC에서 확인할 수 없는 것: 앱을 열 때 포그라운드 서비스 시작, 출발일 8시 알림, 화면이 꺼진 동안의 위치, 재부팅. 순수 함수·가짜로 시험하고, 실기기 확인은 Task 10에서 사용자가 한다.

**검증하며 정한 것(설계가 열어 둔 부분)**
1. **본국 행(V15).**
   - `trip.country_id`가 country 외래 키라 KR 여행에는 KR 행이 있어야 한다.
   - 목록 API는 그 행을 걸러 응답을 R7 전과 같게 둔다. 일일 수집(비자·경보·공관)도 본국을 건너뛴다.
   - 부수 효과: 발걸음 동기화(`/api/checkins`·`/api/daily-steps`)가 KR 기록을 400 없이 받는다. 앱 주석 하나를 고친다.
2. **다음 마이그레이션 번호는 V15**다(V1~V14가 있다). 국내 여행은 여권 만료일을 보내도 저장하지 않는다. 해외 여행의 필수 검사는 `@AssertTrue` 교차 검증으로 옮겼다(국가 코드와 두 필드의 관계라 `@NotNull`로는 못 한다).
3. **`DOMESTIC`은 서버·앱 `VisaVerdict` 둘 다에 넣는다.** wire 값 계약이라 앱이 모르는 값이면 '확인 필요'로 내려가기 때문이다. `judge()`는 이 값을 내지 않는다.
4. **준비물 탭은 국내 여행을 고르지 않는다.** 국내 여행에는 체크리스트·지갑이 없다(설계는 여행 상세만 적었다). 국내 여행뿐이면 해외 여행계획을 만들라고 안내한다.
5. **`shouldRecord`는 기록할 여행(`TripPeriod?`)을 돌려준다.** 겹치면 가장 늦게 출발한 여행, 출발일까지 같으면 id가 큰 여행이다. 점 하나는 한 여행에만 속한다(trip_id).
6. **여행 기록 모드는 같은 서비스, 다른 TaskHandler다.**
   - 실험 세션이 돌고 있으면 여행 기록은 켜지도 끄지도 않는다(측정 오염 방지, 4-1).
   - 실험 화면은 여행 기록 중이면 안내만 하고, [기록 종료]로 여행 기록을 멈출 수 있다. 다음에 앱을 열면 다시 켜진다.
7. **정책은 `step_budget` E = 50m + `adaptive` 감지기로 시작한다.** R6의 '제안' 기본 조합이다. E와 감지기는 실험 뒤 `tripPolicyChoice` 상수 하나만 바꾼다.
8. **점의 국가는 기록 서비스가 세계지도 폴리곤으로 가린다**(실시간 경로와 같은 방법, 오프라인). 모르면 여행의 나라로 둔다. 그래야 해외 여행 출발일의 인천공항 점이 일본 지도에 붙지 않는다.
9. **정지 구간을 새 표 `TripStillSpans`(스키마 3)에 남긴다.**
   - R5가 넘긴 과제다. RoutePoints의 state만으로는 정지 시작·끝을 모른다.
   - 그래서 날짜별 보기의 머문 곳도 제안 방식(5-6)으로 묶는다. `PolicyRunner.onStepUpdate`는 패키지 변경 한 줄이다.
10. **켜는 조건은 위치(앱 사용 중) 권한 하나다.**
    - 배너는 설계대로 백그라운드 위치·활동 인식·알림 중 하나라도 없으면 뜬다. 문구는 설계대로 "기록이 꺼져 있어요"이고, 아래에 없는 권한을 적는다.
    - '항상 허용'까지 요구하면 거절한 사용자에게는 기록이 아예 없다.
11. **출발일 알림은 서울 시각 8시다**(비자 준비 알람과 같다 — 출발은 한국에서 한다).
    - 알림 id는 21억부터다. 일시정지한 여행에는 알림을 만들지 않는다.
    - 새 채널 `com.travelfootsteps.trip_recording`을 쓴다.
12. **스스로 끝내기**: 기록 서비스가 5초 tick마다 날짜를 보고, 1분마다 저장소를 다시 읽어 지워졌거나 일시정지한 여행이면 끝낸다. 화면은 삭제·일시정지 때 서비스를 바로 끈다.
13. **정리 규칙**(PR #32의 알람 주인과 같은 방식)
    - 삭제·404: 그 여행의 기록을 지운다.
    - 서버 목록: 목록에 없는 여행의 기록을 지운다.
    - 로그아웃: 기록을 끄고 일정·알림을 비운다. 좌표는 남긴다 — 같은 계정이 다시 로그인하면 그대로 본다.
    - 다른 계정 로그인: 이전 여행 좌표를 모두 지운다.
14. **날짜별 보기**
    - 경로는 `/visa/trip/:id/footsteps`, 여행 정보는 여행 목록 provider(오프라인 캐시 포함)에서 읽는다.
    - 점은 화면을 열 때·포그라운드 복귀·새로고침 때 다시 읽는다. 다른 isolate가 쓴 행은 drift watch가 모른다.
    - 2000개가 넘는 날(탈것에서 5초마다 잰 날)은 점 하나를 겹쳐 나눠 보낸다.
    - 실패와 서버의 직선 대체(`fallback: true`)는 같은 안내다.
    - 그날 걸음 = 그날 점의 `steps_since_prev` 합, 이동 거리 = 그린 경로 길이(탈것·추정 구간 포함)다.
    - 밤을 넘긴 숙소는 정지 구간을 자르지 않아 두 날 모두 실제 도착·출발 시각으로 보인다.
15. **WorkManager 체크인도 일시정지한 여행에서는 하지 않는다.** 설계는 '여행 기간에만'이라 적었다. 일시정지는 위치를 남기지 말라는 뜻으로 본다.
16. **세 isolate가 같은 SQLite 파일을 쓰므로 `busy_timeout`을 5초로 둔다.** 다른 연결이 쓰는 중이면 바로 실패하지 않는다.
17. **R5가 넘긴 '폰에서 걸음 수 다시 세기'는 하지 않는다.** 앱은 기본 방법 `osrm_match_radius`를 써서 `stepsSincePrev`를 경로에 쓰지 않는다. 그날 걸음 수 합만 걷기 시작 몇 초의 소급 걸음만큼 모자랄 수 있다(한계로 적는다).

## Global Constraints

- 작업 브랜치는 `trip`이다. `analysis`(R6)에서 갈라진다: `git switch -c trip analysis`. PR 쌓임은 research ← replay ← steps ← policy(#37) ← route(#38) ← analysis ← trip이고, PR 대상은 `analysis`다. 다른 브랜치를 만들지 않는다.
- 커밋에 `Co-Authored-By`, `Claude-Session` 같은 AI 트레일러를 넣지 않는다. push 전에 `git log --format=%B analysis..HEAD | grep -iE "co-authored|claude"`가 빈 결과인지 확인한다.
- 비밀정보(`server/.env`, `firebase-service-account.json`, `google-services.json`, `local.properties`)와 기록 데이터(`research/data/`, 폰에서 꺼낸 DB)는 커밋하지 않는다. 각 커밋 전에 `git status --short`를 본다.
- 서버 프로덕션 코드(`server/src/main/**`)에는 Spring 개념을 처음 배우는 사람을 위한 한국어 설명 주석을 단다(CLAUDE.md). 테스트·앱·패키지에는 적용하지 않는다.
- `packages/footstep_core`는 Flutter에 의존하지 않고 의존성을 바꾸지 않는다. 이 계획은 `PolicyRunner`에 선택 매개변수 `onStepUpdate` 하나만 더한다.
- 값(설계 9장과 이 계획에서 정한 값)
  - 여행 기록 정책: `step_budget`, `e_m=50`, 감지기 `adaptive`(`tripPolicyChoice`, 바꿀 곳은 여기 하나)
  - 기록 기간: [출발일 0시, 귀국일 다음 날 0시), 기기 현지 시각. 겹치면 가장 늦게 출발한 여행, 같으면 id가 큰 여행, 일시정지한 여행은 뺀다
  - 출발일 알림: 출발일 08:00(서울)
    - 제목 '여행 발걸음 기록', 본문 "오늘부터 ○○ 여행 발걸음을 기록합니다."
    - id = 2,100,000,000 + tripId % 40,000,000
    - 채널 `com.travelfootsteps.trip_recording`
  - 저장소 키: `trip_recording.trips.v1`, `trip_recording.paused.v1`, `trip_recording.owner.v1`, `trip_recording.notices.v1`
  - 기록 서비스: 5초 tick(날짜 확인), 1분마다 저장소 다시 읽기, 1분마다 배터리 잔량. 재부팅 뒤 자동 시작 없음(`autoRunOnBoot: false`)
  - RoutePoints 새 열(null 허용): `trip_id`, `accuracy_m`, `steps_since_prev`, `state`. 새 표 `trip_still_spans(trip_id, start_at, end_at)`. 스키마 3
  - 복원: 방법을 보내지 않는다(서버 기본 `osrm_match_radius`). 한 번에 점 2000개·머문 곳 500개 이하. 캐시 키 (여행, 날짜, 그날 마지막 점 시각)
  - 문구(그대로): "도로 맞춤을 못 했어요", "기록이 꺼져 있어요", 출발일 알림 본문
- 화면은 와이어프레임을 확인하지 못한 상태로 만든다(Claude Design은 사용자가 시작한 스킬에서만 열린다). 날짜별 보기와 여행 상세의 '발걸음 기록' 칸은 **와이어프레임 확인 필요(사용자)**로 두고, 지금은 여행 상세의 시각 언어를 그대로 따른다.
  - 54px 머리글 + 아래 테두리
  - `WireframeCard`, `FilterPill`, `PillOutlineButton`, `AppColors`·`AppTextStyles`
  - 지도는 `BaseGoogleMap`
- 테스트·분석 명령
  - 앱(`app/`): `flutter test`, `dart analyze lib test`. **`flutter analyze`는 이 PC에서 죽으므로 쓰지 않는다.**
  - Drift 코드 생성(`app/`): `dart run build_runner build --delete-conflicting-outputs --force-jit`(이 PC는 `--force-jit`가 필요하다). 생성 뒤 `git status`에 `wallet_database.g.dart`가 줄바꿈만 바뀌어 보이면 `git checkout -- app/lib/features/wallet/data/wallet_database.g.dart`로 되돌린다.
  - 서버(`server/`, Git Bash): `./gradlew test`. 전체 실행에는 Docker Desktop이 켜져 있어야 한다(Testcontainers). 이 PC는 메모리가 부족하니 다 돌린 뒤 Docker Desktop을 끈다. 태스크 중간에는 `./gradlew test --tests 'com.travelfootsteps.trip.*'`로 빠르게 본다.
  - 패키지(`packages/footstep_core/`): `dart test`, `dart analyze`
- 서버를 띄울 때는 로컬 `server/.env`를 그대로 쓰고 복사하거나 커밋하지 않는다. 포트는 `netsh interface ipv4 show excludedportrange protocol=tcp`로 예약 범위 밖인지 먼저 본다(8080이 막힐 때가 있다).
- 코드 주석은 한국어로 '왜'를 적는다.

## 파일 구조

```
server/src/main/resources/db/migration/V15__domestic_trip.sql   본국 행, passport_expiry NULL 허용 (Task 1)
server/src/main/java/com/travelfootsteps/
  country/Country.java, CountryController.java                  HOME_ISO2·isHome, 목록에서 본국 제외 (Task 1)
  visa/VisaVerdict.java, VisaJudgement.java                     DOMESTIC, VisaJudgement.domestic (Task 1)
  trip/CreateTripRequest.java, Trip.java, TripController.java   국내 여행 생성·새로고침·stale (Task 1)
  batch/DailyDataCollectionScheduler.java                       본국 건너뛰기 (Task 1)
packages/footstep_core/lib/src/runner/policy_runner.dart        onStepUpdate (Task 4)
app/lib/
  core/db/app_database.dart (+ .g.dart)                         RoutePoints 4열, TripStillSpans, 스키마 3, busy_timeout (Task 2)
  features/footsteps/data/route_point.dart                      여행 기록 필드 (Task 2)
  features/footsteps/trip/
    trip_period.dart                 TripPeriod, shouldRecord (Task 3, fromTrip은 Task 8)
    trip_recording_store.dart        isolate 공용 상태(일정·일시정지·주인·출발 알림) (Task 3)
    trip_recorder.dart               TripRecorder, tripPolicyChoice (Task 4)
    trip_recording_session.dart      스스로 끝내기 규칙 (Task 4)
    trip_recording_task_handler.dart 기록 서비스 isolate 껍데기 (Task 4)
    trip_recording_service.dart      화면 → 서비스 켜고 끄기 (Task 4)
    trip_recording_permissions.dart  권한 확인·설정 열기 (Task 5)
    trip_recording_coordinator.dart  켜기·끄기·정리 (Task 5, 정리·알림은 Task 6)
    trip_recording_providers.dart    provider·계정 가드·시계·일시정지 (Task 5~8)
    trip_departure_notices.dart      출발일 08:00 알림 (Task 6)
    trip_day.dart                    날짜 묶음·머문 곳·걸음 (Task 7)
    route_reconstruct_api.dart       복원 API 클라이언트·나눠 보내기 (Task 7)
    trip_footsteps_providers.dart    기록 읽기·복원 캐시·권한 (Task 7)
    trip_footsteps_page.dart         날짜별 보기 화면 (Task 7)
    trip_footsteps_card.dart         여행 상세의 '발걸음 기록' 칸 (Task 8)
  features/footsteps/recording/      trip 모드, RecordingConfig.trip, 서비스 초기화 공용화 (Task 4)
  features/footsteps/lab/lab_page.dart                          여행 기록 중 안내 (Task 4)
  features/footsteps/map/live_route_tracker.dart, providers/footsteps_providers.dart   표시 전용 실시간 경로 (Task 5)
  features/footsteps/background/footstep_task_handler.dart, footstep_workmanager.dart   여행 기간에만 체크인 (Task 5)
  router.dart                                                   앱 셸 sync·updateTrips (Task 5), 날짜별 보기 경로 (Task 7)
  main.dart                                                     계정 가드 (Task 6)
  features/visa/notifications/alarm_scheduler.dart              LocalAlarmBackend 채널 매개변수 (Task 6)
  features/visa/data/trip_deletion.dart                         삭제 때 여행 기록 정리 (Task 6)
  features/visa/visa_result_page.dart                           404 정리 (Task 6), 국내 여행·발걸음 칸 (Task 8)
  features/visa/models/*, visa_result_display.dart, data/trip_api.dart, visa_page.dart   국내 여행 (Task 8)
  features/checklist/checklist_page.dart                        국내 여행 제외 (Task 8)
  features/footsteps/data/footsteps_sync_service.dart           주석 (Task 8)
app/test/footsteps/trip/trip_fakes.dart                         테스트 도우미 (Task 3에서 만들고 4~6에서 늘린다)
docs/research/trip-recording-guide.md, docs/api-spec.md, docs/research/route-guide.md, 설계 문서 9-6 (Task 9)
docs/research/trip-check.md                                     실기기 확인 결과 (Task 10, 사용자)
```

---

### Task 1: 서버 — 대한민국 여행은 비자 판정 없이 국내 여행(`DOMESTIC`)으로 만든다

설계 9-1의 서버 쪽이다. 여행은 country 행을 외래 키로 가리키므로 V15가 본국(KR) 행을 넣는다. 목적지 목록과 일일 수집은 그 행을 건너뛴다. 국내 여행은 여권 만료일 없이 만들 수 있고, 비자 판정·준비 일정·준비물 없이 `DOMESTIC` 스냅샷만 저장한다. 해외 여행의 여권 만료일 필수 검사는 그대로다.

**Files:**
- Create: `server/src/main/resources/db/migration/V15__domestic_trip.sql`
- Modify: `server/src/main/java/com/travelfootsteps/country/Country.java`(`HOME_ISO2`, `isHomeIso2`, `isHome`)
- Modify: `server/src/main/java/com/travelfootsteps/country/CountryController.java`(목록에서 본국을 뺀다)
- Modify: `server/src/main/java/com/travelfootsteps/visa/VisaVerdict.java`(`DOMESTIC`)
- Modify: `server/src/main/java/com/travelfootsteps/visa/VisaJudgement.java`(`domestic` 팩토리)
- Modify: `server/src/main/java/com/travelfootsteps/trip/CreateTripRequest.java`(여권 만료일 교차 검증)
- Modify: `server/src/main/java/com/travelfootsteps/trip/Trip.java`(`passport_expiry` null 허용)
- Modify: `server/src/main/java/com/travelfootsteps/trip/TripController.java`(생성·새로고침·stale의 국내 분기)
- Modify: `server/src/main/java/com/travelfootsteps/batch/DailyDataCollectionScheduler.java`(본국 건너뛰기)
- Test: `server/src/test/java/com/travelfootsteps/trip/TripControllerTest.java`, `country/CountryControllerTest.java`, `country/CountryRepositoryTest.java`, `batch/DailyDataCollectionSchedulerTest.java`

**Interfaces:**
- Consumes: 기존 `TripController`·`Trip.applyJudgementSnapshot`·`TripResponse.of`
- Produces(앱이 기대는 계약)
  - `POST /api/trips`: `countryIso2 = "KR"`(대소문자 무관)이면 `passportExpiry`를 빼도 된다. 응답은 `visaResult.verdict = "DOMESTIC"`, `stayDays` = 일수, `passportOk = true`, `passportExpiry = null`, `tasks = []`, `judgementStale = false`, 체크리스트 0개다.
  - 그 밖의 나라는 `passportExpiry`가 없으면 400이다.
  - `POST /api/trips/{id}/refresh`: 국내 여행이면 아무것도 바꾸지 않고 GET과 같은 값을 돌려준다.
  - `GET /api/trips`: 국내 여행 줄은 `countryNameKo = "대한민국"`, `verdict = "DOMESTIC"`이다.
  - `GET /api/countries`: 그대로 목적지 20개국이다(KR 없음).
  - Java: `Country.HOME_ISO2 = "KR"`, `Country.isHomeIso2(String)`, `Country#isHome()`, `VisaVerdict.DOMESTIC`, `VisaJudgement.domestic(LocalDate, LocalDate)`

- [ ] **Step 1: 실패하는 테스트 작성**

`server/src/test/java/com/travelfootsteps/trip/TripControllerTest.java`의 토큰 목록에 국내 여행 목록 전용 사용자를 더한다. 다음 부분을

```java
            stub.register("token-c", "uid-c");
            return stub;
```

다음으로 바꾼다:

```java
            stub.register("token-c", "uid-c");
            stub.register("token-d", "uid-d");
            return stub;
```

같은 파일의 import에서 다음 부분을

```java
import static org.assertj.core.api.Assertions.assertThat;
```

다음으로 바꾼다:

```java
import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.nullValue;
```

같은 파일에서 다음 부분(마지막 테스트의 시작)을

```java
    @Test
    void 여행_삭제는_소유자만_할_수_있고_일정과_체크리스트도_함께_지운다() throws Exception {
```

다음으로 바꾼다:

```java
    // ─── 국내 여행(설계 2026-11-07 9-1) ─────────────────────────────────────────────

    @Test
    void 국내_여행은_비자_판정_없이_DOMESTIC으로_만들고_일정과_준비물을_만들지_않는다() throws Exception {
        String body = mockMvc.perform(post("/api/trips")
                        .header("Authorization", "Bearer token-a")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"countryIso2": "KR", "departDate": "2026-11-20", "returnDate": "2026-11-22"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.countryIso2").value("KR"))
                .andExpect(jsonPath("$.countryNameKo").value("대한민국"))
                .andExpect(jsonPath("$.passportExpiry").value(nullValue()))
                .andExpect(jsonPath("$.visaResult.verdict").value("DOMESTIC"))
                .andExpect(jsonPath("$.visaResult.stayDays").value(2))
                .andExpect(jsonPath("$.visaResult.passportOk").value(true))
                .andExpect(jsonPath("$.tasks.length()").value(0))
                .andExpect(jsonPath("$.judgementStale").value(false))
                .andReturn().getResponse().getContentAsString();
        Long tripId = objectMapper.readTree(body).get("id").asLong();

        mockMvc.perform(get("/api/trips/" + tripId + "/checklist").header("Authorization", "Bearer token-a"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));
        Integer tasks = jdbcTemplate.queryForObject(
                "SELECT count(*) FROM trip_task WHERE trip_id = ?", Integer.class, tripId);
        assertThat(tasks).isZero();
    }

    @Test
    void 국내_여행은_여권_만료일을_보내도_저장하지_않는다() throws Exception {
        Long tripId = createTrip("token-a", "kr",
                LocalDate.of(2026, 11, 20), LocalDate.of(2026, 11, 22), LocalDate.of(2030, 1, 1));

        mockMvc.perform(get("/api/trips/" + tripId).header("Authorization", "Bearer token-a"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.countryIso2").value("KR"))
                .andExpect(jsonPath("$.passportExpiry").value(nullValue()))
                .andExpect(jsonPath("$.visaResult.verdict").value("DOMESTIC"));
    }

    @Test
    void 해외_여행은_여권_만료일이_없으면_400() throws Exception {
        givenVietnamVisaFree45Days();

        mockMvc.perform(post("/api/trips")
                        .header("Authorization", "Bearer token-a")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"countryIso2": "VN", "departDate": "2026-12-20", "returnDate": "2027-01-09"}
                                """))
                .andExpect(status().isBadRequest());
    }

    @Test
    void 국내_여행_새로고침은_아무것도_바꾸지_않고_지금_값을_돌려준다() throws Exception {
        Long tripId = createTrip("token-a", "KR",
                LocalDate.of(2026, 11, 20), LocalDate.of(2026, 11, 22), null);

        mockMvc.perform(post("/api/trips/" + tripId + "/refresh").header("Authorization", "Bearer token-a"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(tripId.intValue()))
                .andExpect(jsonPath("$.visaResult.verdict").value("DOMESTIC"))
                .andExpect(jsonPath("$.visaResult.stayDays").value(2))
                .andExpect(jsonPath("$.tasks.length()").value(0))
                .andExpect(jsonPath("$.judgementStale").value(false));

        Integer tasks = jdbcTemplate.queryForObject(
                "SELECT count(*) FROM trip_task WHERE trip_id = ?", Integer.class, tripId);
        String verdict = jdbcTemplate.queryForObject(
                "SELECT verdict FROM trip WHERE id = ?", String.class, tripId);
        assertThat(tasks).isZero();
        assertThat(verdict).isEqualTo("DOMESTIC");
    }

    @Test
    void 국내_여행도_목록에_대한민국_DOMESTIC으로_나온다() throws Exception {
        Long tripId = createTrip("token-d", "KR",
                LocalDate.of(2026, 11, 20), LocalDate.of(2026, 11, 22), null);

        mockMvc.perform(get("/api/trips").header("Authorization", "Bearer token-d"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].id").value(tripId.intValue()))
                .andExpect(jsonPath("$[0].countryNameKo").value("대한민국"))
                .andExpect(jsonPath("$[0].verdict").value("DOMESTIC"));
    }

    @Test
    void 여행_삭제는_소유자만_할_수_있고_일정과_체크리스트도_함께_지운다() throws Exception {
```

`createTrip(...)` 도우미는 `new CreateTripRequest(...)`를 그대로 직렬화하므로 여권 만료일에 `null`을 넘기면 `"passportExpiry": null`로 간다.

`server/src/test/java/com/travelfootsteps/country/CountryControllerTest.java`에서 다음 부분을

```java
    @Test
    void health_is_accessible_without_token() throws Exception {
```

다음으로 바꾼다:

```java
    @Test
    void 목적지_목록에는_본국_한국을_넣지_않는다() throws Exception {
        // V15가 국내 여행을 위해 country 표에 KR을 넣었지만, 이 API는 R7 전과 같은 목적지 20개국만 돌려준다.
        mockMvc.perform(get("/api/countries").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(20))
                .andExpect(jsonPath("$[?(@.isoAlpha2=='KR')]").doesNotExist());
    }

    @Test
    void health_is_accessible_without_token() throws Exception {
```

`server/src/test/java/com/travelfootsteps/country/CountryRepositoryTest.java`에서 다음 부분을

```java
    @Test
    void seed_contains_20_tier_a_countries() {
        assertThat(countryRepository.findAll()).hasSize(20);
    }
```

다음으로 바꾼다:

```java
    @Test
    void seed_contains_20_tier_a_destinations_and_home_country() {
        // V1의 목적지 20개국 + V15의 본국(국내 여행용 KR).
        assertThat(countryRepository.findAll()).hasSize(21);
        Country home = countryRepository.findByIsoAlpha2("KR").orElseThrow();
        assertThat(home.getNameKo()).isEqualTo("대한민국");
        assertThat(home.isHome()).isTrue();
        assertThat(countryRepository.findByIsoAlpha2("VN").orElseThrow().isHome()).isFalse();
    }
```

`server/src/test/java/com/travelfootsteps/batch/DailyDataCollectionSchedulerTest.java`에서 다음 부분을

```java
    private Country mockCountry(String iso2) {
```

다음으로 바꾼다:

```java
    @Test
    void 본국_한국은_수집하지_않는다() {
        Country vn = mockCountry("VN");
        Country kr = mockCountry("KR");
        when(kr.isHome()).thenReturn(true);
        when(countryRepository.findAll()).thenReturn(List.of(kr, vn));

        scheduler.runDaily();

        verify(visaCollector, org.mockito.Mockito.never()).collectOne(kr);
        verify(alertCollector, org.mockito.Mockito.never()).collectOne(kr);
        verify(embassyCollector, org.mockito.Mockito.never()).collectOne(kr);
        verify(visaCollector, times(1)).collectOne(vn);
    }

    private Country mockCountry(String iso2) {
```

- [ ] **Step 2: 실패 확인**

Docker Desktop을 켠 뒤(Git Bash, `server/`에서):

```bash
./gradlew test --tests 'com.travelfootsteps.trip.*' --tests 'com.travelfootsteps.country.*' --tests 'com.travelfootsteps.batch.*'
```

Expected: FAIL. 테스트가 쓰는 `Country.isHome()`이 없어 테스트 코드가 컴파일되지 않는다. 구현 전 서버에서는 KR 여행 생성이 404(국가 없음)다.

- [ ] **Step 3: 구현**

`server/src/main/resources/db/migration/V15__domestic_trip.sql`:

```sql
-- 국내 여행(설계 2026-11-07 9-1). trip.country_id는 country 행을 가리켜야 하므로(외래 키) 본국(한국)을
-- 국가 표에 넣는다. 목적지 목록(GET /api/countries)과 일일 공공데이터 수집은 이 행을 건너뛴다
-- (Country.HOME_ISO2). 통화 코드는 비워 둔다 — 원화는 환율 수집 대상이 아니다.
INSERT INTO country (iso_alpha2, iso_alpha3, name_ko, name_en, continent, tier)
VALUES ('KR', 'KOR', '대한민국', 'South Korea', 'Asia', 'A');

-- 국내 여행에는 여권 만료일이 없다. 해외 여행은 요청 검증(CreateTripRequest)이 여전히 필수로 막는다.
ALTER TABLE trip ALTER COLUMN passport_expiry DROP NOT NULL;
```

`server/src/main/java/com/travelfootsteps/country/Country.java`에서 다음 부분을

```java
public class Country {

    // @Id + @GeneratedValue(IDENTITY)
```

다음으로 바꾼다:

```java
public class Country {

    // 본국(한국). V15 마이그레이션이 국내 여행을 위해 넣은 행이다(설계 9-1). 여행 목적지가 아니므로
    // 목적지 목록(CountryController.list)과 일일 공공데이터 수집(DailyDataCollectionScheduler)은 이 행을 건너뛰고,
    // 이 나라로 만든 여행은 비자 판정 대신 국내 여행(DOMESTIC)이 된다(TripController).
    // static final 상수는 엔티티의 필드가 아니라 클래스에 붙은 값이라 JPA가 컬럼으로 보지 않는다.
    public static final String HOME_ISO2 = "KR";

    /** 요청으로 받은 국가 코드가 본국인가(대소문자·앞뒤 공백 무시). */
    public static boolean isHomeIso2(String iso2) {
        return iso2 != null && HOME_ISO2.equalsIgnoreCase(iso2.trim());
    }

    // @Id + @GeneratedValue(IDENTITY)
```

같은 파일 끝의 다음 부분을

```java
    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;
}
```

다음으로 바꾼다:

```java
    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    /** 이 행이 본국(한국)인가. 엔티티 메서드라 Lombok @Getter가 만드는 getter와 별개로 직접 둔다. */
    public boolean isHome() {
        return isHomeIso2(isoAlpha2);
    }
}
```

`server/src/main/java/com/travelfootsteps/country/CountryController.java`에서 다음 부분을

```java
        // DB에서 Country 엔티티 목록을 이름 오름차순으로 가져온 뒤, 엔티티를 그대로 반환하지 않고
        // CountryResponse(DTO)로 하나씩 변환한다. 스프링이 리턴값을 자동으로 JSON 배열로 직렬화해준다.
        return countryRepository.findAllByOrderByNameKoAsc()
                .stream()
                .map(CountryResponse::from)
```

다음으로 바꾼다:

```java
        // DB에서 Country 엔티티 목록을 이름 오름차순으로 가져온 뒤, 엔티티를 그대로 반환하지 않고
        // CountryResponse(DTO)로 하나씩 변환한다. 스프링이 리턴값을 자동으로 JSON 배열로 직렬화해준다.
        // 본국(한국, V15)은 여행 목적지가 아니라 뺀다 — 이 목록은 R7 전과 같은 목적지 20개국이고,
        // 앱은 국내 여행 항목을 스스로 맨 위에 붙인다(설계 9-1).
        return countryRepository.findAllByOrderByNameKoAsc()
                .stream()
                .filter(country -> !country.isHome())
                .map(CountryResponse::from)
```

`server/src/main/java/com/travelfootsteps/visa/VisaVerdict.java`에서 다음 부분을

```java
/**
 * 비자 판정 결과의 4가지 상태. {@code wireValue()}는 Plan B의 {@code VisaVerdict.wireValue}와
 * 문자 그대로 일치해야 한다 — 이 문자열은 API 응답으로 그대로 나가며 Plan B(별도 문서/앱)가
 * 이 정확한 문자열에 의존한다. 바꾸면 Plan B가 깨진다.
 */
public enum VisaVerdict {
    VISA_FREE_OK("VISA_FREE_OK"),
    VISA_FREE_EXCEEDED("VISA_FREE_EXCEEDED"),
    VISA_REQUIRED("VISA_REQUIRED"),
    UNVERIFIED("UNVERIFIED");
```

다음으로 바꾼다:

```java
/**
 * 비자 판정 결과의 4가지 상태와 국내 여행. {@code wireValue()}는 Plan B의 {@code VisaVerdict.wireValue}와
 * 문자 그대로 일치해야 한다 — 이 문자열은 API 응답으로 그대로 나가며 Plan B(별도 문서/앱)가
 * 이 정확한 문자열에 의존한다. 바꾸면 Plan B가 깨진다.
 *
 * <p>{@link #DOMESTIC}은 판정 결과가 아니다. 본국(한국)으로 만든 여행은 비자 판정을 건너뛰고 이 값으로
 * 저장된다(설계 2026-11-07 9-1, TripController). {@link VisaJudgementService#judge}는 이 값을 내지 않는다.
 */
public enum VisaVerdict {
    VISA_FREE_OK("VISA_FREE_OK"),
    VISA_FREE_EXCEEDED("VISA_FREE_EXCEEDED"),
    VISA_REQUIRED("VISA_REQUIRED"),
    UNVERIFIED("UNVERIFIED"),
    DOMESTIC("DOMESTIC");
```

`server/src/main/java/com/travelfootsteps/visa/VisaJudgement.java` 전체를 다음으로 바꾼다:

```java
package com.travelfootsteps.visa;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;

/**
 * {@link VisaJudgementService#judge}의 판정 결과.
 *
 * @param verdict 최종 판정 (UNVERIFIED가 최우선으로 검사된다 — visaFreeDays를 모르면 다른 값은 신뢰할 수 없다).
 * @param stayDays departDate부터 returnDate까지의 체류일수.
 * @param visaFreeDays 무비자 체류 가능 일수. requirement가 없거나 파싱 실패면 null(= UNVERIFIED의 근거).
 * @param passportOk 여권이 요건(있다면)과 귀국일 이후 유효기간을 모두 만족하는지.
 * @param passportValidityMonths 여권 잔여유효기간 요건(개월). 원문에 언급이 없으면 null(= 요건 없음, UNVERIFIED와 무관).
 * @param passportShortfallDays 여권이 부족한 경우 부족한 일수. 문제 없으면 null.
 */
public record VisaJudgement(
        VisaVerdict verdict,
        int stayDays,
        Integer visaFreeDays,
        boolean passportOk,
        Integer passportValidityMonths,
        Integer passportShortfallDays
) {
    /**
     * 국내 여행의 스냅샷 값(설계 2026-11-07 9-1). 비자 판정을 하지 않으므로 허용 일수·여권 요건은 비우고,
     * 여권은 따질 것이 없어 문제없음(true)으로 둔다. 체류일수는 판정과 같은 방식(DAYS.between)으로 센다.
     * 판정 스냅샷을 쓰는 길(Trip.applyJudgementSnapshot)을 해외 여행과 하나로 두려고 같은 타입으로 만든다.
     */
    public static VisaJudgement domestic(LocalDate departDate, LocalDate returnDate) {
        int stayDays = (int) ChronoUnit.DAYS.between(departDate, returnDate);
        return new VisaJudgement(VisaVerdict.DOMESTIC, stayDays, null, true, null, null);
    }
}
```

`server/src/main/java/com/travelfootsteps/trip/CreateTripRequest.java` 전체를 다음으로 바꾼다:

```java
package com.travelfootsteps.trip;

import com.travelfootsteps.country.Country;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;

// record + jakarta.validation 애너테이션: @Valid와 함께 컨트롤러 파라미터에 쓰이면, 스프링이
// 요청 본문을 이 레코드로 역직렬화한 뒤 애너테이션 조건을 검사한다. 하나라도 위반하면
// 컨트롤러 메서드 본문이 실행되기 전에 MethodArgumentNotValidException이 던져지고, 스프링
// 기본 설정상 400 Bad Request로 응답된다.
//
// passportExpiry에는 @NotNull이 없다 — 국내 여행(countryIso2 = "KR")은 여권 만료일을 받지 않는다(설계 9-1).
// 해외 여행에 꼭 있어야 한다는 규칙은 아래 isPassportExpiryGivenUnlessDomestic()이 대신 검사한다.
public record CreateTripRequest(
        @NotBlank String countryIso2,
        @NotNull LocalDate departDate,
        @NotNull LocalDate returnDate,
        LocalDate passportExpiry
) {
    // Jakarta Bean Validation은 getter 스타일 메서드(is-prefixed boolean)를 하나의 제약으로
    // 인식한다 — record의 컴팩트 생성자 밖에서 필드 간 교차 검증(cross-field validation)을 걸 때
    // 쓰는 표준 패턴이다. false를 반환하면 "returnDate는 departDate보다 앞설 수 없습니다"라는
    // 메시지로 위반이 등록되고, @Valid가 컨트롤러 본문 실행 전에 400으로 막는다. null 체크를
    // 먼저 하는 이유: @NotNull 위반과 이 위반이 동시에 나더라도(둘 다 400 이유가 되므로 무해하지만)
    // NPE로 다른 위반 메시지들이 통째로 가려지는 것을 막기 위함이다.
    @AssertTrue(message = "returnDate는 departDate보다 앞설 수 없습니다")
    public boolean isReturnAfterDepart() {
        return departDate == null || returnDate == null || !returnDate.isBefore(departDate);
    }

    // 같은 @AssertTrue 패턴으로 "해외 여행이면 여권 만료일이 필수"를 검사한다. 국가 코드와 여권 만료일 두 필드의
    // 관계라 필드 하나에 붙이는 @NotNull로는 표현할 수 없다. 위반하면 위와 똑같이 400이다.
    @AssertTrue(message = "해외 여행은 passportExpiry가 필요합니다")
    public boolean isPassportExpiryGivenUnlessDomestic() {
        return passportExpiry != null || Country.isHomeIso2(countryIso2);
    }
}
```

`server/src/main/java/com/travelfootsteps/trip/Trip.java`에서 다음 부분을

```java
    @Column(name = "passport_expiry", nullable = false)
    private LocalDate passportExpiry;
```

다음으로 바꾼다:

```java
    // 국내 여행(설계 9-1)은 여권 만료일이 없어 null이다(V15에서 NOT NULL을 풀었다). 해외 여행은 요청 검증이 필수로 막는다.
    @Column(name = "passport_expiry")
    private LocalDate passportExpiry;
```

`TripController.java`는 네 곳을 고친다. 먼저 생성 첫머리에서 본국이면 국내 여행 길로 보낸다. 다음 부분을

```java
    public TripResponse create(@Valid @RequestBody CreateTripRequest request, Authentication authentication) {
        Country country = findCountryOrThrow(request.countryIso2());
        VisaRequirement requirement = findRequirement(country);
```

다음으로 바꾼다:

```java
    public TripResponse create(@Valid @RequestBody CreateTripRequest request, Authentication authentication) {
        Country country = findCountryOrThrow(request.countryIso2());
        if (country.isHome()) {
            return createDomestic(request, country, authentication.getName());
        }
        VisaRequirement requirement = findRequirement(country);
```

create() 바로 뒤(GET 앞)의 다음 부분을

```java
        boolean stale = isJudgementStale(trip, country);
        return TripResponse.of(trip, country, tasks, stale);
    }

    // GET은 저장된 스냅샷만 읽는다
```

다음으로 바꾼다:

```java
        boolean stale = isJudgementStale(trip, country);
        return TripResponse.of(trip, country, tasks, stale);
    }

    // 국내 여행(설계 2026-11-07 9-1): 비자 판정을 건너뛰고 verdict=DOMESTIC 스냅샷만 저장한다. 준비 일정(trip_task)과
    // 준비물 체크리스트(trip_checklist)는 만들지 않는다 — 출국 준비가 없는 여행이고, 앱은 발걸음 기록만 보여 준다.
    // 여권 만료일은 쓰지 않으므로 요청에 들어 있어도 저장하지 않는다. create()와 같은 트랜잭션 안에서 불린다.
    private TripResponse createDomestic(CreateTripRequest request, Country country, String uid) {
        Trip trip = Trip.create(uid, country.getId(), request.departDate(), request.returnDate(), null);
        trip.applyJudgementSnapshot(VisaJudgement.domestic(request.departDate(), request.returnDate()), null);
        trip = tripRepository.save(trip);
        return TripResponse.of(trip, country, List.of(), false);
    }

    // GET은 저장된 스냅샷만 읽는다
```

refresh()의 다음 부분을

```java
    public TripResponse refresh(@PathVariable Long id, Authentication authentication) {
        Trip trip = findOwnedTripOrThrow(id, authentication.getName());
        Country country = findCountryByIdOrThrow(trip.getCountryId());
        VisaRequirement requirement = findRequirement(country);
```

다음으로 바꾼다:

```java
    public TripResponse refresh(@PathVariable Long id, Authentication authentication) {
        Trip trip = findOwnedTripOrThrow(id, authentication.getName());
        Country country = findCountryByIdOrThrow(trip.getCountryId());
        if (country.isHome()) {
            // 국내 여행은 다시 판정할 것이 없다(설계 9-1). 아무것도 바꾸지 않고 지금 값을 GET과 똑같이 돌려준다.
            List<TripTask> tasks = tripTaskRepository.findByTripIdOrderByDueDateAsc(trip.getId());
            return TripResponse.of(trip, country, tasks, false);
        }
        VisaRequirement requirement = findRequirement(country);
```

isJudgementStale()의 다음 부분을

```java
    private boolean isJudgementStale(Trip trip, Country country) {
        OffsetDateTime currentRequirementUpdatedAt = requirementUpdatedAt(findRequirement(country));
```

다음으로 바꾼다:

```java
    // 국내 여행은 판정 기준 데이터가 없으므로 언제나 false다 — 일일 수집이 본국을 건너뛰지만, 그것과 상관없이 여기서 막는다.
    private boolean isJudgementStale(Trip trip, Country country) {
        if (country.isHome()) return false;
        OffsetDateTime currentRequirementUpdatedAt = requirementUpdatedAt(findRequirement(country));
```

`server/src/main/java/com/travelfootsteps/batch/DailyDataCollectionScheduler.java`에서 다음 부분을

```java
        for (Country country : countries) {
            collectSafely(country, "visa", () -> visaRequirementCollector.collectOne(country));
```

다음으로 바꾼다:

```java
        for (Country country : countries) {
            // 본국(한국, V15)은 여행 목적지가 아니라 비자 요건·여행경보·재외공관 자료가 없다 — 외부 API 쿼터를 쓰지 않는다.
            if (country.isHome()) continue;
            collectSafely(country, "visa", () -> visaRequirementCollector.collectOne(country));
```

`ExchangeRateBatchScheduler`는 KR 행의 통화 코드가 비어 있어(`currency_code` NULL) 그대로 둔다. `FootstepsSyncController`는 이제 KR 체크인·걸음 수를 400 없이 받는다(부수 효과, 앱 주석은 Task 8에서 고친다).

- [ ] **Step 4: 통과 확인**

Run(Docker Desktop 켜고, `server/`에서): `./gradlew test`

Expected: 모두 통과(333개). 바뀐 클래스는 `TripControllerTest` 22개(국내 5개 추가), `CountryControllerTest` 8개, `CountryRepositoryTest` 3개, `DailyDataCollectionSchedulerTest` 3개다. 끝나면 Docker Desktop을 끈다.

- [ ] **Step 5: 커밋**

```bash
git add server/src/main/resources/db/migration/V15__domestic_trip.sql \
  server/src/main/java/com/travelfootsteps/country/Country.java \
  server/src/main/java/com/travelfootsteps/country/CountryController.java \
  server/src/main/java/com/travelfootsteps/visa/VisaVerdict.java \
  server/src/main/java/com/travelfootsteps/visa/VisaJudgement.java \
  server/src/main/java/com/travelfootsteps/trip/CreateTripRequest.java \
  server/src/main/java/com/travelfootsteps/trip/Trip.java \
  server/src/main/java/com/travelfootsteps/trip/TripController.java \
  server/src/main/java/com/travelfootsteps/batch/DailyDataCollectionScheduler.java \
  server/src/test/java/com/travelfootsteps/trip/TripControllerTest.java \
  server/src/test/java/com/travelfootsteps/country/CountryControllerTest.java \
  server/src/test/java/com/travelfootsteps/country/CountryRepositoryTest.java \
  server/src/test/java/com/travelfootsteps/batch/DailyDataCollectionSchedulerTest.java
git commit -m "feat(server): 대한민국 여행은 비자 판정 없이 국내 여행(DOMESTIC)으로 만들고 여권 만료일을 비울 수 있게 한다"
```

---

### Task 2: 앱 — RoutePoints에 여행 기록 열을 더하고 정지 구간 표를 만든다 (스키마 3)

설계 9-3이다. 여행 기록 서비스가 남기는 점은 여행 id·정확도·직전 점 이후 걸음 수·정책 상태를 함께 가진다. 걸음 감지기의 정지 구간은 새 표에 둔다 — 날짜별 보기의 머문 곳 묶기(설계 5-6 제안 방식)가 도착·출발 시각으로 쓴다(R5 'R7에 넘기는 것'). 기존 행은 새 열이 모두 null이라 세계지도·국가 지도는 그대로 동작한다.

여행 기록 서비스·WorkManager·화면이 각자의 isolate에서 같은 SQLite 파일을 열게 되므로, 연결마다 `busy_timeout`을 5초로 둔다.

**Files:**
- Modify: `app/lib/features/footsteps/data/route_point.dart`(전체 교체)
- Modify: `app/lib/core/db/app_database.dart`
- Regenerate: `app/lib/core/db/app_database.g.dart`(build_runner)
- Test: `app/test/db/app_database_test.dart`

**Interfaces:**
- Consumes: footstep_core `TimeSpan`(R5)
- Produces
  - `RoutePoint`에 `int? tripId`, `double? accuracyM`, `int? stepsSincePrev`, `String? state`(선택 매개변수)
  - `AppDatabase`
    - `Future<int> insertTripPoint({required int tripId, required double lat, required double lng, required String countryIso, required DateTime recordedAt, double? accuracyM, int? stepsSincePrev, String? state})`
    - `Future<List<RoutePoint>> routePointsForTrip(int tripId)`: 시각순
    - `Future<int> insertTripStillSpan({required int tripId, required DateTime startAt, required DateTime endAt})`
    - `Future<List<TimeSpan>> stillSpansForTrip(int tripId)`: 밀리초, 시작순
    - `Future<void> deleteTripRecords(Iterable<int> tripIds)`
    - `Future<void> deleteTripRecordsExcept(Set<int> keep)`: 비면 여행 기록 전부. `tripId`가 null인 점은 건드리지 않는다
  - drift는 DateTime을 초 단위로 저장한다. 밀리초는 버려지므로 테스트는 초 단위 시각을 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/db/app_database_test.dart`의 import에서 다음 부분을

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
```

다음으로 바꾼다:

```dart
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footstep_core/footstep_core.dart' show TimeSpan;
```

같은 파일 끝의 다음 부분을

```dart
    expect(jp, hasLength(2));
    expect(jp.first.lat, 35.60); // 시간순이므로 9:00이 먼저
    expect(jp.last.lat, 35.61);
  });
}
```

다음으로 바꾼다:

```dart
    expect(jp, hasLength(2));
    expect(jp.first.lat, 35.60); // 시간순이므로 9:00이 먼저
    expect(jp.last.lat, 35.61);
  });

  group('여행 기록(스키마 3)', () {
    test('여행 점을 정확도·걸음·상태와 함께 저장하고 여행별로 시각순 조회한다', () async {
      await db.insertTripPoint(tripId: 7, lat: 37.51, lng: 127.01, countryIso: 'KR',
          recordedAt: DateTime.utc(2026, 11, 20, 9, 5), accuracyM: 8, stepsSincePrev: 64, state: 'walking');
      await db.insertTripPoint(tripId: 7, lat: 37.50, lng: 127.00, countryIso: 'KR',
          recordedAt: DateTime.utc(2026, 11, 20, 9), state: 'unknown');
      await db.insertTripPoint(tripId: 8, lat: 35.6, lng: 139.7, countryIso: 'JP',
          recordedAt: DateTime.utc(2026, 11, 20, 9, 1));
      await db.insertRoutePoint(lat: 37.6, lng: 127.1, countryIso: 'KR', recordedAt: DateTime.utc(2026, 11, 20, 9, 2));

      final points = await db.routePointsForTrip(7);

      expect(points.map((p) => p.lat), [37.50, 37.51]);
      expect(points.last.tripId, 7);
      expect(points.last.accuracyM, 8);
      expect(points.last.stepsSincePrev, 64);
      expect(points.last.state, 'walking');
      expect(points.first.accuracyM, isNull);
      // 세계지도·국가 지도는 여행 점도 그대로 본다.
      expect(await db.routePointsForCountry('KR'), hasLength(3));
      expect((await db.routePointsForCountry('KR')).where((p) => p.tripId == null), hasLength(1));
    });

    test('정지 구간을 저장하고 여행별로 시작 시각순 밀리초 구간으로 돌려준다', () async {
      await db.insertTripStillSpan(
          tripId: 7, startAt: DateTime.utc(2026, 11, 20, 10), endAt: DateTime.utc(2026, 11, 20, 10, 30));
      await db.insertTripStillSpan(
          tripId: 7, startAt: DateTime.utc(2026, 11, 20, 9), endAt: DateTime.utc(2026, 11, 20, 9, 15));
      await db.insertTripStillSpan(
          tripId: 8, startAt: DateTime.utc(2026, 11, 20, 9), endAt: DateTime.utc(2026, 11, 20, 9, 1));

      final spans = await db.stillSpansForTrip(7);

      expect(spans, [
        TimeSpan(DateTime.utc(2026, 11, 20, 9).millisecondsSinceEpoch,
            DateTime.utc(2026, 11, 20, 9, 15).millisecondsSinceEpoch),
        TimeSpan(DateTime.utc(2026, 11, 20, 10).millisecondsSinceEpoch,
            DateTime.utc(2026, 11, 20, 10, 30).millisecondsSinceEpoch),
      ]);
    });

    Future<void> seedTwoTripsAndLegacyPoint() async {
      for (final tripId in [7, 8]) {
        await db.insertTripPoint(tripId: tripId, lat: 37.5, lng: 127.0, countryIso: 'KR',
            recordedAt: DateTime.utc(2026, 11, 20, 9));
        await db.insertTripStillSpan(
            tripId: tripId, startAt: DateTime.utc(2026, 11, 20, 9), endAt: DateTime.utc(2026, 11, 20, 9, 20));
      }
      await db.insertRoutePoint(lat: 37.6, lng: 127.1, countryIso: 'KR', recordedAt: DateTime.utc(2026, 11, 20, 9));
    }

    test('지운 여행의 점과 정지 구간만 지우고 여행에 속하지 않은 점은 남긴다', () async {
      await seedTwoTripsAndLegacyPoint();

      await db.deleteTripRecords([7]);

      expect(await db.routePointsForTrip(7), isEmpty);
      expect(await db.stillSpansForTrip(7), isEmpty);
      expect(await db.routePointsForTrip(8), hasLength(1));
      expect(await db.stillSpansForTrip(8), hasLength(1));
      expect(await db.routePointsForCountry('KR'), hasLength(2));
    });

    test('남길 여행 밖의 여행 기록을 지운다 — 비우면 여행 기록 전부', () async {
      await seedTwoTripsAndLegacyPoint();

      await db.deleteTripRecordsExcept({8});
      expect(await db.routePointsForTrip(7), isEmpty);
      expect(await db.stillSpansForTrip(7), isEmpty);
      expect(await db.routePointsForTrip(8), hasLength(1));

      await db.deleteTripRecordsExcept({});
      expect(await db.routePointsForTrip(8), isEmpty);
      expect(await db.stillSpansForTrip(8), isEmpty);
      expect(await db.routePointsForCountry('KR'), hasLength(1)); // tripId가 없는 기존 점
    });
  });

  test('스키마 2에서 올리면 기존 점은 여행 열이 null로 남고 여행 기록을 쓸 수 있다', () async {
    // setUp이 연 DB와 함께 두 번째 AppDatabase를 여는 것은 의도한 것이다(서로 다른 메모리 DB).
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
    // 스키마 2(R7 전)의 route_points를 만들어 둔 파일을 흉내 낸다. setup은 drift가 마이그레이션을 보기 전에 돈다.
    final old = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
      raw.execute('CREATE TABLE "route_points" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
          '"lat" REAL NOT NULL, "lng" REAL NOT NULL, '
          '"country_iso" TEXT NOT NULL CHECK(length("country_iso") >= 2 AND length("country_iso") <= 2), '
          '"recorded_at" INTEGER NOT NULL);');
      raw.execute('INSERT INTO route_points (lat, lng, country_iso, recorded_at) VALUES (35.6, 139.7, \'JP\', 1792400000);');
      raw.execute('PRAGMA user_version = 2;');
    }));
    addTearDown(old.close);

    final legacy = await old.routePointsForCountry('JP');
    expect(legacy, hasLength(1));
    expect(legacy.single.tripId, isNull);
    expect(legacy.single.state, isNull);

    await old.insertTripPoint(tripId: 3, lat: 35.7, lng: 139.8, countryIso: 'JP',
        recordedAt: DateTime.utc(2026, 11, 20), stepsSincePrev: 10, state: 'walking');
    await old.insertTripStillSpan(
        tripId: 3, startAt: DateTime.utc(2026, 11, 20), endAt: DateTime.utc(2026, 11, 20, 0, 20));
    expect((await old.routePointsForTrip(3)).single.stepsSincePrev, 10);
    expect(await old.stillSpansForTrip(3), hasLength(1));
  });
}
```

- [ ] **Step 2: 실패 확인**

Run(`app/`에서): `flutter test test/db/app_database_test.dart`

Expected: FAIL. `insertTripPoint`·`stillSpansForTrip`이 없어 컴파일되지 않는다.

- [ ] **Step 3: 구현**

`app/lib/features/footsteps/data/route_point.dart` 전체를 다음으로 바꾼다:

```dart
/// 실시간 이동 중 저장되는 좌표 하나. Checkin과 달리 국경 이동 확정 여부와
/// 무관하게 촘촘히 쌓여 "지나온 길"을 영구적으로 재구성하는 데 쓰인다.
///
/// 여행 기록(설계 2026-11-07 9-3)이 남긴 점은 [tripId]·[accuracyM]·[stepsSincePrev]·[state]를 함께 가진다.
/// 그 전의 실시간 경로·해외 매핑이 남긴 점은 넷 다 null이다.
class RoutePoint {
  const RoutePoint({
    required this.lat,
    required this.lng,
    required this.countryIso,
    required this.recordedAt,
    this.tripId,
    this.accuracyM,
    this.stepsSincePrev,
    this.state,
  });

  final double lat;
  final double lng;
  final String countryIso;
  final DateTime recordedAt;

  /// 이 점을 남긴 여행(서버 trip id).
  final int? tripId;

  /// 측위 정확도(m).
  final double? accuracyM;

  /// 직전 점 이후 걸음 수.
  final int? stepsSincePrev;

  /// 측위 때 수집 정책의 상태(`unknown`·`walking`·`still`·`otherMotion`·`vehicle`). 복원 API의 state와 같은 이름이다.
  final String? state;
}
```

`app/lib/core/db/app_database.dart`의 import에서 다음 부분을

```dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

다음으로 바꾼다:

```dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footstep_core/footstep_core.dart' show TimeSpan;
```

같은 파일에서 RoutePoints 표와 DB 클래스 머리(스키마 버전·마이그레이션)를 바꾼다. 다음 부분을

```dart
@DataClassName('RoutePointRow')
class RoutePoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  TextColumn get countryIso => text().withLength(min: 2, max: 2)();
  DateTimeColumn get recordedAt => dateTime()();
}

@DriftDatabase(tables: [Checkins, DailySteps, RoutePoints])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 테스트에서 인메모리 DB를 주입하기 위한 생성자.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(routePoints);
          }
        },
      );
```

다음으로 바꾼다:

```dart
@DataClassName('RoutePointRow')
class RoutePoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  TextColumn get countryIso => text().withLength(min: 2, max: 2)();
  DateTimeColumn get recordedAt => dateTime()();

  // 여행 기록(설계 2026-11-07 9-3, 스키마 3). 실시간 경로·해외 매핑이 남긴 기존 행은 모두 null이라
  // 세계지도·국가 지도는 이 열을 몰라도 그대로 동작한다.
  IntColumn get tripId => integer().nullable()();
  RealColumn get accuracyM => real().nullable()();
  IntColumn get stepsSincePrev => integer().nullable()();
  TextColumn get state => text().nullable()();
}

/// 여행 기록 중 걸음 감지기가 정지였던 구간(스키마 3). 날짜별 보기의 머문 곳 묶기가 도착·출발 시각을 이 구간으로
/// 잡는다(설계 5-6 제안 방식). RoutePoints의 state만으로는 정지가 언제 시작·끝났는지 모른다.
@DataClassName('TripStillSpanRow')
class TripStillSpans extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tripId => integer()();
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime()();
}

@DriftDatabase(tables: [Checkins, DailySteps, RoutePoints, TripStillSpans])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 테스트에서 인메모리 DB를 주입하기 위한 생성자.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // 지금 정의(스키마 3의 여행 열 포함)로 만든다 — 아래 열 추가는 하지 않는다.
            await m.createTable(routePoints);
          } else if (from < 3) {
            await m.addColumn(routePoints, routePoints.tripId);
            await m.addColumn(routePoints, routePoints.accuracyM);
            await m.addColumn(routePoints, routePoints.stepsSincePrev);
            await m.addColumn(routePoints, routePoints.state);
          }
          if (from < 3) {
            await m.createTable(tripStillSpans);
          }
        },
      );
```

`routePointsForCountry` 뒤에 여행 기록 메서드를 더한다. 다음 부분을

```dart
  Future<List<RoutePoint>> routePointsForCountry(String iso) async {
    final rows = await (select(routePoints)
          ..where((t) => t.countryIso.equals(iso))
          ..orderBy([(t) => OrderingTerm.asc(t.recordedAt)]))
        .get();
    return rows.map(_toDomainRoutePoint).toList();
  }
```

다음으로 바꾼다:

```dart
  Future<List<RoutePoint>> routePointsForCountry(String iso) async {
    final rows = await (select(routePoints)
          ..where((t) => t.countryIso.equals(iso))
          ..orderBy([(t) => OrderingTerm.asc(t.recordedAt)]))
        .get();
    return rows.map(_toDomainRoutePoint).toList();
  }

  /// 여행 기록 서비스가 측위 결과 하나를 남긴다(설계 9-3). 기록 좌표는 폰에만 둔다.
  Future<int> insertTripPoint({
    required int tripId,
    required double lat,
    required double lng,
    required String countryIso,
    required DateTime recordedAt,
    double? accuracyM,
    int? stepsSincePrev,
    String? state,
  }) {
    return into(routePoints).insert(RoutePointsCompanion.insert(
      lat: lat,
      lng: lng,
      countryIso: countryIso,
      recordedAt: recordedAt,
      tripId: Value(tripId),
      accuracyM: Value(accuracyM),
      stepsSincePrev: Value(stepsSincePrev),
      state: Value(state),
    ));
  }

  /// 한 여행이 남긴 점(시각순). 날짜별 보기가 기기 현지 날짜로 다시 묶는다.
  Future<List<RoutePoint>> routePointsForTrip(int tripId) async {
    final rows = await (select(routePoints)
          ..where((t) => t.tripId.equals(tripId))
          ..orderBy([(t) => OrderingTerm.asc(t.recordedAt), (t) => OrderingTerm.asc(t.id)]))
        .get();
    return rows.map(_toDomainRoutePoint).toList();
  }

  Future<int> insertTripStillSpan({
    required int tripId,
    required DateTime startAt,
    required DateTime endAt,
  }) {
    return into(tripStillSpans).insert(
      TripStillSpansCompanion.insert(tripId: tripId, startAt: startAt, endAt: endAt),
    );
  }

  /// 한 여행의 정지 구간(시작 시각순). footstep_core의 머문 곳 묶기(detectStays)에 그대로 넘긴다.
  Future<List<TimeSpan>> stillSpansForTrip(int tripId) async {
    final rows = await (select(tripStillSpans)
          ..where((t) => t.tripId.equals(tripId))
          ..orderBy([(t) => OrderingTerm.asc(t.startAt)]))
        .get();
    return [
      for (final row in rows)
        TimeSpan(row.startAt.millisecondsSinceEpoch, row.endAt.millisecondsSinceEpoch),
    ];
  }

  /// 지운 여행의 좌표·정지 구간을 지운다(설계 9-3). 여행에 속하지 않은 기존 점(tripId null)은 건드리지 않는다.
  Future<void> deleteTripRecords(Iterable<int> tripIds) async {
    final ids = tripIds.toList();
    if (ids.isEmpty) return;
    await transaction(() async {
      await (delete(routePoints)..where((t) => t.tripId.isIn(ids))).go();
      await (delete(tripStillSpans)..where((t) => t.tripId.isIn(ids))).go();
    });
  }

  /// [keep]에 없는 여행의 기록을 모두 지운다(서버 목록에서 사라진 여행, 계정 전환). [keep]이 비면 여행 기록 전부다.
  Future<void> deleteTripRecordsExcept(Set<int> keep) async {
    final ids = keep.toList();
    await transaction(() async {
      await (delete(routePoints)
            ..where((t) => t.tripId.isNotNull() & t.tripId.isNotIn(ids)))
          .go();
      await (delete(tripStillSpans)..where((t) => t.tripId.isNotIn(ids))).go();
    });
  }
```

`app/lib/core/db/app_database.dart`에서 다음 부분을

```dart
  RoutePoint _toDomainRoutePoint(RoutePointRow row) => RoutePoint(
        lat: row.lat,
        lng: row.lng,
        countryIso: row.countryIso,
        recordedAt: row.recordedAt,
      );
```

다음으로 바꾼다:

```dart
  RoutePoint _toDomainRoutePoint(RoutePointRow row) => RoutePoint(
        lat: row.lat,
        lng: row.lng,
        countryIso: row.countryIso,
        recordedAt: row.recordedAt,
        tripId: row.tripId,
        accuracyM: row.accuracyM,
        stepsSincePrev: row.stepsSincePrev,
        state: row.state,
      );
```

`app/lib/core/db/app_database.dart`에서 다음 부분을

```dart
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = p.join(dbFolder.path, 'travelfootsteps.sqlite');
    return NativeDatabase.createInBackground(File(file));
  });
}
```

다음으로 바꾼다:

```dart
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = p.join(dbFolder.path, 'travelfootsteps.sqlite');
    // 화면·WorkManager·여행 기록 서비스(R7)가 각자의 isolate에서 같은 파일을 연다. 다른 연결이 쓰는 중이면
    // 바로 'database is locked'로 실패하지 않고 5초까지 기다리게 한다.
    return NativeDatabase.createInBackground(
      File(file),
      setup: (database) => database.execute('PRAGMA busy_timeout = 5000;'),
    );
  });
}
```

코드를 다시 만든다(`app/`에서, 약 2분):

```bash
dart run build_runner build --delete-conflicting-outputs --force-jit
git status --short app/lib
```

`app_database.g.dart`가 바뀐다(`$TripStillSpansTable`, RoutePoints의 새 열). `wallet_database.g.dart`가 줄바꿈만 바뀌어 보이면 `git checkout -- app/lib/features/wallet/data/wallet_database.g.dart`로 되돌린다.

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/db/app_database_test.dart` → 통과(11개). `flutter test`(전체) → 통과(732개). `dart analyze lib test` → 0건.

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/footsteps/data/route_point.dart app/lib/core/db/app_database.dart \
  app/lib/core/db/app_database.g.dart app/test/db/app_database_test.dart
git commit -m "feat(app): RoutePoints에 여행 기록 열을 더하고 걸음 감지기 정지 구간 표를 만든다(스키마 3)"
```

---

### Task 3: 앱 — 여행 기간 판단 `shouldRecord`와 isolate가 함께 보는 여행 기록 저장소

설계 9-2의 판단 로직이다. `shouldRecord(trips, now, pausedTripIds)`는 순수 함수다. 기록 기간은 [출발일 0시, 귀국일 다음 날 0시)(기기 현지 시각)이다. 여행이 겹치면 가장 늦게 출발한 여행을, 출발일까지 같으면 id가 큰(나중에 만든) 여행을 고른다 — 점 하나는 한 여행에만 속하기 때문이다.

화면·기록 서비스·WorkManager가 서로 다른 isolate에서 같은 일정·일시정지를 봐야 한다. 그래서 SharedPreferences에 JSON 문자열로 두고, 백그라운드 isolate는 읽기 전에 `reload`한다(Dart 쪽 값은 isolate마다 따로 들고 있다).

**Files:**
- Create: `app/lib/features/footsteps/trip/trip_period.dart`
- Create: `app/lib/features/footsteps/trip/trip_recording_store.dart`
- Create: `app/test/footsteps/trip/trip_fakes.dart`(테스트 도우미 — Task 4~6에서 늘린다)
- Test: `app/test/footsteps/trip/trip_period_test.dart`, `app/test/footsteps/trip/trip_recording_store_test.dart`

**Interfaces:**
- Consumes: `TripSummary`(여행 목록 한 줄)
- Produces
  - `TripPeriod({tripId, countryIso2, countryNameKo, departDate, returnDate})`
    - `TripPeriod.fromSummary(TripSummary)`, `startsAt`, `endsAt`, `bool covers(DateTime now)`
    - `toJson`·`fromJson`(날짜는 `yyyy-MM-dd`), 값 비교
  - `TripPeriod? shouldRecord(List<TripPeriod> trips, DateTime now, Set<int> pausedTripIds)`
  - `TripRecordingStore(SharedPreferences)`
    - 키: `tripsKey`·`pausedKey`·`ownerKey`·`noticesKey`
    - 일정: `reload()`, `readTrips()`, `replaceTrips(List<TripPeriod>)`(목록에 없는 여행의 일시정지도 지운다), `forget(Set<int>)`, `clearSchedule()`
    - 일시정지: `readPaused()`, `setPaused(int, bool)`
    - 주인: `readOwner()`, `writeOwner(String)`
    - 출발일 알림 기록: `readNoticeTripIds()`, `writeNoticeTripIds(Set<int>)`
  - 테스트 도우미 `period(int id, DateTime depart, DateTime ret, {String iso2 = 'KR', String nameKo = '대한민국'})`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/footsteps/trip/trip_fakes.dart`:

```dart
import 'package:app/features/footsteps/trip/trip_period.dart';

/// 테스트용 여행 기간. 날짜는 시각 없는 달력 날짜로 준다.
TripPeriod period(int id, DateTime depart, DateTime ret, {String iso2 = 'KR', String nameKo = '대한민국'}) =>
    TripPeriod(tripId: id, countryIso2: iso2, countryNameKo: nameKo, departDate: depart, returnDate: ret);
```

`app/test/footsteps/trip/trip_period_test.dart`:

```dart
import 'package:app/features/footsteps/trip/trip_period.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../visa/fake_trip_api.dart' show sampleSummary;
import 'trip_fakes.dart';

void main() {
  // 11/20 출발, 11/22 귀국 여행. 기록 기간은 11/20 0시 ~ 11/23 0시(기기 현지 시각)다.
  final trip = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));

  group('기록 기간의 날짜 경계', () {
    test('출발일 0시부터 기록한다(전날 23:59는 아니다)', () {
      expect(trip.covers(DateTime(2026, 11, 20)), isTrue);
      expect(trip.covers(DateTime(2026, 11, 19, 23, 59, 59)), isFalse);
    });

    test('귀국일 23:59까지 기록하고 다음 날 0시에 끝난다', () {
      expect(trip.covers(DateTime(2026, 11, 22, 23, 59, 59)), isTrue);
      expect(trip.covers(DateTime(2026, 11, 23)), isFalse);
    });

    test('귀국일이 달의 마지막 날이어도 다음 달 1일 0시에 끝난다', () {
      final monthEnd = period(1, DateTime(2026, 11, 29), DateTime(2026, 11, 30));
      expect(monthEnd.endsAt, DateTime(2026, 12, 1));
      expect(monthEnd.covers(DateTime(2026, 11, 30, 23, 59)), isTrue);
      expect(monthEnd.covers(DateTime(2026, 12, 1)), isFalse);
    });

    test('UTC로 준 시각도 같은 순간으로 비교한다', () {
      expect(trip.covers(DateTime(2026, 11, 20, 0, 0, 1).toUtc()), isTrue);
    });
  });

  group('shouldRecord', () {
    test('기간 안의 여행을 고르고, 기간 밖이면 null이다', () {
      expect(shouldRecord([trip], DateTime(2026, 11, 21, 15), const {}), trip);
      expect(shouldRecord([trip], DateTime(2026, 11, 23), const {}), isNull);
      expect(shouldRecord(const [], DateTime(2026, 11, 21), const {}), isNull);
    });

    test('일시정지한 여행은 기간 안이어도 기록하지 않는다', () {
      expect(shouldRecord([trip], DateTime(2026, 11, 21), {7}), isNull);
    });

    test('여행이 겹치면 나중에 출발한 여행을 기록한다', () {
      final long = period(3, DateTime(2026, 11, 18), DateTime(2026, 11, 25));

      expect(shouldRecord([trip, long], DateTime(2026, 11, 19), const {})?.tripId, 3);
      expect(shouldRecord([long, trip], DateTime(2026, 11, 21), const {})?.tripId, 7);
      // 나중 여행을 일시정지하면 겹친 다른 여행을 기록한다.
      expect(shouldRecord([long, trip], DateTime(2026, 11, 21), {7})?.tripId, 3);
    });

    test('출발일까지 같으면 나중에 만든(id가 큰) 여행이다', () {
      final twin = period(9, DateTime(2026, 11, 20), DateTime(2026, 11, 21));
      expect(shouldRecord([twin, trip], DateTime(2026, 11, 20, 8), const {})?.tripId, 9);
    });
  });

  test('여행 목록 한 줄에서 날짜만 뽑고 JSON으로 그대로 되읽힌다', () {
    final fromSummary = TripPeriod.fromSummary(sampleSummary(
      id: 5,
      iso2: 'JP',
      nameKo: '일본',
      depart: DateTime(2026, 12, 20, 13, 5),
      ret: DateTime(2027, 1, 9),
    ));

    expect(fromSummary.departDate, DateTime(2026, 12, 20));
    expect(fromSummary.toJson(), {
      'tripId': 5,
      'countryIso2': 'JP',
      'countryNameKo': '일본',
      'departDate': '2026-12-20',
      'returnDate': '2027-01-09',
    });
    expect(TripPeriod.fromJson(fromSummary.toJson()), fromSummary);
  });
}
```

`app/test/footsteps/trip/trip_recording_store_test.dart`:

```dart
import 'dart:convert';

import 'package:app/features/footsteps/trip/trip_recording_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'trip_fakes.dart';

Future<(TripRecordingStore, SharedPreferences)> _store([Map<String, Object> stored = const {}]) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  return (TripRecordingStore(prefs), prefs);
}

void main() {
  final a = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));
  final b = period(8, DateTime(2026, 12, 1), DateTime(2026, 12, 5));

  test('일정을 통째로 바꾸고 되읽는다', () async {
    final (store, _) = await _store();
    expect(store.readTrips(), isEmpty);

    await store.replaceTrips([a, b]);

    expect(store.readTrips(), [a, b]);
  });

  test('깨진 값은 없는 것으로 본다', () async {
    final (store, _) = await _store({
      TripRecordingStore.tripsKey: '{oops',
      TripRecordingStore.pausedKey: '[1, "x"]',
    });

    expect(store.readTrips(), isEmpty);
    expect(store.readPaused(), isEmpty);
  });

  test('일시정지는 여행별로 켜고 끈다', () async {
    final (store, _) = await _store();

    await store.setPaused(7, true);
    await store.setPaused(8, true);
    await store.setPaused(7, false);

    expect(store.readPaused(), {8});
  });

  test('일정을 바꾸면 목록에 없는 여행의 일시정지는 지운다', () async {
    final (store, _) = await _store();
    await store.setPaused(7, true);
    await store.setPaused(8, true);

    await store.replaceTrips([b]);

    expect(store.readPaused(), {8});
  });

  test('없어진 여행은 일정과 일시정지에서 빠진다', () async {
    final (store, _) = await _store();
    await store.replaceTrips([a, b]);
    await store.setPaused(7, true);

    await store.forget({7});

    expect(store.readTrips(), [b]);
    expect(store.readPaused(), isEmpty);
  });

  test('일정을 비워도 주인과 출발 알림 기록은 남는다', () async {
    final (store, _) = await _store();
    await store.replaceTrips([a]);
    await store.setPaused(7, true);
    await store.writeOwner('uid-a');
    await store.writeNoticeTripIds({7});

    await store.clearSchedule();

    expect(store.readTrips(), isEmpty);
    expect(store.readPaused(), isEmpty);
    expect(store.readOwner(), 'uid-a');
    expect(store.readNoticeTripIds(), {7});
  });

  test('다른 isolate가 쓴 값은 reload한 뒤에 보인다', () async {
    final (store, _) = await _store();
    expect(store.readTrips(), isEmpty);

    // 화면 isolate가 일정을 쓴 상황을 흉내 낸다(같은 Android 저장소, 다른 Dart 캐시).
    SharedPreferences.setMockInitialValues({
      TripRecordingStore.tripsKey: jsonEncode([a.toJson()]),
    });
    expect(store.readTrips(), isEmpty);

    await store.reload();
    expect(store.readTrips(), [a]);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run(`app/`에서): `flutter test test/footsteps/trip/`

Expected: FAIL. `trip_period.dart`·`trip_recording_store.dart`가 없다.

- [ ] **Step 3: 구현**

`app/lib/features/footsteps/trip/trip_period.dart`:

```dart
import '../../visa/models/trip_summary.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// `yyyy-MM-dd`. intl 대신 직접 만든다 — 기록 서비스·WorkManager isolate에서도 읽고 쓴다.
String _wireDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 여행 기록이 알아야 하는 여행 정보(설계 2026-11-07 9-2). 여행 목록의 한 줄에서 뽑아, 화면·기록 서비스·WorkManager가
/// 함께 보는 저장소(TripRecordingStore)에 둔다. 날짜는 시각 없는 달력 날짜다.
class TripPeriod {
  const TripPeriod({
    required this.tripId,
    required this.countryIso2,
    required this.countryNameKo,
    required this.departDate,
    required this.returnDate,
  });

  factory TripPeriod.fromSummary(TripSummary trip) => TripPeriod(
        tripId: trip.id,
        countryIso2: trip.countryIso2,
        countryNameKo: trip.countryNameKo,
        departDate: _dateOnly(trip.departDate),
        returnDate: _dateOnly(trip.returnDate),
      );

  final int tripId;
  final String countryIso2;

  /// 출발일 알림 문구("오늘부터 ○○ 여행 발걸음을 기록합니다.")와 기록 알림에 쓴다.
  final String countryNameKo;
  final DateTime departDate;
  final DateTime returnDate;

  /// 기록을 시작하는 순간: 출발일 0시(기기 현지 시각).
  DateTime get startsAt => DateTime(departDate.year, departDate.month, departDate.day);

  /// 기록을 끝내는 순간: 귀국일 다음 날 0시(기기 현지 시각). DateTime이 달·해 넘김을 알아서 맞춘다.
  DateTime get endsAt => DateTime(returnDate.year, returnDate.month, returnDate.day + 1);

  /// [now]가 기록 기간 [출발일 0시, 귀국일 다음 날 0시) 안인가.
  bool covers(DateTime now) => !now.isBefore(startsAt) && now.isBefore(endsAt);

  Map<String, Object?> toJson() => {
        'tripId': tripId,
        'countryIso2': countryIso2,
        'countryNameKo': countryNameKo,
        'departDate': _wireDate(departDate),
        'returnDate': _wireDate(returnDate),
      };

  factory TripPeriod.fromJson(Map<String, Object?> json) => TripPeriod(
        tripId: json['tripId'] as int,
        countryIso2: json['countryIso2'] as String,
        countryNameKo: json['countryNameKo'] as String,
        departDate: DateTime.parse(json['departDate'] as String),
        returnDate: DateTime.parse(json['returnDate'] as String),
      );

  @override
  bool operator ==(Object other) =>
      other is TripPeriod &&
      other.tripId == tripId &&
      other.countryIso2 == countryIso2 &&
      other.countryNameKo == countryNameKo &&
      other.departDate == departDate &&
      other.returnDate == returnDate;

  @override
  int get hashCode => Object.hash(tripId, countryIso2, countryNameKo, departDate, returnDate);

  @override
  String toString() => 'TripPeriod($tripId $countryIso2 ${_wireDate(departDate)}~${_wireDate(returnDate)})';
}

/// 지금 기록할 여행(설계 9-2의 판단 로직). 없으면 null이다.
///
/// 기간 [출발일 0시, 귀국일 다음 날 0시) 안이고 일시정지하지 않은 여행 중 가장 늦게 출발한 것을 고른다 — 여행이
/// 겹치면 새로 시작한 여행이 지금의 여행이다. 출발일까지 같으면 id가 큰(나중에 만든) 여행이다. 점 하나는 한 여행에만
/// 속하므로(RoutePoints.trip_id) 하나만 고른다.
TripPeriod? shouldRecord(List<TripPeriod> trips, DateTime now, Set<int> pausedTripIds) {
  TripPeriod? best;
  for (final trip in trips) {
    if (pausedTripIds.contains(trip.tripId) || !trip.covers(now)) continue;
    final current = best;
    if (current == null ||
        trip.departDate.isAfter(current.departDate) ||
        (trip.departDate == current.departDate && trip.tripId > current.tripId)) {
      best = trip;
    }
  }
  return best;
}
```

`app/lib/features/footsteps/trip/trip_recording_store.dart`:

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'trip_period.dart';

/// 여행 기록 상태(설계 2026-11-07 9-2). 화면·기록 서비스·WorkManager가 서로 다른 isolate에서 같이 읽는다.
/// 셋 다 같은 Android SharedPreferences를 보지만 Dart 쪽 값은 isolate마다 따로 들고 있으므로, 다른 isolate가 쓴 값을
/// 보려면 읽기 전에 [reload]해야 한다. 값은 모두 JSON 문자열 하나씩이고, 깨진 값은 없는 것으로 본다.
///
/// - 일정: 마지막으로 서버에서 받은 내 여행 목록(기록할 여행을 고르는 재료)
/// - 일시정지: 사용자가 여행 상세에서 멈춘 여행 id(여행별)
/// - 주인: 여행 기록을 남긴 계정 uid. 다른 계정이 로그인하면 이전 계정의 기록을 지우는 기준이다(PR #32의 알람 주인과 같은 방식)
/// - 출발 알림: 출발일 아침 알림을 예약해 둔 여행 id(예약을 지울 때 쓴다)
class TripRecordingStore {
  TripRecordingStore(this._prefs);

  final SharedPreferences _prefs;

  static const tripsKey = 'trip_recording.trips.v1';
  static const pausedKey = 'trip_recording.paused.v1';
  static const ownerKey = 'trip_recording.owner.v1';
  static const noticesKey = 'trip_recording.notices.v1';

  /// 다른 isolate가 쓴 값을 다시 읽어 온다.
  Future<void> reload() => _prefs.reload();

  List<TripPeriod> readTrips() {
    final raw = _prefs.getString(tripsKey);
    if (raw == null) return const [];
    try {
      return [
        for (final e in jsonDecode(raw) as List) TripPeriod.fromJson((e as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 일정을 [trips]로 바꾼다. 목록에 없는 여행의 일시정지도 함께 지운다 — 일정이 곧 지금 있는 여행이다.
  Future<void> replaceTrips(List<TripPeriod> trips) async {
    await _prefs.setString(tripsKey, jsonEncode([for (final t in trips) t.toJson()]));
    final ids = {for (final t in trips) t.tripId};
    final paused = readPaused();
    if (paused.any((id) => !ids.contains(id))) {
      await _writeIds(pausedKey, paused.where(ids.contains).toSet());
    }
  }

  Set<int> readPaused() => _readIds(pausedKey);

  Future<void> setPaused(int tripId, bool paused) {
    final ids = readPaused();
    paused ? ids.add(tripId) : ids.remove(tripId);
    return _writeIds(pausedKey, ids);
  }

  /// 없어진 여행을 일정·일시정지에서 뺀다.
  Future<void> forget(Set<int> tripIds) async {
    await _prefs.setString(
      tripsKey,
      jsonEncode([for (final t in readTrips()) if (!tripIds.contains(t.tripId)) t.toJson()]),
    );
    await _writeIds(pausedKey, readPaused()..removeAll(tripIds));
  }

  /// 일정·일시정지를 비운다(로그아웃·계정 전환). 주인과 출발 알림 기록은 부르는 쪽이 다룬다.
  Future<void> clearSchedule() async {
    await _prefs.remove(tripsKey);
    await _prefs.remove(pausedKey);
  }

  String? readOwner() => _prefs.getString(ownerKey);

  Future<void> writeOwner(String uid) => _prefs.setString(ownerKey, uid);

  Set<int> readNoticeTripIds() => _readIds(noticesKey);

  Future<void> writeNoticeTripIds(Set<int> tripIds) => _writeIds(noticesKey, tripIds);

  Set<int> _readIds(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return <int>{};
    try {
      return {for (final e in jsonDecode(raw) as List) e as int};
    } catch (_) {
      return <int>{};
    }
  }

  Future<void> _writeIds(String key, Set<int> ids) =>
      ids.isEmpty ? _prefs.remove(key) : _prefs.setString(key, jsonEncode(ids.toList()..sort()));
}
```

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/footsteps/trip/` → 통과(16개). `flutter test`(전체) → 통과(748개). `dart analyze lib test` → 0건.

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/footsteps/trip/trip_period.dart app/lib/features/footsteps/trip/trip_recording_store.dart \
  app/test/footsteps/trip/trip_fakes.dart app/test/footsteps/trip/trip_period_test.dart \
  app/test/footsteps/trip/trip_recording_store_test.dart
git commit -m "feat(app): 여행 기간 판단 shouldRecord와 isolate가 함께 보는 여행 기록 저장소를 더한다"
```

---

### Task 4: 기록 서비스에 여행 기록(`trip`) 모드를 붙인다

설계 4-1의 세 번째 모드다. 실험 모드(정답 기록·정책 실행)와 같은 Android 포그라운드 서비스·알림 채널을 쓰되, TaskHandler만 `TripRecordingTaskHandler`로 바꿔 붙인다. 세션 파일을 쓰지 않고 앱 DB에 쓰기 때문이다.

- `TripRecorder`: R4의 `PolicyRunner`로 제안 정책을 돌린다(설계 5-5 "R7 여행 기록이 같은 실행기를 쓴다").
  - 위치는 RoutePoints에 쓴다.
  - 걸음 감지기의 정지 구간은 `TripStillSpans`에 쓴다. 재생기와 같은 규칙(첫 분류 포함, 상태가 바뀐 순간)으로 잡으려고 `PolicyRunner`에 `onStepUpdate` 콜백을 더한다. 감지기를 감싸면 실행기의 `detector is OsStepDetector` 검사가 깨지므로 감싸지 않는다.
- `TripRecordingSession`: 언제 끝낼지 정한다. 5초 tick마다 날짜를 보고 1분마다 저장소를 다시 읽는다. 플러그인을 부르지 않아 시간을 손으로 넘겨 시험한다.
- `TripRecordingTaskHandler`: 플러그인을 이어 붙이기만 하는 얇은 껍데기다. 실기기에서만 확인한다(Task 10).
- `TripRecordingService`: 화면 isolate가 서비스를 켜고 끄는 창구다.
- 실험 화면은 여행 기록이 돌고 있으면 안내만 하고, 모드 선택은 기본값으로 둔다. 그대로 두면 [기록 종료] 뒤 [기록 시작]이 여행 기록 모드로 실험을 켜려 한다.

**Files:**
- Modify: `packages/footstep_core/lib/src/runner/policy_runner.dart`(`onStepUpdate`)
- Test: `packages/footstep_core/test/runner/policy_runner_test.dart`
- Modify: `app/lib/features/footsteps/recording/recording_mode.dart`, `recording_config.dart`(전체 교체)
- Modify: `app/lib/features/footsteps/recording/recording_task_handler.dart`, `session_recorder_factory.dart`, `recording_controller.dart`
- Create: `app/lib/features/footsteps/trip/trip_recorder.dart`, `trip_recording_session.dart`, `trip_recording_task_handler.dart`, `trip_recording_service.dart`
- Modify: `app/lib/features/footsteps/lab/lab_page.dart`
- Modify: `app/test/footsteps/trip/trip_fakes.dart`(전체 교체)
- Test: `app/test/footsteps/trip/trip_recorder_test.dart`, `trip_recording_session_test.dart`, `app/test/footsteps/lab/lab_page_test.dart`

**Interfaces:**
- Consumes
  - Task 2: `AppDatabase.insertTripPoint`·`insertTripStillSpan`
  - Task 3: `TripPeriod`, `TripRecordingStore`
  - R4: `PolicyRunner`, `PolicySensorNeeds`, `PluginSensorSources`, `GeolocatorLocationPort`, `TimerWakeScheduler`, `createPolicy`·`createDetector`
- Produces
  - footstep_core
    - `PolicyRunner({..., void Function(StepUpdate update)? onStepUpdate})`
    - 걸음 감지기의 `StepUpdate`를 정책에 넘기기 직전에 부른다. 오류는 `onError`로 알리고 정책 전달은 계속한다.
  - 기록 모드·설정
    - `RecordingMode.trip`
    - `RecordingConfig({required mode, String? sessionDir, String? carryInitial, String? note, PolicyChoice? policy, TripPeriod? trip})`
    - `recordingServiceId`(7101), `initRecordingService()`(실험·여행 기록 공용)
  - 여행 기록기
    - `const tripPolicyChoice = PolicyChoice(policyId: 'step_budget', policyParams: {'e_m': '50'}, detectorId: 'adaptive')`
    - `TripRecorder({trip, db, sources, clock, countryOf, policy, detector, location, scheduler, needs, onError, batteryInterval = 1분})`
    - 메서드: `start()`, `tick()`, `stop()`(열린 정지 구간을 닫고 남은 쓰기를 마친다)
  - 세션: `TripRecordingSession({trip, openRecorder, stillWanted, clock, checkEvery = 1분})`
    - `Future<bool> start()`, `Future<bool> tick()`: false면 서비스를 끈다
    - `stop()`
  - 서비스
    - `tripRecordingStartCallback()`(top-level), `TripRecordingTaskHandler`
    - `abstract interface class TripRecordingService { isRunning(); recordingTripId(); start(TripPeriod); stop(); }`
    - 구현: `ForegroundTripRecordingService`
  - 테스트 도우미(`trip_fakes.dart`): `FakeTripSensors`, `FakeTripLocation`, `FakeTripScheduler`, `settle()`

- [ ] **Step 1: 실패하는 테스트 작성**

패키지 — `packages/footstep_core/test/runner/policy_runner_test.dart`에 테스트 하나를 더한다.

`packages/footstep_core/test/runner/policy_runner_test.dart`에서 다음 부분을

```dart
  test('가속도 없이 도는 OS 센서판 감지기는 시계를 넘겨 받아야 멈춘 뒤 정지로 바뀐다', () {
```

다음으로 바꾼다:

```dart
  test('걸음 감지기의 StepUpdate를 정책보다 먼저 onStepUpdate로 알리고, 그 오류로 수집을 멈추지 않는다', () {
    final policy = _Scripted();
    final seen = <String>[];
    final r = PolicyRunner(
      policy: policy,
      detector: OsStepDetector(),
      location: location,
      scheduler: scheduler,
      clock: () => now,
      sink: sink,
      onError: (error, _) => errors.add(error),
      onStepUpdate: (update) {
        seen.add('${update.tMs}:${update.state.name}:${policy.events.length}');
        throw StateError('기록 실패');
      },
    )..start();

    r.addOsStep(const OsStepReading(tMs: 100, kind: OsStepReading.count, value: '100'));
    r.addOsStep(const OsStepReading(tMs: 1000, kind: OsStepReading.count, value: '112'));

    // 첫 읽기는 기준값이라 정지로 처음 분류하고, 늘어난 둘째 읽기에서 보행이 된다. 둘 다 정책이 받기 전(받은 사건 수
    // 0, 1)에 알렸고, 오류가 나도 정책은 두 사건을 다 받았다.
    expect(seen, ['100:still:0', '1000:walking:1']);
    expect(policy.events.whereType<StepUpdate>(), hasLength(2));
    expect(errors, hasLength(2));
  });

  test('가속도 없이 도는 OS 센서판 감지기는 시계를 넘겨 받아야 멈춘 뒤 정지로 바뀐다', () {
```

앱 — 테스트 도우미를 늘리고(Task 3의 `period`는 그대로), 기록기·세션·실험 화면 테스트를 쓴다.

`app/test/footsteps/trip/trip_fakes.dart` 전체를 다음으로 바꾼다:

```dart
import 'dart:async';

import 'package:app/features/footsteps/recording/sensor_samples.dart';
import 'package:app/features/footsteps/trip/trip_period.dart';
import 'package:footstep_core/footstep_core.dart';

/// 테스트용 여행 기간. 날짜는 시각 없는 달력 날짜로 준다.
TripPeriod period(int id, DateTime depart, DateTime ret, {String iso2 = 'KR', String nameKo = '대한민국'}) =>
    TripPeriod(tripId: id, countryIso2: iso2, countryNameKo: nameKo, departDate: depart, returnDate: ret);

/// 기록기에 넣을 센서 대역. 스트림에 직접 값을 흘리고, 배터리 읽기 횟수를 센다.
class FakeTripSensors implements SensorSources {
  FakeTripSensors(this.clock);

  final DateTime Function() clock;
  final accelController = StreamController<AccelSample>.broadcast();
  final stepsController = StreamController<OsStepSample>.broadcast();
  int batteryLevel = 80;
  int batteryReads = 0;

  @override
  Stream<GpsSample> gps() => const Stream.empty();

  @override
  Stream<AccelSample> accel() => accelController.stream;

  @override
  Stream<OsStepSample> osSteps() => stepsController.stream;

  @override
  Stream<ActivitySample> activity() => const Stream.empty();

  @override
  Future<BatterySample> readBattery() async {
    batteryReads++;
    return BatterySample(at: clock(), plugged: false, levelPct: batteryLevel);
  }

  void step(DateTime at, int total) =>
      stepsController.add(OsStepSample(at: at, kind: OsStepKind.count, value: '$total'));
}

/// 위치 요청을 붙잡아 두는 GPS 대역. 테스트가 응답을 직접 채운다.
class FakeTripLocation implements LocationPort {
  final requests = <Completer<Fix?>>[];

  @override
  Future<Fix?> currentFix({required int timeoutMs}) {
    final completer = Completer<Fix?>();
    requests.add(completer);
    return completer.future;
  }

  @override
  Stream<Fix> continuousFixes({required int intervalMs, required double distanceFilterM}) => const Stream.empty();
}

/// 예약만 받아 두는 타이머 대역(이 테스트들은 깨우기를 부르지 않는다).
class FakeTripScheduler implements WakeScheduler {
  final scheduled = <Object>[];

  @override
  Object schedule(int atMs, void Function() callback) {
    final handle = Object();
    scheduled.add(handle);
    return handle;
  }

  @override
  void cancel(Object handle) => scheduled.remove(handle);
}

Future<void> settle() => Future<void>.delayed(Duration.zero);
```

`app/test/footsteps/trip/trip_recorder_test.dart`:

```dart
import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/recording/policy_choice.dart';
import 'package:app/features/footsteps/trip/trip_recorder.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footstep_core/footstep_core.dart';

import 'trip_fakes.dart';

void main() {
  late AppDatabase db;
  late DateTime now;
  late FakeTripSensors sensors;
  late FakeTripLocation location;
  late List<Object> errors;
  final trip = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));

  TripRecorder recorder({
    String policyId = 'step_budget',
    String detectorId = 'os',
    Future<String> Function(double lat, double lng)? countryOf,
  }) {
    final choice = PolicyChoice(policyId: policyId, detectorId: detectorId);
    return TripRecorder(
      trip: trip,
      db: db,
      sources: sensors,
      clock: () => now,
      countryOf: countryOf ?? (lat, lng) async => 'KR',
      policy: createPolicy(policyId),
      detector: createDetector(detectorId),
      location: location,
      scheduler: FakeTripScheduler(),
      needs: PolicySensorNeeds.of(choice),
      onError: errors.add,
    );
  }

  Fix fixAt(DateTime at, {double accuracyM = 6}) =>
      Fix(tMs: at.millisecondsSinceEpoch, lat: 37.55, lng: 126.97, accuracyM: accuracyM);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    now = DateTime.utc(2026, 11, 20, 1);
    sensors = FakeTripSensors(() => now);
    location = FakeTripLocation();
    errors = [];
  });

  tearDown(() => db.close());

  test('정책에 알린 위치를 여행 id·정확도·직전 점 이후 걸음 수·정책 상태와 함께 RoutePoints에 남긴다', () async {
    final r = recorder();
    await r.start();
    // step_budget은 시작하자마자 한 번 잰다. 응답을 기다리는 사이 12걸음을 걸어 정책 상태가 보행이 됐다.
    sensors.step(now, 100);
    sensors.step(now.add(const Duration(seconds: 8)), 112);
    await settle();

    now = now.add(const Duration(seconds: 10));
    location.requests.single.complete(fixAt(now, accuracyM: 7.5));
    await settle();
    await r.stop();

    final points = await db.routePointsForTrip(7);
    expect(points, hasLength(1));
    expect(points.single.countryIso, 'KR');
    expect(points.single.accuracyM, 7.5);
    expect(points.single.stepsSincePrev, 12);
    expect(points.single.state, 'walking');
    expect(points.single.recordedAt.toUtc(), DateTime.utc(2026, 11, 20, 1, 0, 10)); // drift는 현지 시각으로 돌려준다
    expect(errors, isEmpty);
  });

  test('국가를 모르거나 가리다 오류가 나면 여행의 나라로 남기고 기록은 계속한다', () async {
    var calls = 0;
    final r = recorder(
      policyId: 'fixed_1m',
      countryOf: (lat, lng) async {
        calls++;
        if (calls == 1) return 'XX';
        throw StateError('폴리곤 오류');
      },
    );
    await r.start();
    location.requests.last.complete(fixAt(now));
    await settle();
    // 1분 주기라 다음 요청은 깨우기 뒤에 온다 — 여기서는 첫 점만 본다.
    await r.stop();

    final points = await db.routePointsForTrip(7);
    expect(points.single.countryIso, 'KR');
    expect(errors, isEmpty);

    // 두 번째 기록기: 국가 판정이 오류를 내도 점은 남고 오류만 알린다.
    final second = recorder(
      policyId: 'fixed_1m',
      countryOf: (lat, lng) async => throw StateError('폴리곤 오류'),
    );
    await second.start();
    location.requests.last.complete(fixAt(now.add(const Duration(minutes: 1))));
    await settle();
    await second.stop();

    expect(await db.routePointsForTrip(7), hasLength(2));
    expect(errors.single, isA<StateError>());
  });

  test('걸음 감지기의 정지 구간을 남기고, 멈출 때 열린 정지 구간을 지금으로 닫는다', () async {
    final start = now;
    final r = recorder();
    await r.start();
    // OS 센서판: 첫 읽기는 기준값(정지로 첫 분류), 늘어나면 보행, 마지막 걸음 뒤 4초가 지나면 정지.
    sensors.step(start, 100);
    await settle();
    sensors.step(start.add(const Duration(seconds: 60)), 160);
    await settle();
    now = start.add(const Duration(seconds: 70));
    await r.tick(); // 시계를 넘겨 정지로 바꾼다
    now = start.add(const Duration(minutes: 20));
    await r.stop();

    final spans = await db.stillSpansForTrip(7);
    expect(spans, [
      TimeSpan(start.millisecondsSinceEpoch, start.add(const Duration(seconds: 60)).millisecondsSinceEpoch),
      TimeSpan(start.add(const Duration(seconds: 70)).millisecondsSinceEpoch,
          start.add(const Duration(minutes: 20)).millisecondsSinceEpoch),
    ]);
  });

  test('정책이 쓰는 센서만 켜고, 멈추면 끊는다', () async {
    final adaptive = recorder(detectorId: 'adaptive');
    await adaptive.start();
    expect(sensors.accelController.hasListener, isTrue);
    expect(sensors.stepsController.hasListener, isFalse);
    await adaptive.stop();
    expect(sensors.accelController.hasListener, isFalse);

    // 걸음 정보를 쓰지 않는 정책은 걸음 센서를 켜지 않는다.
    final fixed = recorder(policyId: 'fixed_5m');
    await fixed.start();
    expect(sensors.stepsController.hasListener, isFalse);
    expect(sensors.accelController.hasListener, isFalse);
    await fixed.stop();
  });

  test('배터리 잔량은 1분마다 읽는다(20% 미만이면 정책이 E를 키운다)', () async {
    final r = recorder();
    await r.start();
    expect(sensors.batteryReads, 1);

    now = now.add(const Duration(seconds: 30));
    await r.tick();
    expect(sensors.batteryReads, 1);

    now = now.add(const Duration(seconds: 30));
    await r.tick();
    expect(sensors.batteryReads, 2);
    await r.stop();
  });

  test('여행 기록은 제안 정책 step_budget(E=50m)로 돈다', () {
    expect(tripPolicyChoice.policyId, 'step_budget');
    expect(tripPolicyChoice.policyParams, {'e_m': '50'});
    expect(createPolicy(tripPolicyChoice.policyId, tripPolicyChoice.policyParams).params['e_m'], 50.0);
    expect(() => createDetector(tripPolicyChoice.detectorId), returnsNormally);
  });
}
```

`app/test/footsteps/trip/trip_recording_session_test.dart`:

```dart
import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/recording/policy_choice.dart';
import 'package:app/features/footsteps/trip/trip_recorder.dart';
import 'package:app/features/footsteps/trip/trip_recording_session.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footstep_core/footstep_core.dart';

import 'trip_fakes.dart';

void main() {
  late AppDatabase db;
  late DateTime now;
  late FakeTripSensors sensors;
  late bool wanted;
  late int wantedChecks;
  late int opened;
  final trip = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));

  TripRecordingSession session() => TripRecordingSession(
        trip: trip,
        clock: () => now,
        stillWanted: () async {
          wantedChecks++;
          return wanted;
        },
        openRecorder: () async {
          opened++;
          return TripRecorder(
            trip: trip,
            db: db,
            sources: sensors,
            clock: () => now.toUtc(),
            countryOf: (lat, lng) async => 'KR',
            policy: createPolicy('step_budget'),
            detector: createDetector('os'),
            location: FakeTripLocation(),
            scheduler: FakeTripScheduler(),
            needs: PolicySensorNeeds.of(const PolicyChoice(policyId: 'step_budget', detectorId: 'os')),
          );
        },
      );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    now = DateTime(2026, 11, 21, 9);
    sensors = FakeTripSensors(() => now.toUtc());
    wanted = true;
    wantedChecks = 0;
    opened = 0;
  });

  tearDown(() => db.close());

  test('여행 기간 안이고 일정에 남아 있으면 기록기를 켠다', () async {
    final s = session();

    expect(await s.start(), isTrue);
    expect(opened, 1);
    expect(sensors.stepsController.hasListener, isTrue);
    await s.stop();
    expect(sensors.stepsController.hasListener, isFalse);
  });

  test('이미 기간이 끝났거나 지워졌거나 일시정지면 켜지 않는다(서비스를 끈다)', () async {
    now = DateTime(2026, 11, 23); // 귀국 다음 날 0시
    expect(await session().start(), isFalse);

    now = DateTime(2026, 11, 21, 9);
    wanted = false;
    expect(await session().start(), isFalse);
    expect(opened, 0);
  });

  test('귀국일 다음 날 0시가 지나면 깰 때 스스로 끝낸다', () async {
    final s = session();
    await s.start();

    now = DateTime(2026, 11, 22, 23, 59, 55);
    expect(await s.tick(), isTrue);

    now = DateTime(2026, 11, 23, 0, 0, 0);
    expect(await s.tick(), isFalse);
    expect(sensors.stepsController.hasListener, isFalse); // 기록기를 멈췄다
    expect(await s.tick(), isFalse);
  });

  test('저장소는 1분마다 다시 읽고, 여행이 지워졌거나 일시정지면 끝낸다', () async {
    final s = session();
    await s.start();
    expect(wantedChecks, 1);

    now = now.add(const Duration(seconds: 55));
    expect(await s.tick(), isTrue);
    expect(wantedChecks, 1); // 아직 1분이 안 됐다

    wanted = false;
    now = now.add(const Duration(seconds: 5));
    expect(await s.tick(), isFalse);
    expect(wantedChecks, 2);
    expect(sensors.stepsController.hasListener, isFalse);
  });
}
```

`app/test/footsteps/lab/lab_page_test.dart`의 import에서 다음 부분을

```dart
import 'package:app/features/footsteps/recording/session_library.dart';
```

다음으로 바꾼다:

```dart
import 'package:app/features/footsteps/recording/session_library.dart';
import 'package:app/features/footsteps/trip/trip_period.dart';
```

같은 파일에서 다음 부분을

```dart
  testWidgets('서비스가 보낸 상태를 보여 준다', (tester) async {
```

다음으로 바꾼다:

```dart
  testWidgets('여행 기록 중에 열면 안내하고, 종료한 뒤 시작하면 여행 기록이 아니라 실험 모드로 켠다', (tester) async {
    final controller = FakeRecordingController()
      ..running = true
      ..config = RecordingConfig(
        mode: RecordingMode.trip,
        policy: const PolicyChoice(policyId: 'step_budget', detectorId: 'adaptive'),
        trip: TripPeriod(
          tripId: 7,
          countryIso2: 'KR',
          countryNameKo: '대한민국',
          departDate: DateTime(2026, 11, 20),
          returnDate: DateTime(2026, 11, 22),
        ),
      );
    await pumpLab(tester, controller);

    expect(find.byKey(const Key('lab-trip-recording')), findsOneWidget);
    final mode = tester.widget<SegmentedButton<RecordingMode>>(find.byKey(const Key('lab-mode')));
    expect(mode.selected, {RecordingMode.groundTruth});

    await tester.tap(find.byKey(const Key('lab-start-stop')));
    await tester.pumpAndSettle();
    expect(controller.stops, 1);
    expect(find.byKey(const Key('lab-trip-recording')), findsNothing);

    await tester.tap(find.byKey(const Key('lab-start-stop')));
    await tester.pumpAndSettle();
    expect(controller.starts.single.mode, RecordingMode.groundTruth);
  });

  testWidgets('서비스가 보낸 상태를 보여 준다', (tester) async {
```

- [ ] **Step 2: 실패 확인**

Run
- `packages/footstep_core/`에서 `dart test test/runner/policy_runner_test.dart`
- `app/`에서 `flutter test test/footsteps/trip/ test/footsteps/lab/`

Expected: FAIL.
- 패키지: `onStepUpdate`라는 이름이 없다.
- 앱: `trip_recorder.dart` 등이 없다. `RecordingConfig`에 `trip`이 없다.

- [ ] **Step 3: 구현**

패키지 — `packages/footstep_core/lib/src/runner/policy_runner.dart`:

생성자에서 다음 부분을

```dart
    required this.sink,
    this.onError,
    int accelBatchMs = 1000,
  }) : _batcher = AccelBatcher(accelBatchMs);
```

다음으로 바꾼다:

```dart
    required this.sink,
    this.onError,
    this.onStepUpdate,
    int accelBatchMs = 1000,
  }) : _batcher = AccelBatcher(accelBatchMs);
```

필드에서 다음 부분을

```dart
  /// 기록·정책·걸음 감지기·GPS에서 난 오류를 받는다(폰에서는 meta.json의 errors로 간다). 없으면 버린다.
  final void Function(Object error, StackTrace stack)? onError;
  final AccelBatcher _batcher;
```

다음으로 바꾼다:

```dart
  /// 기록·정책·걸음 감지기·GPS에서 난 오류를 받는다(폰에서는 meta.json의 errors로 간다). 없으면 버린다.
  final void Function(Object error, StackTrace stack)? onError;

  /// 걸음 감지기가 낸 StepUpdate를 정책에 넘기기 직전에 받는다. R7 여행 기록이 재생기와 같은 규칙(첫 분류 포함,
  /// 상태가 바뀐 순간)으로 정지 구간을 남기는 데 쓴다. 여기서 난 오류는 [onError]로 알리고 정책에는 그대로 넘긴다.
  final void Function(StepUpdate update)? onStepUpdate;
  final AccelBatcher _batcher;
```

`_deliverStep`의 다음 부분을

```dart
  void _deliverStep(StepUpdate? update) {
    if (update != null) _deliver(update);
  }
```

다음으로 바꾼다:

```dart
  void _deliverStep(StepUpdate? update) {
    if (update == null) return;
    final observer = onStepUpdate;
    if (observer != null) _safely(() => observer(update));
    _deliver(update);
  }
```

앱 — 기록 모드와 설정:

`app/lib/features/footsteps/recording/recording_mode.dart` 전체를 다음으로 바꾼다:

```dart
/// 기록 서비스 모드. 한 번에 하나만 돈다(설계 4-1) — 두 모드를 같이 돌리면 배터리 측정이 오염된다.
/// `groundTruth`는 모든 센서를 최대 빈도로 저장하고(R1), `policy`는 고른 정책 하나만 돌려 측위 결과와 배터리만
/// 저장한다(R4, 배터리 실험). `trip`은 여행 기간에 제안 정책을 돌려 앱 DB(RoutePoints)에 저장한다(R7). 실험 두 모드는
/// 실험 화면이 켜고(RecordingTaskHandler), 여행 기록은 앱이 포그라운드로 올 때 앱이 켠다(TripRecordingTaskHandler).
enum RecordingMode { groundTruth, policy, trip }

String _two(int n) => n.toString().padLeft(2, '0');

/// 세션 폴더 이름이자 세션 id. 폴더 목록만 보고도 언제 무슨 모드였는지 알 수 있게 기기 현지 시각을 쓴다.
/// intl 대신 직접 만든다 — 서비스 isolate에서는 화면 쪽 로케일 초기화가 되어 있지 않다.
String sessionDirName(DateTime startLocal, RecordingMode mode) {
  final t = startLocal;
  return '${t.year}${_two(t.month)}${_two(t.day)}-${_two(t.hour)}${_two(t.minute)}${_two(t.second)}'
      '-${mode.name}';
}
```

`app/lib/features/footsteps/recording/recording_config.dart` 전체를 다음으로 바꾼다:

```dart
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
```

`app/lib/features/footsteps/recording/recording_task_handler.dart`(실험 모드 껍데기)는 여행 기록 설정이면 열지 않는다. import에서 다음 부분을

```dart
import 'recording_messages.dart';
```

다음으로 바꾼다:

```dart
import 'recording_messages.dart';
import 'recording_mode.dart';
```

`onStart`에서 다음 부분을

```dart
      final config = RecordingConfig.fromJson(jsonDecode(raw) as Map<String, Object?>);
      final sessionDir = Directory(config.sessionDir);
```

다음으로 바꾼다:

```dart
      final config = RecordingConfig.fromJson(jsonDecode(raw) as Map<String, Object?>);
      final sessionPath = config.sessionDir;
      if (config.mode == RecordingMode.trip || sessionPath == null) {
        // 여행 기록 설정이다(TripRecordingTaskHandler가 맡는다). 실험 세션으로 열지 않는다.
        await FlutterForegroundTask.stopService();
        return;
      }
      final sessionDir = Directory(sessionPath);
```

`app/lib/features/footsteps/recording/recording_task_handler.dart`에서 다음 부분을

```dart
      recorder.field.carry = config.carryInitial;
```

다음으로 바꾼다:

```dart
      recorder.field.carry = config.carryInitial ?? CarryPosition.hand;
```

`app/lib/features/footsteps/recording/recording_task_handler.dart`에서 다음 부분을

```dart
      sessionId: p.basename(config.sessionDir),
```

다음으로 바꾼다:

```dart
      sessionId: p.basename(config.sessionDir!),
```

`app/lib/features/footsteps/recording/recording_task_handler.dart`에서 다음 부분을

```dart
      carryInitial: config.carryInitial,
```

다음으로 바꾼다:

```dart
      carryInitial: config.carryInitial ?? CarryPosition.hand,
```

`app/lib/features/footsteps/recording/session_recorder_factory.dart`에서 다음 부분을

```dart
        needs: PolicySensorNeeds.of(choice),
      );
  }
}
```

다음으로 바꾼다:

```dart
        needs: PolicySensorNeeds.of(choice),
      );
    case RecordingMode.trip:
      // 여행 기록은 세션 파일 없이 앱 DB에 쓴다 — TripRecordingTaskHandler가 TripRecorder를 직접 연다.
      throw StateError('여행 기록 모드는 실험 세션 기록기로 열지 않습니다.');
  }
}
```

`app/lib/features/footsteps/recording/recording_controller.dart`: 서비스 초기화를 여행 기록과 함께 쓰도록 밖으로 꺼낸다. 다음 부분을

```dart
const _recordingServiceId = 7101;
```

다음으로 바꾼다:

```dart
/// 기록 서비스의 서비스 id. 실험 모드와 여행 기록이 같은 서비스 하나를 번갈아 쓴다(설계 4-1 — 동시에 돌지 않는다).
const recordingServiceId = 7101;

/// 기록 서비스의 알림 채널·반복 주기를 정한다. 실험 화면(ForegroundRecordingController)과 여행 기록
/// (ForegroundTripRecordingService)이 서비스를 켜기 전에 똑같이 부른다.
void initRecordingService() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'footstep_recording',
      channelName: '발걸음 기록',
      channelDescription: '발걸음 실험·여행 기록이 진행 중일 때 표시됩니다.',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      // 5초마다 디스크에 쓰고 화면에 상태를 보낸다(설계 4-2). 여행 기록은 이 주기에 날짜를 확인한다(설계 9-2).
      eventAction: ForegroundTaskEventAction.repeat(5000),
      // 재부팅 뒤에는 다시 켜지 않는다 — 여행 기록은 다음에 앱을 열 때 다시 켜진다(설계 9-2).
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );
}
```

`ForegroundRecordingController` 안의 `_initService` 메서드는 위로 옮겼으니 지운다. 다음 부분을

```dart
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
```

이 부분을 통째로 지운다(끝의 빈 줄 하나까지).

`start`에서 다음 부분을

```dart
  }) async {
    final root = await _sessionsRoot();
```

다음으로 바꾼다:

```dart
  }) async {
    if (mode == RecordingMode.trip) {
      throw ArgumentError('여행 기록은 실험 화면이 아니라 ForegroundTripRecordingService로 켭니다.');
    }
    final root = await _sessionsRoot();
```

`app/lib/features/footsteps/recording/recording_controller.dart`에서 다음 부분을

```dart
    _initService();
    final result = await FlutterForegroundTask.startService(
      serviceId: _recordingServiceId,
```

다음으로 바꾼다:

```dart
    initRecordingService();
    final result = await FlutterForegroundTask.startService(
      serviceId: recordingServiceId,
```

`app/lib/features/footsteps/recording/recording_controller.dart`에서 다음 부분을

```dart
        RecordingMode.policy => '정책 실행 모드(${policy?.policyId}) · 알림 버튼으로 도착·탑승을 표시하세요',
      },
```

다음으로 바꾼다:

```dart
        RecordingMode.policy => '정책 실행 모드(${policy?.policyId}) · 알림 버튼으로 도착·탑승을 표시하세요',
        RecordingMode.trip => '', // 위에서 막았다
      },
```

여행 기록기·세션·서비스:

`app/lib/features/footsteps/trip/trip_recorder.dart`:

```dart
import 'dart:async';

import 'package:footstep_core/footstep_core.dart';

import '../../../core/db/app_database.dart';
import '../data/checkin.dart';
import '../recording/policy_choice.dart';
import '../recording/sensor_samples.dart';
import 'trip_period.dart';

/// 여행 기록에 쓰는 정책·걸음 감지기(설계 2026-11-07 9-2). 제안 정책 step_budget, E = 50m로 시작한다.
/// E와 걸음 감지기 종류는 R6 정확도 분석과 배터리 실험으로 확정한다 — 바꿀 곳은 여기 하나다.
const tripPolicyChoice = PolicyChoice(
  policyId: 'step_budget',
  policyParams: {'e_m': '50'},
  detectorId: 'adaptive',
);

/// 여행 기록 모드(설계 4-1 `trip`, 9-2·9-3). 정책 실행 모드(R4)와 같은 폰 실행기(PolicyRunner)로 제안 정책을 돌리되,
/// 세션 파일 대신 앱 DB에 쓴다.
/// - 정책에 알린 위치 → RoutePoints 한 행(여행 id·정확도·직전 점 이후 걸음 수·정책 상태). 국가는 [countryOf]로 가리고,
///   모르면(바다 위 등) 여행의 나라로 둔다.
/// - 걸음 감지기의 정지 구간 → TripStillSpans 한 행. 재생기와 같은 규칙(첫 분류 포함, 상태가 바뀐 순간)으로 잡는다.
///
/// 쓰기는 순서대로 하나씩 한다(같은 연결). 쓰기·센서 오류는 [onError]로 알리고 기록은 계속한다. 타이머를 안에 두지 않고,
/// 기록 서비스가 5초마다 [tick]을 부른다.
class TripRecorder {
  TripRecorder({
    required this.trip,
    required this.db,
    required this.sources,
    required this.clock,
    required this.countryOf,
    required CollectionPolicy policy,
    required this.detector,
    required LocationPort location,
    required WakeScheduler scheduler,
    required this.needs,
    this.onError,
    this.batteryInterval = const Duration(minutes: 1),
  }) {
    _runner = PolicyRunner(
      policy: policy,
      detector: detector,
      location: location,
      scheduler: scheduler,
      clock: () => clock().millisecondsSinceEpoch,
      sink: _TripSink(this),
      onError: (error, _) => _report(error),
      onStepUpdate: _onStepUpdate,
    );
  }

  final TripPeriod trip;
  final AppDatabase db;
  final SensorSources sources;
  final DateTime Function() clock;

  /// 좌표의 국가(ISO2). 기록 서비스에서는 세계지도 폴리곤으로 가린다(PolygonCountryResolver).
  final Future<String> Function(double lat, double lng) countryOf;
  final StepDetector detector;
  final PolicySensorNeeds needs;
  final void Function(Object error)? onError;

  /// 배터리 잔량을 읽는 간격. step_budget이 20% 미만에서 E를 2배로 키우는 데만 쓴다.
  final Duration batteryInterval;
  late final PolicyRunner _runner;

  final _subscriptions = <StreamSubscription<Object?>>[];
  Future<void> _writes = Future.value();
  bool _started = false;
  bool _stopped = false;
  DateTime? _lastBatteryAt;
  StepState? _detectorState;
  int? _stillSinceMs;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _runner.start();
    if (needs.accel) {
      _listen(sources.accel(), (AccelSample s) {
        _runner.addAccel(AccelReading(tMs: s.at.millisecondsSinceEpoch, x: s.x, y: s.y, z: s.z));
      });
    }
    if (needs.osSteps) {
      _listen(sources.osSteps(), (OsStepSample s) {
        _runner.addOsStep(OsStepReading(tMs: s.at.millisecondsSinceEpoch, kind: s.kind, value: s.value));
      });
    }
    await _readBattery();
  }

  void _listen<T>(Stream<T> stream, void Function(T sample) onSample) {
    _subscriptions.add(stream.listen(onSample, onError: (Object e) => _report(e)));
  }

  /// 기록 서비스의 반복 이벤트(5초)마다 부른다.
  Future<void> tick() async {
    if (_stopped) return;
    // OS 센서판 감지기는 가속도 없이 이 주기를 시계로 써야 멈춘 뒤 정지로 바뀐다(PolicyRunner.advanceDetectorClock).
    if (needs.osSteps) _runner.advanceDetectorClock();
    final last = _lastBatteryAt;
    if (last == null || clock().difference(last) >= batteryInterval) await _readBattery();
  }

  /// 멈추고, 열려 있던 정지 구간을 지금으로 닫고, 맡긴 쓰기를 모두 마친다. 여러 번 불러도 한 번만 한다.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    for (final subscription in _subscriptions) {
      try {
        await subscription.cancel();
      } catch (e) {
        _report(e);
      }
    }
    _subscriptions.clear();
    await _runner.stop();
    _closeStill(clock().millisecondsSinceEpoch);
    await _writes;
  }

  void _savePoint(FixRecord record) {
    _enqueue(() async {
      var iso = Checkin.unknownCountry;
      try {
        iso = await countryOf(record.fix.lat, record.fix.lng);
      } catch (e) {
        _report(e);
      }
      if (iso.length != 2 || iso == Checkin.unknownCountry) iso = trip.countryIso2;
      await db.insertTripPoint(
        tripId: trip.tripId,
        lat: record.fix.lat,
        lng: record.fix.lng,
        countryIso: iso,
        recordedAt: DateTime.fromMillisecondsSinceEpoch(record.tMs, isUtc: true),
        accuracyM: record.fix.accuracyM,
        stepsSincePrev: record.stepsSincePrev,
        state: record.state,
      );
    });
  }

  /// 상태가 바뀐 순간만 본다. 정지에 들어가면 시작 시각을 기억하고, 정지에서 나오면 그 구간을 남긴다.
  void _onStepUpdate(StepUpdate update) {
    final previous = _detectorState;
    if (previous == update.state) return;
    _detectorState = update.state;
    if (previous == StepState.still) _closeStill(update.tMs);
    if (update.state == StepState.still) _stillSinceMs = update.tMs;
  }

  void _closeStill(int endMs) {
    final startMs = _stillSinceMs;
    _stillSinceMs = null;
    if (startMs == null || endMs <= startMs) return;
    _enqueue(() => db.insertTripStillSpan(
          tripId: trip.tripId,
          startAt: DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true),
          endAt: DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true),
        ));
  }

  Future<void> _readBattery() async {
    _lastBatteryAt = clock();
    try {
      final battery = await sources.readBattery();
      final level = battery.levelPct;
      // 정책이 배터리 20% 미만 대응을 할 수 있게 잔량을 알린다(바뀔 때만 — 실행기가 거른다).
      if (level != null) _runner.addBatteryLevel(battery.at.millisecondsSinceEpoch, level);
    } catch (e) {
      _report(e);
    }
  }

  void _enqueue(Future<void> Function() write) {
    _writes = _writes.then((_) => write()).then((_) {}, onError: (Object e) => _report(e));
  }

  void _report(Object error) {
    try {
      onError?.call(error);
    } catch (_) {
      // 오류를 받는 곳의 오류까지 퍼뜨리면 기록이 멈춘다.
    }
  }
}

/// 실행기의 기록 중 위치만 DB에 남긴다. 할 일·깨우기 지연은 실험(정책 실행 모드)에서만 파일로 쓴다.
class _TripSink implements RunnerSink {
  _TripSink(this.recorder);

  final TripRecorder recorder;

  @override
  void fix(FixRecord record) => recorder._savePoint(record);

  @override
  void action(ActionRecord record) {}

  @override
  void wakeup(WakeupRecord record) {}
}
```

`app/lib/features/footsteps/trip/trip_recording_session.dart`:

```dart
import 'trip_period.dart';
import 'trip_recorder.dart';

/// 여행 기록 서비스 한 번의 수명(설계 2026-11-07 9-2의 종료 규칙). 기록 서비스 isolate의 TaskHandler가 시작·5초 반복·
/// 종료를 넘기면, 이 객체가 기록기를 켜고 끄고 '스스로 끝낼 때'를 정한다. 플러그인을 부르지 않아 테스트가 시간을 넘긴다.
///
/// 끝낼 때(서비스를 끈다):
/// - 귀국일 다음 날 0시(기기 현지 시각)가 지났다 — 깰 때마다 본다
/// - 화면이 여행을 지웠거나 일시정지했다 — 저장소를 [checkEvery]마다 다시 읽어 본다(화면이 서비스를 바로 끄지만, 화면이
///   그 전에 꺼졌을 때를 대비한다)
class TripRecordingSession {
  TripRecordingSession({
    required this.trip,
    required this.openRecorder,
    required this.stillWanted,
    required this.clock,
    this.checkEvery = const Duration(minutes: 1),
  });

  final TripPeriod trip;
  final Future<TripRecorder> Function() openRecorder;

  /// 이 여행이 아직 일정에 있고 일시정지가 아닌가(저장소를 다시 읽는다).
  final Future<bool> Function() stillWanted;
  final DateTime Function() clock;
  final Duration checkEvery;

  TripRecorder? _recorder;
  DateTime? _lastCheck;
  bool _ended = false;

  /// 기록을 시작한다. 기간이 끝났거나 여행이 지워졌거나 일시정지면 시작하지 않고 false다(서비스를 끈다).
  Future<bool> start() async {
    final now = clock();
    _lastCheck = now;
    if (!trip.covers(now) || !await stillWanted()) {
      _ended = true;
      return false;
    }
    final recorder = await openRecorder();
    _recorder = recorder;
    await recorder.start();
    return true;
  }

  /// 반복 이벤트마다 부른다. 계속 기록하면 true, 끝낼 때면 기록기를 멈추고 false다(서비스를 끈다).
  Future<bool> tick() async {
    if (_ended) return false;
    final now = clock();
    var keep = trip.covers(now);
    final last = _lastCheck;
    if (keep && (last == null || now.difference(last) >= checkEvery)) {
      _lastCheck = now;
      keep = await stillWanted();
    }
    if (!keep) {
      await stop();
      return false;
    }
    await _recorder?.tick();
    return true;
  }

  /// 기록기를 멈춘다(열린 정지 구간을 닫고 남은 쓰기를 마친다). 여러 번 불러도 된다.
  Future<void> stop() async {
    _ended = true;
    final recorder = _recorder;
    _recorder = null;
    await recorder?.stop();
  }
}
```

`app/lib/features/footsteps/trip/trip_recording_task_handler.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:footstep_core/footstep_core.dart' show createDetector, createPolicy;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/db/app_database.dart';
import '../data/checkin.dart';
import '../data/polygon_country_resolver.dart';
import '../map/world_geojson_parser.dart';
import '../recording/plugin_location_port.dart';
import '../recording/plugin_sensor_sources.dart';
import '../recording/policy_choice.dart';
import '../recording/recording_config.dart';
import '../recording/recording_mode.dart';
import 'trip_recorder.dart';
import 'trip_recording_session.dart';
import 'trip_recording_store.dart';

/// 여행 기록 서비스 isolate의 진입점. startService(callback:)로 넘기므로 top-level이어야 한다. 시스템이 서비스를 다시
/// 띄울 때도 이 함수가 다시 불린다(재부팅 뒤에는 autoRunOnBoot가 꺼져 있어 불리지 않는다).
@pragma('vm:entry-point')
void tripRecordingStartCallback() {
  FlutterForegroundTask.setTaskHandler(TripRecordingTaskHandler());
}

/// 여행 기록 모드의 서비스 본체(설계 4-1 `trip`). 화면과 다른 isolate에서 돌므로 Riverpod을 쓰지 않고 의존성을 직접 만든다.
/// 언제 끝낼지는 [TripRecordingSession]이, 무엇을 남길지는 [TripRecorder]가 정한다. 여기서는 플러그인을 이어 붙이기만 한다.
class TripRecordingTaskHandler extends TaskHandler {
  TripRecordingSession? _session;
  AppDatabase? _db;
  bool _stopping = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 이 isolate에서 Dart 쪽 등록이 필요한 플러그인(geolocator_android, shared_preferences 등)을 쓰려면 먼저 불러야 한다.
    DartPluginRegistrant.ensureInitialized();
    try {
      final raw = await FlutterForegroundTask.getData<String>(key: RecordingConfig.storageKey);
      final config =
          raw == null ? null : RecordingConfig.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
      final trip = config?.trip;
      if (config == null || config.mode != RecordingMode.trip || trip == null) {
        await _stopService();
        return;
      }
      final store = TripRecordingStore(await SharedPreferences.getInstance());
      final db = AppDatabase();
      _db = db;
      final choice = config.policy ?? tripPolicyChoice;
      DateTime utcNow() => DateTime.now().toUtc();
      final session = TripRecordingSession(
        trip: trip,
        clock: DateTime.now,
        stillWanted: () => _stillWanted(store, trip.tripId),
        openRecorder: () async => TripRecorder(
          trip: trip,
          db: db,
          sources: PluginSensorSources(clock: utcNow),
          clock: utcNow,
          countryOf: await _loadCountryResolver(),
          policy: createPolicy(choice.policyId, choice.policyParams),
          detector: createDetector(choice.detectorId, choice.detectorParams),
          location: GeolocatorLocationPort(clock: utcNow),
          scheduler: TimerWakeScheduler(clock: utcNow),
          needs: PolicySensorNeeds.of(choice),
          onError: (e) => debugPrint('여행 기록 오류: $e'),
        ),
      );
      _session = session;
      if (!await session.start()) await _stopService();
    } catch (e) {
      // 시작에 실패했는데 알림만 남아 있으면 기록되는 줄 안다. 이유를 남기고 서비스를 끈다.
      debugPrint('여행 기록을 시작하지 못했습니다: $e');
      await _stopService();
    }
  }

  /// 화면 isolate가 지우거나 일시정지했으면 false. 저장소를 읽지 못하면 기록을 끊지 않는다(true).
  static Future<bool> _stillWanted(TripRecordingStore store, int tripId) async {
    try {
      await store.reload();
      return store.readTrips().any((t) => t.tripId == tripId) && !store.readPaused().contains(tripId);
    } catch (e) {
      debugPrint('여행 기록 상태를 읽지 못했습니다: $e');
      return true;
    }
  }

  /// 세계지도 폴리곤으로 좌표의 나라를 가린다(실시간 경로와 같은 방법, 오프라인 동작). 읽지 못하면 늘 미확인(XX)이라
  /// 기록기가 여행의 나라로 둔다.
  static Future<Future<String> Function(double lat, double lng)> _loadCountryResolver() async {
    try {
      final content = await rootBundle.loadString('assets/geo/world_countries.geojson');
      return PolygonCountryResolver(parseWorldGeoJson(content)).resolveIso2;
    } catch (e) {
      debugPrint('세계지도를 읽지 못해 여행의 나라로 기록합니다: $e');
      return (lat, lng) async => Checkin.unknownCountry;
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    final session = _session;
    if (session == null || _stopping) return;
    unawaited(session.tick().then((keep) async {
      if (!keep) await _stopService();
    }).catchError((Object e) {
      debugPrint('여행 기록 tick 실패: $e');
    }));
  }

  Future<void> _stopService() async {
    if (_stopping) return;
    _stopping = true;
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    try {
      await _session?.stop();
    } finally {
      await _db?.close();
    }
  }
}
```

`app/lib/features/footsteps/trip/trip_recording_service.dart`:

```dart
import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../recording/recording_config.dart';
import '../recording/recording_controller.dart';
import '../recording/recording_mode.dart';
import 'trip_period.dart';
import 'trip_recorder.dart';
import 'trip_recording_task_handler.dart';

/// 화면 isolate가 여행 기록 서비스를 다루는 창구. 테스트는 가짜로 바꿔 무엇을 켜고 껐는지 본다.
abstract interface class TripRecordingService {
  /// 기록 서비스가 돌고 있는가(실험 세션 포함).
  Future<bool> isRunning();

  /// 여행 기록 모드로 도는 중이면 그 여행 id. 실험 세션이거나 꺼져 있으면 null이다.
  Future<int?> recordingTripId();

  Future<void> start(TripPeriod trip);

  Future<void> stop();
}

/// flutter_foreground_task로 기록 서비스를 여행 기록 모드로 켠다. 실험 화면과 같은 서비스·알림 채널을 쓴다(설계 4-1 D4).
/// Android 14부터 위치 포그라운드 서비스는 앱이 화면에 있을 때만 켤 수 있어, 앱이 포그라운드로 올 때만 부른다(설계 9-2).
class ForegroundTripRecordingService implements TripRecordingService {
  const ForegroundTripRecordingService();

  @override
  Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  @override
  Future<int?> recordingTripId() async {
    if (!await FlutterForegroundTask.isRunningService) return null;
    final raw = await FlutterForegroundTask.getData<String>(key: RecordingConfig.storageKey);
    if (raw == null) return null;
    try {
      final config = RecordingConfig.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
      return config.mode == RecordingMode.trip ? config.trip?.tripId : null;
    } catch (_) {
      return null; // 읽을 수 없는 설정이면 실험 세션으로 보고 건드리지 않는다
    }
  }

  @override
  Future<void> start(TripPeriod trip) async {
    final config = RecordingConfig(mode: RecordingMode.trip, policy: tripPolicyChoice, trip: trip);
    await FlutterForegroundTask.saveData(key: RecordingConfig.storageKey, value: jsonEncode(config.toJson()));
    initRecordingService();
    final result = await FlutterForegroundTask.startService(
      serviceId: recordingServiceId,
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: '${trip.countryNameKo} 여행 발걸음 기록 중',
      notificationText: '귀국 다음 날 0시에 스스로 꺼져요 · 여행 상세에서 일시정지할 수 있어요',
      callback: tripRecordingStartCallback,
    );
    if (result is ServiceRequestFailure) {
      throw StateError('여행 기록을 시작하지 못했습니다: ${result.error}');
    }
  }

  @override
  Future<void> stop() async {
    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestFailure) {
      throw StateError('여행 기록을 멈추지 못했습니다: ${result.error}');
    }
  }
}
```

실험 화면 `app/lib/features/footsteps/lab/lab_page.dart`에서 다음 부분을

```dart
  bool _running = false;
  bool _busy = false;
```

다음으로 바꾼다:

```dart
  bool _running = false;

  /// 지금 도는 것이 앱이 켠 여행 기록(R7)인가. 실험 화면에서 고를 수 있는 모드가 아니라 안내만 한다.
  bool _tripRecording = false;
  bool _busy = false;
```

`app/lib/features/footsteps/lab/lab_page.dart`에서 다음 부분을

```dart
  void _showConfig(RecordingConfig config) {
    _mode = config.mode;
```

다음으로 바꾼다:

```dart
  void _showConfig(RecordingConfig config) {
    if (config.mode == RecordingMode.trip) {
      // 모드 선택은 기본값으로 둔다. 그대로 두면 [기록 종료] 뒤 [기록 시작]이 여행 기록 모드로 실험을 켜려 한다.
      _tripRecording = true;
      return;
    }
    _mode = config.mode;
```

`app/lib/features/footsteps/lab/lab_page.dart`에서 다음 부분을

```dart
          setState(() {
            _running = false;
            _status = null;
```

다음으로 바꾼다:

```dart
          setState(() {
            _running = false;
            _tripRecording = false;
            _status = null;
```

`app/lib/features/footsteps/lab/lab_page.dart`에서 다음 부분을

```dart
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('lab-start-stop'),
```

다음으로 바꾼다:

```dart
          const SizedBox(height: 8),
          if (_running && _tripRecording)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '여행 기록 중이에요. [기록 종료]를 누르면 여행 기록을 멈추고 실험을 시작할 수 있어요. '
                '여행 기록은 다음에 앱을 열 때 다시 켜져요.',
                key: Key('lab-trip-recording'),
              ),
            ),
          FilledButton(
            key: const Key('lab-start-stop'),
```

- [ ] **Step 4: 통과 확인**

Run
- 패키지(`packages/footstep_core/`): `dart test` → 통과(216개), `dart analyze` → 0건
- 앱(`app/`)
  - `flutter test test/footsteps/trip/ test/footsteps/lab/ test/footsteps/recording/` → 통과
  - 기록기 6개, 세션 4개, 실험 화면 12개다.
  - `flutter test`(전체) → 통과(759개), `dart analyze lib test` → 0건

- [ ] **Step 5: 커밋**

```bash
git add packages/footstep_core/lib/src/runner/policy_runner.dart packages/footstep_core/test/runner/policy_runner_test.dart \
  app/lib/features/footsteps/recording/recording_mode.dart app/lib/features/footsteps/recording/recording_config.dart \
  app/lib/features/footsteps/recording/recording_task_handler.dart app/lib/features/footsteps/recording/session_recorder_factory.dart \
  app/lib/features/footsteps/recording/recording_controller.dart \
  app/lib/features/footsteps/trip/trip_recorder.dart app/lib/features/footsteps/trip/trip_recording_session.dart \
  app/lib/features/footsteps/trip/trip_recording_task_handler.dart app/lib/features/footsteps/trip/trip_recording_service.dart \
  app/lib/features/footsteps/lab/lab_page.dart app/test/footsteps/lab/lab_page_test.dart \
  app/test/footsteps/trip/trip_fakes.dart app/test/footsteps/trip/trip_recorder_test.dart \
  app/test/footsteps/trip/trip_recording_session_test.dart
git commit -m "feat(app,footstep_core): 기록 서비스에 여행 기록 모드를 붙이고 제안 정책으로 RoutePoints와 정지 구간을 남긴다"
```

---

### Task 5: 앱을 열 때 여행 기록을 켜고, 실시간 경로는 표시만, 1시간 체크인은 여행 기간에만

설계 9-2의 1번과 '정책과 기존 동작'이다. `TripRecordingCoordinator`가 `shouldRecord`의 결과에 기록 서비스를 맞춘다.
- 모든 작업은 부른 순서대로 하나씩 한다. 앱을 열자마자 목록이 도착하면 두 작업이 동시에 "꺼져 있다"고 보고 서비스를 두 번 켜려 한다.
- 실험 세션이 돌고 있으면 건드리지 않는다.
- 위치(앱 사용 중) 권한이 없으면 켜지 않는다.

앱 셸(`_TabScaffoldState`)이 부른다.
- 위치 권한 요청이 끝난 뒤와 포그라운드 복귀 때 `sync()`
- 서버에서 여행 목록을 받을 때마다 `updateTrips()`. 오프라인 캐시 목록은 낡았을 수 있어 쓰지 않는다 — 비자 알람 정리(PR #32)와 같은 규칙이다.

실시간 경로(`liveRouteProvider`)는 저장을 멈춘다. WorkManager 체크인은 같은 저장소를 읽어 여행 기간(일시정지 제외)이 아니면 측위 없이 끝낸다.

**Files:**
- Create: `app/lib/features/footsteps/trip/trip_recording_permissions.dart`, `trip_recording_coordinator.dart`, `trip_recording_providers.dart`
- Modify: `app/lib/router.dart`(앱 셸)
- Modify: `app/lib/features/footsteps/map/live_route_tracker.dart`(전체 교체), `app/lib/features/footsteps/providers/footsteps_providers.dart`
- Modify: `app/lib/features/footsteps/background/footstep_task_handler.dart`(전체 교체), `footstep_workmanager.dart`
- Modify: `app/test/footsteps/trip/trip_fakes.dart`(덧붙임)
- Test: `app/test/footsteps/trip/trip_recording_coordinator_test.dart`, `app/test/router_test.dart`, `app/test/footsteps/footstep_task_handler_test.dart`, `app/test/footsteps/live_route_tracker_test.dart`(전체 교체), `app/test/footsteps/live_route_provider_test.dart`(전체 교체)

**Interfaces:**
- Consumes
  - Task 3: `shouldRecord`, `TripPeriod.fromSummary`, `TripRecordingStore`
  - Task 4: `TripRecordingService`, `ForegroundTripRecordingService`
- Produces
  - 권한
    - `enum TripRecordingPermission { backgroundLocation, activityRecognition, notification }`(`label`)
    - `abstract interface class TripRecordingPermissions { Future<bool> canRecord(); Future<Set<TripRecordingPermission>> missing(); Future<void> openSettings(); }`
  - `TripRecordingCoordinator({required store, required service, required permissions, DateTime Function()? clock})`
    - `sync()`, `updateTrips(List<TripSummary>)`, `setPaused(int, bool)`
    - Task 6이 `notices`·`db`와 `forgetTrip`·`claimFor`를 더한다
  - provider: `tripRecordingStoreProvider`, `tripRecordingServiceProvider`, `tripRecordingPermissionsProvider`, `tripRecordingCoordinatorProvider`
  - 실시간 경로: `Stream<List<LatLng>> trackLiveRoute(Stream<Position> positions, {int maxPoints = 2000})` — `trackAndPersistLiveRoute`를 대신한다
  - WorkManager
    - `handleFootstepTask({repository, getCurrentPosition, required Future<bool> Function() isTripPeriod})`
    - `Future<bool> isTripPeriodNow(DateTime now)`
  - 테스트 도우미: `FakeTripRecordingService`(`labRunning`, `started`, `stops`), `FakeTripRecordingPermissions`(`location`, `absent`, `settingsOpened`), `FakeTripRecordingCoordinator`(`syncs`, `updates`, `pauses`)

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/footsteps/trip/trip_fakes.dart`의 import에서 다음 부분을

```dart
import 'package:app/features/footsteps/recording/sensor_samples.dart';
import 'package:app/features/footsteps/trip/trip_period.dart';
import 'package:footstep_core/footstep_core.dart';
```

다음으로 바꾼다:

```dart
import 'package:app/features/footsteps/recording/sensor_samples.dart';
import 'package:app/features/footsteps/trip/trip_period.dart';
import 'package:app/features/footsteps/trip/trip_recording_coordinator.dart';
import 'package:app/features/footsteps/trip/trip_recording_permissions.dart';
import 'package:app/features/footsteps/trip/trip_recording_service.dart';
import 'package:app/features/visa/models/trip_summary.dart';
import 'package:footstep_core/footstep_core.dart';
```

같은 파일 끝에 덧붙인다:

```dart
/// 기록 서비스 대역. 켜고 끈 기록을 남긴다. [labRunning]이면 실험 세션이 도는 중이다.
class FakeTripRecordingService implements TripRecordingService {
  int? runningTripId;
  bool labRunning = false;
  final started = <int>[];
  int stops = 0;

  @override
  Future<bool> isRunning() async => labRunning || runningTripId != null;

  @override
  Future<int?> recordingTripId() async => runningTripId;

  @override
  Future<void> start(TripPeriod trip) async {
    started.add(trip.tripId);
    runningTripId = trip.tripId;
  }

  @override
  Future<void> stop() async {
    stops++;
    runningTripId = null;
    labRunning = false;
  }
}

/// 권한 대역.
class FakeTripRecordingPermissions implements TripRecordingPermissions {
  FakeTripRecordingPermissions({this.location = true, this.absent = const {}});

  bool location;
  Set<TripRecordingPermission> absent;
  int settingsOpened = 0;

  @override
  Future<bool> canRecord() async => location;

  @override
  Future<Set<TripRecordingPermission>> missing() async => absent;

  @override
  Future<void> openSettings() async => settingsOpened++;
}

/// 앱 셸·여행 상세 위젯 테스트용 코디네이터 대역. 불린 것만 기록한다.
class FakeTripRecordingCoordinator implements TripRecordingCoordinator {
  int syncs = 0;
  final updates = <List<int>>[];
  final pauses = <(int, bool)>[];

  @override
  Future<void> sync() async => syncs++;

  @override
  Future<void> updateTrips(List<TripSummary> trips) async => updates.add([for (final t in trips) t.id]);

  @override
  Future<void> setPaused(int tripId, bool paused) async => pauses.add((tripId, paused));
}
```

`app/test/footsteps/trip/trip_recording_coordinator_test.dart`:

```dart
import 'package:app/features/footsteps/trip/trip_recording_coordinator.dart';
import 'package:app/features/footsteps/trip/trip_recording_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../visa/fake_trip_api.dart' show sampleSummary;
import 'trip_fakes.dart';

void main() {
  late TripRecordingStore store;
  late FakeTripRecordingService service;
  late FakeTripRecordingPermissions permissions;
  late DateTime now;
  late TripRecordingCoordinator coordinator;

  final domestic = sampleSummary(
      id: 7, iso2: 'KR', nameKo: '대한민국', depart: DateTime(2026, 11, 20), ret: DateTime(2026, 11, 22));
  final later = sampleSummary(id: 9, depart: DateTime(2026, 11, 21), ret: DateTime(2026, 11, 25));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = TripRecordingStore(await SharedPreferences.getInstance());
    service = FakeTripRecordingService();
    permissions = FakeTripRecordingPermissions();
    now = DateTime(2026, 11, 20, 9);
    coordinator = TripRecordingCoordinator(
      store: store,
      service: service,
      permissions: permissions,
      clock: () => now,
    );
  });

  test('목록을 받으면 일정을 바꾸고, 오늘이 여행 기간이면 그 여행으로 기록 서비스를 켠다', () async {
    await coordinator.updateTrips([domestic]);

    expect(store.readTrips().single.tripId, 7);
    expect(service.started, [7]);

    // 이미 그 여행으로 돌고 있으면 다시 켜지 않는다(앱을 다시 열 때마다 부른다).
    await coordinator.sync();
    expect(service.started, [7]);
  });

  test('여행 기간이 아니면 켜지 않고, 돌던 여행 기록은 끈다', () async {
    now = DateTime(2026, 11, 19, 23, 59);
    await coordinator.updateTrips([domestic]);
    expect(service.started, isEmpty);

    now = DateTime(2026, 11, 20);
    await coordinator.sync();
    expect(service.started, [7]);

    now = DateTime(2026, 11, 23);
    await coordinator.sync();
    expect(service.stops, 1);
    expect(service.runningTripId, isNull);
  });

  test('일시정지하면 끄고, 재개하면 다시 켠다', () async {
    await coordinator.updateTrips([domestic]);

    await coordinator.setPaused(7, true);
    expect(store.readPaused(), {7});
    expect(service.runningTripId, isNull);

    await coordinator.setPaused(7, false);
    expect(service.started, [7, 7]);
  });

  test('겹치는 여행이 새로 시작하면 그 여행으로 바꿔 켠다', () async {
    await coordinator.updateTrips([domestic, later]);
    expect(service.started, [7]);

    now = DateTime(2026, 11, 21, 8);
    await coordinator.sync();
    expect(service.stops, 1);
    expect(service.started, [7, 9]);
  });

  test('실험 화면의 세션이 돌고 있으면 건드리지 않는다(배터리 측정이 오염된다)', () async {
    service.labRunning = true;

    await coordinator.updateTrips([domestic]);

    expect(service.started, isEmpty);
    expect(service.stops, 0);
  });

  test('위치 권한이 없으면 켜지 않는다', () async {
    permissions.location = false;

    await coordinator.updateTrips([domestic]);

    expect(service.started, isEmpty);
  });

  test('앱을 열 때와 목록 도착이 겹쳐도 한 번만 켠다', () async {
    await store.replaceTrips([period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22))]);

    await Future.wait([coordinator.sync(), coordinator.updateTrips([domestic]), coordinator.sync()]);

    expect(service.started, [7]);
  });
}
```

앱 셸 테스트 — `app/test/router_test.dart`. 셸이 이제 코디네이터를 부르므로 모든 `pumpApp`과 실험 화면 경로 테스트가 대역을 넣는다.

`app/test/router_test.dart`에서 다음 부분을

```dart
import 'package:app/features/footsteps/recording/session_library.dart';
import 'package:app/features/visa/data/trip_list_providers.dart';
```

다음으로 바꾼다:

```dart
import 'package:app/features/footsteps/recording/session_library.dart';
import 'package:app/features/footsteps/trip/trip_recording_providers.dart';
import 'package:app/features/visa/data/trip_list_providers.dart';
```

`app/test/router_test.dart`에서 다음 부분을

```dart
import 'footsteps/lab/fake_recording_controller.dart';
```

다음으로 바꾼다:

```dart
import 'footsteps/lab/fake_recording_controller.dart';
import 'footsteps/trip/trip_fakes.dart';
import 'visa/fake_trip_api.dart' show sampleSummary;
```

`app/test/router_test.dart`에서 다음 부분을

```dart
Future<void> pumpApp(WidgetTester tester, {required bool isLoggedIn}) async {
  await tester.pumpWidget(
    ProviderScope(
      // 첫 탭(여행 목록)이 서버를 부르지 않게 빈 목록으로 고정한다.
      overrides: [
        tripListProvider.overrideWith((ref) async => const TripListState(trips: [])),
      ],
      child: TravelFootstepsApp(router: createRouter(isLoggedIn: isLoggedIn)),
    ),
  );
  await tester.pumpAndSettle();
}
```

다음으로 바꾼다:

```dart
Future<FakeTripRecordingCoordinator> pumpApp(
  WidgetTester tester, {
  required bool isLoggedIn,
  TripListState trips = const TripListState(trips: []),
}) async {
  final coordinator = FakeTripRecordingCoordinator();
  await tester.pumpWidget(
    ProviderScope(
      // 첫 탭(여행 목록)이 서버를 부르지 않게 목록을 고정한다. 여행 기록은 서비스를 켜지 않게 대역으로 바꾼다.
      overrides: [
        tripListProvider.overrideWith((ref) async => trips),
        tripRecordingCoordinatorProvider.overrideWithValue(coordinator),
      ],
      child: TravelFootstepsApp(router: createRouter(isLoggedIn: isLoggedIn)),
    ),
  );
  await tester.pumpAndSettle();
  return coordinator;
}
```

'앱 생명주기' 그룹 끝의 다음 부분을

```dart
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(container.read(realtimeTrackingEnabledProvider), isTrue);
    });
  });
```

다음으로 바꾼다:

```dart
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(container.read(realtimeTrackingEnabledProvider), isTrue);
    });

    // 설계 9-2의 1번: 여행 기록은 앱이 포그라운드로 올 때만 켠다(Android 14 제한).
    testWidgets('앱을 열면 여행 기록을 맞추고, 포그라운드로 돌아올 때마다 다시 맞춘다', (tester) async {
      final coordinator = await pumpApp(tester, isLoggedIn: true);
      // 시작할 때는 위치 권한 요청(플랫폼 채널)이 끝난 뒤에 맞춘다 — 그 응답은 실제 이벤트 루프에서 온다.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(coordinator.syncs, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(coordinator.syncs, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(coordinator.syncs, 2);
    });

    testWidgets('서버에서 받은 여행 목록으로 여행 기록 일정을 바꾼다', (tester) async {
      final coordinator =
          await pumpApp(tester, isLoggedIn: true, trips: TripListState(trips: [sampleSummary(id: 3)]));

      expect(coordinator.updates, [
        [3],
      ]);
    });

    testWidgets('오프라인 캐시 목록으로는 여행 기록 일정을 바꾸지 않는다', (tester) async {
      final coordinator = await pumpApp(tester,
          isLoggedIn: true, trips: TripListState(trips: [sampleSummary(id: 3)], offline: true));

      expect(coordinator.updates, isEmpty);
    });
  });
```

실험 화면 경로 테스트의 다음 부분을

```dart
          overrides: [
            tripListProvider.overrideWith((ref) async => const TripListState(trips: [])),
            recordingControllerProvider.overrideWithValue(FakeRecordingController()),
```

다음으로 바꾼다:

```dart
          overrides: [
            tripListProvider.overrideWith((ref) async => const TripListState(trips: [])),
            tripRecordingCoordinatorProvider.overrideWithValue(FakeTripRecordingCoordinator()),
            recordingControllerProvider.overrideWithValue(FakeRecordingController()),
```

`app/test/footsteps/footstep_task_handler_test.dart`의 import에서 다음 부분을

```dart
import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/background/footstep_task_handler.dart';
```

다음으로 바꾼다:

```dart
import 'dart:convert';

import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/background/footstep_task_handler.dart';
import 'package:app/features/footsteps/background/footstep_workmanager.dart';
import 'package:app/features/footsteps/trip/trip_recording_store.dart';
```

`app/test/footsteps/footstep_task_handler_test.dart`에서 다음 부분을

```dart
import 'package:geolocator/geolocator.dart';
```

다음으로 바꾼다:

```dart
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'trip/trip_fakes.dart' show period;
```

`app/test/footsteps/footstep_task_handler_test.dart`에서 다음 부분을

```dart
  test('좌표를 얻으면 AUTO 소스로 체크인을 저장한다', () async {
    await handleFootstepTask(
      repository: repo,
      getCurrentPosition: () async => _fakePosition(35.6, 139.7),
    );
```

다음으로 바꾼다:

```dart
  test('여행 기간이면 좌표를 얻어 AUTO 소스로 체크인을 저장한다', () async {
    await handleFootstepTask(
      repository: repo,
      isTripPeriod: () async => true,
      getCurrentPosition: () async => _fakePosition(35.6, 139.7),
    );
```

파일 끝의 다음 부분을

```dart
    await handleFootstepTask(
      repository: repo,
      getCurrentPosition: () async => throw StateError('위치 서비스 꺼짐'),
    );

    expect(await repo.allCheckins(), isEmpty);
  });
}
```

다음으로 바꾼다:

```dart
    await handleFootstepTask(
      repository: repo,
      isTripPeriod: () async => true,
      getCurrentPosition: () async => throw StateError('위치 서비스 꺼짐'),
    );

    expect(await repo.allCheckins(), isEmpty);
  });

  test('여행 기간이 아니면 측위 없이 끝낸다', () async {
    var asked = 0;
    await handleFootstepTask(
      repository: repo,
      isTripPeriod: () async => false,
      getCurrentPosition: () async {
        asked++;
        return _fakePosition(35.6, 139.7);
      },
    );

    expect(asked, 0);
    expect(await repo.allCheckins(), isEmpty);
  });

  test('WorkManager isolate는 화면이 저장해 둔 여행 기록 일정·일시정지로 여행 기간을 본다', () async {
    final trip = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));
    SharedPreferences.setMockInitialValues({TripRecordingStore.tripsKey: jsonEncode([trip.toJson()])});

    expect(await isTripPeriodNow(DateTime(2026, 11, 21, 9)), isTrue);
    expect(await isTripPeriodNow(DateTime(2026, 11, 23)), isFalse);

    SharedPreferences.setMockInitialValues({
      TripRecordingStore.tripsKey: jsonEncode([trip.toJson()]),
      TripRecordingStore.pausedKey: jsonEncode([7]),
    });
    expect(await isTripPeriodNow(DateTime(2026, 11, 21, 9)), isFalse);
  });
}
```

`app/test/footsteps/live_route_tracker_test.dart` 전체를 다음으로 바꾼다:

```dart
import 'package:app/features/footsteps/map/live_route_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Position _positionAt(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  test('위치가 들어올 때마다 지금까지의 전체 경로를 누적해서 낸다', () async {
    final positions = Stream.fromIterable([
      _positionAt(1, 1),
      _positionAt(2, 2),
      _positionAt(3, 3),
    ]);

    final snapshots = await trackLiveRoute(positions).toList();

    expect(snapshots, [
      [const LatLng(1, 1)],
      [const LatLng(1, 1), const LatLng(2, 2)],
      [const LatLng(1, 1), const LatLng(2, 2), const LatLng(3, 3)],
    ]);
  });

  test('maxPoints를 넘으면 오래된 좌표부터 버린다', () async {
    final positions = Stream.fromIterable([
      _positionAt(1, 1),
      _positionAt(2, 2),
      _positionAt(3, 3),
    ]);

    final snapshots = await trackLiveRoute(positions, maxPoints: 2).toList();

    expect(snapshots.last, [const LatLng(2, 2), const LatLng(3, 3)]);
  });

  test('위치가 없으면 빈 스트림을 낸다', () async {
    expect(await trackLiveRoute(const Stream.empty()).toList(), isEmpty);
  });
}
```

`app/test/footsteps/live_route_provider_test.dart` 전체를 다음으로 바꾼다:

```dart
import 'dart:async';

import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/providers/footsteps_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Position _positionAt(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  // 설계 2026-11-07 9-2: 실시간 경로는 화면 표시용으로만 남는다. 이동 기록은 여행 기간에만 기록 서비스가 남긴다.
  test('실시간 경로는 좌표를 화면에 내기만 하고 RoutePoints에 저장하지 않는다', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final positions = StreamController<Position>();
    addTearDown(positions.close);
    final container = ProviderContainer(overrides: [
      livePositionsProvider.overrideWithValue(() => positions.stream),
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    final seen = <List<LatLng>>[];
    container.listen(liveRouteProvider, (_, next) {
      final value = next.asData?.value;
      if (value != null) seen.add(value);
    });

    positions.add(_positionAt(37.5, 127.0));
    positions.add(_positionAt(37.6, 127.1));
    await pumpEventQueue();

    expect(seen.last, [const LatLng(37.5, 127.0), const LatLng(37.6, 127.1)]);
    expect(await db.select(db.routePoints).get(), isEmpty);
  });
}
```

`live_route_provider_test.dart`의 예전 테스트(국가 판정 도중 추적이 꺼질 때 disposed ref)는 저장 경로가 없어져 의미가 없어서 "저장하지 않는다" 테스트로 바꾼다.

- [ ] **Step 2: 실패 확인**

Run(`app/`에서): `flutter test test/footsteps/ test/router_test.dart`

Expected: FAIL. 다음이 아직 없다.
- `trip_recording_coordinator.dart`
- `trackLiveRoute`
- `handleFootstepTask`의 `isTripPeriod`
- `isTripPeriodNow`

- [ ] **Step 3: 구현**

`app/lib/features/footsteps/trip/trip_recording_permissions.dart`:

```dart
import 'package:permission_handler/permission_handler.dart';

/// 여행 기록이 제대로 돌려면 있어야 하는 권한 중, 없으면 날짜별 보기 위에 "기록이 꺼져 있어요" 배너를 띄우는 것(설계 9-4).
enum TripRecordingPermission {
  /// 위치 '항상 허용'. 기록 서비스는 앱이 화면에 있을 때 켜 '앱 사용 중' 권한으로도 돌지만, 시스템이 서비스를 다시
  /// 띄우거나 WorkManager 체크인이 위치를 읽으려면 필요하다.
  backgroundLocation('백그라운드 위치'),

  /// 걸음 감지(OS 걸음 센서)에 쓴다.
  activityRecognition('활동 인식'),

  /// 기록 중 알림과 출발일 아침 알림을 보이게 한다.
  notification('알림');

  const TripRecordingPermission(this.label);

  final String label;
}

/// 여행 기록 권한 확인. 플러그인을 부르므로 화면·코디네이터 테스트는 가짜로 바꾼다.
abstract interface class TripRecordingPermissions {
  /// 위치(앱 사용 중) 권한이 있어 기록 서비스를 켤 수 있는가. 없으면 켜지 않는다(위치 서비스가 바로 죽는다).
  Future<bool> canRecord();

  /// 없는 권한들.
  Future<Set<TripRecordingPermission>> missing();

  /// 앱 설정 화면을 연다(권한은 사용자가 직접 켠다).
  Future<void> openSettings();
}

class PermissionHandlerTripRecordingPermissions implements TripRecordingPermissions {
  const PermissionHandlerTripRecordingPermissions();

  @override
  Future<bool> canRecord() => Permission.locationWhenInUse.isGranted;

  @override
  Future<Set<TripRecordingPermission>> missing() async => {
        if (!await Permission.locationAlways.isGranted) TripRecordingPermission.backgroundLocation,
        if (!await Permission.activityRecognition.isGranted) TripRecordingPermission.activityRecognition,
        if (!await Permission.notification.isGranted) TripRecordingPermission.notification,
      };

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }
}
```

`app/lib/features/footsteps/trip/trip_recording_coordinator.dart`:

```dart
import '../../visa/models/trip_summary.dart';
import 'trip_period.dart';
import 'trip_recording_permissions.dart';
import 'trip_recording_service.dart';
import 'trip_recording_store.dart';

/// 화면(main isolate)에서 여행 기록을 켜고 끄는 곳(설계 2026-11-07 9-2). 무엇을 기록할지는 순수 함수 [shouldRecord]가
/// 정하고, 여기서는 그 결과에 기록 서비스를 맞춘다.
///
/// 켜는 것은 언제나 앱이 화면에 있을 때다 — Android 14가 백그라운드에서 위치 포그라운드 서비스를 켜는 것을 막는다.
/// 그래서 앱 셸이 앱을 열 때·포그라운드로 돌아올 때 [sync]를, 여행 목록을 받을 때 [updateTrips]를 부르고, 여행 상세의
/// 일시정지·재개가 [setPaused]를 부른다. 끄는 것은 여기(일시정지·기간 밖)와 기록 서비스 자신(귀국 다음 날)이 한다.
///
/// 모든 작업은 부른 순서대로 하나씩 한다. 앱을 열자마자 목록이 도착하면 두 작업이 동시에 "꺼져 있다"고 보고 서비스를
/// 두 번 켜려 하기 때문이다.
class TripRecordingCoordinator {
  TripRecordingCoordinator({
    required this._store,
    required this._service,
    required this._permissions,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TripRecordingStore _store;
  final TripRecordingService _service;
  final TripRecordingPermissions _permissions;
  final DateTime Function() _clock;

  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (Object _) {}); // 한 작업이 실패해도 다음 작업은 이어간다.
    return result;
  }

  /// 기록 서비스를 지금(일정·일시정지·날짜)에 맞춘다.
  Future<void> sync() => _serial(_sync);

  /// 서버에서 받은 내 여행 목록으로 일정을 바꾸고 기록 서비스를 다시 맞춘다. 오프라인 캐시 목록은 넘기지 않는다.
  Future<void> updateTrips(List<TripSummary> trips) => _serial(() async {
        await _store.replaceTrips([for (final t in trips) TripPeriod.fromSummary(t)]);
        await _sync();
      });

  /// 여행 상세의 일시정지·재개. 일시정지 상태는 여행별로 기기에 남는다.
  Future<void> setPaused(int tripId, bool paused) => _serial(() async {
        await _store.setPaused(tripId, paused);
        await _sync();
      });

  Future<void> _sync() async {
    final running = await _service.isRunning();
    final active = running ? await _service.recordingTripId() : null;
    // 실험 화면의 세션이 돌고 있다. 같이 돌면 배터리 측정이 오염되므로(설계 4-1) 건드리지 않는다.
    if (running && active == null) return;
    final target = shouldRecord(_store.readTrips(), _clock(), _store.readPaused());
    if (active != null && active != target?.tripId) await _service.stop();
    if (target == null || active == target.tripId) return;
    // 위치 권한이 없으면 서비스가 켜지자마자 죽는다. 날짜별 보기의 "기록이 꺼져 있어요" 배너가 알린다.
    if (!await _permissions.canRecord()) return;
    await _service.start(target);
  }
}
```

`app/lib/features/footsteps/trip/trip_recording_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import 'trip_recording_coordinator.dart';
import 'trip_recording_permissions.dart';
import 'trip_recording_service.dart';
import 'trip_recording_store.dart';

final tripRecordingStoreProvider = Provider<TripRecordingStore>(
  (ref) => TripRecordingStore(ref.watch(sharedPreferencesProvider)),
);

final tripRecordingServiceProvider =
    Provider<TripRecordingService>((ref) => const ForegroundTripRecordingService());

final tripRecordingPermissionsProvider =
    Provider<TripRecordingPermissions>((ref) => const PermissionHandlerTripRecordingPermissions());

/// 작업을 한 줄로 세우는 객체라 앱 전체에 하나만 둔다.
final tripRecordingCoordinatorProvider = Provider<TripRecordingCoordinator>(
  (ref) => TripRecordingCoordinator(
    store: ref.watch(tripRecordingStoreProvider),
    service: ref.watch(tripRecordingServiceProvider),
    permissions: ref.watch(tripRecordingPermissionsProvider),
  ),
);
```

앱 셸 `app/lib/router.dart`. import에서 다음 부분을

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

다음으로 바꾼다:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

`app/lib/router.dart`에서 다음 부분을

```dart
import 'features/footsteps/providers/footsteps_providers.dart';
```

다음으로 바꾼다:

```dart
import 'features/footsteps/providers/footsteps_providers.dart';
import 'features/footsteps/trip/trip_recording_providers.dart';
import 'features/visa/data/trip_list_providers.dart';
```

`_TabScaffoldState`의 `initState`를 바꾸고 `_syncTripRecording`을 더한다. 다음 부분을

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 앱 실행 직후(로그인 후 탭 화면 진입 시) 위치 권한을 받고 이동 기록 저장을 시작한다.
    // 권한이 없을 때 이미 구독된 스트림은 에러로 끝나므로, 응답을 받은 뒤 다시 구독한다.
    Future.microtask(() async {
      try {
        await Geolocator.requestPermission();
      } catch (_) {}
      if (mounted) ref.invalidate(liveRouteProvider);
    });
  }
```

다음으로 바꾼다:

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 앱 실행 직후(로그인 후 탭 화면 진입 시) 위치 권한을 받고 실시간 경로 표시를 시작한다.
    // 권한이 없을 때 이미 구독된 스트림은 에러로 끝나므로, 응답을 받은 뒤 다시 구독한다.
    // 권한을 받은 뒤 오늘이 여행 기간이면 여행 기록을 켠다(설계 9-2의 1번 — 시작은 항상 앱을 연 순간이다).
    Future.microtask(() async {
      try {
        await Geolocator.requestPermission();
      } catch (_) {}
      if (!mounted) return;
      ref.invalidate(liveRouteProvider);
      _syncTripRecording();
    });
    // 서버에서 여행 목록을 받을 때마다 여행 기록 일정을 바꾼다. 오프라인 캐시 목록은 낡았을 수 있어 쓰지 않는다
    // (비자 알람 정리와 같은 규칙, PR #32).
    ref.listenManual(tripListProvider, (_, next) {
      final state = next.asData?.value;
      if (state == null || state.offline) return;
      unawaited(ref.read(tripRecordingCoordinatorProvider).updateTrips(state.trips).catchError((Object e) {
        debugPrint('여행 기록 일정을 바꾸지 못했습니다: $e');
      }));
    }, fireImmediately: true);
  }

  void _syncTripRecording() {
    unawaited(ref.read(tripRecordingCoordinatorProvider).sync().catchError((Object e) {
      debugPrint('여행 기록을 맞추지 못했습니다: $e');
    }));
  }
```

`app/lib/router.dart`에서 다음 부분을

```dart
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(realtimeTrackingEnabledProvider.notifier).state = state == AppLifecycleState.resumed;
  }
```

다음으로 바꾼다:

```dart
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(realtimeTrackingEnabledProvider.notifier).state = state == AppLifecycleState.resumed;
    // 앱이 포그라운드로 돌아오면 여행 기록을 다시 맞춘다 — 출발일 아침 알림을 눌러 연 경우, 재부팅 뒤 다시 연 경우.
    if (state == AppLifecycleState.resumed) _syncTripRecording();
  }
```

`app/lib/router.dart`에서 다음 부분을

```dart
    // 구독만 유지한다(화면 갱신 불필요) — 어느 탭에 있든 이동 좌표가 계속 저장된다.
    ref.listen(liveRouteProvider, (_, _) {});
```

다음으로 바꾼다:

```dart
    // 구독만 유지한다(화면 갱신 불필요) — 어느 탭에 있든 지도·주변 정보가 지금 위치를 바로 쓴다(저장은 하지 않는다).
    ref.listen(liveRouteProvider, (_, _) {});
```

`app/lib/features/footsteps/map/live_route_tracker.dart` 전체를 다음으로 바꾼다:

```dart
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// 위치 스트림을 받아 화면에 바로 이어 그릴 수 있도록 지금까지 지나온 좌표를 그대로 누적해 낸다.
/// 반환하는 좌표 목록은 이번 스트림 구독 동안만 유효한 화면 표시용 캐시다.
///
/// 저장은 하지 않는다(설계 2026-11-07 9-2). 예전에는 앱이 켜져 있을 때마다 모든 좌표를 RoutePoints에 남겼지만,
/// 이제 이동 기록은 여행 기간에만 기록 서비스가 제안 정책으로 남긴다(trip/trip_recorder.dart).
///
/// 촘촘한 distanceFilter로 구독해야 걷는 경로가 자연스럽게 이어진다. 국가 판정(체크인)은 이 스트림과 무관하게
/// WorkManager 1시간 주기(여행 기간에만)와 수동 "여기 저장"만 담당한다.
Stream<List<LatLng>> trackLiveRoute(Stream<Position> positions, {int maxPoints = 2000}) async* {
  final points = <LatLng>[];
  await for (final position in positions) {
    points.add(LatLng(position.latitude, position.longitude));
    while (points.length > maxPoints) {
      points.removeAt(0);
    }
    yield List.unmodifiable(points);
  }
}
```

`app/lib/features/footsteps/providers/footsteps_providers.dart`에서 다음 부분을

```dart
/// "지금 걷고 있는 경로"를 국가 판정과 무관하게 그대로 이어 그리기 위한 좌표 목록이자,
/// 각 좌표를 RoutePoints 테이블에 영구 저장하는 부수효과를 겸한다(live_route_tracker.dart).
/// 경로가 뚝뚝 끊기지 않도록 촘촘한(10m) distanceFilter로 구독한다. 반환하는
/// 좌표 목록 자체는 이번 구독 동안만 유효한 화면 표시용 캐시이고(화면을 벗어나면 autoDispose로 사라짐),
/// DB에 쌓인 기록은 앱을 껐다 켜도 남는다 — CountryDetailMapPage가 그 기록을 다시 읽는다.
/// 해외 매핑이 진행 중인지. 진행 중에는 한국에서의 실제 이동을 RoutePoints에 저장하지
/// 않는다(해외 매핑 화면이 대신 해외 경로를 저장한다).
final overseasMappingActiveProvider = StateProvider<bool>((ref) => false);
```

다음으로 바꾼다:

```dart
/// 해외 매핑이 진행 중인지. 해외 매핑 화면이 대신 해외 경로를 RoutePoints에 저장한다.
/// (실시간 경로는 R7부터 저장하지 않으므로 이 값이 저장을 막을 일은 없다.)
final overseasMappingActiveProvider = StateProvider<bool>((ref) => false);
```

`app/lib/features/footsteps/providers/footsteps_providers.dart`에서 다음 부분을

```dart
final liveRouteProvider = StreamProvider.autoDispose<List<LatLng>>((ref) {
  final enabled = ref.watch(realtimeTrackingEnabledProvider);
  if (!enabled) return const Stream.empty();

  final positions = ref.watch(livePositionsProvider)();

  return trackAndPersistLiveRoute(
    positions: positions,
    countryResolver: ref.watch(realtimeCountryResolverProvider),
    repository: ref.watch(footstepsRepositoryProvider),
    // 국가 판정을 기다리는 사이 추적이 꺼지거나(백그라운드 전환) 화면을 떠나 이 provider가 사라졌으면
    // ref를 쓸 수 없다. 그때 들어온 좌표는 저장하지 않는다 — 구독이 이미 끝난 뒤의 마지막 한 점이다.
    shouldPersist: () => ref.mounted && !ref.read(overseasMappingActiveProvider),
  );
});
```

다음으로 바꾼다:

```dart
/// "지금 걷고 있는 경로"를 화면에 이어 그리기 위한 좌표 목록(표시 전용, 설계 9-2). 저장하지 않는다 — 이동 기록은
/// 여행 기간에만 기록 서비스가 남긴다. 경로가 뚝뚝 끊기지 않도록 촘촘한(10m) distanceFilter로 구독하고, 화면을
/// 벗어나면 autoDispose로 사라진다. 국가 상세 지도·주변 정보·해외 매핑이 지금 위치로 쓴다.
final liveRouteProvider = StreamProvider.autoDispose<List<LatLng>>((ref) {
  final enabled = ref.watch(realtimeTrackingEnabledProvider);
  if (!enabled) return const Stream.empty();

  return trackLiveRoute(ref.watch(livePositionsProvider)());
});
```

`app/lib/features/footsteps/background/footstep_task_handler.dart` 전체를 다음으로 바꾼다:

```dart
import 'package:geolocator/geolocator.dart';

import '../data/checkin.dart';
import '../data/footsteps_repository.dart';

/// WorkManager 콜백의 실제 판단 로직. isolate 엔트리포인트에서 분리해
/// 단위 테스트가 가능하게 한다.
///
/// 여행 기간에만 체크인한다(설계 2026-11-07 9-2). 작업은 늘 등록해 두되, [isTripPeriod]가 false면 측위 없이 끝낸다 —
/// 여행이 아닌 날 1시간마다 GPS를 켜지 않는다.
Future<void> handleFootstepTask({
  required FootstepsRepository repository,
  required Future<Position> Function() getCurrentPosition,
  required Future<bool> Function() isTripPeriod,
}) async {
  try {
    if (!await isTripPeriod()) return;
    final position = await getCurrentPosition();
    await repository.recordCheckinAt(
      position.latitude,
      position.longitude,
      DateTime.now().toUtc(),
      CheckinSource.auto,
    );
  } catch (_) {
    // 권한 거부, GPS 꺼짐, 오프라인 등. 다음 1시간 주기가 다시 시도하므로
    // 여기서 재시도하지 않는다 — WorkManager에 실패로 보고하면 짧은
    // 백오프로 재시도가 몰려 배터리를 더 쓰게 된다.
  }
}
```

`app/lib/features/footsteps/background/footstep_workmanager.dart`의 import에서 다음 부분을

```dart
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/db/app_database.dart';
import '../data/footsteps_repository.dart';
import '../data/geocoding_country_resolver.dart';
import 'footstep_task_handler.dart';
```

다음으로 바꾼다:

```dart
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/db/app_database.dart';
import '../data/footsteps_repository.dart';
import '../data/geocoding_country_resolver.dart';
import '../trip/trip_period.dart';
import '../trip/trip_recording_store.dart';
import 'footstep_task_handler.dart';
```

`app/lib/features/footsteps/background/footstep_workmanager.dart`에서 다음 부분을

```dart
  await handleFootstepTask(
    repository: repository,
    getCurrentPosition: () => Geolocator.getCurrentPosition(
```

다음으로 바꾼다:

```dart
  await handleFootstepTask(
    repository: repository,
    isTripPeriod: () => isTripPeriodNow(DateTime.now()),
    getCurrentPosition: () => Geolocator.getCurrentPosition(
```

`app/lib/features/footsteps/background/footstep_workmanager.dart`에서 다음 부분을

```dart
/// 앱 시작 시 1회 호출한다(그 전에 `initializeBackgroundWork()`가 끝나 있어야 한다).
```

다음으로 바꾼다:

```dart
/// 지금이 기록할 여행의 기간인가(설계 9-2). 화면 isolate가 저장해 둔 여행 기록 일정·일시정지를 읽는다 — 이 isolate의
/// SharedPreferences 캐시는 낡았을 수 있어 먼저 reload한다.
Future<bool> isTripPeriodNow(DateTime now) async {
  final store = TripRecordingStore(await SharedPreferences.getInstance());
  await store.reload();
  return shouldRecord(store.readTrips(), now, store.readPaused()) != null;
}

/// 앱 시작 시 1회 호출한다(그 전에 `initializeBackgroundWork()`가 끝나 있어야 한다).
```

- [ ] **Step 4: 통과 확인**

Run
- `flutter test test/footsteps/ test/router_test.dart` → 통과
  - 코디네이터 7개, 앱 셸 12개(3개 추가), WorkManager 4개, 실시간 경로 3+1개다.
- `flutter test`(전체) → 통과(768개), `dart analyze lib test` → 0건

앱 셸 테스트의 첫 `sync`는 위치 권한 요청(플랫폼 채널)이 끝난 뒤에 불린다. 그래서 그 테스트는 `tester.runAsync`로 실제 이벤트 루프를 한 번 돌린다.

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/footsteps/trip/trip_recording_permissions.dart \
  app/lib/features/footsteps/trip/trip_recording_coordinator.dart app/lib/features/footsteps/trip/trip_recording_providers.dart \
  app/lib/router.dart app/lib/features/footsteps/map/live_route_tracker.dart \
  app/lib/features/footsteps/providers/footsteps_providers.dart \
  app/lib/features/footsteps/background/footstep_task_handler.dart app/lib/features/footsteps/background/footstep_workmanager.dart \
  app/test/footsteps/trip/trip_fakes.dart app/test/footsteps/trip/trip_recording_coordinator_test.dart \
  app/test/router_test.dart app/test/footsteps/footstep_task_handler_test.dart \
  app/test/footsteps/live_route_tracker_test.dart app/test/footsteps/live_route_provider_test.dart
git commit -m "feat(app): 앱을 열 때 여행 기간이면 여행 기록을 켜고, 실시간 경로는 표시만 하며 1시간 체크인은 여행 기간에만 한다"
```

---

### Task 6: 출발일 아침 알림과 여행 기록 정리(삭제·404·목록·계정 전환)

설계 9-2의 2번과 9-3의 정리다.

출발일 08:00(서울)에 "오늘부터 ○○ 여행 발걸음을 기록합니다." 알림을 예약한다. 누르면 앱이 열리고(플러그인 기본 동작) 앱 셸이 포그라운드로 온 김에 기록을 켠다. 일시정지한 여행에는 만들지 않는다. 비자 알람의 `LocalAlarmBackend`를 채널만 바꿔 다시 쓴다.

정리는 PR #32의 비자 알람 정리와 같은 때에 한다.
- 여행 삭제(`TripDeleter`), 상세 404: `forgetTrip`
- 서버 목록: `updateTrips`가 목록에 없는 여행의 기록을 지운다
- 계정 가드: `claimFor`. 주인 uid를 적어 두는 방식이 알람과 같다.
  - 로그아웃은 기록을 끄고 일정·알림만 비운다. 좌표는 남긴다 — 같은 계정이 다시 로그인하면 그대로 본다.
  - 다른 계정이 로그인하면 이전 여행 좌표를 모두 지운다.

**Files:**
- Modify: `app/lib/features/visa/notifications/alarm_scheduler.dart`(`LocalAlarmBackend`가 채널을 받는다)
- Create: `app/lib/features/footsteps/trip/trip_departure_notices.dart`
- Modify: `app/lib/features/footsteps/trip/trip_recording_coordinator.dart`(전체 교체), `trip_recording_providers.dart`(전체 교체)
- Modify: `app/lib/features/visa/data/trip_deletion.dart`, `app/lib/features/visa/visa_result_page.dart`(404), `app/lib/main.dart`(계정 가드)
- Modify: `app/test/footsteps/trip/trip_fakes.dart`(코디네이터 대역에 두 메서드)
- Test: `app/test/footsteps/trip/trip_departure_notices_test.dart`, `trip_recording_coordinator_test.dart`(전체 교체), `trip_recording_account_guard_test.dart`, `app/test/visa/trip_deletion_test.dart`, `app/test/visa/visa_result_page_test.dart`

**Interfaces:**
- Consumes
  - Task 2: `AppDatabase.deleteTripRecords`·`deleteTripRecordsExcept`
  - Task 3: 저장소의 `forget`·`clearSchedule`·`readOwner`·`writeOwner`·`readNoticeTripIds`·`writeNoticeTripIds`
  - Task 5: 코디네이터
  - 비자 알람의 `AlarmBackend`·`ScheduledAlarm`·`seoulLocation`
- Produces
  - 알림 백엔드: `LocalAlarmBackend([FlutterLocalNotificationsPlugin? plugin, NotificationDetails details = 비자 채널])`
  - 출발일 알림
    - `departureNoticeIdFor(int)`, `departureNoticeTime(TripPeriod)`, `tripNoticeDetails`
    - `TripDepartureNotices(AlarmBackend, TripRecordingStore, {now})`: `sync(trips, paused)`, `cancelAll()`
  - 코디네이터
    - 생성자에 `required notices`, `required db`
    - 새 메서드 `forgetTrip(int)`, `claimFor(String?)`
    - `updateTrips`가 목록 밖 여행의 기록을 지우고 출발일 알림을 맞춘다
  - provider: `tripDepartureNoticesProvider`, `tripRecordingAccountGuardProvider`
  - 테스트 도우미: `FakeTripRecordingCoordinator.forgotten`·`claims`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/footsteps/trip/trip_fakes.dart`의 코디네이터 대역 끝에서 다음 부분을

```dart
  @override
  Future<void> setPaused(int tripId, bool paused) async => pauses.add((tripId, paused));
}
```

다음으로 바꾼다:

```dart
  @override
  Future<void> setPaused(int tripId, bool paused) async => pauses.add((tripId, paused));

  final forgotten = <int>[];
  final claims = <String?>[];

  @override
  Future<void> forgetTrip(int tripId) async => forgotten.add(tripId);

  @override
  Future<void> claimFor(String? uid) async => claims.add(uid);
}
```

`app/test/footsteps/trip/trip_departure_notices_test.dart`:

```dart
import 'package:app/features/footsteps/trip/trip_departure_notices.dart';
import 'package:app/features/footsteps/trip/trip_recording_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../visa/fake_alarm_backend.dart';
import 'trip_fakes.dart';

void main() {
  late FakeAlarmBackend backend;
  late TripRecordingStore store;
  late TripDepartureNotices notices;

  final domestic = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));
  final japan = period(8, DateTime(2026, 12, 1), DateTime(2026, 12, 5), iso2: 'JP', nameKo: '일본');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = TripRecordingStore(await SharedPreferences.getInstance());
    backend = FakeAlarmBackend();
    notices = TripDepartureNotices(backend, store, now: () => seoulTime(2026, 11, 12, 15));
  });

  test('출발일 아침 8시(서울)에 "오늘부터 ○○ 여행 발걸음을 기록합니다." 알림을 예약한다', () async {
    await notices.sync([domestic, japan], const {});

    final alarm = backend.scheduled[departureNoticeIdFor(7)]!;
    expect(alarm.at, seoulTime(2026, 11, 20, 8));
    expect(alarm.body, '오늘부터 대한민국 여행 발걸음을 기록합니다.');
    expect(backend.scheduled[departureNoticeIdFor(8)]!.body, '오늘부터 일본 여행 발걸음을 기록합니다.');
    expect(store.readNoticeTripIds(), {7, 8});
  });

  test('일시정지했거나 이미 아침 8시가 지난 여행은 예약하지 않는다', () async {
    final today = TripDepartureNotices(backend, store, now: () => seoulTime(2026, 11, 20, 8, 1));

    await today.sync([domestic, japan], {8});

    expect(backend.scheduled, isEmpty);
    expect(store.readNoticeTripIds(), isEmpty);
  });

  test('일정에서 빠지거나 일시정지한 여행의 알림은 지운다', () async {
    await notices.sync([domestic, japan], const {});

    await notices.sync([japan], {8});

    expect(backend.cancelled, unorderedEquals([departureNoticeIdFor(7), departureNoticeIdFor(8)]));
    expect(backend.scheduled, isEmpty);
    expect(store.readNoticeTripIds(), isEmpty);
  });

  test('모두 지우면(로그아웃) 예약해 둔 알림이 남지 않는다', () async {
    await notices.sync([domestic, japan], const {});

    await notices.cancelAll();

    expect(backend.scheduled, isEmpty);
    expect(store.readNoticeTripIds(), isEmpty);
  });

  test('비자 준비 알람·환율 알림 id와 겹치지 않고 32비트 안에 든다', () {
    expect(departureNoticeIdFor(1), greaterThanOrEqualTo(2100000000));
    expect(departureNoticeIdFor(39999999), lessThan(2147483647));
  });
}
```

`app/test/footsteps/trip/trip_recording_coordinator_test.dart` 전체를 다음으로 바꾼다:

```dart
import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/trip/trip_departure_notices.dart';
import 'package:app/features/footsteps/trip/trip_recording_coordinator.dart';
import 'package:app/features/footsteps/trip/trip_recording_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../visa/fake_alarm_backend.dart';
import '../../visa/fake_trip_api.dart' show sampleSummary;
import 'trip_fakes.dart';

void main() {
  late TripRecordingStore store;
  late FakeTripRecordingService service;
  late FakeTripRecordingPermissions permissions;
  late FakeAlarmBackend alarms;
  late AppDatabase db;
  late DateTime now;
  late TripRecordingCoordinator coordinator;

  final domestic = sampleSummary(
      id: 7, iso2: 'KR', nameKo: '대한민국', depart: DateTime(2026, 11, 20), ret: DateTime(2026, 11, 22));
  final later = sampleSummary(id: 9, depart: DateTime(2026, 11, 21), ret: DateTime(2026, 11, 25));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = TripRecordingStore(await SharedPreferences.getInstance());
    service = FakeTripRecordingService();
    permissions = FakeTripRecordingPermissions();
    alarms = FakeAlarmBackend();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    now = DateTime(2026, 11, 20, 9);
    coordinator = TripRecordingCoordinator(
      store: store,
      service: service,
      permissions: permissions,
      notices: TripDepartureNotices(alarms, store, now: () => seoulTime(2026, 11, 12, 15)),
      db: db,
      clock: () => now,
    );
  });

  Future<void> addPoint(int tripId) => db.insertTripPoint(
      tripId: tripId, lat: 37.5, lng: 127.0, countryIso: 'KR', recordedAt: DateTime.utc(2026, 11, 20, 1));

  group('켜기·끄기', () {
    test('목록을 받으면 일정을 바꾸고, 오늘이 여행 기간이면 그 여행으로 기록 서비스를 켠다', () async {
      await coordinator.updateTrips([domestic]);

      expect(store.readTrips().single.tripId, 7);
      expect(service.started, [7]);

      // 이미 그 여행으로 돌고 있으면 다시 켜지 않는다(앱을 다시 열 때마다 부른다).
      await coordinator.sync();
      expect(service.started, [7]);
    });

    test('여행 기간이 아니면 켜지 않고, 돌던 여행 기록은 끈다', () async {
      now = DateTime(2026, 11, 19, 23, 59);
      await coordinator.updateTrips([domestic]);
      expect(service.started, isEmpty);

      now = DateTime(2026, 11, 20);
      await coordinator.sync();
      expect(service.started, [7]);

      now = DateTime(2026, 11, 23);
      await coordinator.sync();
      expect(service.stops, 1);
      expect(service.runningTripId, isNull);
    });

    test('일시정지하면 끄고, 재개하면 다시 켠다', () async {
      await coordinator.updateTrips([domestic]);

      await coordinator.setPaused(7, true);
      expect(store.readPaused(), {7});
      expect(service.runningTripId, isNull);

      await coordinator.setPaused(7, false);
      expect(service.started, [7, 7]);
    });

    test('겹치는 여행이 새로 시작하면 그 여행으로 바꿔 켠다', () async {
      await coordinator.updateTrips([domestic, later]);
      expect(service.started, [7]);

      now = DateTime(2026, 11, 21, 8);
      await coordinator.sync();
      expect(service.stops, 1);
      expect(service.started, [7, 9]);
    });

    test('실험 화면의 세션이 돌고 있으면 건드리지 않는다(배터리 측정이 오염된다)', () async {
      service.labRunning = true;

      await coordinator.updateTrips([domestic]);

      expect(service.started, isEmpty);
      expect(service.stops, 0);
    });

    test('위치 권한이 없으면 켜지 않는다', () async {
      permissions.location = false;

      await coordinator.updateTrips([domestic]);

      expect(service.started, isEmpty);
    });

    test('앱을 열 때와 목록 도착이 겹쳐도 한 번만 켠다', () async {
      await store.replaceTrips([period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22))]);

      await Future.wait([coordinator.sync(), coordinator.updateTrips([domestic]), coordinator.sync()]);

      expect(service.started, [7]);
    });
  });

  group('출발일 알림', () {
    test('목록을 받으면 출발일 아침 알림을 맞추고, 일시정지하면 지운다', () async {
      await coordinator.updateTrips([domestic, later]);
      expect(alarms.scheduled.keys, unorderedEquals([departureNoticeIdFor(7), departureNoticeIdFor(9)]));

      await coordinator.setPaused(9, true);
      expect(alarms.scheduled.keys, [departureNoticeIdFor(7)]);
    });

    test('알림이 실패해도 기록은 켠다', () async {
      final failing = TripRecordingCoordinator(
        store: store,
        service: service,
        permissions: permissions,
        notices: TripDepartureNotices(FakeAlarmBackend(failing: true), store,
            now: () => seoulTime(2026, 11, 12, 15)),
        db: db,
        clock: () => now,
      );

      await failing.updateTrips([domestic]);

      expect(service.started, [7]);
    });
  });

  group('기록 정리(설계 9-3)', () {
    test('목록에 없는 여행의 좌표·정지 구간은 지운다(다른 기기에서 지웠거나 다른 계정의 여행)', () async {
      await addPoint(7);
      await addPoint(8);
      await db.insertTripStillSpan(
          tripId: 8, startAt: DateTime.utc(2026, 11, 20, 1), endAt: DateTime.utc(2026, 11, 20, 2));

      await coordinator.updateTrips([domestic]);

      expect(await db.routePointsForTrip(7), hasLength(1));
      expect(await db.routePointsForTrip(8), isEmpty);
      expect(await db.stillSpansForTrip(8), isEmpty);
    });

    test('여행을 지우면 기록 중이던 서비스를 끄고 좌표·일시정지·출발일 알림을 지운다', () async {
      await coordinator.updateTrips([domestic, later]);
      await coordinator.setPaused(9, true);
      await addPoint(7);

      await coordinator.forgetTrip(7);

      expect(service.runningTripId, isNull);
      expect(await db.routePointsForTrip(7), isEmpty);
      expect(store.readTrips().map((t) => t.tripId), [9]);
      expect(alarms.scheduled, isEmpty); // 7은 지웠고 9는 일시정지
    });

    test('기록 중이 아닌 여행을 지우면 서비스는 그대로 둔다', () async {
      await coordinator.updateTrips([domestic, later]);

      await coordinator.forgetTrip(9);

      expect(service.runningTripId, 7);
    });

    test('같은 계정이면 아무것도 하지 않고, 처음 로그인하면 주인만 적는다', () async {
      await addPoint(7);

      await coordinator.claimFor('uid-a');
      expect(store.readOwner(), 'uid-a');

      await coordinator.updateTrips([domestic]);
      await coordinator.claimFor('uid-a');
      expect(service.runningTripId, 7);
      expect(await db.routePointsForTrip(7), hasLength(1));
    });

    test('로그아웃하면 기록을 끄고 일정·알림을 비우되 좌표는 남긴다', () async {
      await coordinator.claimFor('uid-a');
      await coordinator.updateTrips([domestic]);
      await addPoint(7);

      await coordinator.claimFor(null);

      expect(service.runningTripId, isNull);
      expect(store.readTrips(), isEmpty);
      expect(alarms.scheduled, isEmpty);
      expect(await db.routePointsForTrip(7), hasLength(1));
      expect(store.readOwner(), 'uid-a');
    });

    test('다른 계정이 로그인하면 이전 계정의 여행 좌표를 모두 지운다', () async {
      await coordinator.claimFor('uid-a');
      await coordinator.updateTrips([domestic]);
      await addPoint(7);
      await coordinator.claimFor(null);

      await coordinator.claimFor('uid-b');

      expect(await db.routePointsForTrip(7), isEmpty);
      expect(store.readOwner(), 'uid-b');
    });
  });
}
```

`app/test/footsteps/trip/trip_recording_account_guard_test.dart`:

```dart
import 'dart:async';

import 'package:app/core/auth/app_user.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/footsteps/trip/trip_recording_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'trip_fakes.dart';

void main() {
  test('인증 상태를 알 때마다 기록의 주인을 맞추고, 아직 모를 때는 아무것도 하지 않는다', () async {
    final auth = StreamController<AppUser?>();
    addTearDown(auth.close);
    final coordinator = FakeTripRecordingCoordinator();
    final container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => auth.stream),
      tripRecordingCoordinatorProvider.overrideWithValue(coordinator),
    ]);
    addTearDown(container.dispose);
    container.listen(tripRecordingAccountGuardProvider, (_, _) {});

    await pumpEventQueue();
    expect(coordinator.claims, isEmpty, reason: '로딩 중에는 로그인한 사용자의 기록을 끄면 안 된다');

    auth.add(const AppUser(uid: 'uid-a'));
    await pumpEventQueue();
    auth.add(null);
    await pumpEventQueue();
    auth.add(const AppUser(uid: 'uid-b'));
    await pumpEventQueue();

    expect(coordinator.claims, ['uid-a', null, 'uid-b']);
  });
}
```

`app/test/visa/trip_deletion_test.dart`의 import에서 다음 부분을

```dart
import 'package:app/core/prefs/shared_preferences_provider.dart';
```

다음으로 바꾼다:

```dart
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/footsteps/trip/trip_recording_providers.dart';
```

`app/test/visa/trip_deletion_test.dart`에서 다음 부분을

```dart
import 'fake_alarm_backend.dart';
import 'fake_trip_api.dart';

Future<({ProviderContainer container, WalletDatabase db, SharedPreferences prefs, FakeAlarmBackend alarms})>
    _setUp(FakeTripApi api, {FakeAlarmBackend? alarms}) async {
```

다음으로 바꾼다:

```dart
import '../footsteps/trip/trip_fakes.dart';
import 'fake_alarm_backend.dart';
import 'fake_trip_api.dart';

/// 정리하다 실패하는 여행 기록 대역.
class _FailingRecording extends FakeTripRecordingCoordinator {
  @override
  Future<void> forgetTrip(int tripId) async => throw StateError('기록 정리 실패');
}

Future<
        ({
          ProviderContainer container,
          WalletDatabase db,
          SharedPreferences prefs,
          FakeAlarmBackend alarms,
          FakeTripRecordingCoordinator recording,
        })>
    _setUp(FakeTripApi api, {FakeAlarmBackend? alarms, FakeTripRecordingCoordinator? recording}) async {
```

`app/test/visa/trip_deletion_test.dart`에서 다음 부분을

```dart
  final alarmBackend = alarms ?? FakeAlarmBackend();
  final container = ProviderContainer(overrides: [
```

다음으로 바꾼다:

```dart
  final alarmBackend = alarms ?? FakeAlarmBackend();
  final trips = recording ?? FakeTripRecordingCoordinator();
  final container = ProviderContainer(overrides: [
    tripRecordingCoordinatorProvider.overrideWithValue(trips),
```

`app/test/visa/trip_deletion_test.dart`에서 다음 부분을

```dart
  return (container: container, db: db, prefs: prefs, alarms: alarmBackend);
```

다음으로 바꾼다:

```dart
  return (container: container, db: db, prefs: prefs, alarms: alarmBackend, recording: trips);
```

`app/test/visa/trip_deletion_test.dart`에서 다음 부분을

```dart
    expect(s.container.read(selectedTripIdProvider), isNull);
    expect(s.alarms.scheduled.keys, [notificationIdFor(80)]);
  });
```

다음으로 바꾼다:

```dart
    expect(s.container.read(selectedTripIdProvider), isNull);
    expect(s.alarms.scheduled.keys, [notificationIdFor(80)]);
    expect(s.recording.forgotten, [7]); // 발걸음 기록(좌표·정지 구간)도 지운다
  });

  test('발걸음 기록 정리가 실패해도 삭제는 성공으로 끝나고 지갑까지 정리한다', () async {
    final s = await _setUp(FakeTripApi(), recording: _FailingRecording());

    await s.container.read(tripDeleterProvider).delete(7);

    expect(await s.db.watchExpenses(7).first, isEmpty);
  });
```

`app/test/visa/trip_deletion_test.dart`에서 다음 부분을

```dart
    expect(s.alarms.scheduled.keys,
        unorderedEquals([notificationIdFor(70), notificationIdFor(80)]));
  });
```

다음으로 바꾼다:

```dart
    expect(s.alarms.scheduled.keys,
        unorderedEquals([notificationIdFor(70), notificationIdFor(80)]));
    expect(s.recording.forgotten, isEmpty);
  });
```

`app/test/visa/visa_result_page_test.dart`: 여행 상세가 이제 코디네이터를 부르므로 대역을 넣는다. import에서 다음 부분을

```dart
import 'package:app/core/prefs/shared_preferences_provider.dart';
```

다음으로 바꾼다:

```dart
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/footsteps/trip/trip_recording_providers.dart';
```

`app/test/visa/visa_result_page_test.dart`에서 다음 부분을

```dart
import 'fake_alarm_backend.dart';
import 'fake_trip_api.dart';
```

다음으로 바꾼다:

```dart
import '../footsteps/trip/trip_fakes.dart';
import 'fake_alarm_backend.dart';
import 'fake_trip_api.dart';
```

`app/test/visa/visa_result_page_test.dart`에서 다음 부분을

```dart
      _FakeTripDeleter deleter,
      FakeAlarmBackend alarms,
    })> pumpResultPage(
```

다음으로 바꾼다:

```dart
      _FakeTripDeleter deleter,
      FakeAlarmBackend alarms,
      FakeTripRecordingCoordinator recording,
    })> pumpResultPage(
```

`app/test/visa/visa_result_page_test.dart`에서 다음 부분을

```dart
  final deleter = _FakeTripDeleter(fails: deleteFails);
  final alarmBackend = alarms ?? FakeAlarmBackend();
```

다음으로 바꾼다:

```dart
  final deleter = _FakeTripDeleter(fails: deleteFails);
  final alarmBackend = alarms ?? FakeAlarmBackend();
  final recording = FakeTripRecordingCoordinator();
```

`app/test/visa/visa_result_page_test.dart`에서 다음 부분을

```dart
        notificationPermissionProvider.overrideWithValue(permission ?? FakePermission()),
      ],
```

다음으로 바꾼다:

```dart
        notificationPermissionProvider.overrideWithValue(permission ?? FakePermission()),
        tripRecordingCoordinatorProvider.overrideWithValue(recording),
      ],
```

`app/test/visa/visa_result_page_test.dart`에서 다음 부분을

```dart
  return (api: api, prefs: prefs, deleter: deleter, alarms: alarmBackend);
```

다음으로 바꾼다:

```dart
  return (api: api, prefs: prefs, deleter: deleter, alarms: alarmBackend, recording: recording);
```

`app/test/visa/visa_result_page_test.dart`에서 다음 부분을

```dart
  testWidgets('404면 여행 목록을 다시 불러온다', (tester) async {
```

다음으로 바꾼다:

```dart
  testWidgets('404면 그 여행의 발걸음 기록도 지운다', (tester) async {
    final r = await pumpResultPage(tester, getTripStatusCode: 404);

    expect(r.recording.forgotten, [7]);
  });

  testWidgets('404면 여행 목록을 다시 불러온다', (tester) async {
```

- [ ] **Step 2: 실패 확인**

Run(`app/`에서): `flutter test test/footsteps/trip/ test/visa/`

Expected: FAIL. `trip_departure_notices.dart`가 없고, 코디네이터에 `notices`·`db`·`forgetTrip`·`claimFor`가 없다.

- [ ] **Step 3: 구현**

`app/lib/features/visa/notifications/alarm_scheduler.dart`에서 다음 부분을

```dart
/// flutter_local_notifications로 기기에 예약한다. 재부팅 후 다시 예약하는 일은 플러그인의
/// ScheduledNotificationBootReceiver(AndroidManifest.xml)가 한다.
class LocalAlarmBackend implements AlarmBackend {
  LocalAlarmBackend([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
```

다음으로 바꾼다:

```dart
/// flutter_local_notifications로 기기에 예약한다. 재부팅 후 다시 예약하는 일은 플러그인의
/// ScheduledNotificationBootReceiver(AndroidManifest.xml)가 한다.
///
/// [_details]로 알림 채널을 고른다. 기본은 비자 준비 알람이고, 여행 출발일 알림(R7)은 자기 채널을 넘긴다.
class LocalAlarmBackend implements AlarmBackend {
  LocalAlarmBackend([FlutterLocalNotificationsPlugin? plugin, this._details = _visaDetails])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final NotificationDetails _details;
  bool _initialized = false;
```

`app/lib/features/visa/notifications/alarm_scheduler.dart`에서 다음 부분을

```dart
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
```

다음으로 바꾼다:

```dart
  static const _visaDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
```

`schedule`은 이미 `_details`를 쓰므로 그대로다(이제 필드다).

`app/lib/features/footsteps/trip/trip_departure_notices.dart`:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../visa/notifications/alarm_scheduler.dart';
import 'trip_period.dart';
import 'trip_recording_store.dart';

/// 출발일 알림 시각: 출발일 아침 8시(설계 2026-11-07 9-2의 2번). 출발은 한국에서 하므로 서울 시간으로 맞춘다
/// (비자 준비 알람과 같은 시간대 데이터를 쓴다).
const _noticeHour = 8;

/// 비자 준비 알람 id(11억~21억) 뒤에 두어 겹치지 않게 한다. 끝(21.4억)이 32비트 정수 한도(약 21.47억) 안에 들어간다.
const _noticeIdBase = 2100000000;
const _noticeIdSlots = 40000000;

int departureNoticeIdFor(int tripId) => _noticeIdBase + tripId % _noticeIdSlots;

tz.TZDateTime departureNoticeTime(TripPeriod trip) => tz.TZDateTime(
    seoulLocation(), trip.departDate.year, trip.departDate.month, trip.departDate.day, _noticeHour);

/// 출발일 알림 채널. Android는 채널 id를 영구 식별자로 다루므로 바꾸지 않는다.
const tripNoticeDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'com.travelfootsteps.trip_recording',
    '여행 기록 알림',
    channelDescription: '여행 출발일 아침, 발걸음 기록을 시작한다고 알려 줍니다.',
    importance: Importance.high,
    priority: Priority.high,
  ),
);

/// 출발일 아침 알림(설계 9-2의 2번). "오늘부터 ○○ 여행 발걸음을 기록합니다." 알림을 누르면 앱이 열리고(플러그인 기본
/// 동작), 앱 셸이 포그라운드로 온 김에 여행 기록을 켠다. 기록 서비스는 백그라운드에서 켤 수 없어서 이 알림이 사용자를
/// 앱으로 데려온다.
///
/// 예약해 둔 여행 id를 저장소에 적어 두고, 일정이 바뀌면 필요 없어진 알림을 지운다. 재부팅 뒤 다시 예약하는 일은
/// 플러그인의 ScheduledNotificationBootReceiver가 한다.
class TripDepartureNotices {
  TripDepartureNotices(this._backend, this._store, {tz.TZDateTime Function()? now})
      : _now = now ?? (() => tz.TZDateTime.now(seoulLocation()));

  final AlarmBackend _backend;
  final TripRecordingStore _store;
  final tz.TZDateTime Function() _now;

  /// [trips] 중 일시정지하지 않았고 아직 아침 8시 전인 여행마다 알림을 예약하고, 그 밖에 예약해 둔 알림은 지운다.
  Future<void> sync(List<TripPeriod> trips, Set<int> paused) async {
    final now = _now();
    final wanted = {
      for (final trip in trips)
        if (!paused.contains(trip.tripId) && departureNoticeTime(trip).isAfter(now)) trip.tripId: trip,
    };
    final registered = _store.readNoticeTripIds();
    try {
      for (final tripId in registered.difference(wanted.keys.toSet())) {
        await _backend.cancel(departureNoticeIdFor(tripId));
        registered.remove(tripId);
      }
      for (final trip in wanted.values) {
        // 예약 전에 적는다 — 도중에 실패해도 다음 sync가 지울 수 있게.
        registered.add(trip.tripId);
        await _store.writeNoticeTripIds(registered);
        await _backend.schedule(ScheduledAlarm(
          id: departureNoticeIdFor(trip.tripId),
          title: '여행 발걸음 기록',
          body: '오늘부터 ${trip.countryNameKo} 여행 발걸음을 기록합니다.',
          at: departureNoticeTime(trip),
        ));
      }
    } finally {
      await _store.writeNoticeTripIds(registered);
    }
  }

  /// 예약해 둔 출발일 알림을 모두 지운다(로그아웃·계정 전환).
  Future<void> cancelAll() => sync(const [], const {});
}
```

`app/lib/features/footsteps/trip/trip_recording_coordinator.dart` 전체를 다음으로 바꾼다:

```dart
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/db/app_database.dart';
import '../../visa/models/trip_summary.dart';
import 'trip_departure_notices.dart';
import 'trip_period.dart';
import 'trip_recording_permissions.dart';
import 'trip_recording_service.dart';
import 'trip_recording_store.dart';

/// 화면(main isolate)에서 여행 기록을 켜고 끄는 곳(설계 2026-11-07 9-2). 무엇을 기록할지는 순수 함수 [shouldRecord]가
/// 정하고, 여기서는 그 결과에 기록 서비스를 맞춘다.
///
/// 켜는 것은 언제나 앱이 화면에 있을 때다 — Android 14가 백그라운드에서 위치 포그라운드 서비스를 켜는 것을 막는다.
/// 그래서 앱 셸이 앱을 열 때·포그라운드로 돌아올 때 [sync]를, 여행 목록을 받을 때 [updateTrips]를 부르고, 여행 상세의
/// 일시정지·재개가 [setPaused]를 부른다. 끄는 것은 여기(일시정지·기간 밖·정리)와 기록 서비스 자신(귀국 다음 날)이 한다.
///
/// 기록 정리(설계 9-3)도 여기서 한다. 비자 알람 정리(PR #32)와 같은 때에 부른다: 여행 삭제·없는 여행(404)은 [forgetTrip],
/// 목록을 다시 받을 때는 [updateTrips], 계정이 바뀔 때는 [claimFor].
///
/// 모든 작업은 부른 순서대로 하나씩 한다. 앱을 열자마자 목록이 도착하면 두 작업이 동시에 "꺼져 있다"고 보고 서비스를
/// 두 번 켜려 하고, 지우는 중인 여행을 다른 작업이 다시 켤 수 있기 때문이다.
class TripRecordingCoordinator {
  TripRecordingCoordinator({
    required this._store,
    required this._service,
    required this._permissions,
    required this._notices,
    required this._db,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TripRecordingStore _store;
  final TripRecordingService _service;
  final TripRecordingPermissions _permissions;
  final TripDepartureNotices _notices;
  final AppDatabase _db;
  final DateTime Function() _clock;

  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (Object _) {}); // 한 작업이 실패해도 다음 작업은 이어간다.
    return result;
  }

  /// 기록 서비스를 지금(일정·일시정지·날짜)에 맞춘다.
  Future<void> sync() => _serial(_sync);

  /// 서버에서 받은 내 여행 목록으로 일정을 바꾼다. 목록에 없는 여행의 기록(좌표·정지 구간)은 지운다 — 다른 기기에서
  /// 지웠거나 다른 계정의 여행이다. 출발일 알림과 기록 서비스도 다시 맞춘다. 오프라인 캐시 목록은 넘기지 않는다.
  Future<void> updateTrips(List<TripSummary> trips) => _serial(() async {
        final periods = [for (final t in trips) TripPeriod.fromSummary(t)];
        await _store.replaceTrips(periods);
        await _db.deleteTripRecordsExcept({for (final p in periods) p.tripId});
        await _syncNotices();
        await _sync();
      });

  /// 여행 상세의 일시정지·재개. 일시정지 상태는 여행별로 기기에 남는다. 일시정지한 여행은 출발일 알림도 없다.
  Future<void> setPaused(int tripId, bool paused) => _serial(() async {
        await _store.setPaused(tripId, paused);
        await _syncNotices();
        await _sync();
      });

  /// 여행이 없어졌을 때(삭제, 다른 기기에서 지워져 404): 그 여행을 기록 중이면 끄고, 좌표·정지 구간·일시정지·출발일
  /// 알림을 지운다. 서비스가 끝나며 마저 쓴 점이 남으면 다음 [updateTrips]가 지운다.
  Future<void> forgetTrip(int tripId) => _serial(() async {
        if (await _service.recordingTripId() == tripId) await _service.stop();
        await _db.deleteTripRecords([tripId]);
        await _store.forget({tripId});
        await _syncNotices();
      });

  /// 지금 로그인한 계정([uid], 로그아웃이면 null)을 기록의 주인으로 정한다(PR #32의 알람 주인과 같은 방식).
  /// - 같은 계정이면 아무것도 하지 않는다.
  /// - 로그아웃이면 기록을 끄고 일정·일시정지·출발일 알림을 비운다. 좌표는 남긴다 — 같은 계정이 다시 로그인하면 그대로 본다.
  /// - 다른 계정이면 위에 더해 이전 계정의 여행 좌표·정지 구간을 모두 지운다.
  /// 주인이 적혀 있지 않으면(처음 실행) 지울 좌표가 없다고 보고 주인만 적는다.
  Future<void> claimFor(String? uid) => _serial(() async {
        final owner = _store.readOwner();
        if (uid != null && owner == uid) return;
        if (await _service.recordingTripId() != null) await _service.stop();
        await _store.clearSchedule();
        try {
          await _notices.cancelAll();
        } catch (e) {
          debugPrint('출발일 알림을 지우지 못했습니다: $e');
        }
        if (uid == null) return;
        if (owner != null) await _db.deleteTripRecordsExcept(const {});
        await _store.writeOwner(uid);
      });

  /// 알림은 부가 기능이라 실패해도(플러그인·권한 오류) 기록을 맞추는 일은 막지 않는다.
  Future<void> _syncNotices() async {
    try {
      await _notices.sync(_store.readTrips(), _store.readPaused());
    } catch (e) {
      debugPrint('출발일 알림을 맞추지 못했습니다: $e');
    }
  }

  Future<void> _sync() async {
    final running = await _service.isRunning();
    final active = running ? await _service.recordingTripId() : null;
    // 실험 화면의 세션이 돌고 있다. 같이 돌면 배터리 측정이 오염되므로(설계 4-1) 건드리지 않는다.
    if (running && active == null) return;
    final target = shouldRecord(_store.readTrips(), _clock(), _store.readPaused());
    if (active != null && active != target?.tripId) await _service.stop();
    if (target == null || active == target.tripId) return;
    // 위치 권한이 없으면 서비스가 켜지자마자 죽는다. 날짜별 보기의 "기록이 꺼져 있어요" 배너가 알린다.
    if (!await _permissions.canRecord()) return;
    await _service.start(target);
  }
}
```

`app/lib/features/footsteps/trip/trip_recording_providers.dart` 전체를 다음으로 바꾼다:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_user.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/prefs/shared_preferences_provider.dart';
import '../../visa/notifications/alarm_scheduler.dart';
import 'trip_departure_notices.dart';
import 'trip_recording_coordinator.dart';
import 'trip_recording_permissions.dart';
import 'trip_recording_service.dart';
import 'trip_recording_store.dart';

final tripRecordingStoreProvider = Provider<TripRecordingStore>(
  (ref) => TripRecordingStore(ref.watch(sharedPreferencesProvider)),
);

final tripRecordingServiceProvider =
    Provider<TripRecordingService>((ref) => const ForegroundTripRecordingService());

final tripRecordingPermissionsProvider =
    Provider<TripRecordingPermissions>((ref) => const PermissionHandlerTripRecordingPermissions());

final tripDepartureNoticesProvider = Provider<TripDepartureNotices>(
  (ref) => TripDepartureNotices(
    LocalAlarmBackend(null, tripNoticeDetails),
    ref.watch(tripRecordingStoreProvider),
  ),
);

/// 작업을 한 줄로 세우는 객체라 앱 전체에 하나만 둔다.
final tripRecordingCoordinatorProvider = Provider<TripRecordingCoordinator>(
  (ref) => TripRecordingCoordinator(
    store: ref.watch(tripRecordingStoreProvider),
    service: ref.watch(tripRecordingServiceProvider),
    permissions: ref.watch(tripRecordingPermissionsProvider),
    notices: ref.watch(tripDepartureNoticesProvider),
    db: ref.watch(appDatabaseProvider),
  ),
);

/// 로그아웃하거나 다른 계정으로 바뀌면 이전 계정의 여행 기록을 끄고 정리한다(설계 9-3, PR #32의 비자 알람 계정 가드와
/// 같은 방식). 앱 최상단(main.dart의 _Root)이 watch해서 앱이 떠 있는 동안 계속 지켜본다. 인증 상태를 아직 모를 때(로딩)는
/// 아무것도 하지 않는다 — 로그인한 사용자의 기록을 끄면 안 된다.
final tripRecordingAccountGuardProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<AppUser?>>(authStateProvider, (previous, next) {
    if (!next.hasValue) return;
    unawaited(ref.read(tripRecordingCoordinatorProvider).claimFor(next.value?.uid).catchError((Object e) {
      debugPrint('이전 계정의 여행 기록 정리 실패: $e');
    }));
  }, fireImmediately: true);
});
```

`app/lib/features/visa/data/trip_deletion.dart`에서 다음 부분을

```dart
import '../../checklist/data/checklist_providers.dart';
import '../../wallet/data/wallet_database.dart';
```

다음으로 바꾼다:

```dart
import '../../checklist/data/checklist_providers.dart';
import '../../footsteps/trip/trip_recording_providers.dart';
import '../../wallet/data/wallet_database.dart';
```

`app/lib/features/visa/data/trip_deletion.dart`에서 다음 부분을

```dart
    try {
      await ref.read(alarmSchedulerProvider).cancelForTrip(tripId);
    } catch (_) {}
    await ref.read(walletDatabaseProvider).clearWallet(tripId);
```

다음으로 바꾼다:

```dart
    try {
      await ref.read(alarmSchedulerProvider).cancelForTrip(tripId);
    } catch (_) {}
    // 여행 기록(설계 9-3)도 같은 이유로 실패해도 삭제를 막지 않는다. 남은 좌표는 다음에 목록을 받을 때 지운다.
    try {
      await ref.read(tripRecordingCoordinatorProvider).forgetTrip(tripId);
    } catch (_) {}
    await ref.read(walletDatabaseProvider).clearWallet(tripId);
```

`app/lib/features/visa/visa_result_page.dart`(상세 404 처리)에서 다음 부분을

```dart
import '../../core/theme/wireframe_widgets.dart';
import '../rate_alert/notify/notification_permission.dart';
```

다음으로 바꾼다:

```dart
import '../../core/theme/wireframe_widgets.dart';
import '../footsteps/trip/trip_recording_providers.dart';
import '../rate_alert/notify/notification_permission.dart';
```

`app/lib/features/visa/visa_result_page.dart`에서 다음 부분을

```dart
      ref.read(alarmSchedulerProvider).cancelForTrip(tripId).catchError((Object e) {
        debugPrint('지워진 여행의 비자 준비 알람 정리 실패: $e');
      });
```

다음으로 바꾼다:

```dart
      ref.read(alarmSchedulerProvider).cancelForTrip(tripId).catchError((Object e) {
        debugPrint('지워진 여행의 비자 준비 알람 정리 실패: $e');
      });
      // 그 여행의 발걸음 기록(좌표·정지 구간·일시정지)도 지운다(설계 9-3).
      ref.read(tripRecordingCoordinatorProvider).forgetTrip(tripId).catchError((Object e) {
        debugPrint('지워진 여행의 발걸음 기록 정리 실패: $e');
      });
```

`app/lib/main.dart`에서 다음 부분을

```dart
import 'features/footsteps/background/footstep_workmanager.dart';
```

다음으로 바꾼다:

```dart
import 'features/footsteps/background/footstep_workmanager.dart';
import 'features/footsteps/trip/trip_recording_providers.dart';
```

`app/lib/main.dart`에서 다음 부분을

```dart
    // 로그아웃·계정 전환 때 이전 계정의 비자 준비 알람을 지운다(앱이 떠 있는 동안 계속 지켜본다).
    ref.watch(visaAlarmAccountGuardProvider);
```

다음으로 바꾼다:

```dart
    // 로그아웃·계정 전환 때 이전 계정의 비자 준비 알람을 지운다(앱이 떠 있는 동안 계속 지켜본다).
    ref.watch(visaAlarmAccountGuardProvider);
    // 같은 때에 이전 계정의 여행 기록을 끄고, 다른 계정이면 그 좌표까지 지운다(설계 9-3).
    ref.watch(tripRecordingAccountGuardProvider);
```

- [ ] **Step 4: 통과 확인**

Run
- `flutter test test/footsteps/trip/ test/visa/` → 통과
  - 출발일 알림 5개, 코디네이터 15개, 계정 가드 1개, 삭제 5개, 여행 상세 36개다.
- `flutter test`(전체) → 통과(784개), `dart analyze lib test` → 0건

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/visa/notifications/alarm_scheduler.dart app/lib/features/footsteps/trip/trip_departure_notices.dart \
  app/lib/features/footsteps/trip/trip_recording_coordinator.dart app/lib/features/footsteps/trip/trip_recording_providers.dart \
  app/lib/features/visa/data/trip_deletion.dart app/lib/features/visa/visa_result_page.dart app/lib/main.dart \
  app/test/footsteps/trip/trip_fakes.dart app/test/footsteps/trip/trip_departure_notices_test.dart \
  app/test/footsteps/trip/trip_recording_coordinator_test.dart app/test/footsteps/trip/trip_recording_account_guard_test.dart \
  app/test/visa/trip_deletion_test.dart app/test/visa/visa_result_page_test.dart
git commit -m "feat(app): 출발일 아침 알림을 예약하고 여행 삭제·목록·계정 전환 때 여행 기록을 정리한다"
```

---

### Task 7: 여행의 날짜별 발걸음 화면

설계 9-4다. **화면 모양은 와이어프레임 확인 필요(사용자)** — Claude Design 프로젝트를 열 수 없어 여행 상세의 시각 언어를 그대로 따랐다.
- 머리글: 54px, 뒤로가기, 제목 '○○ 발걸음', 날짜 범위
- 날짜: `FilterPill` 칩
- 지도: `BaseGoogleMap`
- 요약: `WireframeCard`

동작은 다음과 같다.
- 날짜·묶음
  - 출발일~귀국일 날짜 칩을 둔다. 처음 고르는 날은 여행 중이면 오늘, 아니면 기록이 있는 마지막 날, 그것도 없으면 출발일이다.
  - 점은 기기 현지 날짜로 묶는다. 국가 지도·걸음 귀속과 같은 `dayKeyOf`를 쓴다.
- 머문 곳
  - footstep_core `detectStays`(R5)에 그날과 겹치는 정지 구간을 자르지 않고 넘긴다. 밤을 넘긴 숙소도 실제 도착·출발 시각으로 보인다.
  - 마커 제목은 '10:00 도착', 설명은 '32분 머묾'이다.
- 경로
  - `POST /api/route/reconstruct`를 방법 없이(서버 기본 `osrm_match_radius`) 부른다. 2000개가 넘으면 점 하나를 겹쳐 나눈다.
  - 결과는 `FutureProvider.family`(autoDispose 아님)에 (여행, 날짜, 마지막 점 시각)을 키로 남긴다.
  - 실패하면 점을 직선으로 잇고 "도로 맞춤을 못 했어요"와 [다시 시도]를 보인다. 서버가 직선으로 대신 채운 구간(`fallback: true`)도 같은 안내다.
  - `estimated`는 점선, 탈것은 주황 선이다.
- 그날 걸음은 `steps_since_prev` 합, 이동 거리는 그린 경로 길이다.
- 권한(백그라운드 위치·활동 인식·알림)이 하나라도 없으면 "기록이 꺼져 있어요" 배너와 [설정 열기]를 띄운다.
- 기록 서비스는 다른 isolate의 DB 연결로 쓰므로 drift watch로는 새 점을 모른다. 화면을 열 때·포그라운드 복귀·새로고침 버튼으로 다시 읽는다.

**Files:**
- Create: `app/lib/features/footsteps/trip/trip_day.dart`, `route_reconstruct_api.dart`, `trip_footsteps_providers.dart`, `trip_footsteps_page.dart`
- Modify: `app/lib/features/footsteps/trip/trip_recording_providers.dart`(`tripClockProvider`), `app/lib/router.dart`(경로)
- Test: `app/test/footsteps/trip/trip_day_test.dart`, `route_reconstruct_api_test.dart`, `trip_footsteps_page_test.dart`

**Interfaces:**
- Consumes
  - Task 2: `AppDatabase.routePointsForTrip`·`stillSpansForTrip`
  - Task 3: `TripPeriod`
  - Task 5: `tripRecordingPermissionsProvider`
  - R5: `detectStays`, `Stay`, `TimeSpan`
  - 기존: `apiClientProvider`, `tripListProvider`, `dayKeyOf`, `totalDistanceMeters`, `BaseGoogleMap`
- Produces
  - 날짜 묶음(`trip_day.dart`)
    - `tripDates(TripPeriod)`, `initialTripDate(trip, points, now)`
    - `TripDay({date, points, stays})`(`steps`, `lastPointMs`), `buildTripDay(date, tripPoints, stillSpans)`
  - 복원 API(`route_reconstruct_api.dart`)
    - `RouteSegmentView({kind, coords, fallback})`(`walk`·`vehicle`·`estimated`)
    - `reconstructChunks(points, stays, {maxPoints = 2000})`
    - `RouteReconstructApi(Dio).reconstruct(points, stays)`
  - provider(`trip_footsteps_providers.dart`)
    - `tripRecordsProvider(tripId)`, `routeReconstructApiProvider`
    - `DayRouteRequest({tripId, day})`, `DayRoute({segments, roadMatched})`(`distanceMeters`, `DayRoute.straight`)
    - `dayRouteProvider(request)`, `missingTripPermissionsProvider`
  - `tripClockProvider`(`DateTime Function()`, 테스트가 날짜를 고정한다)
  - 화면: `TripFootstepsPage({tripId})`, `stayDurationLabel(Duration)`, `distanceLabel(double)`
  - 경로: `AppRoutes.tripFootsteps = '/visa/trip/:id/footsteps'`, `AppRoutes.tripFootstepsOf(int)`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/footsteps/trip/trip_day_test.dart`:

```dart
import 'package:app/features/footsteps/data/route_point.dart';
import 'package:app/features/footsteps/trip/trip_day.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footstep_core/footstep_core.dart' show TimeSpan;

import 'trip_fakes.dart';

/// 위도 1도 = 111,195m(footstep_core geo.dart의 지구 반지름 기준).
const _degPerMeter = 1 / 111195.08;

RoutePoint point(DateTime at, {double northM = 0, int? steps, String state = 'walking'}) => RoutePoint(
      lat: 37.5 + northM * _degPerMeter,
      lng: 127.0,
      countryIso: 'KR',
      recordedAt: at,
      tripId: 7,
      accuracyM: 5,
      stepsSincePrev: steps,
      state: state,
    );

TimeSpan span(DateTime from, DateTime to) => TimeSpan(from.millisecondsSinceEpoch, to.millisecondsSinceEpoch);

void main() {
  final trip = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));

  test('날짜 칩은 출발일부터 귀국일까지(양 끝 포함)다', () {
    expect(tripDates(trip), [DateTime(2026, 11, 20), DateTime(2026, 11, 21), DateTime(2026, 11, 22)]);
    expect(tripDates(period(1, DateTime(2026, 11, 30), DateTime(2026, 12, 1))),
        [DateTime(2026, 11, 30), DateTime(2026, 12, 1)]);
  });

  test('처음 고르는 날: 여행 중이면 오늘, 아니면 기록이 있는 마지막 날, 없으면 출발일', () {
    final points = [point(DateTime(2026, 11, 20, 9)), point(DateTime(2026, 11, 21, 9))];

    expect(initialTripDate(trip, points, DateTime(2026, 11, 22, 15)), DateTime(2026, 11, 22));
    expect(initialTripDate(trip, points, DateTime(2026, 12, 1)), DateTime(2026, 11, 21));
    expect(initialTripDate(trip, const [], DateTime(2026, 12, 1)), DateTime(2026, 11, 20));
  });

  test('점을 기기 현지 날짜로 묶고, 그날 걸음은 직전 점 이후 걸음의 합이다', () {
    final points = [
      point(DateTime(2026, 11, 20, 23, 50), steps: 100),
      point(DateTime(2026, 11, 21, 0, 10), steps: 40),
      point(DateTime(2026, 11, 21, 9), steps: null), // 시작 직후 점은 걸음을 모를 수 있다
      point(DateTime(2026, 11, 21, 9, 5), steps: 600),
    ];

    final day = buildTripDay(DateTime(2026, 11, 21, 15), points, const []);

    expect(day.date, DateTime(2026, 11, 21));
    expect(day.points.map((p) => p.recordedAt.hour), [0, 9, 9]);
    expect(day.steps, 640);
    expect(day.lastPointMs, DateTime(2026, 11, 21, 9, 5).millisecondsSinceEpoch);
    expect(buildTripDay(DateTime(2026, 11, 22), points, const []).points, isEmpty);
    expect(buildTripDay(DateTime(2026, 11, 22), points, const []).lastPointMs, 0);
  });

  test('머문 곳은 걸음 감지기 정지 구간으로 도착·출발을 잡는다(5분마다 잰 점이 드물어도)', () {
    // 10:00에 카페에 도착해 10:32에 떠났다. 정지 확인 점은 5분마다다.
    final points = [
      point(DateTime(2026, 11, 21, 9, 55), northM: -300),
      for (var m = 0; m <= 25; m += 5) point(DateTime(2026, 11, 21, 10, 0, 30).add(Duration(minutes: m)), state: 'still'),
      point(DateTime(2026, 11, 21, 10, 33), northM: 300),
    ];
    final spans = [span(DateTime(2026, 11, 21, 10), DateTime(2026, 11, 21, 10, 32))];

    final stay = buildTripDay(DateTime(2026, 11, 21), points, spans).stays.single;

    expect(DateTime.fromMillisecondsSinceEpoch(stay.arriveMs), DateTime(2026, 11, 21, 10));
    expect(Duration(milliseconds: stay.durationMs), const Duration(minutes: 32));
  });

  test('밤을 넘긴 숙소는 두 날 모두 실제 도착·출발 시각으로 보인다', () {
    final points = [
      point(DateTime(2026, 11, 20, 21, 55), northM: -500),
      for (var t = DateTime(2026, 11, 20, 22, 5); t.isBefore(DateTime(2026, 11, 21, 8)); t = t.add(const Duration(minutes: 5)))
        point(t, state: 'still'),
      point(DateTime(2026, 11, 21, 8, 5), northM: 500),
    ];
    final spans = [span(DateTime(2026, 11, 20, 22), DateTime(2026, 11, 21, 8))];

    for (final date in [DateTime(2026, 11, 20), DateTime(2026, 11, 21)]) {
      final stay = buildTripDay(date, points, spans).stays.single;
      expect(DateTime.fromMillisecondsSinceEpoch(stay.arriveMs), DateTime(2026, 11, 20, 22), reason: '$date');
      expect(DateTime.fromMillisecondsSinceEpoch(stay.leaveMs), DateTime(2026, 11, 21, 8), reason: '$date');
    }
  });
}
```

`app/test/footsteps/trip/route_reconstruct_api_test.dart`:

```dart
import 'dart:convert';

import 'package:app/features/footsteps/data/route_point.dart';
import 'package:app/features/footsteps/trip/route_reconstruct_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footstep_core/footstep_core.dart' show Stay;

import '../../support/stub_http_client_adapter.dart';

RoutePoint point(int second, {int? steps, String? state}) => RoutePoint(
      lat: 37.5 + second / 100000,
      lng: 127.0,
      countryIso: 'KR',
      recordedAt: DateTime.fromMillisecondsSinceEpoch(1792400000000 + second * 1000),
      tripId: 7,
      accuracyM: 8,
      stepsSincePrev: steps,
      state: state,
    );

Stay stay(int fromSecond, int toSecond) => Stay(
      arriveMs: 1792400000000 + fromSecond * 1000,
      leaveMs: 1792400000000 + toSecond * 1000,
      lat: 37.6,
      lng: 127.1,
      nPoints: 3,
    );

void main() {
  test('점·머문 곳을 복원 API 계약대로 보내고(방법은 서버 기본값) 구간을 받는다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    final adapter = StubHttpClientAdapter(
      path: '/api/route/reconstruct',
      statusCode: 200,
      body: jsonEncode({
        'method': 'osrm_match_radius',
        'segments': [
          {
            'kind': 'walk',
            'coords': [
              {'lat': 37.5, 'lng': 127.0},
              {'lat': 37.51, 'lng': 127.01},
            ],
            'fallback': false,
          },
          {
            'kind': 'estimated',
            'coords': [
              {'lat': 37.51, 'lng': 127.01},
              {'lat': 37.6, 'lng': 127.1},
            ],
            'fallback': true,
          },
        ],
      }),
    );
    dio.httpClientAdapter = adapter;

    final segments = await RouteReconstructApi(dio)
        .reconstruct([point(0, state: 'unknown'), point(60, steps: 64, state: 'walking')], [stay(30, 40)]);

    final sent = adapter.lastRequest!.data as Map<String, dynamic>;
    expect(sent.containsKey('method'), isFalse);
    expect(sent['points'], [
      {'t': 1792400000000, 'lat': 37.5, 'lng': 127.0, 'accuracy': 8.0, 'stepsSincePrev': null, 'state': 'unknown'},
      {'t': 1792400060000, 'lat': 37.5006, 'lng': 127.0, 'accuracy': 8.0, 'stepsSincePrev': 64, 'state': 'walking'},
    ]);
    expect(sent['stays'], [
      {'arrive': 1792400030000, 'leave': 1792400040000, 'lat': 37.6, 'lng': 127.1},
    ]);
    expect(segments.map((s) => (s.kind, s.coords.length, s.fallback)), [('walk', 2, false), ('estimated', 2, true)]);
  });

  test('서버 상한을 넘는 날은 마지막 점을 겹쳐 나누고, 머문 곳은 그 조각과 겹치는 것만 넣는다', () {
    final points = [for (var s = 0; s < 5; s++) point(s * 100)];
    final stays = [stay(50, 80), stay(250, 350), stay(420, 430)];

    final chunks = reconstructChunks(points, stays, maxPoints: 3);

    expect(chunks.map((c) => c.points.map((p) => p.recordedAt.millisecondsSinceEpoch ~/ 1000 - 1792400000)), [
      [0, 100, 200],
      [200, 300, 400],
    ]);
    expect(chunks[0].stays.map((s) => s.arriveMs ~/ 1000 - 1792400000), [50]);
    expect(chunks[1].stays.map((s) => s.arriveMs ~/ 1000 - 1792400000), [250]);
    expect(reconstructChunks(const [], stays), isEmpty);
    expect(reconstructChunks(points, stays), hasLength(1));
  });
}
```

`app/test/footsteps/trip/trip_footsteps_page_test.dart`:

```dart
import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/data/route_point.dart';
import 'package:app/features/footsteps/map/base_google_map.dart';
import 'package:app/features/footsteps/trip/route_reconstruct_api.dart';
import 'package:app/features/footsteps/trip/trip_footsteps_page.dart';
import 'package:app/features/footsteps/trip/trip_footsteps_providers.dart';
import 'package:app/features/footsteps/trip/trip_recording_permissions.dart';
import 'package:app/features/footsteps/trip/trip_recording_providers.dart';
import 'package:app/features/visa/data/trip_list_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformViewCreatedCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footstep_core/footstep_core.dart' show Stay;
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import '../../visa/fake_trip_api.dart' show sampleSummary;
import 'trip_fakes.dart';

/// GoogleMap이 실제 플랫폼 뷰를 요구해 위젯 테스트가 멈추므로 플랫폼 뷰 생성을 건너뛴다(국가 지도 테스트와 같은 대역).
class _FakeGoogleMapsFlutterPlatform extends GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) {
    return const SizedBox.shrink();
  }

  @override
  Future<void> init(int mapId) async {}
}

/// 복원 API 대역. 받은 점 수를 기록하고, 정해 둔 구간을 돌려주거나 실패한다.
class _FakeReconstructApi implements RouteReconstructApi {
  List<RouteSegmentView> Function(List<RoutePoint> points)? respond;
  bool fails = false;
  final calls = <int>[];

  @override
  Future<List<RouteSegmentView>> reconstruct(List<RoutePoint> points, List<Stay> stays) async {
    calls.add(points.length);
    if (fails) throw StateError('서버 꺼짐');
    return respond?.call(points) ??
        [RouteSegmentView(kind: 'walk', coords: [for (final p in points) LatLng(p.lat + 0.001, p.lng)], fallback: false)];
  }
}

void main() {
  setUpAll(() => GoogleMapsFlutterPlatform.instance = _FakeGoogleMapsFlutterPlatform());

  late AppDatabase db;
  late _FakeReconstructApi api;
  late FakeTripRecordingPermissions permissions;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeReconstructApi();
    permissions = FakeTripRecordingPermissions();
  });

  tearDown(() => db.close());

  Future<void> addPoint(DateTime at, {double lat = 37.5, int? steps, String state = 'walking'}) =>
      db.insertTripPoint(
          tripId: 7, lat: lat, lng: 127.0, countryIso: 'KR', recordedAt: at, stepsSincePrev: steps, state: state);

  /// DB 조회(실제 I/O) → 재빌드 → 복원 → 재빌드가 차례로 일어나야 지도가 확정된다(국가 지도 테스트와 같은 방법).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpPage(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/visa/trip/7/footsteps',
      routes: [
        GoRoute(
          path: '/visa/trip/:id/footsteps',
          builder: (_, state) =>
              Scaffold(body: TripFootstepsPage(tripId: int.parse(state.pathParameters['id']!))),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tripListProvider.overrideWith((ref) async => TripListState(trips: [
              sampleSummary(
                  id: 7, iso2: 'KR', nameKo: '대한민국', depart: DateTime(2026, 11, 20), ret: DateTime(2026, 11, 22)),
            ])),
        appDatabaseProvider.overrideWithValue(db),
        routeReconstructApiProvider.overrideWithValue(api),
        tripRecordingPermissionsProvider.overrideWithValue(permissions),
        tripClockProvider.overrideWithValue(() => DateTime(2026, 11, 21, 15)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle(tester);
  }

  Set<Polyline> polylines(WidgetTester tester) => tester.widget<BaseGoogleMap>(find.byType(BaseGoogleMap)).polylines;

  Future<void> seedTwoDays() async {
    await addPoint(DateTime(2026, 11, 20, 9), steps: 10);
    await addPoint(DateTime(2026, 11, 20, 9, 5), lat: 37.501, steps: 20);
    await addPoint(DateTime(2026, 11, 21, 9), state: 'unknown');
    await addPoint(DateTime(2026, 11, 21, 9, 5), lat: 37.502, steps: 1200);
    await addPoint(DateTime(2026, 11, 21, 9, 10), lat: 37.504, steps: 2345);
  }

  testWidgets('출발일~귀국일 날짜 칩을 두고, 오늘(여행 중)의 복원 경로·걸음·이동 거리를 보여 준다', (tester) async {
    await seedTwoDays();
    api.respond = (points) => [
          RouteSegmentView(kind: 'walk', coords: [const LatLng(37.5, 127.0), const LatLng(37.502, 127.0)], fallback: false),
          RouteSegmentView(kind: 'estimated', coords: [const LatLng(37.502, 127.0), const LatLng(37.504, 127.0)], fallback: false),
        ];

    await pumpPage(tester);

    expect(find.text('대한민국 발걸음'), findsOneWidget);
    for (final label in ['11/20', '11/21', '11/22']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(api.calls, [3]);
    final lines = polylines(tester).toList()..sort((a, b) => a.polylineId.value.compareTo(b.polylineId.value));
    expect(lines.map((l) => l.patterns.isEmpty), [true, false]); // estimated는 점선
    expect(find.text('3,545'), findsOneWidget); // 걸음
    expect(find.text('445m'), findsOneWidget); // 복원 경로 길이(0.004도 ≈ 445m)
    expect(find.byKey(const Key('roadMatchFailed')), findsNothing);
  });

  testWidgets('다른 날을 고르면 그날 점으로 복원하고, 한 번 본 날은 다시 부르지 않는다(메모리 캐시)', (tester) async {
    await seedTwoDays();
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('tripDate_2026-11-20')));
    await settle(tester);
    expect(api.calls, [3, 2]);
    expect(find.text('30'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tripDate_2026-11-21')));
    await settle(tester);
    expect(api.calls, [3, 2]);
  });

  testWidgets('복원에 실패하면 점을 직선으로 잇고 "도로 맞춤을 못 했어요"라고 안내한다', (tester) async {
    await seedTwoDays();
    api.fails = true;

    await pumpPage(tester);

    final line = polylines(tester).single;
    expect(line.points, [const LatLng(37.5, 127.0), const LatLng(37.502, 127.0), const LatLng(37.504, 127.0)]);
    expect(find.byKey(const Key('roadMatchFailed')), findsOneWidget);

    // 다시 시도하면 그 날만 다시 부른다.
    api.fails = false;
    await tester.tap(find.text('다시 시도'));
    await settle(tester);
    expect(api.calls, [3, 3]);
    expect(find.byKey(const Key('roadMatchFailed')), findsNothing);
  });

  testWidgets('서버가 직선으로 대신 채운 구간(fallback)이 있어도 안내한다', (tester) async {
    await seedTwoDays();
    api.respond = (points) => [
          RouteSegmentView(kind: 'walk', coords: [for (final p in points) LatLng(p.lat, p.lng)], fallback: true),
        ];

    await pumpPage(tester);

    expect(find.byKey(const Key('roadMatchFailed')), findsOneWidget);
  });

  testWidgets('머문 곳은 도착 시각과 머문 시간으로 지도 마커와 목록에 보인다', (tester) async {
    await addPoint(DateTime(2026, 11, 21, 9, 55), lat: 37.497);
    for (var m = 0; m <= 25; m += 5) {
      await addPoint(DateTime(2026, 11, 21, 10, 0, 30).add(Duration(minutes: m)), state: 'still');
    }
    await addPoint(DateTime(2026, 11, 21, 10, 33), lat: 37.503);
    await db.insertTripStillSpan(
        tripId: 7, startAt: DateTime(2026, 11, 21, 10), endAt: DateTime(2026, 11, 21, 10, 32));

    await pumpPage(tester);

    final marker = tester.widget<BaseGoogleMap>(find.byType(BaseGoogleMap)).markers.single;
    expect(marker.infoWindow.title, '10:00 도착');
    expect(marker.infoWindow.snippet, '32분 머묾');
    expect(find.text('10:00 도착 · 32분 머묾'), findsOneWidget);
    expect(find.text('1곳'), findsOneWidget);
  });

  testWidgets('기록이 없는 날은 지도 대신 안내를 보여 준다', (tester) async {
    await seedTwoDays();
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('tripDate_2026-11-22')));
    await settle(tester);

    expect(find.text('이 날의 발걸음 기록이 없어요'), findsOneWidget);
    expect(find.byType(BaseGoogleMap), findsNothing);
  });

  testWidgets('권한이 없으면 "기록이 꺼져 있어요" 배너와 설정 이동 버튼을 띄운다', (tester) async {
    permissions.absent = {TripRecordingPermission.notification, TripRecordingPermission.backgroundLocation};
    await pumpPage(tester);

    expect(find.text('기록이 꺼져 있어요'), findsOneWidget);
    expect(find.text('권한이 없어요: 백그라운드 위치, 알림'), findsOneWidget);
    await tester.tap(find.byKey(const Key('openRecordingSettings')));
    expect(permissions.settingsOpened, 1);
  });

  testWidgets('권한이 모두 있으면 배너가 없다', (tester) async {
    await pumpPage(tester);

    expect(find.byKey(const Key('tripRecordingOffBanner')), findsNothing);
  });

  test('머문 시간·이동 거리 문구', () {
    expect(stayDurationLabel(const Duration(minutes: 32)), '32분');
    expect(stayDurationLabel(const Duration(hours: 1, minutes: 5)), '1시간 5분');
    expect(stayDurationLabel(const Duration(hours: 9)), '9시간');
    expect(distanceLabel(850.4), '850m');
    expect(distanceLabel(8249), '8.2km');
  });
}
```

- [ ] **Step 2: 실패 확인**

Run(`app/`에서): `flutter test test/footsteps/trip/trip_day_test.dart test/footsteps/trip/route_reconstruct_api_test.dart test/footsteps/trip/trip_footsteps_page_test.dart`

Expected: FAIL. `trip_day.dart`·`route_reconstruct_api.dart`·`trip_footsteps_page.dart`가 없다.

- [ ] **Step 3: 구현**

`app/lib/features/footsteps/trip/trip_day.dart`:

```dart
import 'package:footstep_core/footstep_core.dart' show Fix, Stay, TimeSpan, detectStays;

import '../data/route_point.dart';
import '../health/step_attribution.dart' show dayKeyOf;
import 'trip_period.dart';

/// 여행 기간의 날짜(출발일~귀국일, 양 끝 포함). 날짜별 보기의 날짜 칩이 된다(설계 9-4).
List<DateTime> tripDates(TripPeriod trip) => [
      for (var d = trip.startsAt; d.isBefore(trip.endsAt); d = DateTime(d.year, d.month, d.day + 1)) d,
    ];

/// 날짜별 보기에서 처음 고를 날: 여행 중이면 오늘, 아니면 기록이 있는 마지막 날, 그것도 없으면 출발일.
DateTime initialTripDate(TripPeriod trip, List<RoutePoint> points, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (trip.covers(now)) return today;
  final dates = tripDates(trip);
  for (final point in points.reversed) {
    final day = dayKeyOf(point.recordedAt);
    if (dates.contains(day)) return day;
  }
  return trip.startsAt;
}

/// 고른 날 하루의 여행 기록(설계 9-4). 점은 기기 현지 날짜로 묶는다(국가 지도·걸음 귀속과 같은 [dayKeyOf]).
class TripDay {
  const TripDay({required this.date, required this.points, required this.stays});

  final DateTime date;

  /// 그날의 점(시각순).
  final List<RoutePoint> points;

  /// 그날의 머문 곳. 밤을 넘긴 머문 곳은 도착이 전날·출발이 다음 날일 수 있다.
  final List<Stay> stays;

  /// 그날의 걸음 수 = 그날 점들의 '직전 점 이후 걸음 수' 합. 하루의 마지막 측위 뒤 걸음은 다음 측위(다음 날일 수 있다)에 든다.
  int get steps => points.fold(0, (sum, p) => sum + (p.stepsSincePrev ?? 0));

  /// 복원 결과 캐시 키의 일부(설계 9-4: 여행, 날짜, 마지막 점 시각). 점이 없으면 0이다.
  int get lastPointMs => points.isEmpty ? 0 : points.last.recordedAt.millisecondsSinceEpoch;
}

/// [tripPoints](한 여행의 모든 점, 시각순)와 [stillSpans](정지 구간, 시작 시각순)에서 [date] 하루를 뽑는다.
///
/// 머문 곳은 footstep_core의 [detectStays](설계 5-6, 재생기와 같은 코드)로 묶는다. 그날과 겹치는 정지 구간을 잘라내지 않고
/// 넘겨, 밤새 머문 숙소처럼 날을 넘긴 머문 곳도 실제 도착·출발 시각으로 보인다.
TripDay buildTripDay(DateTime date, List<RoutePoint> tripPoints, List<TimeSpan> stillSpans) {
  final day = DateTime(date.year, date.month, date.day);
  final next = DateTime(day.year, day.month, day.day + 1);
  final points = [for (final p in tripPoints) if (dayKeyOf(p.recordedAt) == day) p];
  final fixes = [
    for (final p in points)
      Fix(tMs: p.recordedAt.millisecondsSinceEpoch, lat: p.lat, lng: p.lng, accuracyM: p.accuracyM ?? 0),
  ];
  final dayStart = day.millisecondsSinceEpoch;
  final dayEnd = next.millisecondsSinceEpoch;
  final spans = [
    for (final s in stillSpans)
      if (s.endMs >= dayStart && s.startMs < dayEnd) s,
  ];
  return TripDay(date: day, points: points, stays: detectStays(fixes, stillSpans: spans));
}
```

`app/lib/features/footsteps/trip/route_reconstruct_api.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:footstep_core/footstep_core.dart' show Stay;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/route_point.dart';

/// 복원한 경로의 구간 하나(서버 `route/RouteSegment.java`). [kind]는 `walk`·`vehicle`·`estimated`다.
/// [fallback]이면 OSRM이 없거나 매칭에 실패해 직선으로 대신 채운 구간이다.
class RouteSegmentView {
  const RouteSegmentView({required this.kind, required this.coords, required this.fallback});

  /// 복원 API의 구간 종류. `estimated`는 GPS가 없던 10분 이상의 공백(지하철 등)을 최단경로로 이은 것이라 점선으로 그린다.
  static const walk = 'walk';
  static const vehicle = 'vehicle';
  static const estimated = 'estimated';

  final String kind;
  final List<LatLng> coords;
  final bool fallback;

  factory RouteSegmentView.fromJson(Map<String, dynamic> json) => RouteSegmentView(
        kind: json['kind'] as String,
        coords: [
          for (final c in json['coords'] as List)
            LatLng(((c as Map)['lat'] as num).toDouble(), (c['lng'] as num).toDouble()),
        ],
        fallback: json['fallback'] as bool? ?? false,
      );
}

/// 한 번에 보낼 점·머문 곳. 서버가 점 2000개, 머문 곳 500개까지 받는다(설계 6-1).
class ReconstructChunk {
  const ReconstructChunk(this.points, this.stays);

  final List<RoutePoint> points;
  final List<Stay> stays;
}

/// 하루치 점이 서버 상한([maxPoints])을 넘으면(탈것을 오래 타 5초마다 잰 날) 나눠 보낸다. 앞 조각의 마지막 점을 다음 조각의
/// 첫 점으로 겹쳐 구간이 끊기지 않게 하고, 머문 곳은 그 조각의 시간 범위와 겹치는 것만 넣는다 — 서버는 범위 밖의 머문 곳도
/// 중심점을 끼워 넣기 때문이다.
List<ReconstructChunk> reconstructChunks(List<RoutePoint> points, List<Stay> stays, {int maxPoints = 2000}) {
  if (points.isEmpty) return const [];
  final chunks = <ReconstructChunk>[];
  var start = 0;
  while (true) {
    final end = (start + maxPoints).clamp(0, points.length);
    final part = points.sublist(start, end);
    final from = part.first.recordedAt.millisecondsSinceEpoch;
    final to = part.last.recordedAt.millisecondsSinceEpoch;
    chunks.add(ReconstructChunk(part, [
      for (final s in stays)
        if (s.leaveMs >= from && s.arriveMs <= to) s,
    ]));
    if (end >= points.length) return chunks;
    start = end - 1;
  }
}

/// `POST /api/route/reconstruct`(R5)의 앱 쪽 클라이언트. 방법은 보내지 않아 서버 기본값(`osrm_match_radius`)을 쓴다(설계 9-4).
/// 기록 좌표는 복원할 때만 보내고 서버는 저장하지 않는다(설계 9-3). 실패하면 dio의 [DioException]을 그대로 던진다.
class RouteReconstructApi {
  RouteReconstructApi(this._dio);

  final Dio _dio;

  Future<List<RouteSegmentView>> reconstruct(List<RoutePoint> points, List<Stay> stays) async {
    final segments = <RouteSegmentView>[];
    for (final chunk in reconstructChunks(points, stays)) {
      final response = await _dio.post<Map<String, dynamic>>('/api/route/reconstruct', data: {
        'points': [
          for (final p in chunk.points)
            {
              't': p.recordedAt.millisecondsSinceEpoch,
              'lat': p.lat,
              'lng': p.lng,
              'accuracy': p.accuracyM,
              'stepsSincePrev': p.stepsSincePrev,
              'state': p.state,
            },
        ],
        'stays': [
          for (final s in chunk.stays) {'arrive': s.arriveMs, 'leave': s.leaveMs, 'lat': s.lat, 'lng': s.lng},
        ],
      });
      segments.addAll([
        for (final s in response.data!['segments'] as List) RouteSegmentView.fromJson(s as Map<String, dynamic>),
      ]);
    }
    return segments;
  }
}
```

`app/lib/features/footsteps/trip/trip_footsteps_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footstep_core/footstep_core.dart' show TimeSpan;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/db/app_database.dart';
import '../../../core/network/api_client.dart';
import '../data/route_point.dart';
import '../health/distance_step_estimator.dart' show totalDistanceMeters;
import 'route_reconstruct_api.dart';
import 'trip_day.dart';
import 'trip_recording_permissions.dart';
import 'trip_recording_providers.dart';

/// 한 여행의 기록(점·정지 구간). 기록 서비스는 다른 isolate의 DB 연결로 쓰므로 drift의 watch로는 바뀐 것을 알 수 없다 —
/// 화면을 다시 열거나 새로고침할 때 다시 읽는다(autoDispose).
final tripRecordsProvider =
    FutureProvider.autoDispose.family<({List<RoutePoint> points, List<TimeSpan> spans}), int>((ref, tripId) async {
  final db = ref.watch(appDatabaseProvider);
  return (points: await db.routePointsForTrip(tripId), spans: await db.stillSpansForTrip(tripId));
});

final routeReconstructApiProvider =
    Provider<RouteReconstructApi>((ref) => RouteReconstructApi(ref.watch(apiClientProvider)));

/// 복원 결과의 캐시 키(설계 9-4): 여행, 날짜, 그날 마지막 점 시각. 점이 새로 쌓이면 마지막 점 시각이 바뀌어 다시 복원한다.
/// [day]는 키가 아니라 서버에 보낼 재료다 — 같은 키면 같은 점이다.
class DayRouteRequest {
  const DayRouteRequest({required this.tripId, required this.day});

  final int tripId;
  final TripDay day;

  @override
  bool operator ==(Object other) =>
      other is DayRouteRequest &&
      other.tripId == tripId &&
      other.day.date == day.date &&
      other.day.lastPointMs == day.lastPointMs;

  @override
  int get hashCode => Object.hash(tripId, day.date, day.lastPointMs);
}

/// 고른 날의 지도에 그릴 경로.
class DayRoute {
  const DayRoute({required this.segments, required this.roadMatched});

  /// 점을 순서대로 이은 직선. 서버·네트워크가 실패했을 때 쓴다.
  factory DayRoute.straight(List<RoutePoint> points, {required bool roadMatched}) => DayRoute(
        segments: [
          if (points.isNotEmpty)
            RouteSegmentView(
              kind: RouteSegmentView.walk,
              coords: [for (final p in points) LatLng(p.lat, p.lng)],
              fallback: !roadMatched,
            ),
        ],
        roadMatched: roadMatched,
      );

  final List<RouteSegmentView> segments;

  /// false면 서버·네트워크 실패나 OSRM 대체로 직선이 섞였다 — "도로 맞춤을 못 했어요"라고 안내한다.
  final bool roadMatched;

  /// 그린 경로의 길이(탈것·추정 구간 포함). 도로에 맞췄으면 도로 거리, 아니면 직선거리다.
  double get distanceMeters => segments.fold(0.0, (sum, s) => sum + totalDistanceMeters(s.coords));
}

/// 날짜별 복원 경로. autoDispose가 아니라 앱이 떠 있는 동안 메모리에 남는다(설계 9-4의 캐시). 실패는 직선으로 바꿔 돌려주므로
/// 같은 키로는 다시 부르지 않는다 — 화면의 [다시 시도]가 이 항목만 invalidate한다. Riverpod의 자동 재시도는 끈다.
final dayRouteProvider = FutureProvider.family<DayRoute, DayRouteRequest>((ref, request) async {
  final points = request.day.points;
  // 점이 둘보다 적으면 이을 길이 없다 — 서버를 부르지 않는다.
  if (points.length < 2) return DayRoute.straight(points, roadMatched: true);
  try {
    final segments = await ref.watch(routeReconstructApiProvider).reconstruct(points, request.day.stays);
    return DayRoute(segments: segments, roadMatched: !segments.any((s) => s.fallback));
  } catch (_) {
    return DayRoute.straight(points, roadMatched: false);
  }
}, retry: (_, _) => null);

/// 여행 기록에 필요한데 없는 권한(설계 9-4 배너). 설정에서 돌아오면 화면이 다시 묻는다.
final missingTripPermissionsProvider = FutureProvider.autoDispose<Set<TripRecordingPermission>>(
  (ref) => ref.watch(tripRecordingPermissionsProvider).missing(),
);
```

`app/lib/features/footsteps/trip/trip_footsteps_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footstep_core/footstep_core.dart' show Stay;
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/wireframe_widgets.dart';
import '../../../router.dart';
import '../../visa/data/trip_list_providers.dart';
import '../map/base_google_map.dart';
import 'route_reconstruct_api.dart';
import 'trip_day.dart';
import 'trip_footsteps_providers.dart';
import 'trip_period.dart';
import 'trip_recording_permissions.dart';
import 'trip_recording_providers.dart';

final _chipDate = DateFormat('M/d');
final _clock = DateFormat('HH:mm');
final _steps = NumberFormat('#,###');

/// 국가 상세 지도와 같은 도시 단위 줌(country_detail_map_page.dart의 근거 참고).
const _dayZoom = 13.7;

/// 머문 시간 문구: `32분`, `1시간 5분`.
String stayDurationLabel(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  if (hours == 0) return '$minutes분';
  return minutes == 0 ? '$hours시간' : '$hours시간 $minutes분';
}

/// 이동 거리 문구: 1km 미만은 m, 넘으면 소수 한 자리 km.
String distanceLabel(double meters) =>
    meters < 1000 ? '${meters.round()}m' : '${(meters / 1000).toStringAsFixed(1)}km';

/// 머문 곳의 도착·출발 시각. 고른 날이 아닌 시각(밤을 넘긴 숙소)은 날짜를 붙인다.
String _stayClock(DateTime at, DateTime day) {
  final local = at.toLocal();
  final sameDay = local.year == day.year && local.month == day.month && local.day == day.day;
  return sameDay ? _clock.format(local) : '${_chipDate.format(local)} ${_clock.format(local)}';
}

/// 날짜별 보기(설계 2026-11-07 9-4, 여행 상세 → 발걸음). 출발일~귀국일 날짜 칩과, 고른 날의 복원 경로·머문 곳·걸음·이동
/// 거리를 보여 준다. 와이어프레임 확인 전이라 여행 상세의 머리글·pill 칩·카드 모양을 그대로 따른다.
class TripFootstepsPage extends ConsumerStatefulWidget {
  const TripFootstepsPage({super.key, required this.tripId});

  final int tripId;

  @override
  ConsumerState<TripFootstepsPage> createState() => _TripFootstepsPageState();
}

class _TripFootstepsPageState extends ConsumerState<TripFootstepsPage> with WidgetsBindingObserver {
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 설정에서 권한을 켜고 돌아오면 배너를 다시 확인하고, 그동안 기록 서비스가 쓴 점을 다시 읽는다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.invalidate(missingTripPermissionsProvider);
    ref.invalidate(tripRecordsProvider(widget.tripId));
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(tripListProvider);
    final summary = listAsync.asData?.value.trips.where((t) => t.id == widget.tripId).firstOrNull;
    final trip = summary == null ? null : TripPeriod.fromSummary(summary);

    return Column(
      children: [
        _Header(
          title: trip == null ? '발걸음' : '${trip.countryNameKo} 발걸음',
          caption: trip == null
              ? null
              : '${_chipDate.format(trip.departDate)} – ${_chipDate.format(trip.returnDate)}',
          onRefresh: () => ref.invalidate(tripRecordsProvider(widget.tripId)),
        ),
        const _PermissionBanner(),
        Expanded(
          child: trip == null
              ? Center(
                  child: listAsync.isLoading
                      ? const CircularProgressIndicator()
                      : Text('여행을 찾을 수 없어요', style: AppTextStyles.caption),
                )
              : ref.watch(tripRecordsProvider(widget.tripId)).when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('기록을 읽지 못했어요\n$e', textAlign: TextAlign.center)),
                    data: (records) {
                      final now = ref.watch(tripClockProvider)();
                      final selected = _selected ?? initialTripDate(trip, records.points, now);
                      final day = buildTripDay(selected, records.points, records.spans);
                      return Column(
                        children: [
                          _DateChips(
                            dates: tripDates(trip),
                            selected: selected,
                            onSelected: (date) => setState(() => _selected = date),
                          ),
                          Expanded(child: _DayView(tripId: widget.tripId, day: day)),
                        ],
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.caption, required this.onRefresh});

  final String title;
  final String? caption;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textBody),
            onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.visa),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          Flexible(child: Text(title, style: AppTextStyles.screenTitle, overflow: TextOverflow.ellipsis)),
          if (caption != null) ...[
            const SizedBox(width: 8),
            Text(caption!, style: AppTextStyles.caption),
          ],
          const Spacer(),
          IconButton(
            key: const Key('tripFootstepsRefresh'),
            icon: const Icon(Icons.refresh, color: AppColors.textBody),
            tooltip: '다시 읽기',
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}

/// 권한(백그라운드 위치·활동 인식·알림)이 없으면 띄우는 배너(설계 9-4).
class _PermissionBanner extends ConsumerWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missing = ref.watch(missingTripPermissionsProvider).asData?.value ?? const <TripRecordingPermission>{};
    if (missing.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: WireframeCard(
        key: const Key('tripRecordingOffBanner'),
        color: AppColors.warnBg,
        borderColor: AppColors.warnBorder,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('기록이 꺼져 있어요', style: AppTextStyles.label.copyWith(color: AppColors.warn)),
                  const SizedBox(height: 4),
                  Text(
                    '권한이 없어요: ${[for (final p in TripRecordingPermission.values) if (missing.contains(p)) p.label].join(', ')}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textBody),
                  ),
                ],
              ),
            ),
            TextButton(
              key: const Key('openRecordingSettings'),
              onPressed: () => ref.read(tripRecordingPermissionsProvider).openSettings(),
              style: TextButton.styleFrom(foregroundColor: AppColors.warn),
              child: Text('설정 열기', style: AppTextStyles.caption),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateChips extends StatelessWidget {
  const _DateChips({required this.dates, required this.selected, required this.onSelected});

  final List<DateTime> dates;
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        itemCount: dates.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => FilterPill(
          key: Key('tripDate_${DateFormat('yyyy-MM-dd').format(dates[i])}'),
          label: _chipDate.format(dates[i]),
          selected: dates[i] == selected,
          onTap: () => onSelected(dates[i]),
        ),
      ),
    );
  }
}

/// 고른 날의 지도와 요약.
class _DayView extends ConsumerWidget {
  const _DayView({required this.tripId, required this.day});

  final int tripId;
  final TripDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (day.points.isEmpty) {
      return Center(child: Text('이 날의 발걸음 기록이 없어요', style: AppTextStyles.caption));
    }
    final request = DayRouteRequest(tripId: tripId, day: day);
    final route = ref.watch(dayRouteProvider(request)).asData?.value;
    final first = day.points.first;

    return Column(
      children: [
        Expanded(
          flex: 3,
          child: BaseGoogleMap(
            // 날짜를 바꾸면 그날 첫 점으로 카메라를 새로 잡는다.
            key: ValueKey(day.date),
            initialCamera: CameraPosition(target: LatLng(first.lat, first.lng), zoom: _dayZoom),
            myLocationEnabled: false,
            polylines: {
              for (final (i, segment) in (route?.segments ?? const <RouteSegmentView>[]).indexed)
                Polyline(
                  polylineId: PolylineId('segment_$i'),
                  points: segment.coords,
                  color: segment.kind == RouteSegmentView.vehicle ? AppColors.warn : AppColors.accent,
                  width: 4,
                  patterns: segment.kind == RouteSegmentView.estimated
                      ? [PatternItem.dash(12), PatternItem.gap(8)]
                      : const [],
                ),
            },
            markers: {
              for (final (i, stay) in day.stays.indexed)
                Marker(
                  markerId: MarkerId('stay_$i'),
                  position: LatLng(stay.lat, stay.lng),
                  infoWindow: InfoWindow(title: _arrivalLabel(stay), snippet: _stayLabel(stay)),
                ),
            },
          ),
        ),
        Expanded(
          flex: 2,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              if (route != null && !route.roadMatched) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '도로 맞춤을 못 했어요 · 직선으로 이었어요',
                        key: const Key('roadMatchFailed'),
                        style: AppTextStyles.caption.copyWith(color: AppColors.warn),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(dayRouteProvider(request)),
                      child: Text('다시 시도', style: AppTextStyles.caption),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              WireframeCard(
                child: Row(
                  children: [
                    Expanded(child: _Stat(label: '걸음', value: _steps.format(day.steps))),
                    Expanded(
                      child: _Stat(label: '이동 거리', value: route == null ? '…' : distanceLabel(route.distanceMeters)),
                    ),
                    Expanded(child: _Stat(label: '머문 곳', value: '${day.stays.length}곳')),
                  ],
                ),
              ),
              for (final stay in day.stays)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('${_arrivalLabel(stay)} · ${_stayLabel(stay)}', style: AppTextStyles.body),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _arrivalLabel(Stay stay) =>
      '${_stayClock(DateTime.fromMillisecondsSinceEpoch(stay.arriveMs), day.date)} 도착';

  String _stayLabel(Stay stay) => '${stayDurationLabel(Duration(milliseconds: stay.durationMs))} 머묾';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.caption),
        const SizedBox(height: 4),
        Text(value, style: AppTextStyles.cardTitle),
      ],
    );
  }
}
```

`app/lib/features/footsteps/trip/trip_recording_providers.dart`에서 다음 부분을

```dart
final tripRecordingStoreProvider = Provider<TripRecordingStore>(
```

다음으로 바꾼다:

```dart
/// 날짜별 보기·여행 상세가 "오늘"을 정할 때 쓰는 시계. 위젯 테스트가 날짜를 고정한다.
final tripClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final tripRecordingStoreProvider = Provider<TripRecordingStore>(
```

`app/lib/router.dart`에서 다음 부분을

```dart
import 'features/footsteps/providers/footsteps_providers.dart';
import 'features/footsteps/trip/trip_recording_providers.dart';
```

다음으로 바꾼다:

```dart
import 'features/footsteps/providers/footsteps_providers.dart';
import 'features/footsteps/trip/trip_footsteps_page.dart';
import 'features/footsteps/trip/trip_recording_providers.dart';
```

같은 파일에서 다음 부분을

```dart
  static String tripOf(int id) => '/visa/trip/$id';
```

다음으로 바꾼다:

```dart
  static String tripOf(int id) => '/visa/trip/$id';

  /// 여행의 날짜별 발걸음(설계 2026-11-07 9-4). `tripFootstepsOf(3)` → `/visa/trip/3/footsteps`.
  static const tripFootsteps = '/visa/trip/:id/footsteps';

  static String tripFootstepsOf(int id) => '/visa/trip/$id/footsteps';
```

같은 파일의 셸 경로 목록에서 다음 부분을

```dart
          GoRoute(
            path: AppRoutes.tripDetail,
            builder: (_, state) =>
                VisaResultPage(tripId: int.parse(state.pathParameters['id']!)),
          ),
```

다음으로 바꾼다:

```dart
          GoRoute(
            path: AppRoutes.tripDetail,
            builder: (_, state) =>
                VisaResultPage(tripId: int.parse(state.pathParameters['id']!)),
          ),
          GoRoute(
            path: AppRoutes.tripFootsteps,
            builder: (_, state) =>
                TripFootstepsPage(tripId: int.parse(state.pathParameters['id']!)),
          ),
```

`trip_footsteps_page.dart`는 `router.dart`(뒤로 갈 곳 `AppRoutes.visa`)를, `router.dart`는 이 화면을 가져온다. 여행 상세(`visa_result_page.dart`)와 같은 순환 import이고 Dart는 허용한다.

- [ ] **Step 4: 통과 확인**

Run
- `flutter test test/footsteps/trip/` → 통과
  - 날짜 묶음 5개, 복원 API 2개, 화면 9개다.
- `flutter test`(전체) → 통과(800개), `dart analyze lib test` → 0건

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/footsteps/trip/trip_day.dart app/lib/features/footsteps/trip/route_reconstruct_api.dart \
  app/lib/features/footsteps/trip/trip_footsteps_providers.dart app/lib/features/footsteps/trip/trip_footsteps_page.dart \
  app/lib/features/footsteps/trip/trip_recording_providers.dart app/lib/router.dart \
  app/test/footsteps/trip/trip_day_test.dart app/test/footsteps/trip/route_reconstruct_api_test.dart \
  app/test/footsteps/trip/trip_footsteps_page_test.dart
git commit -m "feat(app): 여행의 날짜별 발걸음 화면(복원 경로·머문 곳·걸음·이동 거리·권한 배너)을 더한다"
```

---

### Task 8: 국내 여행 화면과 여행 상세의 '발걸음 기록' 칸

설계 9-1의 앱 쪽과 9-2의 3번(일시정지·재개)이다.
- 여행 만들기
  - 국가 목록 맨 위에 '대한민국(국내 여행)'을 둔다. 앱이 이미 가진 `homeCountry`·`countriesWithHomeProvider`를 다시 쓴다.
  - 국내 여행을 고르면 여권 만료일 입력을 숨기고, 버튼은 '여행 만들기'다.
- 여행 상세
  - 국내 여행은 비자 결과·근거·역산 일정·체크리스트·지갑을 숨기고 '발걸음 기록' 칸만 보인다.
  - 준비 일정이 없으니 알람 예약도 알림 권한 요청도 하지 않는다.
  - 해외 여행 상세에도 같은 칸을 역산 일정 아래에 둔다.
- 준비물 탭은 국내 여행을 고르지 않는다.
- '발걸음 기록' 칸(**와이어프레임 확인 필요(사용자)**)
  - 지금 단계를 말한다: 출발 전·여행 중·일시정지·마친 뒤
  - [기록 일시정지·재개]와 [날짜별 발걸음]을 둔다.
  - 재부팅 한계를 적어 둔다(설계 9-2: "이 한계는 사용자 화면과 보고서에 적는다").

**Files:**
- Modify: `app/lib/features/visa/models/trip.dart`, `models/trip_summary.dart`, `visa_result_display.dart`, `data/trip_api.dart`
- Modify: `app/lib/features/visa/visa_page.dart`, `visa_result_page.dart`, `app/lib/features/checklist/checklist_page.dart`
- Modify: `app/lib/features/footsteps/data/footsteps_sync_service.dart`(주석: 서버 country 표에 KR이 생겼다)
- Modify: `app/lib/features/footsteps/trip/trip_period.dart`(`fromTrip`), `trip_recording_providers.dart`(`pausedTripIdsProvider`)
- Create: `app/lib/features/footsteps/trip/trip_footsteps_card.dart`
- Modify: `app/test/visa/fake_trip_api.dart`(여권 만료일 선택)
- Test: `app/test/visa/trip_test.dart`, `trip_api_test.dart`, `visa_result_display_test.dart`, `visa_page_test.dart`, `visa_result_page_test.dart`, `app/test/checklist/checklist_page_test.dart`, `app/test/footsteps/trip/trip_footsteps_card_test.dart`

**Interfaces:**
- Consumes
  - Task 1: `DOMESTIC`·`passportExpiry` 계약
  - Task 5: 코디네이터 `setPaused`
  - Task 7: `tripClockProvider`, `AppRoutes.tripFootstepsOf`
- Produces
  - 모델
    - `VisaVerdict.domestic('DOMESTIC')`
    - `Trip.passportExpiry`는 `DateTime?`, `Trip.isDomestic`, `TripSummary.isDomestic`
    - `TripApi.createTrip({..., DateTime? passportExpiry})`: null이면 보내지 않는다
  - 여행 기간: `TripPeriod.fromTrip(Trip)`
  - 일시정지
    - `pausedTripIdsProvider`(`NotifierProvider<PausedTripsNotifier, Set<int>>`)
    - `PausedTripsNotifier.setPaused(tripId, paused)`: 코디네이터를 거친다
  - 카드
    - `enum TripRecordingPhase { upcoming, recording, paused, ended }`, `tripRecordingPhaseOf(trip, now, {required paused})`
    - `TripFootstepsCard({required TripPeriod trip})`
    - 키: `tripFootstepsCard`, `tripRecordingStatus`, `tripRecordingToggle`, `openTripFootsteps`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/visa/fake_trip_api.dart`: 국내 여행은 여권 만료일이 없다. 다음 부분을

```dart
  final List<Map<String, Object>> createTripCalls = [];
```

다음으로 바꾼다:

```dart
  final List<Map<String, Object?>> createTripCalls = [];
```

같은 파일에서 다음 부분을

```dart
    required DateTime returnDate,
    required DateTime passportExpiry,
  }) async {
    createTripCalls.add({
```

다음으로 바꾼다:

```dart
    required DateTime returnDate,
    DateTime? passportExpiry,
  }) async {
    createTripCalls.add({
```

`app/test/visa/trip_test.dart`의 wire 값 테스트에서 다음 부분을

```dart
      ['VISA_FREE_OK', 'VISA_FREE_EXCEEDED', 'VISA_REQUIRED', 'UNVERIFIED'],
```

다음으로 바꾼다:

```dart
      ['VISA_FREE_OK', 'VISA_FREE_EXCEEDED', 'VISA_REQUIRED', 'UNVERIFIED', 'DOMESTIC'],
```

같은 파일 끝의 다음 부분을

```dart
    test('완료된 항목은 마감이 지나도 false다', () {
      expect(taskDue(DateTime(2026, 9, 29), done: true).isPastDueAt(now), isFalse);
    });
  });
}
```

다음으로 바꾼다:

```dart
    test('완료된 항목은 마감이 지나도 false다', () {
      expect(taskDue(DateTime(2026, 9, 29), done: true).isPastDueAt(now), isFalse);
    });
  });

  test('국내 여행은 여권 만료일 없이 파싱하고 국내 여행으로 본다', () {
    final trip = Trip.fromJson({
      ...json,
      'countryIso2': 'KR',
      'countryNameKo': '대한민국',
      'passportExpiry': null,
      'visaResult': {
        'verdict': 'DOMESTIC',
        'stayDays': 2,
        'visaFreeDays': null,
        'passportOk': true,
        'passportValidityMonths': null,
        'passportShortfallDays': null,
      },
      'tasks': <Object>[],
    });

    expect(trip.passportExpiry, isNull);
    expect(trip.isDomestic, isTrue);
    expect(Trip.fromJson(json).isDomestic, isFalse);
  });
}
```

`app/test/visa/trip_api_test.dart`에서 다음 부분을

```dart
  test('getTrip이 /api/trips/{id}로 GET 요청을 보낸다', () async {
```

다음으로 바꾼다:

```dart
  test('국내 여행은 여권 만료일을 보내지 않는다', () async {
    final adapter = StubHttpClientAdapter(path: '/api/trips', statusCode: 200, body: _tripJson);

    await _apiReturning(adapter).createTrip(
      countryIso2: 'KR',
      departDate: DateTime(2026, 11, 20),
      returnDate: DateTime(2026, 11, 22),
    );

    expect(adapter.lastRequest!.data, {
      'countryIso2': 'KR',
      'departDate': '2026-11-20',
      'returnDate': '2026-11-22',
    });
  });

  test('getTrip이 /api/trips/{id}로 GET 요청을 보낸다', () async {
```

`app/test/visa/visa_result_display_test.dart`에서 다음 부분을

```dart
    expect(verdictChipOf(VisaVerdict.unverified), (label: '확인 필요', tone: BadgeTone.neutral));
  });
```

다음으로 바꾼다:

```dart
    expect(verdictChipOf(VisaVerdict.unverified), (label: '확인 필요', tone: BadgeTone.neutral));
    expect(verdictChipOf(VisaVerdict.domestic), (label: '국내', tone: BadgeTone.info));
  });
```

`app/test/visa/visa_page_test.dart`에서 다음 부분을

```dart
    testWidgets('서버가 거절하면 오류 문구를 보여주고 화면에 남는다', (tester) async {
```

다음으로 바꾼다:

```dart
    testWidgets('국가 목록 맨 위에 대한민국(국내 여행)이 있다', (tester) async {
      await _pumpVisaPage(tester, api: FakeTripApi());

      await tester.tap(find.byKey(const Key('countryField')));
      await tester.pumpAndSettle();

      final options = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      expect((options.first.title as Text).data, '대한민국(국내 여행)');
      expect((options[1].title as Text).data, '베트남');
    });

    testWidgets('국내 여행을 고르면 여권 만료일을 묻지 않고, 여권 없이 여행을 만든다', (tester) async {
      final api = FakeTripApi(tripToReturn: sampleTrip(id: 43));
      await _pumpVisaPage(tester, api: api);

      await tester.tap(find.byKey(const Key('countryField')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('domesticTripOption')));
      await tester.pumpAndSettle();
      expect(find.text('국내 여행'), findsOneWidget);
      expect(find.byKey(const Key('passportExpiryField')), findsNothing);

      await _confirmDefaultDate(tester, 'departDateField');
      await _confirmDefaultDate(tester, 'returnDateField');
      expect(find.text('여행 만들기'), findsOneWidget);
      await tester.tap(find.byKey(const Key('submitTripButton')));
      await tester.pumpAndSettle();

      final call = api.createTripCalls.single;
      expect(call['countryIso2'], 'KR');
      expect(call['passportExpiry'], isNull);
      expect(find.text('결과 43'), findsOneWidget);
    });

    testWidgets('서버가 거절하면 오류 문구를 보여주고 화면에 남는다', (tester) async {
```

`app/test/visa/visa_result_page_test.dart`에서 다음 부분을

```dart
      GoRoute(path: '/checklist', builder: (_, _) => const Scaffold(body: Text('준비물 탭'))),
```

다음으로 바꾼다:

```dart
      GoRoute(
        path: '/visa/trip/:id/footsteps',
        builder: (_, state) => Scaffold(body: Text('발걸음 ${state.pathParameters['id']}')),
      ),
      GoRoute(path: '/checklist', builder: (_, _) => const Scaffold(body: Text('준비물 탭'))),
```

같은 파일에서 다음 부분을

```dart
  testWidgets('국가 이름과 판정 결과를 서버 데이터로 보여준다', (tester) async {
```

다음으로 바꾼다:

```dart
  group('국내 여행(설계 9-1)', () {
    Trip domesticTrip() => Trip(
          id: 7,
          countryIso2: 'KR',
          countryNameKo: '대한민국',
          departDate: DateTime(2026, 12, 20),
          returnDate: DateTime(2026, 12, 22),
          passportExpiry: null,
          visaResult: const VisaResult(verdict: VisaVerdict.domestic, stayDays: 2, passportOk: true),
          tasks: const [],
        );

    testWidgets('비자 결과·준비 일정·체크리스트·지갑을 숨기고 발걸음 기록만 보여 준다', (tester) async {
      final permission = FakePermission();
      final r = await pumpResultPage(tester, trip: domesticTrip(), permission: permission);

      expect(find.text('대한민국 국내 여행'), findsOneWidget);
      expect(find.byKey(const Key('tripFootstepsCard')), findsOneWidget);
      expect(find.text('역산 일정'), findsNothing);
      expect(find.textContaining('근거'), findsNothing);
      expect(find.byKey(const Key('openChecklistButton')), findsNothing);
      expect(find.byKey(const Key('openWalletButton')), findsNothing);
      // 준비 일정이 없으니 알람도, 알림 권한 요청도 없다.
      expect(r.alarms.scheduled, isEmpty);
      expect(permission.calls, 0);
    });

    testWidgets('삭제 확인은 발걸음 기록이 지워진다고 알린다', (tester) async {
      await pumpResultPage(tester, trip: domesticTrip());

      await tester.tap(find.byKey(const Key('tripMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteTripMenuItem')));
      await tester.pumpAndSettle();

      expect(find.text('이 여행의 발걸음 기록이 모두 지워집니다.'), findsOneWidget);
    });
  });

  testWidgets('해외 여행 상세에도 발걸음 기록 칸이 있고, 날짜별 발걸음으로 간다', (tester) async {
    await pumpResultPage(tester);

    await tester.ensureVisible(find.byKey(const Key('openTripFootsteps')));
    await tester.tap(find.byKey(const Key('openTripFootsteps')));
    await tester.pumpAndSettle();

    expect(find.text('발걸음 7'), findsOneWidget);
  });

  testWidgets('국가 이름과 판정 결과를 서버 데이터로 보여준다', (tester) async {
```

`app/test/checklist/checklist_page_test.dart`에서 다음 부분을

```dart
  testWidgets('선택한 여행이 없으면 가장 가까운 다가오는 여행의 체크리스트를 보여준다', (tester) async {
```

다음으로 바꾼다:

```dart
  testWidgets('국내 여행은 준비물 탭에서 고르지 않는다(체크리스트·지갑이 없다)', (tester) async {
    final domestic = sampleSummary(
      id: 3,
      iso2: 'KR',
      nameKo: '대한민국',
      depart: _today.add(const Duration(days: 1)),
      ret: _today.add(const Duration(days: 2)),
      verdict: VisaVerdict.domestic,
    );

    final r = await _pumpChecklist(tester, trips: [domestic, _upcomingVn], stored: {'selected_trip_id.uid-a': 3});
    expect(find.text('준비물 · 베트남'), findsOneWidget);
    expect(r.api.getChecklistCalls, [1]);
  });

  testWidgets('국내 여행만 있으면 해외 여행계획을 만들라고 안내한다', (tester) async {
    await _pumpChecklist(tester, trips: [
      sampleSummary(id: 3, iso2: 'KR', nameKo: '대한민국', verdict: VisaVerdict.domestic),
    ]);

    expect(find.textContaining('국내 여행에는 준비물이 없어요'), findsOneWidget);
  });

  testWidgets('선택한 여행이 없으면 가장 가까운 다가오는 여행의 체크리스트를 보여준다', (tester) async {
```

같은 파일에서 다음 부분을

```dart
import 'package:app/features/visa/models/trip_checklist_item.dart';
```

다음으로 바꾼다:

```dart
import 'package:app/features/visa/models/trip.dart' show VisaVerdict;
import 'package:app/features/visa/models/trip_checklist_item.dart';
```

`app/test/footsteps/trip/trip_footsteps_card_test.dart`:

```dart
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/footsteps/trip/trip_footsteps_card.dart';
import 'package:app/features/footsteps/trip/trip_recording_providers.dart';
import 'package:app/features/footsteps/trip/trip_recording_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'trip_fakes.dart';

void main() {
  final trip = period(7, DateTime(2026, 11, 20), DateTime(2026, 11, 22));

  test('기록 단계: 출발 전·여행 중·일시정지·귀국 다음 날 이후', () {
    expect(tripRecordingPhaseOf(trip, DateTime(2026, 11, 19, 23), paused: false), TripRecordingPhase.upcoming);
    expect(tripRecordingPhaseOf(trip, DateTime(2026, 11, 20), paused: false), TripRecordingPhase.recording);
    expect(tripRecordingPhaseOf(trip, DateTime(2026, 11, 21), paused: true), TripRecordingPhase.paused);
    expect(tripRecordingPhaseOf(trip, DateTime(2026, 11, 23), paused: true), TripRecordingPhase.ended);
  });

  Future<FakeTripRecordingCoordinator> pumpCard(
    WidgetTester tester, {
    required DateTime now,
    Map<String, Object> stored = const {},
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    final coordinator = FakeTripRecordingCoordinator();
    final router = GoRouter(
      initialLocation: '/visa/trip/7',
      routes: [
        GoRoute(
          path: '/visa/trip/:id',
          builder: (_, _) => Scaffold(body: TripFootstepsCard(trip: trip)),
        ),
        GoRoute(
          path: '/visa/trip/:id/footsteps',
          builder: (_, state) => Scaffold(body: Text('발걸음 ${state.pathParameters['id']}')),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        tripRecordingCoordinatorProvider.overrideWithValue(coordinator),
        tripClockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return coordinator;
  }

  testWidgets('여행 중이면 기록 중이라고 알리고, 일시정지·재개를 코디네이터로 보낸다', (tester) async {
    final coordinator = await pumpCard(tester, now: DateTime(2026, 11, 21, 9));
    expect(find.text('여행 중이라 발걸음을 기록하고 있어요.'), findsOneWidget);

    await tester.tap(find.text('기록 일시정지'));
    await tester.pumpAndSettle();
    expect(coordinator.pauses, [(7, true)]);
    expect(find.text('기록을 일시정지했어요.'), findsOneWidget);

    await tester.tap(find.text('기록 재개'));
    await tester.pumpAndSettle();
    expect(coordinator.pauses, [(7, true), (7, false)]);
    expect(find.text('여행 중이라 발걸음을 기록하고 있어요.'), findsOneWidget);
  });

  testWidgets('일시정지 상태는 여행별로 기기에 남은 값을 보여 준다', (tester) async {
    await pumpCard(tester, now: DateTime(2026, 11, 21, 9), stored: {TripRecordingStore.pausedKey: '[7]'});

    expect(find.text('기록을 일시정지했어요.'), findsOneWidget);
    expect(find.text('기록 재개'), findsOneWidget);
  });

  testWidgets('출발 전에는 출발일 0시부터 기록한다고 알리고, 재부팅 한계를 적어 둔다', (tester) async {
    await pumpCard(tester, now: DateTime(2026, 11, 12, 9));

    expect(find.text('출발일(11/20) 0시부터 발걸음을 기록해요.'), findsOneWidget);
    expect(find.textContaining('휴대폰을 다시 켠 뒤에는 앱을 한 번 열어 주세요'), findsOneWidget);
  });

  testWidgets('귀국 다음 날부터는 일시정지 버튼 없이 날짜별 발걸음만 연다', (tester) async {
    await pumpCard(tester, now: DateTime(2026, 11, 23));

    expect(find.text('귀국 다음 날 기록을 마쳤어요.'), findsOneWidget);
    expect(find.byKey(const Key('tripRecordingToggle')), findsNothing);

    await tester.tap(find.byKey(const Key('openTripFootsteps')));
    await tester.pumpAndSettle();
    expect(find.text('발걸음 7'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run(`app/`에서): `flutter test test/visa/ test/checklist/ test/footsteps/trip/trip_footsteps_card_test.dart`

Expected: FAIL. `VisaVerdict.domestic`·`Trip.isDomestic`·`trip_footsteps_card.dart`가 없다.

- [ ] **Step 3: 구현**

`app/lib/features/visa/models/trip.dart`에서 다음 부분을

```dart
/// 서버 `visa/VisaVerdict.java`의 wireValue와 문자 그대로 일치해야 한다.
enum VisaVerdict {
  visaFreeOk('VISA_FREE_OK'),
  visaFreeExceeded('VISA_FREE_EXCEEDED'),
  visaRequired('VISA_REQUIRED'),
  unverified('UNVERIFIED');
```

다음으로 바꾼다:

```dart
/// 서버 `visa/VisaVerdict.java`의 wireValue와 문자 그대로 일치해야 한다.
/// [domestic]은 판정 결과가 아니라 국내 여행(대한민국)이다 — 서버가 비자 판정을 건너뛰고 이 값으로 저장한다(설계 9-1).
enum VisaVerdict {
  visaFreeOk('VISA_FREE_OK'),
  visaFreeExceeded('VISA_FREE_EXCEEDED'),
  visaRequired('VISA_REQUIRED'),
  unverified('UNVERIFIED'),
  domestic('DOMESTIC');
```

같은 파일에서 다음 부분을

```dart
  final DateTime departDate;
  final DateTime returnDate;
  final DateTime passportExpiry;
  final VisaResult visaResult;
  final List<TripTask> tasks;
```

다음으로 바꾼다:

```dart
  final DateTime departDate;
  final DateTime returnDate;

  /// 국내 여행은 여권 만료일이 없어 null이다(설계 9-1).
  final DateTime? passportExpiry;
  final VisaResult visaResult;
  final List<TripTask> tasks;
```

같은 파일에서 다음 부분을

```dart
  final bool judgementStale;

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
```

다음으로 바꾼다:

```dart
  final bool judgementStale;

  /// 국내 여행이면 여행 상세가 비자 결과·준비 일정·체크리스트·지갑을 숨기고 발걸음 기록만 보여 준다(설계 9-1).
  bool get isDomestic => visaResult.verdict == VisaVerdict.domestic;

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
```

같은 파일에서 다음 부분을

```dart
        passportExpiry: DateTime.parse(json['passportExpiry'] as String),
```

다음으로 바꾼다:

```dart
        passportExpiry: json['passportExpiry'] == null ? null : DateTime.parse(json['passportExpiry'] as String),
```

`app/lib/features/visa/models/trip_summary.dart`에서 다음 부분을

```dart
  final VisaVerdict verdict;

  /// 목록 카드·준비물 탭 상단에 쓰는 `12/20~1/9` 형식.
```

다음으로 바꾼다:

```dart
  final VisaVerdict verdict;

  /// 국내 여행(설계 9-1). 준비물 탭은 이 여행을 고르지 않는다 — 체크리스트·지갑이 없다.
  bool get isDomestic => verdict == VisaVerdict.domestic;

  /// 목록 카드·준비물 탭 상단에 쓰는 `12/20~1/9` 형식.
```

`app/lib/features/visa/visa_result_display.dart`에서 다음 부분을

```dart
    case VisaVerdict.unverified:
      return _consulateCheck(result.stayDays);
  }
}
```

다음으로 바꾼다:

```dart
    case VisaVerdict.unverified:
      return _consulateCheck(result.stayDays);

    // 국내 여행 상세는 배지를 보여 주지 않지만(설계 9-1) 모든 판정 값을 다룬다.
    case VisaVerdict.domestic:
      return ResultBadge(
        title: '국내 여행',
        caption: '체류 ${result.stayDays}일 · 비자 필요 없음',
        tone: BadgeTone.info,
      );
  }
}
```

같은 파일에서 다음 부분을

```dart
      VisaVerdict.unverified => (label: '확인 필요', tone: BadgeTone.neutral),
    };
```

다음으로 바꾼다:

```dart
      VisaVerdict.unverified => (label: '확인 필요', tone: BadgeTone.neutral),
      VisaVerdict.domestic => (label: '국내', tone: BadgeTone.info),
    };
```

`app/lib/features/visa/data/trip_api.dart`에서 다음 부분을

```dart
  /// 여행계획을 저장하고 비자 판정 + 역산 일정이 담긴 결과를 받는다.
  Future<Trip> createTrip({
    required String countryIso2,
    required DateTime departDate,
    required DateTime returnDate,
    required DateTime passportExpiry,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/trips',
      data: {
        'countryIso2': countryIso2,
        'departDate': _wireDate.format(departDate),
        'returnDate': _wireDate.format(returnDate),
        'passportExpiry': _wireDate.format(passportExpiry),
      },
    );
```

다음으로 바꾼다:

```dart
  /// 여행계획을 저장하고 비자 판정 + 역산 일정이 담긴 결과를 받는다. 국내 여행(KR)은 [passportExpiry]를 보내지 않는다 —
  /// 서버가 판정을 건너뛰고 DOMESTIC으로 저장한다(설계 9-1).
  Future<Trip> createTrip({
    required String countryIso2,
    required DateTime departDate,
    required DateTime returnDate,
    DateTime? passportExpiry,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/trips',
      data: {
        'countryIso2': countryIso2,
        'departDate': _wireDate.format(departDate),
        'returnDate': _wireDate.format(returnDate),
        if (passportExpiry != null) 'passportExpiry': _wireDate.format(passportExpiry),
      },
    );
```

`app/lib/features/visa/visa_page.dart`에서 다음 부분을

```dart
  bool get _datesInOrder =>
```

다음으로 바꾼다:

```dart
  /// 대한민국을 고르면 국내 여행이다 — 여권 만료일을 받지 않고 비자 판정도 하지 않는다(설계 9-1).
  bool get _isDomestic => _country?.isoAlpha2 == homeCountryIso2;

  bool get _datesInOrder =>
```

같은 파일에서 다음 부분을

```dart
      _returnDate != null &&
      _passportExpiry != null &&
      _datesInOrder &&
```

다음으로 바꾼다:

```dart
      _returnDate != null &&
      (_isDomestic || _passportExpiry != null) &&
      _datesInOrder &&
```

같은 파일에서 다음 부분을

```dart
            returnDate: _returnDate!,
            passportExpiry: _passportExpiry!,
          );
```

다음으로 바꾼다:

```dart
            returnDate: _returnDate!,
            passportExpiry: _isDomestic ? null : _passportExpiry,
          );
```

같은 파일에서 다음 부분을

```dart
                const SizedBox(height: 18),
                _FieldGroup(
                  label: '여권 만료일',
                  child: _DateBox(
                    key: const Key('passportExpiryField'),
                    value: _passportExpiry,
                    onTap: _submitting ? null : _pickPassportExpiry,
                  ),
                ),
```

다음으로 바꾼다:

```dart
                if (!_isDomestic) ...[
                  const SizedBox(height: 18),
                  _FieldGroup(
                    label: '여권 만료일',
                    child: _DateBox(
                      key: const Key('passportExpiryField'),
                      value: _passportExpiry,
                      onTap: _submitting ? null : _pickPassportExpiry,
                    ),
                  ),
                ],
```

같은 파일에서 다음 부분을

```dart
                  label: _submitting ? '판정 중…' : '비자 판정하기',
```

다음으로 바꾼다:

```dart
                  label: _isDomestic
                      ? (_submitting ? '저장 중…' : '여행 만들기')
                      : (_submitting ? '판정 중…' : '비자 판정하기'),
```

같은 파일에서 다음 부분을

```dart
/// 서버의 국가 목록(`/api/countries`)을 바텀시트로 보여주고, 고른 국가를 pop으로 돌려준다.
/// 시트를 열 때 처음 불러오므로 화면 진입만으로는 서버를 호출하지 않는다.
class _CountryPickerSheet extends ConsumerWidget {
  const _CountryPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countries = ref.watch(countryListProvider);
```

다음으로 바꾼다:

```dart
/// 서버의 국가 목록(`/api/countries`)을 바텀시트로 보여주고, 고른 국가를 pop으로 돌려준다. 맨 위에는 앱이 붙인
/// '대한민국(국내 여행)'이 온다(설계 9-1, [countriesWithHomeProvider]). 시트를 열 때 처음 불러오므로 화면 진입만으로는
/// 서버를 호출하지 않는다.
class _CountryPickerSheet extends ConsumerWidget {
  const _CountryPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countries = ref.watch(countriesWithHomeProvider);
```

같은 파일에서 다음 부분을

```dart
            itemBuilder: (context, i) => ListTile(
              title: Text(list[i].nameKo),
              subtitle: Text(list[i].nameEn ?? '-'),
              trailing: Text('Tier ${list[i].tier}'),
              onTap: () => Navigator.of(context).pop(list[i]),
            ),
```

다음으로 바꾼다:

```dart
            itemBuilder: (context, i) => list[i].isoAlpha2 == homeCountryIso2
                ? ListTile(
                    key: const Key('domesticTripOption'),
                    title: Text('${list[i].nameKo}(국내 여행)'),
                    subtitle: const Text('여권·비자 없이 발걸음을 기록해요'),
                    onTap: () => Navigator.of(context).pop(list[i]),
                  )
                : ListTile(
                    title: Text(list[i].nameKo),
                    subtitle: Text(list[i].nameEn ?? '-'),
                    trailing: Text('Tier ${list[i].tier}'),
                    onTap: () => Navigator.of(context).pop(list[i]),
                  ),
```

같은 파일에서 다음 부분을

```dart
            Text(
              '${selected.isoAlpha2} · Tier ${selected.tier}',
              style: AppTextStyles.caption,
            ),
```

다음으로 바꾼다:

```dart
            Text(
              selected.isoAlpha2 == homeCountryIso2
                  ? '국내 여행'
                  : '${selected.isoAlpha2} · Tier ${selected.tier}',
              style: AppTextStyles.caption,
            ),
```

`app/lib/features/visa/visa_result_page.dart`에서 다음 부분을

```dart
import '../footsteps/trip/trip_recording_providers.dart';
```

다음으로 바꾼다:

```dart
import '../footsteps/trip/trip_footsteps_card.dart';
import '../footsteps/trip/trip_period.dart';
import '../footsteps/trip/trip_recording_providers.dart';
```

같은 파일에서 다음 부분을

```dart
    final tripAsync = ref.watch(tripProvider(tripId));
    final countryName = tripAsync.asData?.value.countryNameKo;

    return Column(
      children: [
        _Header(
          title: countryName == null ? '판정 결과' : '$countryName 판정 결과',
          onDelete: tripAsync.hasValue ? () => _confirmDelete(context, ref) : null,
        ),
```

다음으로 바꾼다:

```dart
    final tripAsync = ref.watch(tripProvider(tripId));
    final loaded = tripAsync.asData?.value;
    final title = switch (loaded) {
      null => '판정 결과',
      final trip when trip.isDomestic => '${trip.countryNameKo} 국내 여행',
      final trip => '${trip.countryNameKo} 판정 결과',
    };

    return Column(
      children: [
        _Header(
          title: title,
          onDelete: loaded == null ? null : () => _confirmDelete(context, ref, domestic: loaded.isDomestic),
        ),
```

같은 파일에서 다음 부분을

```dart
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('여행을 삭제할까요?'),
        content: const Text('준비 일정·체크리스트와 이 여행의 지갑 기록이 모두 지워집니다.'),
```

다음으로 바꾼다:

```dart
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, {required bool domestic}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('여행을 삭제할까요?'),
        content: Text(domestic
            ? '이 여행의 발걸음 기록이 모두 지워집니다.'
            : '준비 일정·체크리스트·지갑 기록과 이 여행의 발걸음 기록이 모두 지워집니다.'),
```

같은 파일에서 다음 부분을

```dart
  @override
  void initState() {
    super.initState();
    // 열 때마다 서버의 최신 일정으로 알람을 맞춘다. 새로 만든 여행도 이 화면으로 오므로 여기서 예약된다.
    final trip = _trip;
```

다음으로 바꾼다:

```dart
  @override
  void initState() {
    super.initState();
    // 국내 여행은 준비 일정이 없어 알람도 없다(설계 9-1) — 알림 권한도 묻지 않는다.
    if (_trip.isDomestic) return;
    // 열 때마다 서버의 최신 일정으로 알람을 맞춘다. 새로 만든 여행도 이 화면으로 오므로 여기서 예약된다.
    final trip = _trip;
```

같은 파일에서 다음 부분을

```dart
  @override
  Widget build(BuildContext context) {
    final visa = visaBadgeOf(_trip.visaResult);
```

다음으로 바꾼다:

```dart
  @override
  Widget build(BuildContext context) {
    final footsteps = TripFootstepsCard(trip: TripPeriod.fromTrip(_trip));
    // 국내 여행은 비자 결과·준비 일정·체크리스트·지갑을 숨기고 발걸음 기록만 보여 준다(설계 9-1).
    if (_trip.isDomestic) {
      return SingleChildScrollView(padding: const EdgeInsets.all(18), child: footsteps);
    }
    final visa = visaBadgeOf(_trip.visaResult);
```

같은 파일에서 다음 부분을

```dart
                onTap: () => _toggleDone(tasks[i]),
              ),
          const SizedBox(height: 24),
          Row(
```

다음으로 바꾼다:

```dart
                onTap: () => _toggleDone(tasks[i]),
              ),
          const SizedBox(height: 24),
          footsteps,
          const SizedBox(height: 14),
          Row(
```

`app/lib/features/checklist/checklist_page.dart`에서 다음 부분을

```dart
      data: (state) {
        final trip = resolveSelectedTrip(state.trips, selectedId, DateTime.now());
        if (trip == null) {
          return Column(
            children: [
              const _Header(),
              Expanded(
                child: _CenteredMessage(
                  message: '여행계획을 먼저 만들어 주세요.',
```

다음으로 바꾼다:

```dart
      data: (state) {
        // 국내 여행은 체크리스트·지갑이 없다(설계 9-1) — 고를 여행에서 뺀다.
        final trips = [for (final t in state.trips) if (!t.isDomestic) t];
        final trip = resolveSelectedTrip(trips, selectedId, DateTime.now());
        if (trip == null) {
          return Column(
            children: [
              const _Header(),
              Expanded(
                child: _CenteredMessage(
                  message: state.trips.isEmpty
                      ? '여행계획을 먼저 만들어 주세요.'
                      : '국내 여행에는 준비물이 없어요.\n해외 여행계획을 만들어 주세요.',
```

같은 파일에서 다음 부분을

```dart
            _Header(trip: trip, onChangeTrip: () => _pickTrip(context, ref, state.trips)),
```

다음으로 바꾼다:

```dart
            _Header(trip: trip, onChangeTrip: () => _pickTrip(context, ref, trips)),
```

`app/lib/features/footsteps/data/footsteps_sync_service.dart`에서 다음 부분을

```dart
/// 테이블에 없는 국가 코드(판정 실패 시의 `XX`, seed에 없는 `KR` 등)가 한 줄이라도
```

다음으로 바꾼다:

```dart
/// 테이블에 없는 국가 코드(판정 실패 시의 `XX` 등, `KR`은 V15부터 있다)가 한 줄이라도
```

`app/lib/features/footsteps/trip/trip_period.dart`에서 다음 부분을

```dart
import '../../visa/models/trip_summary.dart';
```

다음으로 바꾼다:

```dart
import '../../visa/models/trip.dart';
import '../../visa/models/trip_summary.dart';
```

같은 파일에서 다음 부분을

```dart
  final int tripId;
  final String countryIso2;

  /// 출발일 알림 문구
```

다음으로 바꾼다:

```dart
  factory TripPeriod.fromTrip(Trip trip) => TripPeriod(
        tripId: trip.id,
        countryIso2: trip.countryIso2,
        countryNameKo: trip.countryNameKo,
        departDate: _dateOnly(trip.departDate),
        returnDate: _dateOnly(trip.returnDate),
      );

  final int tripId;
  final String countryIso2;

  /// 출발일 알림 문구
```

`app/lib/features/footsteps/trip/trip_recording_providers.dart`의 계정 가드 앞에 일시정지 상태를 더한다. 다음 부분을

```dart
/// 로그아웃하거나 다른 계정으로 바뀌면 이전 계정의 여행 기록을 끄고 정리한다
```

다음으로 바꾼다:

```dart
/// 일시정지한 여행 id(여행 상세가 보여 준다). 바꿀 때는 [PausedTripsNotifier.setPaused]로 코디네이터를 거쳐 기록 서비스까지
/// 맞춘다.
class PausedTripsNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => ref.watch(tripRecordingStoreProvider).readPaused();

  Future<void> setPaused(int tripId, bool paused) async {
    await ref.read(tripRecordingCoordinatorProvider).setPaused(tripId, paused);
    state = {...state.where((id) => id != tripId), if (paused) tripId};
  }
}

final pausedTripIdsProvider = NotifierProvider<PausedTripsNotifier, Set<int>>(PausedTripsNotifier.new);

/// 로그아웃하거나 다른 계정으로 바뀌면 이전 계정의 여행 기록을 끄고 정리한다
```

`app/lib/features/footsteps/trip/trip_footsteps_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/wireframe_widgets.dart';
import '../../../router.dart';
import 'trip_period.dart';
import 'trip_recording_providers.dart';

final _shortDate = DateFormat('M/d');

/// 여행 기록의 지금 단계.
enum TripRecordingPhase { upcoming, recording, paused, ended }

/// 여행 상세 카드가 말할 단계. 기간·일시정지만 본다 — 권한 문제는 날짜별 보기의 배너가 알린다(설계 9-4).
TripRecordingPhase tripRecordingPhaseOf(TripPeriod trip, DateTime now, {required bool paused}) {
  if (!now.isBefore(trip.endsAt)) return TripRecordingPhase.ended;
  if (paused) return TripRecordingPhase.paused;
  return now.isBefore(trip.startsAt) ? TripRecordingPhase.upcoming : TripRecordingPhase.recording;
}

/// 여행 상세의 '발걸음 기록' 칸(설계 9-2의 3번, 9-4의 입구). 기록 상태와 [기록 일시정지·재개], [날짜별 발걸음]을 둔다.
/// 국내 여행 상세에는 이 칸만 있다(설계 9-1).
class TripFootstepsCard extends ConsumerWidget {
  const TripFootstepsCard({super.key, required this.trip});

  final TripPeriod trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(tripClockProvider)();
    final paused = ref.watch(pausedTripIdsProvider).contains(trip.tripId);
    final phase = tripRecordingPhaseOf(trip, now, paused: paused);
    final message = switch (phase) {
      TripRecordingPhase.upcoming => '출발일(${_shortDate.format(trip.departDate)}) 0시부터 발걸음을 기록해요.',
      TripRecordingPhase.recording => '여행 중이라 발걸음을 기록하고 있어요.',
      TripRecordingPhase.paused => '기록을 일시정지했어요.',
      TripRecordingPhase.ended => '귀국 다음 날 기록을 마쳤어요.',
    };

    return WireframeCard(
      key: const Key('tripFootstepsCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('발걸음 기록', style: AppTextStyles.cardTitle),
          const SizedBox(height: 6),
          Text(message, key: const Key('tripRecordingStatus'), style: AppTextStyles.body),
          if (phase != TripRecordingPhase.ended) ...[
            const SizedBox(height: 4),
            // 재부팅하면 자동으로 다시 켜지 않는다(설계 9-2) — 사용자 화면에 이 한계를 적는다.
            Text(
              '앱을 열면 기록이 켜져요. 휴대폰을 다시 켠 뒤에는 앱을 한 번 열어 주세요.',
              style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (phase != TripRecordingPhase.ended) ...[
                Expanded(
                  child: PillOutlineButton(
                    key: const Key('tripRecordingToggle'),
                    label: paused ? '기록 재개' : '기록 일시정지',
                    height: 44,
                    onPressed: () => ref.read(pausedTripIdsProvider.notifier).setPaused(trip.tripId, !paused),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: PillOutlineButton(
                  key: const Key('openTripFootsteps'),
                  label: '날짜별 발걸음',
                  height: 44,
                  onPressed: () => context.push(AppRoutes.tripFootstepsOf(trip.tripId)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 통과 확인**

Run
- `flutter test test/visa/ test/checklist/ test/footsteps/trip/` → 통과
  - 늘어난 테스트: 여행 상세 3개(합 39), 여행 만들기 2개, 준비물 2개, 모델·API 1개씩, 발걸음 칸 5개
- `flutter test`(전체) → 통과(814개), `dart analyze lib test` → 0건

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/visa/models/trip.dart app/lib/features/visa/models/trip_summary.dart \
  app/lib/features/visa/visa_result_display.dart app/lib/features/visa/data/trip_api.dart \
  app/lib/features/visa/visa_page.dart app/lib/features/visa/visa_result_page.dart \
  app/lib/features/checklist/checklist_page.dart app/lib/features/footsteps/data/footsteps_sync_service.dart \
  app/lib/features/footsteps/trip/trip_period.dart app/lib/features/footsteps/trip/trip_recording_providers.dart \
  app/lib/features/footsteps/trip/trip_footsteps_card.dart \
  app/test/visa/fake_trip_api.dart app/test/visa/trip_test.dart app/test/visa/trip_api_test.dart \
  app/test/visa/visa_result_display_test.dart app/test/visa/visa_page_test.dart app/test/visa/visa_result_page_test.dart \
  app/test/checklist/checklist_page_test.dart app/test/footsteps/trip/trip_footsteps_card_test.dart
git commit -m "feat(app): 대한민국을 국내 여행으로 만들고 여행 상세에 발걸음 기록 칸(일시정지·재개·날짜별 보기)을 둔다"
```

---

### Task 9: 문서 — 여행 기록 안내, API 명세, 설계 문서

**Files:**
- Create: `docs/research/trip-recording-guide.md`
- Modify: `docs/api-spec.md`
  - 국가 목록에서 본국을 뺀다.
  - 국내 여행 생성·검증, `DOMESTIC`, 국내 새로고침을 적는다.
- Modify: `docs/research/route-guide.md`(6절의 "R7에서 고친다"를 바로잡는다 — 앱은 `stepsSincePrev`를 경로에 쓰지 않는다)
- Modify: `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md`(9-6 R7에서 정한 세부 규칙)

**Interfaces:**
- Consumes: Task 1~8 전체
- Produces: 문서만

- [ ] **Step 1: 여행 기록 안내 작성**

`docs/research/trip-recording-guide.md`:

````markdown
# 여행 기록 안내 (R7)

여행 기간에 앱이 발걸음을 남기는 방법과 그 기록을 확인하는 방법이다. 설계는 `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md` 9장이다.

## 1. 언제 켜지고 꺼지나

| 때 | 하는 일 |
|---|---|
| 앱을 열거나 포그라운드로 돌아올 때 | 오늘이 여행 기간이고 일시정지가 아니면 기록 서비스를 `trip` 모드로 켠다 |
| 서버에서 여행 목록을 받을 때 | 일정을 바꾸고 기록 서비스·출발일 알림을 다시 맞춘다 |
| 출발일 08:00(서울) | "오늘부터 ○○ 여행 발걸음을 기록합니다." 알림. 누르면 앱이 열리며 켜진다 |
| 여행 상세 [기록 일시정지·재개] | 끄고 켠다. 일시정지는 여행별로 기기에 남는다 |
| 귀국일 다음 날 0시(기기 현지 시각) | 기록 서비스가 스스로 끈다 |
| 여행 삭제·로그아웃 | 화면이 서비스를 바로 끈다 |
| 재부팅 | 다시 켜지지 않는다. 다음에 앱을 열 때 켜진다 |

- 기록 기간은 [출발일 0시, 귀국일 다음 날 0시)이다. 여행이 겹치면 가장 늦게 출발한 여행을 기록한다.
- Android 14는 백그라운드에서 위치 포그라운드 서비스를 켜지 못하게 막는다. 그래서 시작은 언제나 앱을 연 순간이다.
- 실험 화면의 세션이 돌고 있으면 여행 기록을 켜지 않는다. 실험 화면에서 [기록 종료]를 누르면 여행 기록도 멈추고, 다음에 앱을 열 때 다시 켜진다.

## 2. 무엇을 남기나

- 정책
  - `step_budget`, E = 50m, 걸음 감지기 `adaptive`다.
  - `app/lib/features/footsteps/trip/trip_recorder.dart`의 `tripPolicyChoice`다. R6·배터리 실험 결과로 바꿀 곳은 이 상수 하나다.
- RoutePoints(앱 DB `travelfootsteps.sqlite`)에 측위 결과마다 한 행을 쓴다.
  - 좌표와 `trip_id`
  - 국가: 세계지도 폴리곤으로 가린다. 모르면 여행의 나라다.
  - `accuracy_m`, `steps_since_prev`
  - `state`: `unknown`·`walking`·`still`·`otherMotion`·`vehicle`
- `trip_still_spans`에 걸음 감지기가 정지였던 구간(시작·끝)을 쓴다. 날짜별 보기가 머문 곳의 도착·출발 시각을 이것으로 잡는다(설계 5-6).
- 서버로 보내지 않는다. 날짜별 보기가 복원할 때만 그날 점을 보내고, 서버는 저장하지 않는다.
- WorkManager 1시간 국가 체크인은 여행 기간에만 위치를 읽는다. 일시정지한 여행은 뺀다.
- 실시간 경로(`liveRouteProvider`)는 화면 표시용이라 저장하지 않는다.

## 3. 날짜별 보기

여행 상세 → [날짜별 발걸음]. 출발일~귀국일 날짜 칩과 그날의 복원 경로·머문 곳·걸음·이동 거리를 보여 준다.
- 복원은 `POST /api/route/reconstruct`의 기본 방법(`osrm_match_radius`)이다. (여행, 날짜, 그날 마지막 점 시각)을 키로 앱이 떠 있는 동안 메모리에 둔다.
- 선 모양
  - 점선: `estimated` — GPS가 없던 10분 이상의 공백을 최단경로로 이은 것
  - 주황 선: 탈것 구간
- 서버·네트워크가 실패하거나 OSRM이 없어 직선으로 대신 채웠으면 "도로 맞춤을 못 했어요"가 뜬다. [다시 시도]는 그 날만 다시 부른다.
- 그날 걸음 = 그날 점들의 `steps_since_prev` 합. 이동 거리 = 그린 경로 길이(탈것·추정 구간 포함).
- 백그라운드 위치·활동 인식·알림 권한 중 하나라도 없으면 "기록이 꺼져 있어요" 배너와 [설정 열기]가 뜬다.

## 4. 기록 정리

| 때 | 지우는 것 |
|---|---|
| 여행 삭제, 다른 기기에서 지워져 상세가 404 | 그 여행의 점·정지 구간·일시정지·출발일 알림 |
| 서버 목록을 받을 때 | 목록에 없는 여행의 점·정지 구간 |
| 로그아웃 | 기록을 끄고 일정·일시정지·출발일 알림을 비운다(점은 남긴다) |
| 다른 계정 로그인 | 이전 계정의 여행 점·정지 구간 전부 |

## 5. 폰에서 꺼내 보기

디버그 빌드에서(Git Bash, 저장소 루트):

```bash
mkdir -p research/data
MSYS_NO_PATHCONV=1 adb exec-out run-as com.travelfootsteps.app cat app_flutter/travelfootsteps.sqlite > research/data/trip.sqlite
research/.venv/Scripts/python - <<'EOF'
import sqlite3
db = sqlite3.connect('research/data/trip.sqlite')
for row in db.execute("SELECT trip_id, count(*), min(recorded_at), max(recorded_at), sum(steps_since_prev) "
                      "FROM route_points WHERE trip_id IS NOT NULL GROUP BY trip_id"):
    print(row)
for row in db.execute("SELECT trip_id, start_at, end_at FROM trip_still_spans ORDER BY start_at DESC LIMIT 10"):
    print(row)
EOF
```

- `recorded_at`·`start_at`·`end_at`은 유닉스 초다.
- 꺼낸 DB에는 실제 이동 경로가 있다. `research/data/`에 두고 커밋하지 않는다.
- 기록 서비스의 오류는 `adb logcat -s flutter`에서 "여행 기록"으로 시작하는 줄로 남는다.

## 6. 한계

- 재부팅하면 다시 켜지지 않는다. 앱을 한 번 열어야 한다(여행 상세에도 적어 둔다).
- 시스템이 서비스를 다시 띄우면 정책이 처음부터 돈다. 그 뒤 첫 점의 state는 `unknown`이다.
- 걸음 수 합이 실제보다 조금 적거나 다른 날에 들어갈 수 있다.
  - 걷기 시작 몇 초 안의 측위는 `adaptive`가 나중에 소급해 센 걸음이 빠진다.
  - 하루의 마지막 측위 뒤 걸음은 다음 측위에 든다(다음 날일 수 있다).
- 복원은 한국 OSRM만 쓴다(설계 6-1). 해외 여행의 날짜별 보기는 직선으로 그리고 "도로 맞춤을 못 했어요"가 뜬다.
- 같은 날 여행이 겹치면 점은 나중에 출발한 여행에만 남는다.
````

- [ ] **Step 2: API 명세·경로 복원 안내·설계 문서 고치기**

`docs/api-spec.md`에서 다음 부분을

```markdown
### `GET /api/countries`
전체 국가 목록(한글 이름 오름차순).
```

다음으로 바꾼다:

```markdown
### `GET /api/countries`
여행 목적지 국가 목록(한글 이름 오름차순). 국내 여행용 본국 행(`KR`, V15)은 넣지 않는다 — 앱이 '대한민국(국내 여행)'을 스스로 맨 위에 붙인다(R7).
```

같은 파일에서 다음 부분을

```markdown
### `POST /api/trips`
여행을 생성하고, 비자 판정 + 역산 준비 일정 + 준비물 체크리스트(스냅샷)를 한 번에 만든다.
```

다음으로 바꾼다:

```markdown
### `POST /api/trips`
여행을 생성하고, 비자 판정 + 역산 준비 일정 + 준비물 체크리스트(스냅샷)를 한 번에 만든다.

`countryIso2`가 `KR`(대소문자 무관)이면 **국내 여행**이다(R7): 비자 판정을 건너뛰고 `verdict: "DOMESTIC"`으로 저장하며, 준비 일정과 체크리스트를 만들지 않는다. 앱은 이 여행의 발걸음만 기록한다.
```

같은 파일에서 다음 부분을

```markdown
| `departDate`, `returnDate`, `passportExpiry` | 필수, `returnDate`는 `departDate`보다 앞설 수 없음(위반 시 400) |

**응답 200** — 아래 "TripResponse" 참고.
**404** — 존재하지 않는 국가.
**400** — 필수 필드 누락 / `returnDate < departDate`.
```

다음으로 바꾼다:

```markdown
| `departDate`, `returnDate` | 필수, `returnDate`는 `departDate`보다 앞설 수 없음(위반 시 400) |
| `passportExpiry` | 해외 여행은 필수(없으면 400). 국내 여행(`KR`)은 빼도 되고, 보내도 저장하지 않는다(응답은 `null`) |

**응답 200** — 아래 "TripResponse" 참고.
**404** — 존재하지 않는 국가.
**400** — 필수 필드 누락(해외 여행의 `passportExpiry` 포함) / `returnDate < departDate`.
```

같은 파일에서 다음 부분을

```markdown
`verdict` 값 (4가지, **문자열 그대로 클라이언트-바인딩 고정값** — 임의 변경 금지):
```

다음으로 바꾼다:

```markdown
`verdict` 값 (5가지, **문자열 그대로 클라이언트-바인딩 고정값** — 임의 변경 금지):
```

같은 파일에서 다음 부분을

```markdown
| `UNVERIFIED` | 데이터 미수집/파싱 실패 — 영사관 확인 필요 (절대 "무비자 OK"로 낙관 처리하지 않음) |
```

다음으로 바꾼다:

```markdown
| `UNVERIFIED` | 데이터 미수집/파싱 실패 — 영사관 확인 필요 (절대 "무비자 OK"로 낙관 처리하지 않음) |
| `DOMESTIC` | 국내 여행(대한민국) — 판정하지 않는다. `passportOk: true`, 허용 일수·여권 요건은 `null`, 준비 일정 없음, `judgementStale`은 언제나 `false` (R7) |
```

같은 파일에서 다음 부분을

```markdown
### `POST /api/trips/{id}/refresh`
사용자가 명시적으로 동의했을 때만 호출. 판정을 다시 계산해 스냅샷을 덮어쓰고, 기존 준비 일정을 전부 지운 뒤 새로 만든다.
```

다음으로 바꾼다:

```markdown
### `POST /api/trips/{id}/refresh`
사용자가 명시적으로 동의했을 때만 호출. 판정을 다시 계산해 스냅샷을 덮어쓰고, 기존 준비 일정을 전부 지운 뒤 새로 만든다. 국내 여행(`DOMESTIC`)은 아무것도 바꾸지 않고 지금 값을 그대로 돌려준다.
```

같은 파일에서 다음 부분을

```markdown
- `VisaVerdict`: `VISA_FREE_OK`, `VISA_FREE_EXCEEDED`, `VISA_REQUIRED`, `UNVERIFIED`
```

다음으로 바꾼다:

```markdown
- `VisaVerdict`: `VISA_FREE_OK`, `VISA_FREE_EXCEEDED`, `VISA_REQUIRED`, `UNVERIFIED`, `DOMESTIC`(국내 여행, R7)
```

`docs/research/route-guide.md`에서 다음 부분을

```markdown
- `stepsSincePrev`는 재생기가 끝에 걸음 시각으로 다시 센 값이다. 폰 정책 실행 모드의 `fixes.csv`는 걷기 시작 몇 초 안의 측위에서 걸음 몇 개가 빠질 수 있다(R7에서 고친다).
```

다음으로 바꾼다:

```markdown
- `stepsSincePrev`는 재생기가 끝에 걸음 시각으로 다시 센 값이다. 폰 정책 실행 모드의 `fixes.csv`와 앱 여행 기록(R7)은 걷기 시작 몇 초 안의 측위에서 걸음 몇 개가 빠질 수 있다. 앱의 날짜별 보기는 기본 방법(`osrm_match_radius`)이라 이 값을 경로에 쓰지 않고, 그날 걸음 수 합만 그만큼 모자랄 수 있다.
```

`docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md`에서 다음 부분을

```markdown
- 앱 위젯: 국내 여행 상세의 섹션 숨김, 날짜별 묶음, 복원 실패 시 직선 표시

## 10. 위험과 대응
```

다음으로 바꾼다:

```markdown
- 앱 위젯: 국내 여행 상세의 섹션 숨김, 날짜별 묶음, 복원 실패 시 직선 표시

### 9-6. R7에서 정한 세부 규칙

구현 계획 `docs/superpowers/plans/2026-11-12-research-r7-trip.md`에서 정한 것이다. 안내는 `docs/research/trip-recording-guide.md`다.
- 국내 여행
  - V15가 country 표에 본국(KR) 행을 넣는다(여행의 외래 키). 목적지 목록 API와 일일 수집은 그 행을 건너뛴다.
  - 국내 여행은 여권 만료일을 보내도 저장하지 않는다. `DOMESTIC`은 서버·앱 `VisaVerdict` 둘 다에 있다.
  - 준비물 탭은 국내 여행을 고르지 않는다(체크리스트·지갑이 없다).
- `shouldRecord`는 기록할 여행 하나를 돌려준다. 겹치면 가장 늦게 출발한 여행, 같으면 id가 큰 여행이다.
- 기록 서비스
  - 실험 모드와 같은 포그라운드 서비스·알림 채널에 TaskHandler만 다르게 붙인다. 실험 세션이 돌고 있으면 여행 기록은 켜지도 끄지도 않는다.
  - 정책은 `step_budget` E = 50m에 `adaptive` 감지기다(`tripPolicyChoice` 하나로 바꾼다). 점의 국가는 세계지도 폴리곤으로 가리고, 모르면 여행의 나라다.
  - 5초마다 날짜를, 1분마다 저장소(지워졌는지·일시정지인지)를 다시 본다.
- 걸음 감지기의 정지 구간을 `trip_still_spans`(스키마 3)에 남긴다. 날짜별 보기의 머문 곳도 5-6의 제안 방식으로 묶는다.
- 권한
  - 기록 서비스는 위치(앱 사용 중) 권한만 있으면 켠다.
  - 배너는 백그라운드 위치·활동 인식·알림 중 하나라도 없으면 뜬다.
- 출발일 알림은 서울 시각 08:00이다. 일시정지한 여행에는 만들지 않는다. WorkManager 체크인도 일시정지한 여행에서는 하지 않는다.
- 정리(PR #32의 알람 주인과 같은 방식)
  - 로그아웃은 기록을 끄고 일정·알림만 비운다(좌표는 남긴다).
  - 다른 계정이 로그인하면 이전 여행 좌표를 모두 지운다.
- 날짜별 보기
  - 그날 걸음 = 그날 점의 `steps_since_prev` 합, 이동 거리 = 그린 경로 길이다.
  - 점이 2000개를 넘으면 점 하나를 겹쳐 나눠 복원한다. 밤을 넘긴 숙소는 두 날 모두 실제 도착·출발 시각으로 보인다.
- 한계: 재부팅 뒤에는 앱을 열어야 다시 켜진다. 시스템이 서비스를 다시 띄우면 정책이 처음부터 돈다. 해외 여행은 한국 OSRM만 있어 직선으로 그린다.

## 10. 위험과 대응
```

- [ ] **Step 3: 커밋**

```bash
git add docs/research/trip-recording-guide.md docs/api-spec.md docs/research/route-guide.md \
  docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md
git commit -m "docs: 여행 기록 안내를 추가하고 API 명세와 설계 문서에 R7 규칙을 적는다"
```

- [ ] **Step 4: 마무리 확인**

- `app/`: `flutter test` → 통과(814개). `dart analyze lib test` → 0건.
- `packages/footstep_core/`: `dart test` → 통과(216개). `dart analyze` → 0건.
- `server/`: Docker Desktop을 켜고 `./gradlew test` → 통과(333개). 끝나면 Docker Desktop을 끈다.
- `git status --short`에 `research/data/`, `server/.env`, `firebase-service-account.json`, `google-services.json`이 없다.
- `git log --format=%B analysis..HEAD | grep -iE "co-authored|claude"`가 빈 결과다.

---

### Task 10: 실기기 확인 (사용자)

이 태스크는 서브에이전트가 아니라 **사용자가** 폰으로 한다(컨트롤러는 절차와 기록을 돕는다). PC에서 확인할 수 없는 네 가지를 본다.
- 앱을 열 때 포그라운드 서비스가 켜지는가
- 출발일 08:00 알림이 오는가
- 화면이 꺼진 동안에도 위치가 남는가
- 재부팅 뒤 자동으로 켜지지 않는가

폰은 Galaxy S23(Android 14 이상)이고 USB 디버깅을 쓴다. 결과는 `docs/research/trip-check.md`에 적는다. 기록 데이터는 커밋하지 않는다.

**Files:**
- Create: `docs/research/trip-check.md`(사용자가 결과를 적는다)

- [ ] **Step 1: 백업·빌드·설치**

`flutter install`은 기존 앱을 지워 폰의 세션·로그인·권한이 사라진다. 먼저 실험 세션을 PC로 옮긴다(Git Bash, 저장소 루트):

```bash
MSYS_NO_PATHCONV=1 adb pull /sdcard/Android/data/com.travelfootsteps.app/files/sessions/ research/data/sessions-backup-$(date +%Y%m%d)/
```

1. 서버를 띄운다(`server/`에서, 로컬 `server/.env` 그대로).
   - 포트는 `netsh interface ipv4 show excludedportrange protocol=tcp`로 예약 범위 밖인지 먼저 본다(예: 9090).
   - 명령: `SERVER_PORT=9090 ./gradlew bootRun`
   - 한국 OSRM이 있으면 `OSRM_BASE_URL=http://localhost:5001`도 준다(`docs/research/route-guide.md` 1절). 없으면 날짜별 보기가 "도로 맞춤을 못 했어요"로 그리는 것까지가 확인 대상이다.
2. 폰을 PC 서버에 잇는다: `adb reverse tcp:9090 tcp:9090`
3. `app/`에서 실행한다: `flutter run --dart-define=API_BASE_URL=http://localhost:9090`(또는 `flutter install`).
4. 로그인하고, 권한을 준다: 위치 '항상 허용', 신체 활동, 알림, 배터리 최적화 제외.

- [ ] **Step 2: 국내 여행 만들기와 앱을 열 때 켜지기**

1. 여행 탭 → '+ 새 여행계획' → 국가 목록 맨 위 '대한민국(국내 여행)'을 고른다.
   - 여권 만료일 칸이 없고 버튼이 '여행 만들기'인지 본다.
2. 출발일 = 오늘, 귀국일 = 오늘로 만든다.
3. 상세를 본다.
   - 제목이 '대한민국 국내 여행'이다.
   - '발걸음 기록' 칸만 보인다. 비자·일정·준비물·지갑은 없다.
   - 준비물 탭에 이 여행이 나오지 않는다.
4. 앱을 홈으로 보냈다가 다시 연다.
   - 알림창에 '대한민국 여행 발걸음 기록 중'이 뜨는지 본다(설계 9-2의 1번).
5. 실험 화면(발걸음 탭 요약 문구 길게 누르기)을 연다.
   - "여행 기록 중이에요" 안내가 보이는지 본다. [기록 종료]는 누르지 않는다.

- [ ] **Step 3: 화면을 끄고 기록하기 (약 40분)**

화면을 끄고 주머니에 넣는다.
1. 걷기 10분
2. 실내에서 멈춰 있기 12분 이상(머문 곳 10분 기준을 넘기려는 것이다)
3. 다시 걷기 10분
4. 가능하면 버스나 지하철을 한 구간 탄다.

- [ ] **Step 4: 날짜별 보기와 기록 확인**

1. 여행 상세 → [날짜별 발걸음]을 연다.
   - 오늘 칩이 골라져 있는가
   - 경로가 그려지는가(OSRM이 없으면 직선 + "도로 맞춤을 못 했어요")
   - 머문 곳 마커가 '도착 시각 · 머문 시간'으로 보이는가
   - 걸음 수·이동 거리가 보이는가
2. 설정에서 알림 권한을 끄고 돌아온다.
   - "기록이 꺼져 있어요" 배너가 뜨고 [설정 열기]가 설정을 여는지 본다. 다시 켠다.
3. DB를 꺼내 본다(`docs/research/trip-recording-guide.md` 5절의 명령).
   - `route_points`에 trip_id가 있는 행이 쌓였는가
   - 걷는 동안 약 30초(약 60걸음)마다, 머무는 동안 5분마다인가
   - `state`가 `walking`·`still`(탈것을 탔으면 `vehicle`)로 바뀌는가
   - `trip_still_spans`에 머문 구간이 있는가
4. 발걸음 탭 → 대한민국 국가 지도에도 오늘 점이 보이는지 본다(세계지도·국가 지도는 수정 없이 동작).

- [ ] **Step 5: 일시정지·재개, 재부팅, 삭제**

1. 여행 상세 [기록 일시정지]
   - 알림이 사라지는지 본다.
   - [기록 재개]를 누르면 다시 뜨는지 본다.
2. 폰을 재부팅한다.
   - 기록 알림이 **자동으로 뜨지 않는지** 본다.
   - 앱을 열면 다시 뜨는지 본다(설계 9-2의 재부팅 한계).
3. 여행을 삭제한다.
   - 알림이 사라지는지 본다.
   - DB를 다시 꺼내 그 trip_id의 행이 없는지 본다.

- [ ] **Step 6: 출발일 알림과 귀국 다음 날 스스로 끝내기 (다음 날 아침)**

1. 전날 밤에 '내일 출발·내일 귀국' 국내 여행을 하나 만든다.
2. 다음 날 08:00에 "오늘부터 대한민국 여행 발걸음을 기록합니다." 알림이 오는지 본다.
   - 누르면 앱이 열리고 기록 알림이 뜨는지 본다.
3. 그다음 날 0시가 지나면 기록 알림이 스스로 사라지는지 본다(아침에 확인해도 된다).

- [ ] **Step 7: 결과 기록**

`docs/research/trip-check.md`에 R1의 `device-check.md` 형식으로 적는다.
- 폰·앱 버전, 날짜
- 위 단계마다 확인 결과(되었다/안 되었다, 본 값). 측위 간격과 행 수는 DB에서 센 숫자로 적는다.
- 안 된 것과 로그(`adb logcat -s flutter`의 "여행 기록" 줄)

실제 위치가 든 DB·세션은 `research/data/`에만 둔다.

```bash
git add docs/research/trip-check.md
git commit -m "docs: 여행 기록 실기기 확인 결과를 기록한다"
```

---

## R7 뒤에 남는 것

- **정책 확정.**
  - R6 정확도 분석과 배터리 반복 측정(설계 8-2)이 끝나면 `tripPolicyChoice`(E, 걸음 감지기)를 정한다.
  - 하루 종일 도는 기록이라 `os` 감지기(하드웨어 걸음 센서)가 배터리에 유리할 수 있다. `adaptive`는 50Hz 가속도를 계속 읽는다.
- **와이어프레임 맞추기(사용자).**
  - 날짜별 보기와 여행 상세의 '발걸음 기록' 칸을 Claude Design 와이어프레임과 견준다.
  - 다르면 위젯 키(`tripDate_*`, `roadMatchFailed`, `tripRecordingOffBanner`, `tripRecordingToggle`, `openTripFootsteps`)를 지키며 모양만 고친다.
- **`hmm_steps`를 앱 기본으로 바꾸려면** 폰에서도 소급 걸음을 직전 점에 다시 세어야 한다(R5 'R7에 넘기는 것'). 지금 앱은 `osrm_match_radius`라 필요 없다.
- **배포.** 날짜별 보기의 도로 맞춤은 서버의 한국 OSRM이 있어야 한다. 배포 계획(Oracle Cloud)에 OSRM을 넣을지 정한다.

