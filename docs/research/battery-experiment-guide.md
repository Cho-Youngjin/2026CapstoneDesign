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
- `meta.json`의 errors에 `restarted by system`이 있으면 그 회차는 분석에서 뺀다. 시스템이 기록 서비스를 다시 띄우면 정책이 처음부터 다시 돌고, `summary.json`은 다시 시작한 뒤만 센다.
- 안드로이드는 속도가 없는 위치를 속도 0으로 준다(멈춤과 구분되지 않는다). 속도를 쓰는 기준 정책(`time_speed`·`speed_adaptive`)을 해석할 때 참고한다.
- OS 센서판(`os`)은 가속도를 켜지 않아, 기록 서비스 주기(5초)를 시계로 써서 정지를 판정한다. 그래서 정지로 바뀌는 시각이 재생(1초 가속도 묶음)보다 최대 5초 늦을 수 있다.
- 결과 폴더(`research/results/`)와 세션(`research/data/`)은 커밋하지 않는다.
