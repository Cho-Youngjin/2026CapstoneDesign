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
| `time_speed_still` | `time_speed` + EnTracked(4.1절)의 멈춤 감지: 걸음 감지기가 정지면 다음 측위를 미루고(예약 시각도 건너뜀), 다시 움직이면 남은 예약을 버리고 바로 측위(멈춤↔움직임 판정이 자주 바뀌는 감지기에서는 측위가 늘어난다). 측위 실패 재시도는 정지 중에도 한다 | `e_m`(기본 50) |
| `still_suppress` | Zhuang 외(2010): 1분마다 확인, 직전·이번 확인이 모두 정지면 건너뜀, 억제 중에도 5분마다 확인 측위 | `interval_s`(기본 60), `verify_s`(기본 300) |
| `step_budget` | **제안**: 보행은 '오차 + 걸음 수 × 보폭 > E'일 때(최소 5초 간격), 정지는 30초 이어지면 한 번 + 5분 확인, 기타 움직임은 확인 측위 두 번으로 탈것(시속 12km 이상)이면 time_speed 규칙(감지기 정지와 측위상 한 자리가 2분, GPS가 흔들리면 E 안 5분 넘을 때만 정지로) | `e_m`(50), `stride_m`(0.75), `use_steps`·`suppress_still`·`vehicle_probe`(true, 절제 실험) |
| `activity_gated` | 상용 방식: 활동 인식 STILL이면 연속 측위 끔, 움직임이면 켬 | 없음 |

`time_speed`는 RAPS(Paek 외 2010)의 장소·시간대별 속도 이력과 가속도 활동 비율을 쓰지 않고, 마지막 측위 속도만 쓰는 단순화판이다. EnTracked(Kjærgaard 외 2009)는 가속도로 멈춤을 감지해 GPS를 쉬므로, 공정한 비교를 위해 그 판(`time_speed_still`)을 따로 둔다. 두 판 모두 EnTracked의 기기 전력 모델(GPS 끄기 지연 등)과 동적 계획법 스케줄링은 넣지 않았다. 보고서에 이 차이를 적는다. 같은 정책을 폰에서 돌리는 방법(배터리 실험)은 `docs/research/battery-experiment-guide.md`에 있다.

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
