# 분석 실행 안내 (R6)

세션 폴더를 재생하고 복원해 지표·그래프를 만든다. 설계는 `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md` 7장이다. 재생기·걸음 감지·복원 API 안내는 `replay-guide.md`·`steps-guide.md`·`route-guide.md`에 있다.

## 1. 준비 (처음 한 번)

Git Bash에서 `research/`로 가서 가상환경을 만든다. Python 3.10 이상이면 된다.

```bash
cd research
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements.txt
.venv/Scripts/python -m pytest          # 105 passed
```

`dart`가 PATH에 있어야 한다(재생기를 부른다). 없으면 `experiments.yaml`의 `dart:`에 `C:/flutter/bin/dart.bat`처럼 적는다. `packages/footstep_core/`에서 `dart pub get`을 한 번 해 둔다.

## 2. 세션 등록 — `sessions.yaml`

세션 폴더를 `research/data/sessions/<id>/`에 두고(`recording-guide.md` 3절) 목록에 적는다.

```yaml
sessions:
  - id: 20261120-101500-groundTruth
    use: pilot          # pilot | eval | battery
    course: 골목 도보 + 카페 15분 + 버스 4정거장
    carry: mixed
```

- `pilot`: 파라미터(β·σ 하한, 걸음 감지기, E)를 정할 때만 쓴다.
- `eval`: 평가용. **파라미터를 정할 때 보지 않는다**(설계 7-1). 그래프는 eval 세션이 하나라도 있으면 eval만 그린다.
- `battery`: 배터리 실험 한 회(정책 실행 모드 세션 + `batterystats.txt`, `battery-experiment-guide.md`). 방식 이름은 `meta.json`의 `policy`에서 정해진다.

## 3. 실행

```bash
cd research
.venv/Scripts/python -m analysis.run --config experiments.yaml
```

| 옵션 | 뜻 |
|---|---|
| `--no-reconstruct` | 서버 복원을 건너뛴다(`local_straight`만) |
| `--session <id>` | 이 세션만(여러 번 줄 수 있다). `sessions.yaml`에 없는 id는 오류로 멈춘다 |
| `--force` | 재생·복원 캐시를 무시하고 다시 돈다. 재생 CLI나 서버 코드를 바꾼 뒤에 쓴다 |
| `--data-dir`·`--results-dir` | 세션·결과 폴더를 바꾼다 |
| `--no-plots` | 그래프를 만들지 않는다 |

도는 순서: 세션마다 `runs`의 재생(정책 × 설정을 모두 곱한 조합) → 복원 방법마다 경로 → 지표. `step_detectors`마다 steps CLI → 걸음 지표. `battery` 세션 → 배터리 지표. 재생 결과(`results/replay/`)와 서버 응답(`results/recon/`)은 캐시라, 지표만 고쳐 다시 돌리면 몇 초 안에 끝난다. 처음에는 세션 하나에 1~2분 걸린다(재생 25개 + 걸음 감지 3개).

세션 하나가 망가져도(깨진 `meta.json`, 빠진 `summary.json` 등) 나머지 세션은 계속 돈다. 망가진 세션·재생은 `skipped.csv`에 이유를 남기고 건너뛴다.

