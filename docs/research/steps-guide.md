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
| `brajdic` | `smooth_s` | 0.31 | 중심 이동 평균 길이(초, 논문 표 4) |
| `brajdic` | `peak_win_s` | 0.59 | 봉우리를 찾는 창 크기(초, 논문 표 4). 창 하나에 봉우리 하나 |
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
- 손으로 폰을 규칙적으로 흔드는 동작처럼, 흔들림이 걸음 대역 안에서 박자를 가지면 걸음으로 셀 수 있다(확장 과제: DePedo). 간격이 조금 불규칙해도 3초 창 자기상관 봉우리가 0.4를 넘으면 보행으로 본다.
- `adaptive`는 세션 시작과 기록 공백 뒤 약 3초(박자 창이 차는 동안)는 보행·기타 움직임을 판정하지 않는다. 그동안 걸은 걸음은 판정이 선 뒤 소급해 센다(최대 10걸음).
- `adaptive`의 `cadence_hz`는 초당 1.25걸음보다 느린 걸음에서 2배로 나온다(걸음 수는 맞다).
- `brajdic`은 봉우리 뒤 약 0.45초 시점의 흔들림으로 보행 여부를 본다. 그래서 걷기 시작·끝의 걸음 한두 개가 빠질 수 있다.
- 결과 폴더(`research/results/`)와 세션(`research/data/`)은 커밋하지 않는다.
