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