**복원 서버** — `route-guide.md` 1·2절대로 로컬 OSRM과 서버(`local` 프로필, `dev-fake-token`)를 띄운다. `experiments.yaml`의 `reconstruct.server_url`의 포트를 서버와 맞춘다. 서버 토큰은 `reconstruct.token`(기본 `dev-fake-token`)이고, 환경변수 `TF_TOKEN`이 있으면 그 값이 우선한다.
- 서버에 연결하지 못하면(연결 실패·연결 시간 초과) 남은 복원 호출을 모두 건너뛰고 `skipped.csv`에 이유를 남긴다. `local_straight` 지표는 그대로 나온다.
- 읽기 시간 초과(`ReadTimeout`)는 느린 `hmm_steps` 요청 하나가 길어진 것일 수 있어 그 호출 하나(그 방법)만 건너뛴다. 서버가 꺼졌다고 보지 않으므로 다음 호출은 보낸다.
- 401/403(`ReconstructAuthError`)은 토큰이 틀린 것이라 이어 돌아도 소용이 없다. 실행을 멈춘다 — `TF_TOKEN`이나 `reconstruct.token`을 고친다.
- 서버는 떴는데 OSRM이 없으면 도로 맞춤 방법이 모두 직선 대체(`fallback: true`)가 된다. 그 결과를 방법 이름으로 내면 오해를 부르므로 `skipped.csv`로 보낸다(`skip_all_fallback: true`). 점이 하나뿐인 재생(`hourly`)은 대체할 것이 없어 그대로 남는다.
- 모든 구간이 직선 대체인 응답은 캐시에 쓰지 않는다. OSRM을 켠 뒤 다시 돌리면 바로 새로 받는다. 캐시 키에는 `hmm` 조정값(β·σ 하한)도 들어 있어 값이 다르면 다른 캐시다.
- 서버 코드나 OSRM 데이터를 바꾼 뒤에는 `--force`로 다시 돈다.

## 4. β·σ 하한 정하기 (pilot만)

```bash
.venv/Scripts/python -m analysis.tune --config experiments.yaml
```

- `tune.runs`의 재생(기본 `step_budget[adaptive] e_m=50`)을 pilot 세션마다 `hmm_steps`로 β ∈ {2, 5, 10, 20, 50}m × σ 하한 ∈ {3, 5, 10}m 복원하고, 경로 오차 P95의 세션 평균이 가장 작은 조합을 고른다(같으면 작은 β·σ).
- **완전한 칸만** 고를 수 있다. P95가 나온 (세션 × 재생) 수가 가장 꽉 찬 칸보다 적은 칸은 `hmm_grid.csv`의 `complete`가 False로 표에만 남는다 — 쉬운 세션만 평균 낸 칸이 우연히 이기는 것을 막는다.
- 결과: `results/hmm_grid.csv`, `results/hmm_grid_by_session.csv`, `results/hmm_best.json`. 두 표에 `fallback_share`(서버가 직선으로 대신 채운 구간 비율) 열이 있다. 0이 아니면 그 칸의 P95는 HMM 결과와 직선이 섞인 값이니 고른 조합의 `fallback_share`를 꼭 본다. 고른 값을 `experiments.yaml`의 `reconstruct.methods`에 `{name: hmm_steps_tuned, method: hmm_steps, hmm: {betaM: …, sigmaMinM: …}}`로 고정하고 eval을 돌린다.
- 종료 코드: 0 성공 / 1 결과 없음(pilot 세션 없음, `tune.runs` 비어 있음, 고를 수 있는 칸 없음 — 이때 `hmm_best.json`은 만들지 않는다) / 2 서버·OSRM을 쓸 수 없음(모든 구간이 직선이면 β·σ를 비교할 수 없다) / 3 재생 CLI(dart) 오류.

## 5. 결과 파일 (`research/results/`, 커밋하지 않는다)

| 파일 | 내용 |
|---|---|
| `path_metrics.csv` | 재생 × 복원 방법마다: 정답 점 수, 경로까지 거리 평균·P95(전체·도보·탈것), 복원 경로 길이·정답 이동거리·이동거리 오차 %, 측위 횟수, 시간당 측위, 추정 GPS 켜짐(초), fallback 구간 비율(`fallback_share`) |
| `stay_metrics.csv` | 재생마다: 검출·정답 머문 곳 수, 일치 수, 정밀도·재현율·F1 |
| `step_metrics.csv` | 세션 × 감지기: 총 걸음, 걸음 수 오차(Σ 기준 부호 있는 %·구간별 \|%\| 평균), 탈것 가짜 걸음(합·분당), 보행 판정 정밀도·재현율, 첫 걸음까지 지연(초) |
| `step_counts_by_carry.csv` | 걸음 세기 구간마다 휴대 위치·직접 센 수·감지 수·오차 % |
| `battery_runs.csv` | 배터리 회차마다: 방식, 제외 사유, 잰 시간, mAh, 시간당 mAh, 계단 맞춤 여부, 전류 평균(mA), batterystats GPS 시간(전체·앱), 추정 GPS 켜짐 |
| `battery_summary.csv` | 방식마다 n, 계단 맞춤 회차 수(`n_aligned`), 시간당 mAh 평균·표준편차, 전류 평균, 앱 GPS 시간 평균 |
| `skipped.csv` | 건너뛴 세션·재생·복원과 이유 |
| `figures/` | `1_tradeoff_fixes.png`·`1_tradeoff_mah.png`(배터리–오차 곡선), `2_battery.png`, `3_stay_f1.png`, `4_steps.png`, `5_reconstruct.png` — 값이 있는 것만 |

