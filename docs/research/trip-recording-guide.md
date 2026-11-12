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