- 표가 비어도(한 세션도 못 돌았거나 해당 값이 없어도) 모든 CSV에 머리줄은 쓴다. 열 이름이 없는 빈 파일은 만들지 않는다.
- 걸음 세기·탈것·10분 넘는 머문 곳 표시가 없는 세션 하나를 `--no-reconstruct`로 돌리면 그림은 `1_tradeoff_fixes.png` 하나만 나온다. 나머지는 값이 없거나(배터리·머문 곳·걸음 세기) 복원 방법이 하나뿐이라(5번) 그리지 않는다.

## 6. 지표 정의 (설계 7-2)

- **정답 경로**: `gps.csv` 중 정확도 20m 이하 행을 시각 순으로 정렬한 것(파일 안에서 순서가 섞여 있어도 같은 값이 나온다). 탈것 구간은 `board`~`alight`, 그 밖은 도보다.
- **경로 오차**: 정답 점마다 복원 경로(모든 구간)까지 가장 가까운 거리. 평균과 P95(선형 보간 백분위).
- **이동거리 오차**: (복원 경로 길이 − 정답 이동거리) ÷ 정답 이동거리. 정답 이동거리는 마지막으로 센 점에서 10m(`truth.min_hop_m`) 이상 벗어난 점만 이어 잰다 — 서 있는 동안 GPS가 몇 m씩 흔들린 것이 거리로 쌓이지 않게 하려는 것이다.
- **머문 곳**: 정답은 `arrive`~`depart` 중 10분 이상(출발을 안 눌렀으면 세션 끝까지). 겹친 시간이 두 머문 곳 **각각의** 50% 이상이고 중심이 100m 이내면 일치다. 일대일로, 겹친 시간이 긴 쌍부터 짝짓는다. 정답 구간 안에 GPS 점이 없으면 중심을 몰라 시간만 본다.
  - 정밀도(검출 0개)·재현율(정답 0개)은 분모가 0이면 비운다. F1은 한쪽(검출 또는 정답)만 비어 있으면 0.0이다 — 놓쳤거나 헛검출한 것이라 '틀렸다'는 값이지 '알 수 없다'가 아니다. 양쪽 다 비어 있을 때만 F1도 비운다.
- **보행 판정**: 1초 격자. 정답 보행 = 머문 곳(길이 상관없이)과 탈것 밖. 예측 보행 = `step_states.csv`의 상태가 `walking`.
- **첫 걸음 지연**: 걸음 세기 구간마다 `count_start`에서 첫 감지 걸음까지(초)의 평균.
- **배터리**: 가장 길게 이어진 `plugged=0` 행만 쓴다. 전하량 계단이 처음 바뀐 행 ~ 마지막으로 바뀐 행 사이의 감소 ÷ 시간(계단 변화가 두 번 미만이면 처음 ~ 끝 행). `meta.json` errors에 `restarted by system`이 있는 회차는 평균에서 뺀다. 전류(`current_ua`)의 실제 단위는 기종마다 달라 `battery.current_units`에 적는다(SM-S911N은 mA). `battery_summary.csv`의 `n_aligned`가 `n`보다 작으면 일부 회차는 계단 맞춤이 안 돼 처음~끝 행으로 쟀다는 뜻이다.
- **batterystats GPS 시간**: 파일에서 처음 나오는 `Statistics since …` 구역만 센다(뒤 구역과 겹치면 같은 센서 시간이 두 번 더해진다). 그 구역의 `Sensor GPS: … realtime` 줄을 더한다. 앱 uid는 `Apk <패키지>:` 줄이 든 Uid 묶음에서 찾고, 못 찾으면 앱 몫은 비운다. 기종·Android 버전마다 형식이 달라 최선 노력 값이다 — 비면 `summary.json`의 추정 GPS 켜짐과 전하량만 보고한다.

## 7. 해석할 때 주의

- `local_straight`는 서버 `straight`와 달리 머문 곳 중심 치환·10분 공백(`estimated`) 처리를 하지 않는다. 서버 없이 도는 기준선이다.
- 경로 오차는 '가장 가까운 경로까지 거리'라 시간 순서를 보지 않는다. 같은 길을 되돌아온 경로에서는 오차가 실제보다 작게 나온다.
- 배터리–오차 곡선(1번 그림)은 본 실험만 그린다(ttff 0, 파라미터가 없거나 `e_m` 하나). 절제 실험·ttff 민감도는 `path_metrics.csv`로 본다. 실기기 mAh판(`1_tradeoff_mah.png`)은 배터리 방식 이름과 재생 이름이 같을 때만 점이 찍힌다(예: `step_budget[adaptive] e_m=50`). 머문 곳 F1(3번 그림)도 본 실험 재생만 그린다.
- 정답 GPS 자체에도 오차가 있다(설계 10장 위험 7). 실내 정지 구간은 정답이 약 7초 간격이다.
- 세션 데이터(`research/data/`)와 결과(`research/results/`)는 커밋하지 않는다. 가상환경(`research/.venv/`)도 올리지 않는다.

## 8. 문제가 생기면

- **한글이 깨져 보인다** — `run`·`tune`은 출력 인코딩을 UTF-8로 맞춘다. 재생 CLI(dart)의 오류 출력은 Windows 콘솔 코드 페이지(cp949)로 나오는 경우가 있어 UTF-8과 cp949 둘 다로 읽는다.
- **그림의 한글이 네모로 나온다** — 이 PC에서 한글 글꼴(맑은 고딕·AppleGothic·NanumGothic)을 못 찾으면 경고를 내고 기본 글꼴로 그린다. 글꼴을 설치한 뒤 다시 돌린다(캐시가 있어 몇 초면 끝난다).
- **CSV가 0바이트다** — `adb pull`이 중간에 끊긴 파일 등이다. 없는 파일처럼 빈 표로 읽으므로 분석은 멈추지 않고 그 값만 비어 나온다.
- **`skipped.csv`에 `session`이 보인다** — 그 세션의 파일(`meta.json`·`gps.csv`·`summary.json` 등)이 깨졌다는 뜻이다. 이유 열의 오류 이름과 메시지를 본다. 나머지 세션 결과는 정상이다.
- **`tune`이 2로 끝난다** — 서버나 OSRM이 꺼져 있다(`route-guide.md` 1·2절). 3이면 `dart`가 안 돈다(`dart:` 경로, `dart pub get`).
- **실행이 401/403으로 멈춘다** — `TF_TOKEN` 또는 `reconstruct.token`이 서버 프로필의 토큰과 다르다.
- **`--session`이 오류를 낸다** — id를 `sessions.yaml`에 적은 것과 똑같이 쓴다. 오류 메시지에 있는 id가 나열된다.

## 9. 범위 밖 (선택 과제)

설계 7-2의 위치공유 전송량 비교(현재 5초 고정 ↔ "상태 변화·20m 이동·60초 경과 중 하나면 전송")는 이번 R6에 넣지 않았다. 같은 1초 GPS로 메시지 수와 받는 쪽 위치 오차를 재는 함수 하나(`analysis/share.py`)로 나중에 붙일 수 있다.
