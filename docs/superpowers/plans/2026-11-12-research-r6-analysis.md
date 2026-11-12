# R6 Python 분석 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 세션 폴더를 재생·복원해 설계 7-2의 지표(경로 오차·이동거리 오차·머문 곳 F1·걸음 감지·배터리)와 7-3의 그래프를 만드는 Python 분석 `research/analysis/`를 만든다. `python -m analysis.run --config experiments.yaml` 한 번으로 재생 CLI → 서버 복원 → 지표·그래프까지 돌고, 서버나 OSRM이 없어도 끝까지 돈다. `hmm_steps`의 β·σ 하한은 `python -m analysis.tune`으로 예비용(pilot) 세션에서만 고른다.

**Architecture:**
- 지표는 모두 순수 함수다(DataFrame·목록 → 사전). 손으로 답을 셀 수 있는 합성 데이터로 pytest를 돌린다(설계 7-4).
  - `geo`(평면 근사·점–선분 거리) ← `session`(세션 읽기·관찰 표시 구간) ← `path_metrics`·`stay_metrics`·`step_metrics`·`battery`
- 바깥 프로그램은 얇은 객체 뒤에 둔다. 테스트는 가짜로 바꿔 끼워 실제 dart·서버를 부르지 않는다.
  - `DartCli`(replay·steps CLI, `subprocess.run`을 주입), `ReconstructClient`(POST `/api/route/reconstruct`, `post`를 주입)
- `run`이 `experiments.yaml`을 읽어 세션 × 재생 설정 × 복원 방법을 돌고 `research/results/`에 CSV·그림을 쓴다.
  - 재생 결과와 서버 응답은 결과 폴더에 캐시한다(재생은 결정적이다). 지표만 고쳐 다시 돌리면 몇 초다.
  - 서버에 연결하지 못하면 남은 복원을 건너뛴다. 서버는 떴는데 OSRM이 없어 모든 구간이 직선 대체면 그 방법의 지표를 내지 않는다. 둘 다 `skipped.csv`에 이유가 남는다. 서버 없이도 `local_straight`(점을 직선으로 이음) 지표는 늘 나온다.

**Tech Stack:**
- Python 3.10(이 PC 3.10.8), 가상환경 `research/.venv`
- numpy 2.2.6, pandas 2.3.3, matplotlib 3.10.9, PyYAML 6.0.3, requests 2.34.2, pytest 9.2.0(모두 PyPI, `research/requirements.txt`에 고정)
- 재생: `packages/footstep_core`의 `dart run footstep_core:replay`·`footstep_core:steps`(R2~R5, 바꾸지 않는다)
- 복원: R5 서버 `POST /api/route/reconstruct`(`local` 프로필, `dev-fake-token`)

**설계 문서·근거:**
- `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md`
  - 3-1: `research/analysis/`, `research/sessions.yaml`, `research/data/`·`research/results/`(커밋 금지)
  - 4-2: 세션 파일(`gps.csv`, `marks.csv`, `battery.csv`, `meta.json`)
  - 5-4: 재생 출력(`fixes.csv`, `stays.csv`, `summary.json`), steps CLI 출력
  - 6장: 복원 API 요청·응답, `hmm` 조정값
  - 7장: R6(세션 관리, 지표 표 7-2, 그래프 7-3, 테스트 7-4)
  - 8장: 정확도 실험(재생)·배터리 실험(실기기) 절차
- `docs/research/route-guide.md`(복원 호출, β·σ 격자), `battery-experiment-guide.md`(mAh/h, `restarted by system` 제외, `plugged=1` 제외), `device-check.md`(전하량 3.7mAh 계단, SM-S911N의 `current_ua`는 mA), `steps-guide.md`(`step_summary.json`), `replay-guide.md`
- Newson & Krumm(2009) 5.2절: β·σ는 성능을 최대로 하는 값 찾기가 후속 과제 → 격자 탐색으로 정한다(R5 'R6에 넘기는 것')

## 설계 검증 (임시 작업 폴더, 커밋하지 않음)

이 계획의 코드는 `route` 브랜치(0e937ed)에서 갈라 둔 임시 작업 폴더에서 먼저 그대로 짜서 검증했다.
- `research/`에서 pytest 64개 통과(Task 1~7: 12 → 19 → 31 → 39 → 47 → 55 → 64). 태스크마다 그 태스크까지의 파일만 놓고 테스트가 통과하는 것도 확인했다.
- 실제 세션 `20261109-213324-groundTruth`(15분 47초, 손에 들고 걷기 + 실내 정지 약 6분, 걸음 세기·탈것·10분 넘는 머문 곳 표시 없음)를 pilot으로 등록하고 `experiments.yaml` 그대로 돌렸다. 재생 25개 + steps 3개, 처음 83초, 캐시가 있으면 4초.
- 서버는 `local` 프로필로 띄우고 OSRM 주소를 비웠다(로컬 KR OSRM 데이터 없음). `straight`는 서버가 실제로 복원했고, 도로 맞춤 5개 방법은 모든 구간이 직선 대체라 120건이 `skipped.csv`로 갔다. `--no-reconstruct`(서버 없음)도 같은 `local_straight` 값으로 끝까지 돌았다. `analysis.tune`은 OSRM이 없어 종료 코드 2로 멈췄다(의도).

아래 표가 Task 8의 확인 기준이다(정답 점 842개, 정답 이동거리 566.5m, 복원 `local_straight`, ttff는 표시가 없으면 0). 측위 횟수·GPS 켜짐은 R5 표와 같다. `straight`(서버) 열은 같은 점을 서버가 이은 P95다.

| 재생 | 측위 | GPS 켜짐(초) | 오차 평균(m) | 오차 P95(m) | 이동거리 오차(%) | 머문 곳 | `straight` P95 |
|---|---|---|---|---|---|---|---|
| `hourly` | 1 | 0.6 | 52.6 | 165.9 | -100.0 | 0 | 165.9 |
| `continuous_10m` | 53 | 947.1 | 1.9 | 5.0 | -0.0 | 0 | 5.0 |
| `fixed_30s` | 32 | 13.7 | 1.5 | 7.8 | -2.2 | 0 | 7.8 |
| `fixed_1m` | 16 | 6.6 | 3.8 | 16.9 | -15.5 | 0 | 16.9 |
| `fixed_5m` | 4 | 1.6 | 26.8 | 115.3 | -62.9 | 0 | 115.3 |
| `speed_adaptive` | 17 | 9.4 | 2.1 | 9.4 | -12.7 | 0 | 9.4 |
| `time_speed e_m=25` | 66 | 38.8 | 0.5 | 2.4 | 8.1 | 0 | 2.4 |
| `time_speed e_m=50` | 29 | 17.4 | 1.6 | 9.4 | -3.1 | 0 | 9.4 |
| `time_speed e_m=100` | 14 | 7.9 | 2.3 | 9.9 | -12.8 | 0 | 9.9 |
| `still_suppress[os]` | 11 | 4.3 | 4.4 | 18.6 | -19.2 | 0 | 18.6 |
| `activity_gated` | 53 | 499.9 | 1.9 | 5.0 | -0.2 | 0 | 5.0 |
| `step_budget[os] e_m=25` | 36 | 20.8 | 0.9 | 3.2 | 0.0 | 0 | 3.2 |
| `step_budget[os] e_m=50` | 18 | 7.7 | 1.7 | 7.4 | -6.9 | 0 | 7.4 |
| `step_budget[os] e_m=100` | 11 | 5.8 | 2.5 | 12.7 | -14.5 | 0 | 12.7 |
| `step_budget[adaptive] e_m=25` | 35 | 23.6 | 1.6 | 3.8 | 0.8 | 0 | 3.8 |
| `step_budget[adaptive] e_m=50` | 16 | 9.5 | 2.0 | 7.8 | -7.7 | 0 | 7.8 |
| `step_budget[adaptive] e_m=100` | 9 | 5.3 | 2.3 | 9.0 | -10.3 | 0 | 9.0 |
| `step_budget[adaptive] e_m=50 use_steps=false` | 20 | 10.4 | 1.8 | 7.8 | -5.1 | 0 | 7.8 |
| `step_budget[adaptive] e_m=50 suppress_still=false` | 29 | 24.8 | 1.6 | 7.8 | -3.5 | 0 | 7.8 |
| `step_budget[adaptive] e_m=50 vehicle_probe=false` | 16 | 9.5 | 2.0 | 7.8 | -7.7 | 0 | 7.8 |
| `step_budget[adaptive] e_m=50 stay.use_still=false` | 16 | 9.5 | 2.0 | 7.8 | -7.7 | 0 | 7.8 |
| `step_budget[adaptive] e_m=50 ttff=5` | 14 | 80.1 | 2.6 | 11.3 | -10.9 | 0 | 11.3 |
| `step_budget[adaptive] e_m=50 ttff=10` | 13 | 153.7 | 2.1 | 10.1 | -7.9 | 0 | 10.1 |
| `fixed_1m ttff=5` | 16 | 89.8 | 4.1 | 19.2 | -16.5 | 0 | 19.2 |
| `fixed_1m ttff=10` | 15 | 171.0 | 4.3 | 20.3 | -18.6 | 0 | 20.3 |

- 모든 재생의 머문 곳 정답은 0개(10분 넘는 arrive~depart 없음)라 F1은 비어 있다.
- 걸음 감지(`step_metrics.csv`): 총 걸음 os 875 · brajdic 922 · adaptive 871. 보행 판정 정밀도 1.0 / 재현율 0.484 · 0.523 · 0.496. 이 세션은 처음 3초짜리 arrive~depart 말고는 머문 곳 표시가 없어 실내 6분도 정답 '보행'이 된다 — 재현율이 약 0.5인 이유이고, 표시를 넣은 세션이 와야 의미 있는 값이다. 걸음 세기·탈것 표시가 없어 걸음 수 오차·가짜 걸음·첫 걸음 지연은 비어 있다.
- 배터리: 같은 폰의 재측정 세션 `20261109-232936-groundTruth`(정답 기록 모드, 실내 20분, 배터리 90%)를 임시로 `battery`로 등록해 봤다. 처음~끝 행 184.1 mAh/h(device-check.md의 184와 같다), 계단 맞춤 175.3 mAh/h(19분 1초 동안 55.6mAh), 전류 평균 190.9mA. 계단 맞춤 값을 주 지표로 쓰고 처음~끝 값과 전류는 교차 확인으로 본다. 이 세션은 정책 실행 세션이 아니라 저장소 `sessions.yaml`에는 넣지 않는다.

**검증 중에 정한 것**
- 1번 그림(배터리–오차 곡선)에 재생 25개를 모두 찍었더니 이름표가 겹쳐 읽을 수 없었다. 본 실험(ttff 0, 파라미터가 없거나 `e_m` 하나)만 정책 계열마다 선으로 잇고(`fixed_*`는 한 계열, `hourly`·`continuous_10m`은 '현재 앱' 점 둘), y는 로그 눈금으로 바꿨다. 절제·ttff는 표로 본다.
- 처음에는 곡선의 복원 방법을 '선호 순서의 첫 방법'으로 골랐는데, OSRM이 없어 `hmm_steps`가 `hourly` 한 줄뿐이라 점 하나짜리 그림이 나왔다. 지표가 나온 재생이 가장 많은 방법을 고르고, 같으면 선호 순서(제안 → 앱 기본 → 직선)로 바꿨다.
- 5번 그림(복원 방법별)을 재생 × 방법 막대로 그렸더니 4천 픽셀이 넘었다. 본 실험 재생 중 모든 방법이 돈 재생만 골라 방법마다 P95 중앙값 막대 하나로 줄였다.
- 정답 이동거리를 1초 점을 모두 이어 재면 실내에서 서 있는 동안 흔들림이 쌓인다. 마지막으로 센 점에서 10m 이상 벗어난 점만 잇는다(`min_hop_m`). 이 세션에서 566.5m다.
- Windows 콘솔(Git Bash)에서 한글 출력이 깨져 `run`·`tune`이 출력 인코딩을 UTF-8로 맞춘다. matplotlib는 이 PC에 있는 한글 글꼴(맑은 고딕)만 고른다.

## Global Constraints

- 작업 브랜치는 `analysis`다. `route`(R5, PR #38)에서 갈라진다: `git switch -c analysis route`. 다른 브랜치를 만들지 않는다.
- 커밋에 `Co-Authored-By`, `Claude-Session` 같은 AI 트레일러를 넣지 않는다. push 전에 `git log --format=%B route..HEAD | grep -iE "co-authored|claude"`가 빈 결과인지 확인한다.
- 수집한 세션(`research/data/`)·결과(`research/results/`)·가상환경(`research/.venv/`)은 커밋하지 않는다. 비밀정보(`server/.env`, `firebase-service-account.json`)도 커밋하지 않는다. 각 커밋 전에 `git status --short`에 이것들이 없는지 본다.
- 앱(`app/`)·패키지(`packages/footstep_core`)·서버(`server/`) 코드는 바꾸지 않는다. 이 계획은 `research/`와 문서, `.gitignore`만 건드린다.
- Python 의존성은 `research/requirements.txt`의 6개(numpy, pandas, matplotlib, PyYAML, requests, pytest)뿐이고 버전을 고정한다. 새 의존성을 더하지 않는다.
- 시각은 모두 `t_ms`(UTC epoch 밀리초) 정수다. 분석 코드는 현재 시각·난수를 쓰지 않는다.
- 지표 값(설계 7-2와 이 계획에서 정한 값)
  - 정답 경로 = `gps.csv` 중 `accuracy_m` ≤ 20. 탈것 = `board`~`alight`(내리지 않은 탑승은 버림), 도보 = 그 밖
  - 경로 오차 = 정답 점마다 복원 경로(모든 구간)까지 가장 가까운 거리, 평균·P95(`numpy.percentile` 선형)
  - 정답 이동거리는 마지막으로 센 점에서 `min_hop_m`(10m) 이상 벗어난 점만 잇는다
  - 정답 머문 곳 = `arrive`~`depart` 중 600초 이상(출발이 없으면 세션 끝까지), 중심 = 그 안 정답 점 평균(없으면 None → 시간만 비교)
  - 머문 곳 일치 = 겹친 시간 ≥ 0.5 × max(두 머문 곳 길이) 그리고 중심 ≤ 100m, 일대일(겹침이 긴 쌍부터)
  - 보행 판정 = 1초 격자, 정답 보행 = 머문 곳(길이 무관)·탈것 밖
  - 배터리 = 가장 긴 `plugged=0` 묶음, 전하량 계단이 처음·마지막으로 바뀐 행 사이(두 번 미만이면 처음~끝), `restarted by system` 회차 제외, 방식마다 평균 ± 표본 표준편차
- 복원 호출: 점 최대 2000개(넘으면 마지막 점을 겹쳐 나눈다), 머문 곳 최대 500개, 헤더 `Authorization: Bearer dev-fake-token`, 기본 주소 `http://localhost:9090`
- β·σ 격자: β ∈ {2, 5, 10, 20, 50}m, σ 하한 ∈ {3, 5, 10}m, pilot 세션만, 세션 평균 P95 최소(같으면 작은 β·σ)
- 테스트·실행은 Git Bash에서 `research/`로 가서 한다.
  - 테스트: `.venv/Scripts/python -m pytest`(태스크 중간에는 파일 하나만: `.venv/Scripts/python -m pytest tests/test_geo.py`)
  - 실행: `.venv/Scripts/python -m analysis.run --config experiments.yaml`
- 코드 주석·문서는 한국어로 '왜'를 적는다(Spring 학습용 주석 규칙은 서버 코드에만 해당하므로 여기에는 적용하지 않는다).

## 파일 구조

```
research/
  requirements.txt            고정 의존성 6개 (Task 1)
  pytest.ini                  testpaths = tests (Task 1)
  sessions.yaml               세션 id·용도(pilot/eval/battery)·코스·휴대 위치 (Task 6)
  experiments.yaml            재생 설정 격자·복원 방법·지표 값·배터리·tune (Task 6)
  analysis/
    __init__.py               (Task 1)
    geo.py                    LocalProjection, offset, distance_m, polyline_length, point_to_segments_distance (Task 1)
    session.py                Session, Interval, read_csv, read_meta, load_session, truth_points, paired_intervals,
                              stay_intervals, vehicle_intervals, count_intervals, in_intervals, carry_at (Task 1)
    path_metrics.py           local_straight, segments_to_xy, segments_length, truth_length, path_metrics (Task 2)
    stay_metrics.py           truth_stays, read_stays, is_match, stay_scores (Task 3)
    step_metrics.py           read_steps_output, count_errors, vehicle_false_steps, state_at, walking_scores,
                              first_step_latency, step_metrics, count_rows_by_carry (Task 3)
    battery.py                exclusion_reason, longest_unplugged, charge_rate, current_rate, parse_duration_ms,
                              gps_seconds_from_batterystats, method_label, battery_run, battery_summary (Task 4)
    replay.py                 RunSpec, replay_args, steps_args, CliError, DartCli (Task 5)
    reconstruct.py            read_fixes, to_points, to_stays, build_requests, ServerUnavailable, ReconstructError,
                              ReconstructClient (Task 5)
    config.py                 load_sessions, expand_runs, Experiment, load_experiment (Task 6)
    run.py                    run_experiment, write_tables, main — python -m analysis.run (Task 6)
    tune.py                   grid_search, main — python -m analysis.tune (Task 7)
    plots.py                  pick_method, family, main_runs, plot_* 5종, make_all (Task 7)
  tests/
    conftest.py               가짜 세션 폴더 도우미(make_session, gps_row, write_csv) (Task 1)
    test_geo.py, test_session.py (Task 1), test_path_metrics.py (Task 2),
    test_stay_metrics.py, test_step_metrics.py (Task 3), test_battery.py (Task 4),
    test_replay.py, test_reconstruct.py (Task 5), test_config.py, test_run.py (Task 6),
    test_tune.py, test_plots.py (Task 7)
.gitignore                    research/.venv/, research/.pytest_cache/, research/**/__pycache__/ (Task 1)
docs/research/analysis-guide.md          분석 실행 안내 (Task 8)
docs/research/recording-guide.md         sessions.yaml 안내 한 줄 (Task 8)
docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md   7장 (Task 8)
```

---

### Task 1: 분석 뼈대 — 가상환경, 좌표 계산, 세션 읽기

**Files:**
- Create: `research/requirements.txt`, `research/pytest.ini`, `research/analysis/__init__.py`, `research/analysis/geo.py`, `research/analysis/session.py`
- Modify: `.gitignore`(끝에 3줄)
- Test: `research/tests/conftest.py`, `research/tests/test_geo.py`, `research/tests/test_session.py`

**Interfaces:**
- Consumes: 세션 폴더 형식(설계 4-2). `meta.json`의 `startedAt`·`endedAt`(ISO, Z), `carryInitial`, `errors[].message`, `policy`
- Produces:
  - `LocalProjection(lat0, lng0)`: `to_xy(lat, lng) -> ndarray (…, 2)`(동쪽 x, 북쪽 y, m), `to_latlng(x, y) -> (lat, lng)`
  - `offset(lat, lng, east_m, north_m) -> (lat, lng)`, `distance_m(lat1, lng1, lat2, lng2) -> float`
  - `polyline_length(xy) -> float`, `point_to_segments_distance(points, starts, ends, chunk=512) -> ndarray`
  - `Interval(start_ms, end_ms, value="")`(frozen, `duration_s`), `Session(session_id, path, meta, gps, marks, start_ms, end_ms)`
  - `read_csv(path, columns, numeric) -> DataFrame`, `read_meta(dir) -> dict`, `load_session(dir) -> Session`
  - `truth_points(gps, max_accuracy_m=20)`, `paired_intervals(marks, open_kind, close_kind, end_ms=None)`, `stay_intervals(session)`, `vehicle_intervals(session)`, `count_intervals(session)`, `in_intervals(t_ms, intervals) -> bool ndarray`, `carry_at(session, t_ms) -> str`
  - 상수 `GPS_COLUMNS`, `MARK_COLUMNS`, `BATTERY_COLUMNS`
  - 테스트 도우미(`tests/conftest.py`): `LAT0, LNG0, T0`, `write_csv(path, header, rows)`, `gps_row(t_ms, east_m, north_m, acc=5.0)`, `make_session(root, name="s1", gps, marks, battery, meta) -> Path`, 픽스처 `walk_session`

- [ ] **Step 1: 브랜치와 가상환경**

```bash
git switch -c analysis route
mkdir -p research/analysis research/tests
```

`research/requirements.txt`:

```text
# R6 분석 의존성. research/.venv에 설치한다(docs/research/analysis-guide.md).
numpy==2.2.6
pandas==2.3.3
matplotlib==3.10.9
PyYAML==6.0.3
requests==2.34.2
pytest==9.2.0
```

`research/pytest.ini`:

```ini
[pytest]
testpaths = tests
addopts = -q
```

`.gitignore` 끝에 더한다:

```gitignore
# R6 분석 Python 가상환경·캐시
research/.venv/
research/.pytest_cache/
research/**/__pycache__/
```

```bash
cd research
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements.txt
```

Expected: 설치 성공. `git status --short`에 `.venv`가 보이지 않는다.

- [ ] **Step 2: 실패하는 테스트 작성**

`research/tests/conftest.py`:

```python
"""테스트용 가짜 세션 폴더를 만드는 도우미. 손으로 답을 셀 수 있는 작은 합성 데이터만 쓴다(설계 7-4)."""
import csv
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from analysis.geo import offset  # noqa: E402

LAT0, LNG0 = 37.5665, 126.9780
T0 = 1_794_227_600_000


def write_csv(path: Path, header: list[str], rows: list[list]):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


def gps_row(t_ms, east_m, north_m, acc=5.0):
    lat, lng = offset(LAT0, LNG0, east_m, north_m)
    return [t_ms, t_ms, lat, lng, acc, 0.0, 0.0, 0.0]


def make_session(root: Path, name="s1", gps=None, marks=None, battery=None, meta=None) -> Path:
    d = root / name
    d.mkdir(parents=True, exist_ok=True)
    write_csv(d / "gps.csv", ["t_ms", "fix_t_ms", "lat", "lng", "accuracy_m", "speed_mps", "bearing_deg",
                              "altitude_m"], gps or [])
    write_csv(d / "marks.csv", ["t_ms", "kind", "value"], marks or [])
    if battery is not None:
        write_csv(d / "battery.csv", ["t_ms", "charge_uah", "current_ua", "level_pct", "temp_c", "plugged"],
                  battery)
    m = {"sessionId": name, "mode": "groundTruth", "deviceModel": "test", "carryInitial": "hand",
         "errors": []}
    m.update(meta or {})
    (d / "meta.json").write_text(json.dumps(m), encoding="utf-8")
    return d


@pytest.fixture
def walk_session(tmp_path):
    """동쪽으로 1m/s, 100초 걷는 세션(정답 점 101개, 하나는 정확도 30m라 정답에서 빠진다)."""
    rows = [gps_row(T0 + k * 1000, k, 0.0) for k in range(101)]
    rows[50][4] = 30.0
    return make_session(tmp_path, gps=rows)
```

`research/tests/test_geo.py`:

```python
import numpy as np
import pytest

from analysis.geo import LocalProjection, distance_m, offset, point_to_segments_distance, polyline_length
from conftest import LAT0, LNG0


def test_offset_and_distance_round_trip():
    lat, lng = offset(LAT0, LNG0, 30.0, 40.0)
    assert distance_m(LAT0, LNG0, lat, lng) == pytest.approx(50.0, abs=0.01)


def test_projection_round_trip():
    proj = LocalProjection(LAT0, LNG0)
    xy = proj.to_xy([LAT0, LAT0 + 0.001], [LNG0, LNG0 + 0.001])
    lat, lng = proj.to_latlng(xy[:, 0], xy[:, 1])
    assert lat[1] == pytest.approx(LAT0 + 0.001)
    assert lng[1] == pytest.approx(LNG0 + 0.001)
    # 위도 0.001도 ≈ 111.19m
    assert xy[1, 1] == pytest.approx(111.19, abs=0.01)


def test_polyline_length():
    assert polyline_length(np.array([[0, 0], [3, 4], [3, 10]])) == pytest.approx(11.0)
    assert polyline_length(np.array([[1, 1]])) == 0.0


def test_point_to_segments_distance_cases():
    starts = np.array([[0, 0], [20, 20]])
    ends = np.array([[10, 0], [20, 20]])        # 둘째 선분은 점 하나
    pts = np.array([[5, 3], [-4, 0], [13, 4], [20, 25]])
    d = point_to_segments_distance(pts, starts, ends, chunk=2)
    # (5,3)→선분 안 3m, (-4,0)→끝점(0,0) 4m, (13,4)→끝점(10,0) 5m, (20,25)→점 (20,20) 5m
    assert d == pytest.approx([3.0, 4.0, 5.0, 5.0])


def test_point_to_segments_requires_segments():
    with pytest.raises(ValueError):
        point_to_segments_distance(np.array([[0, 0]]), np.empty((0, 2)), np.empty((0, 2)))
```

`research/tests/test_session.py`:

```python
import numpy as np
import pytest

from analysis.session import (Interval, carry_at, count_intervals, in_intervals, load_session, paired_intervals,
                              stay_intervals, truth_points, vehicle_intervals)
from conftest import T0, gps_row, make_session


def test_load_session_reads_files_and_drops_broken_rows(tmp_path):
    d = make_session(tmp_path, gps=[gps_row(T0 + 1000, 1, 0), gps_row(T0, 0, 0)],
                     meta={"startedAt": "2026-11-09T12:33:20Z", "endedAt": None})
    with (d / "gps.csv").open("a", encoding="utf-8") as f:
        f.write("123,broken\n")
    s = load_session(d)
    assert s.session_id == "s1"
    assert list(s.gps["t_ms"]) == [T0, T0 + 1000]      # 시각순, 깨진 행 버림
    assert s.start_ms == 1794227600000                 # startedAt
    assert s.end_ms == T0 + 1000                       # endedAt이 없으면 마지막 기록 시각


def test_load_session_missing_folder(tmp_path):
    with pytest.raises(FileNotFoundError):
        load_session(tmp_path / "none")


def test_truth_points_keeps_accuracy_20_or_less(walk_session):
    s = load_session(walk_session)
    assert len(s.gps) == 101
    assert len(truth_points(s.gps)) == 100
    assert len(truth_points(s.gps, max_accuracy_m=40)) == 101


def test_paired_intervals_rules(tmp_path):
    marks = [[T0, "arrive", "카페"], [T0 + 1000, "arrive", "식당"], [T0 + 5000, "depart", ""],
             [T0 + 6000, "depart", ""], [T0 + 9000, "arrive", ""]]
    s = load_session(make_session(tmp_path, gps=[gps_row(T0 + 20000, 0, 0)], marks=marks))
    # 다시 연 것(식당)이 쓰이고, 짝 없는 depart는 무시, 끝의 arrive는 세션 끝까지
    assert stay_intervals(s) == [Interval(T0 + 1000, T0 + 5000, "식당"), Interval(T0 + 9000, T0 + 20000, "")]
    assert paired_intervals(s.marks, "arrive", "depart") == [Interval(T0 + 1000, T0 + 5000, "식당")]


def test_vehicle_and_count_intervals(tmp_path):
    marks = [[T0, "board", "bus"], [T0 + 60_000, "alight", ""], [T0 + 70_000, "count_start", ""],
             [T0 + 170_000, "count_end", " 120 "], [T0 + 200_000, "board", "subway"]]
    s = load_session(make_session(tmp_path, gps=[gps_row(T0 + 300_000, 0, 0)], marks=marks))
    assert vehicle_intervals(s) == [Interval(T0, T0 + 60_000, "bus")]     # 내리지 않은 지하철은 뺀다
    assert count_intervals(s) == [Interval(T0 + 70_000, T0 + 170_000, "120")]
    assert Interval(T0, T0 + 60_000).duration_s == 60


def test_in_intervals_inclusive():
    mask = in_intervals([0, 5, 10, 11], [Interval(5, 10)])
    assert mask.tolist() == [False, True, True, False]
    assert in_intervals(np.array([1, 2]), []).tolist() == [False, False]


def test_carry_at(tmp_path):
    marks = [[T0 + 10, "carry", "pocket"], [T0 + 20, "carry", "bag"]]
    s = load_session(make_session(tmp_path, gps=[gps_row(T0, 0, 0)], marks=marks))
    assert carry_at(s, T0) == "hand"
    assert carry_at(s, T0 + 15) == "pocket"
    assert carry_at(s, T0 + 20) == "bag"
```

- [ ] **Step 3: 실패 확인**

Run: `.venv/Scripts/python -m pytest`
Expected: FAIL — `ModuleNotFoundError: No module named 'analysis'`

- [ ] **Step 4: 구현**

`research/analysis/__init__.py`:

```python
"""발걸음 연구 R6 분석(설계 7장). 세션·재생 출력·복원 경로를 읽어 지표와 그래프를 만든다."""
```

`research/analysis/geo.py`:

```python
"""좌표 계산. 한 세션(도시 하나) 안에서는 기준 위도에서 편 평면 좌표(m)로 충분하다."""
from __future__ import annotations

import math

import numpy as np

EARTH_RADIUS_M = 6_371_000.0


class LocalProjection:
    """기준점 둘레를 평면(동쪽 x, 북쪽 y, m)으로 편다. 수 km 안에서 오차는 0.1% 미만이다."""

    def __init__(self, lat0: float, lng0: float):
        self.lat0 = lat0
        self.lng0 = lng0
        self._kx = math.radians(1) * EARTH_RADIUS_M * math.cos(math.radians(lat0))
        self._ky = math.radians(1) * EARTH_RADIUS_M

    def to_xy(self, lat, lng) -> np.ndarray:
        lat = np.asarray(lat, dtype=float)
        lng = np.asarray(lng, dtype=float)
        return np.stack([(lng - self.lng0) * self._kx, (lat - self.lat0) * self._ky], axis=-1)

    def to_latlng(self, x, y) -> tuple[np.ndarray, np.ndarray]:
        x = np.asarray(x, dtype=float)
        y = np.asarray(y, dtype=float)
        return self.lat0 + y / self._ky, self.lng0 + x / self._kx


def offset(lat: float, lng: float, east_m: float, north_m: float) -> tuple[float, float]:
    """(lat, lng)에서 동쪽·북쪽으로 몇 m 옮긴 좌표. 테스트용 합성 경로를 만들 때 쓴다."""
    proj = LocalProjection(lat, lng)
    la, ln = proj.to_latlng(east_m, north_m)
    return float(la), float(ln)


def distance_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """두 점 사이 거리(m). 기준점을 첫 점으로 한 평면 근사다."""
    xy = LocalProjection(lat1, lng1).to_xy([lat1, lat2], [lng1, lng2])
    return float(np.hypot(*(xy[1] - xy[0])))


def polyline_length(xy: np.ndarray) -> float:
    """평면 좌표 꺾은선의 길이(m)."""
    xy = np.asarray(xy, dtype=float)
    if len(xy) < 2:
        return 0.0
    return float(np.hypot(*np.diff(xy, axis=0).T).sum())


def point_to_segments_distance(points: np.ndarray, starts: np.ndarray, ends: np.ndarray,
                               chunk: int = 512) -> np.ndarray:
    """점마다 선분 묶음 중 가장 가까운 선분까지의 거리(m). 점 하나짜리 선분(start == end)은 점까지 거리다.

    정답 점(시간당 3600개)과 선분(연속 측위면 수천 개)을 한꺼번에 곱하면 메모리가 커서 점을 [chunk]개씩 나눈다.
    """
    points = np.asarray(points, dtype=float).reshape(-1, 2)
    starts = np.asarray(starts, dtype=float).reshape(-1, 2)
    ends = np.asarray(ends, dtype=float).reshape(-1, 2)
    if len(starts) == 0:
        raise ValueError("선분이 없습니다")
    d = ends - starts                       # (S, 2)
    len2 = (d ** 2).sum(axis=1)             # (S,)
    safe = np.where(len2 > 0, len2, 1.0)
    out = np.empty(len(points))
    for k in range(0, len(points), chunk):
        p = points[k:k + chunk, None, :]    # (P, 1, 2)
        t = ((p - starts) * d).sum(axis=2) / safe
        t = np.where(len2 > 0, np.clip(t, 0.0, 1.0), 0.0)
        nearest = starts + t[..., None] * d  # (P, S, 2)
        out[k:k + chunk] = np.sqrt(((p - nearest) ** 2).sum(axis=2)).min(axis=1)
    return out
```

`research/analysis/session.py`:

```python
"""R1 세션 폴더 읽기(설계 4-2)와 관찰 표시(marks.csv)로 만드는 정답 구간."""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

GPS_COLUMNS = ["t_ms", "fix_t_ms", "lat", "lng", "accuracy_m", "speed_mps", "bearing_deg", "altitude_m"]
MARK_COLUMNS = ["t_ms", "kind", "value"]
BATTERY_COLUMNS = ["t_ms", "charge_uah", "current_ua", "level_pct", "temp_c", "plugged"]


@dataclass(frozen=True)
class Interval:
    """[start_ms, end_ms] 구간. value는 여는 표시의 값(장소 이름, 탈것 종류 등)."""
    start_ms: int
    end_ms: int
    value: str = ""

    @property
    def duration_s(self) -> float:
        return (self.end_ms - self.start_ms) / 1000


@dataclass
class Session:
    session_id: str
    path: Path
    meta: dict
    gps: pd.DataFrame
    marks: pd.DataFrame
    start_ms: int
    end_ms: int
    extra: dict = field(default_factory=dict)


def read_csv(path: Path, columns: list[str], numeric: list[str]) -> pd.DataFrame:
    """헤더 있는 CSV를 읽는다. 파일이 없으면 빈 표, 깨진 행(서비스 강제 종료 등)은 버린다."""
    if not path.exists():
        return pd.DataFrame(columns=columns)
    df = pd.read_csv(path, dtype=str, keep_default_na=False, on_bad_lines="skip")
    for c in columns:
        if c not in df.columns:
            df[c] = ""
    df = df[columns].copy()
    for c in numeric:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    df = df.dropna(subset=numeric).reset_index(drop=True)
    if "t_ms" in numeric:
        df["t_ms"] = df["t_ms"].astype("int64")
        df = df.sort_values("t_ms", kind="stable").reset_index(drop=True)
    return df


def _iso_ms(value: str | None) -> int | None:
    if not value:
        return None
    return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000)


def read_meta(path: Path) -> dict:
    meta_path = path / "meta.json"
    return json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.exists() else {}


def load_session(path: Path) -> Session:
    path = Path(path)
    if not path.is_dir():
        raise FileNotFoundError(f"세션 폴더가 없습니다: {path}")
    meta = read_meta(path)
    gps = read_csv(path / "gps.csv", GPS_COLUMNS, ["t_ms", "lat", "lng", "accuracy_m"])
    marks = read_csv(path / "marks.csv", MARK_COLUMNS, ["t_ms"])
    times = list(gps["t_ms"]) + list(marks["t_ms"])
    start = _iso_ms(meta.get("startedAt")) or (min(times) if times else 0)
    end = _iso_ms(meta.get("endedAt")) or (max(times) if times else start)
    return Session(meta.get("sessionId", path.name), path, meta, gps, marks, int(start), int(end))


def truth_points(gps: pd.DataFrame, max_accuracy_m: float = 20.0) -> pd.DataFrame:
    """1초 정답 경로 — 정확도가 max_accuracy_m 이하인 GPS 행만 쓴다(설계 7-2, 10장 위험 7)."""
    return gps[gps["accuracy_m"] <= max_accuracy_m].reset_index(drop=True)


def paired_intervals(marks: pd.DataFrame, open_kind: str, close_kind: str,
                     end_ms: int | None = None) -> list[Interval]:
    """여는 표시 다음의 닫는 표시를 짝짓는다. 닫기 전에 또 열면 나중 것을 쓴다(steps CLI와 같은 규칙).

    end_ms를 주면 끝까지 닫지 않은 구간을 end_ms에서 닫는다(기록 끝까지 머문 곳). 안 주면 버린다(끝을 모른다).
    """
    out: list[Interval] = []
    opened: tuple[int, str] | None = None
    for t, kind, value in zip(marks["t_ms"], marks["kind"], marks["value"]):
        if kind == open_kind:
            opened = (int(t), str(value))
        elif kind == close_kind and opened is not None:
            out.append(Interval(opened[0], int(t), opened[1]))
            opened = None
    if opened is not None and end_ms is not None and end_ms > opened[0]:
        out.append(Interval(opened[0], int(end_ms), opened[1]))
    return out


def stay_intervals(session: Session) -> list[Interval]:
    """arrive~depart. 끝까지 출발하지 않았으면 세션 끝까지 머문 것으로 본다."""
    return paired_intervals(session.marks, "arrive", "depart", end_ms=session.end_ms)


def vehicle_intervals(session: Session) -> list[Interval]:
    """board~alight. 내리기 전에 끝난 탑승은 끝을 몰라 뺀다(steps CLI와 같다)."""
    return paired_intervals(session.marks, "board", "alight")


def count_intervals(session: Session) -> list[Interval]:
    """count_start~count_end. value는 count_end에 적은 직접 센 걸음 수(문자열)."""
    out: list[Interval] = []
    start: int | None = None
    for t, kind, value in zip(session.marks["t_ms"], session.marks["kind"], session.marks["value"]):
        if kind == "count_start":
            start = int(t)
        elif kind == "count_end" and start is not None:
            out.append(Interval(start, int(t), str(value).strip()))
            start = None
    return out


def in_intervals(t_ms, intervals: list[Interval]) -> np.ndarray:
    """시각마다 구간(양 끝 포함) 안이면 True."""
    t = np.asarray(t_ms, dtype="int64")
    mask = np.zeros(len(t), dtype=bool)
    for iv in intervals:
        mask |= (t >= iv.start_ms) & (t <= iv.end_ms)
    return mask


def carry_at(session: Session, t_ms: int) -> str:
    """t_ms 시점의 휴대 위치. t_ms 이전 마지막 carry 표시, 없으면 meta의 carryInitial."""
    carry = session.meta.get("carryInitial") or "unknown"
    for t, kind, value in zip(session.marks["t_ms"], session.marks["kind"], session.marks["value"]):
        if t > t_ms:
            break
        if kind == "carry" and value:
            carry = str(value)
    return carry
```

- [ ] **Step 5: 통과 확인**

Run: `.venv/Scripts/python -m pytest`
Expected: PASS — `12 passed`

- [ ] **Step 6: 커밋**

```bash
cd ..
git status --short          # research/.venv, research/data가 없어야 한다
git add .gitignore research/requirements.txt research/pytest.ini research/analysis research/tests
git commit -m "feat(research): R6 분석 뼈대 — 가상환경 의존성, 좌표 계산, 세션·관찰 표시 읽기"
```

---

### Task 2: 경로 지표 — 정답 점에서 복원 경로까지 거리, 이동거리 오차

**Files:**
- Create: `research/analysis/path_metrics.py`
- Test: `research/tests/test_path_metrics.py`

**Interfaces:**
- Consumes: Task 1의 `LocalProjection`, `point_to_segments_distance`, `polyline_length`, `Interval`, `in_intervals`, `offset`(테스트)
- Produces:
  - 복원 경로 형식 = 서버 응답 `segments`와 같다: `[{"kind": str, "coords": [{"lat", "lng"}…], "fallback": bool}]`
  - `local_straight(fixes: DataFrame) -> list[dict]` — 점을 시각순 직선 한 구간으로(서버 없이 도는 기준선)
  - `segments_to_xy(segments, proj) -> (starts, ends)`, `segments_length(segments, proj) -> float`
  - `truth_length(truth_xy, min_hop_m=10.0) -> float`
  - `path_metrics(truth, segments, vehicles, min_hop_m=10.0) -> dict` 키: `n_truth, n_segments, fallback_share, mean_m, p95_m, walk_n, walk_mean_m, walk_p95_m, vehicle_n, vehicle_mean_m, vehicle_p95_m, path_length_m, truth_length_m, dist_err_pct`(값이 없으면 None)

- [ ] **Step 1: 실패하는 테스트 작성**

`research/tests/test_path_metrics.py`:

```python
import numpy as np
import pandas as pd
import pytest

from analysis.geo import offset
from analysis.path_metrics import local_straight, path_metrics, truth_length
from analysis.session import Interval
from conftest import LAT0, LNG0, T0


def _truth(points):
    """[(t_ms, east, north)] → 정답 표(정확도 5m)."""
    rows = []
    for t, e, n in points:
        lat, lng = offset(LAT0, LNG0, e, n)
        rows.append({"t_ms": t, "lat": lat, "lng": lng, "accuracy_m": 5.0})
    return pd.DataFrame(rows)


def _seg(points, kind="walk", fallback=False):
    coords = []
    for e, n in points:
        lat, lng = offset(LAT0, LNG0, e, n)
        coords.append({"lat": lat, "lng": lng})
    return {"kind": kind, "coords": coords, "fallback": fallback}


def test_parallel_path_10m_away_gives_10m_error():
    # 동쪽으로 100m 직선 정답(1m 간격) ↔ 북쪽 10m 평행선 → 평균·P95 모두 10m, 길이 오차 0%
    truth = _truth([(T0 + k * 1000, k, 0) for k in range(101)])
    row = path_metrics(truth, [_seg([(0, 10), (100, 10)])], vehicles=[], min_hop_m=0)
    assert row["n_truth"] == 101
    assert row["mean_m"] == pytest.approx(10.0, abs=0.01)
    assert row["p95_m"] == pytest.approx(10.0, abs=0.01)
    assert row["truth_length_m"] == pytest.approx(100.0, abs=0.01)
    assert row["path_length_m"] == pytest.approx(100.0, abs=0.01)
    assert row["dist_err_pct"] == pytest.approx(0.0, abs=0.01)
    assert row["vehicle_n"] == 0 and row["vehicle_mean_m"] is None
    assert row["fallback_share"] == 0.0


def test_walk_and_vehicle_split():
    # 0~9초 도보(경로 위, 오차 0), 10~19초 탈것(경로에서 20m) — 탑승 board~alight = 10~19초
    pts = [(T0 + k * 1000, k * 10, 0 if k < 10 else 20) for k in range(20)]
    truth = _truth(pts)
    row = path_metrics(truth, [_seg([(0, 0), (190, 0)])],
                       vehicles=[Interval(T0 + 10_000, T0 + 19_000, "bus")], min_hop_m=0)
    assert row["walk_n"] == 10 and row["vehicle_n"] == 10
    assert row["walk_mean_m"] == pytest.approx(0.0, abs=0.01)
    assert row["vehicle_mean_m"] == pytest.approx(20.0, abs=0.01)
    assert row["mean_m"] == pytest.approx(10.0, abs=0.01)


def test_p95_uses_linear_percentile():
    # 거리 0,1,…,19m(정답 20점이 경로에서 북쪽으로 k m) → P95 = 18.05m(numpy 선형 보간)
    truth = _truth([(T0 + k, 0, k) for k in range(20)])
    row = path_metrics(truth, [_seg([(-50, 0), (50, 0)])], vehicles=[], min_hop_m=0)
    assert row["mean_m"] == pytest.approx(9.5, abs=0.01)
    assert row["p95_m"] == pytest.approx(np.percentile(np.arange(20), 95), abs=0.01)


def test_single_point_path_and_fallback_share():
    truth = _truth([(T0, 0, 0), (T0 + 1, 30, 40)])
    row = path_metrics(truth, [_seg([(0, 0)]), _seg([(0, 0)], fallback=True)], vehicles=[], min_hop_m=0)
    assert row["mean_m"] == pytest.approx(25.0, abs=0.01)    # (0 + 50) / 2
    assert row["path_length_m"] == 0.0
    assert row["dist_err_pct"] == pytest.approx(-100.0)
    assert row["fallback_share"] == 0.5


def test_empty_path_or_truth():
    truth = _truth([(T0, 0, 0)])
    assert path_metrics(truth, [], vehicles=[])["mean_m"] is None
    empty = path_metrics(truth.iloc[0:0], [_seg([(0, 0)])], vehicles=[])
    assert empty["n_truth"] == 0 and empty["mean_m"] is None


def test_truth_length_ignores_jitter_below_min_hop():
    # 제자리 흔들림 3m 왕복 10번 후 동쪽으로 50m 이동
    jitter = [[0, 0], [3, 0]] * 10
    xy = np.array(jitter + [[50, 0]], dtype=float)
    assert truth_length(xy, min_hop_m=0) == pytest.approx(3 * 19 + 47)   # 마지막 흔들림 점(3,0)에서 50m까지 47m
    assert truth_length(xy, min_hop_m=10) == pytest.approx(50.0)


def test_local_straight_orders_by_time():
    fixes = pd.DataFrame({"t_ms": [2, 1], "lat": [1.0, 2.0], "lng": [3.0, 4.0]})
    seg = local_straight(fixes)
    assert seg == [{"kind": "walk", "coords": [{"lat": 2.0, "lng": 4.0}, {"lat": 1.0, "lng": 3.0}],
                    "fallback": False}]
    assert local_straight(fixes.iloc[0:0]) == []
```

- [ ] **Step 2: 실패 확인**

Run: `.venv/Scripts/python -m pytest tests/test_path_metrics.py`
Expected: FAIL — `No module named 'analysis.path_metrics'`

- [ ] **Step 3: 구현**

`research/analysis/path_metrics.py`:

```python
"""수집·복원 지표(설계 7-2 첫 줄): 1초 정답 점마다 복원 경로까지 거리, 이동거리 오차.

복원 경로는 서버 응답과 같은 모양의 구간 목록이다: [{"kind", "coords": [{"lat", "lng"}…], "fallback"}].
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from .geo import LocalProjection, point_to_segments_distance, polyline_length
from .session import Interval, in_intervals


def local_straight(fixes: pd.DataFrame) -> list[dict]:
    """서버 없이 쓰는 기준선: 남은 점을 시각순으로 직선으로 잇는다.

    서버 `straight`와 달리 머문 곳 중심 치환·10분 공백(estimated) 처리를 하지 않는다. 서버가 꺼져 있어도
    분석이 끝까지 돌게 하려는 것이라 결과표에는 method = local_straight로 따로 적는다.
    """
    if fixes.empty:
        return []
    f = fixes.sort_values("t_ms", kind="stable")
    coords = [{"lat": float(a), "lng": float(b)} for a, b in zip(f["lat"], f["lng"])]
    return [{"kind": "walk", "coords": coords, "fallback": False}]


def segments_to_xy(segments: list[dict], proj: LocalProjection) -> tuple[np.ndarray, np.ndarray]:
    """구간 목록을 선분 시작·끝 배열로 바꾼다. 좌표 하나짜리 구간은 길이 0 선분(점)이 된다."""
    starts, ends = [], []
    for seg in segments:
        coords = seg.get("coords") or []
        if not coords:
            continue
        xy = proj.to_xy([c["lat"] for c in coords], [c["lng"] for c in coords]).reshape(-1, 2)
        if len(xy) == 1:
            starts.append(xy)
            ends.append(xy)
        else:
            starts.append(xy[:-1])
            ends.append(xy[1:])
    if not starts:
        return np.empty((0, 2)), np.empty((0, 2))
    return np.concatenate(starts), np.concatenate(ends)


def segments_length(segments: list[dict], proj: LocalProjection) -> float:
    total = 0.0
    for seg in segments:
        coords = seg.get("coords") or []
        if len(coords) >= 2:
            total += polyline_length(proj.to_xy([c["lat"] for c in coords], [c["lng"] for c in coords]))
    return total


def truth_length(truth_xy: np.ndarray, min_hop_m: float = 10.0) -> float:
    """정답 이동거리. 마지막으로 센 점에서 min_hop_m 이상 벗어난 점만 이어, 서 있는 동안의 GPS 흔들림
    (실내 약 7초 간격, 몇 m씩)이 거리로 쌓이지 않게 한다. min_hop_m = 0이면 모든 점을 잇는다."""
    truth_xy = np.asarray(truth_xy, dtype=float).reshape(-1, 2)
    if len(truth_xy) < 2:
        return 0.0
    total = 0.0
    last = truth_xy[0]
    for p in truth_xy[1:]:
        hop = float(np.hypot(*(p - last)))
        if hop >= min_hop_m:
            total += hop
            last = p
    return total


def _stats(d: np.ndarray) -> tuple[float | None, float | None]:
    if len(d) == 0:
        return None, None
    return float(d.mean()), float(np.percentile(d, 95))


def path_metrics(truth: pd.DataFrame, segments: list[dict], vehicles: list[Interval],
                 min_hop_m: float = 10.0) -> dict:
    """정답 점(정확도 필터를 거친 gps 행) ↔ 복원 경로.

    - mean_m·p95_m: 정답 점마다 경로(모든 구간)까지 가장 가까운 거리의 평균·95백분위
    - walk_*·vehicle_*: 정답 점의 시각이 board~alight 안이면 탈것, 아니면 도보로 나눈 같은 값
    - dist_err_pct: (복원 경로 길이 − 정답 이동거리) ÷ 정답 이동거리 × 100
    - fallback_share: 서버가 직선으로 대신 채운 구간의 비율(구간 수 기준)
    """
    row: dict = {"n_truth": int(len(truth)), "n_segments": len(segments),
                 "fallback_share": (sum(bool(s.get("fallback")) for s in segments) / len(segments))
                 if segments else None}
    keys = ["mean_m", "p95_m", "walk_n", "walk_mean_m", "walk_p95_m", "vehicle_n", "vehicle_mean_m",
            "vehicle_p95_m", "path_length_m", "truth_length_m", "dist_err_pct"]
    row.update({k: None for k in keys})
    if truth.empty:
        return row
    proj = LocalProjection(float(truth["lat"].iloc[0]), float(truth["lng"].iloc[0]))
    truth_xy = proj.to_xy(truth["lat"].to_numpy(), truth["lng"].to_numpy())
    row["truth_length_m"] = truth_length(truth_xy, min_hop_m)
    starts, ends = segments_to_xy(segments, proj)
    if len(starts) == 0:
        return row
    d = point_to_segments_distance(truth_xy, starts, ends)
    is_vehicle = in_intervals(truth["t_ms"].to_numpy(), vehicles)
    row["mean_m"], row["p95_m"] = _stats(d)
    row["walk_n"] = int((~is_vehicle).sum())
    row["walk_mean_m"], row["walk_p95_m"] = _stats(d[~is_vehicle])
    row["vehicle_n"] = int(is_vehicle.sum())
    row["vehicle_mean_m"], row["vehicle_p95_m"] = _stats(d[is_vehicle])
    row["path_length_m"] = segments_length(segments, proj)
    if row["truth_length_m"] > 0:
        row["dist_err_pct"] = (row["path_length_m"] - row["truth_length_m"]) / row["truth_length_m"] * 100
    return row
```

- [ ] **Step 4: 통과 확인**

Run: `.venv/Scripts/python -m pytest`
Expected: PASS — `19 passed`

- [ ] **Step 5: 커밋**

```bash
git add research/analysis/path_metrics.py research/tests/test_path_metrics.py
git commit -m "feat(research): 정답 점에서 복원 경로까지 거리 평균·P95와 이동거리 오차를 도보·탈것으로 나눠 잰다"
```

---

### Task 3: 머문 곳·걸음 감지 지표

**Files:**
- Create: `research/analysis/stay_metrics.py`, `research/analysis/step_metrics.py`
- Test: `research/tests/test_stay_metrics.py`, `research/tests/test_step_metrics.py`

**Interfaces:**
- Consumes: Task 1의 `Session`, `stay_intervals`, `vehicle_intervals`, `in_intervals`, `carry_at`, `distance_m`. 재생 출력 `stays.csv`(`arrive_ms,leave_ms,lat,lng,n_points`), steps CLI 출력(`steps.csv` `t_ms,total_steps`, `step_states.csv` `t_ms,state,cadence_hz`, `step_summary.json`의 `detector_id, total_steps, start_ms, end_ms, count_intervals[{start_ms,end_ms,manual_steps,detected_steps,error_pct}], vehicle_intervals[{board_ms,alight_ms,kind,detected_steps}]`)
- Produces:
  - 머문 곳 사전 형식 `{"arrive_ms", "leave_ms", "lat", "lng"}`
  - `truth_stays(session, truth, min_stay_s=600) -> list[dict]`, `read_stays(replay_dir) -> list[dict]`
  - `is_match(detected, truth, min_overlap=0.5, max_distance_m=100) -> bool`
  - `stay_scores(detected, truth, min_overlap=0.5, max_distance_m=100) -> dict` 키: `stays_detected, stays_truth, stay_tp, stay_precision, stay_recall, stay_f1`
  - `read_steps_output(dir) -> (step_times ndarray, states DataFrame, summary dict)`
  - `count_errors(summary)` 키 `count_intervals, manual_steps, detected_steps, count_error_pct, count_abs_error_pct`
  - `vehicle_false_steps(summary)` 키 `vehicle_s, vehicle_false_steps, vehicle_false_steps_per_min`
  - `state_at(states, t_ms) -> ndarray`, `walking_scores(session, states, start_ms, end_ms)` 키 `walk_precision, walk_recall`
  - `first_step_latency(summary, step_times) -> float | None`
  - `step_metrics(session, steps_dir) -> dict`(`detector, total_steps` + 위 키 전부 + `first_step_latency_s`)
  - `count_rows_by_carry(session, summary) -> list[dict]`(`carry, start_ms, end_ms, manual_steps, detected_steps, error_pct`)

- [ ] **Step 1: 실패하는 테스트 작성**

`research/tests/test_stay_metrics.py`:

```python
import pandas as pd
import pytest

from analysis.geo import offset
from analysis.session import load_session, truth_points
from analysis.stay_metrics import is_match, read_stays, stay_scores, truth_stays
from conftest import LAT0, LNG0, T0, gps_row, make_session, write_csv

MIN = 60_000


def _stay(a_min, l_min, east=0.0, north=0.0):
    lat, lng = offset(LAT0, LNG0, east, north)
    return {"arrive_ms": T0 + a_min * MIN, "leave_ms": T0 + l_min * MIN, "lat": lat, "lng": lng}


def test_overlap_boundary_is_inclusive_at_50_percent():
    truth = _stay(0, 20)
    assert is_match(_stay(10, 30), truth)          # 10분 겹침 = 두 머문 곳 각각의 50%
    assert not is_match(_stay(11, 31), truth)      # 9분 = 45%
    # 정답 20분 안에 든 10분짜리: 검출의 100%지만 정답의 50% → 일치
    assert is_match(_stay(5, 15), truth)
    # 하루를 덮는 검출(100분)은 정답 20분과 20%만 겹친다 → 불일치
    assert not is_match(_stay(0, 100), truth)


def test_distance_boundary_100m():
    truth = _stay(0, 20)
    assert is_match(_stay(0, 20, east=99.9), truth)
    assert not is_match(_stay(0, 20, east=100.1), truth)
    assert is_match(_stay(0, 20, east=500), {**truth, "lat": None, "lng": None})   # 중심을 모르면 시간만


def test_scores_one_to_one():
    truth = [_stay(0, 20), _stay(60, 80)]
    detected = [_stay(0, 20), _stay(1, 19), _stay(200, 220)]   # 둘째는 첫 정답과 겹치지만 이미 짝지어짐
    s = stay_scores(detected, truth)
    assert s["stay_tp"] == 1
    assert s["stay_precision"] == pytest.approx(1 / 3)
    assert s["stay_recall"] == pytest.approx(1 / 2)
    assert s["stay_f1"] == pytest.approx(2 * (1 / 3) * (1 / 2) / (1 / 3 + 1 / 2))


def test_scores_empty_sides():
    assert stay_scores([], [])["stay_f1"] is None
    s = stay_scores([], [_stay(0, 20)])
    assert s["stay_precision"] is None and s["stay_recall"] == 0.0 and s["stay_f1"] is None
    s = stay_scores([_stay(0, 20)], [_stay(100, 120)])
    assert s["stay_precision"] == 0.0 and s["stay_recall"] == 0.0 and s["stay_f1"] == 0.0


def test_truth_stays_filters_short_and_takes_center(tmp_path):
    gps = [gps_row(T0 + k * MIN, 10.0 if k % 2 else -10.0, 0) for k in range(0, 31)]
    marks = [[T0, "arrive", ""], [T0 + 3 * MIN, "depart", ""],          # 3분 → 정답 아님
             [T0 + 10 * MIN, "arrive", "카페"], [T0 + 21 * MIN, "depart", ""]]
    s = load_session(make_session(tmp_path, gps=gps, marks=marks))
    stays = truth_stays(s, truth_points(s.gps), min_stay_s=600)
    assert len(stays) == 1
    assert stays[0]["arrive_ms"] == T0 + 10 * MIN and stays[0]["leave_ms"] == T0 + 21 * MIN
    # 10~21분의 12점: 동쪽 +10, −10이 6개씩 → 중심은 원점
    assert stays[0]["lng"] == pytest.approx(LNG0, abs=1e-9)


def test_read_stays(tmp_path):
    write_csv(tmp_path / "stays.csv", ["arrive_ms", "leave_ms", "lat", "lng", "n_points"],
              [[1, 2, 37.5, 127.0, 3]])
    assert read_stays(tmp_path) == [{"arrive_ms": 1, "leave_ms": 2, "lat": 37.5, "lng": 127.0}]
    assert read_stays(tmp_path / "none") == []
```

`research/tests/test_step_metrics.py`:

```python
import json

import numpy as np
import pandas as pd
import pytest

from analysis.session import load_session
from analysis.step_metrics import (count_errors, count_rows_by_carry, first_step_latency, state_at, step_metrics,
                                   vehicle_false_steps, walking_scores)
from conftest import T0, gps_row, make_session, write_csv


def _summary(**kw):
    base = {"detector_id": "os", "total_steps": 0, "start_ms": T0, "end_ms": T0 + 100_000,
            "count_intervals": [], "vehicle_intervals": []}
    base.update(kw)
    return base


def test_count_errors_signed_total_and_mean_abs():
    s = _summary(count_intervals=[
        {"start_ms": 0, "end_ms": 1, "manual_steps": 100, "detected_steps": 110, "error_pct": 10.0},
        {"start_ms": 2, "end_ms": 3, "manual_steps": 200, "detected_steps": 180, "error_pct": -10.0},
        {"start_ms": 4, "end_ms": 5, "manual_steps": None, "detected_steps": 50, "error_pct": None},
    ])
    r = count_errors(s)
    assert r["count_intervals"] == 2 and r["manual_steps"] == 300 and r["detected_steps"] == 290
    assert r["count_error_pct"] == pytest.approx(-10 / 3)
    assert r["count_abs_error_pct"] == pytest.approx(10.0)
    assert count_errors(_summary())["count_error_pct"] is None


def test_vehicle_false_steps():
    s = _summary(vehicle_intervals=[{"board_ms": 0, "alight_ms": 120_000, "kind": "bus", "detected_steps": 6},
                                    {"board_ms": 0, "alight_ms": 60_000, "kind": "subway", "detected_steps": 3}])
    r = vehicle_false_steps(s)
    assert r == {"vehicle_s": 180.0, "vehicle_false_steps": 9, "vehicle_false_steps_per_min": 3.0}
    assert vehicle_false_steps(_summary())["vehicle_false_steps"] is None


def test_state_at_uses_last_change_and_unknown_before_first():
    states = pd.DataFrame({"t_ms": [10, 20], "state": ["walking", "still"], "cadence_hz": ["", ""]})
    assert state_at(states, np.array([5, 10, 15, 20, 99])).tolist() == ["unknown", "walking", "walking", "still",
                                                                         "still"]


def test_walking_scores_on_grid(tmp_path):
    # 0~99초. 머문 곳 60~79초, 탈것 80~89초 → 정답 보행 = 0~59, 90~99 (70초)
    marks = [[T0 + 60_000, "arrive", ""], [T0 + 79_000, "depart", ""],
             [T0 + 80_000, "board", "bus"], [T0 + 89_000, "alight", ""]]
    s = load_session(make_session(tmp_path, gps=[gps_row(T0 + 100_000, 0, 0)], marks=marks,
                                  meta={"startedAt": None}))
    # 감지기: 0~9 unknown, 10~69 walking, 70~99 still → 예측 보행 60초, 그중 정답 보행 10~59 = 50초
    states = pd.DataFrame({"t_ms": [T0 + 10_000, T0 + 70_000], "state": ["walking", "still"],
                           "cadence_hz": ["", ""]})
    r = walking_scores(s, states, T0, T0 + 100_000)
    assert r["walk_precision"] == pytest.approx(50 / 60)
    assert r["walk_recall"] == pytest.approx(50 / 70)


def test_first_step_latency():
    s = _summary(count_intervals=[{"start_ms": 1000, "end_ms": 9000, "manual_steps": 10, "detected_steps": 1},
                                  {"start_ms": 20_000, "end_ms": 30_000, "manual_steps": 10, "detected_steps": 0}])
    assert first_step_latency(s, np.array([500, 3000, 4000])) == pytest.approx(2.0)
    assert first_step_latency(_summary(), np.array([1])) is None


def test_step_metrics_reads_cli_output_and_carry_rows(tmp_path):
    marks = [[T0 + 1000, "count_start", ""], [T0 + 5000, "count_end", "4"], [T0 + 500, "carry", "pocket"]]
    s = load_session(make_session(tmp_path, gps=[gps_row(T0 + 10_000, 0, 0)],
                                  marks=sorted(marks, key=lambda m: m[0])))
    out = tmp_path / "steps"
    write_csv(out / "steps.csv", ["t_ms", "total_steps"], [[T0 + 2000, 1], [T0 + 3000, 2], [T0 + 4000, 3]])
    write_csv(out / "step_states.csv", ["t_ms", "state", "cadence_hz"], [[T0 + 1500, "walking", 1.0]])
    summary = _summary(detector_id="adaptive", total_steps=3, end_ms=T0 + 10_000, count_intervals=[
        {"start_ms": T0 + 1000, "end_ms": T0 + 5000, "manual_steps": 4, "detected_steps": 3, "error_pct": -25.0}])
    (out / "step_summary.json").write_text(json.dumps(summary), encoding="utf-8")
    r = step_metrics(s, out)
    assert r["detector"] == "adaptive" and r["count_error_pct"] == pytest.approx(-25.0)
    assert r["first_step_latency_s"] == pytest.approx(1.0)
    assert r["walk_precision"] == pytest.approx(1.0)
    assert count_rows_by_carry(s, summary)[0]["carry"] == "pocket"
```

- [ ] **Step 2: 실패 확인**

Run: `.venv/Scripts/python -m pytest tests/test_stay_metrics.py tests/test_step_metrics.py`
Expected: FAIL — `No module named 'analysis.stay_metrics'`(그리고 `step_metrics`)

- [ ] **Step 3: 구현**

`research/analysis/stay_metrics.py`:

```python
"""머문 곳 지표(설계 7-2): 검출한 머문 곳(stays.csv)을 arrive~depart 표시와 견준 정밀도·재현율·F1."""
from __future__ import annotations

from pathlib import Path

import pandas as pd

from .geo import distance_m
from .session import Session, stay_intervals


def truth_stays(session: Session, truth: pd.DataFrame, min_stay_s: float = 600) -> list[dict]:
    """정답 머문 곳 = arrive~depart 중 min_stay_s 이상인 것(분석 기준 T = 10분과 같다, recording-guide).

    중심은 그 구간 안 정답 점(정확도 필터 후)의 평균이다. 점이 없으면(실내에서 GPS가 끊김) 중심을 모르므로
    None으로 두고, 짝지을 때 거리 조건을 보지 않는다.
    """
    out = []
    for iv in stay_intervals(session):
        if iv.duration_s < min_stay_s:
            continue
        inside = truth[(truth["t_ms"] >= iv.start_ms) & (truth["t_ms"] <= iv.end_ms)]
        out.append({"arrive_ms": iv.start_ms, "leave_ms": iv.end_ms,
                    "lat": float(inside["lat"].mean()) if len(inside) else None,
                    "lng": float(inside["lng"].mean()) if len(inside) else None})
    return out


def read_stays(replay_dir: Path) -> list[dict]:
    path = Path(replay_dir) / "stays.csv"
    if not path.exists():
        return []
    df = pd.read_csv(path)
    return [{"arrive_ms": int(r.arrive_ms), "leave_ms": int(r.leave_ms), "lat": float(r.lat), "lng": float(r.lng)}
            for r in df.itertuples()]


def _overlap_ms(a: dict, b: dict) -> int:
    return max(0, min(a["leave_ms"], b["leave_ms"]) - max(a["arrive_ms"], b["arrive_ms"]))


def is_match(detected: dict, truth: dict, min_overlap: float = 0.5, max_distance_m: float = 100) -> bool:
    """겹친 시간이 두 머문 곳 각각의 min_overlap 이상이고, 중심이 max_distance_m 이내면 같은 곳이다.

    '각각'으로 재는 이유: 하루를 통째로 덮는 머문 곳 하나가 그 안의 정답 여럿과 모두 맞는 것을 막는다.
    """
    ov = _overlap_ms(detected, truth)
    longest = max(detected["leave_ms"] - detected["arrive_ms"], truth["leave_ms"] - truth["arrive_ms"])
    if longest <= 0 or ov < min_overlap * longest:
        return False
    if truth.get("lat") is None:
        return True
    return distance_m(detected["lat"], detected["lng"], truth["lat"], truth["lng"]) <= max_distance_m


def stay_scores(detected: list[dict], truth: list[dict], min_overlap: float = 0.5,
                max_distance_m: float = 100) -> dict:
    """일대일로 짝짓는다(겹친 시간이 긴 쌍부터). 분모가 0인 값은 None이다."""
    pairs = [(_overlap_ms(d, t), i, j) for i, d in enumerate(detected) for j, t in enumerate(truth)
             if is_match(d, t, min_overlap, max_distance_m)]
    used_d, used_t, tp = set(), set(), 0
    for _, i, j in sorted(pairs, key=lambda p: (-p[0], p[1], p[2])):
        if i in used_d or j in used_t:
            continue
        used_d.add(i)
        used_t.add(j)
        tp += 1
    precision = tp / len(detected) if detected else None
    recall = tp / len(truth) if truth else None
    if precision is None or recall is None:
        f1 = None
    else:
        f1 = 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)
    return {"stays_detected": len(detected), "stays_truth": len(truth), "stay_tp": tp,
            "stay_precision": precision, "stay_recall": recall, "stay_f1": f1}
```

`research/analysis/step_metrics.py`:

```python
"""걸음 감지 지표(설계 7-2): steps CLI 출력(steps.csv·step_states.csv·step_summary.json)과 관찰 표시를 견준다."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd

from .session import Session, carry_at, in_intervals, stay_intervals, vehicle_intervals


def read_steps_output(steps_dir: Path) -> tuple[np.ndarray, pd.DataFrame, dict]:
    steps_dir = Path(steps_dir)
    steps = pd.read_csv(steps_dir / "steps.csv")
    states = pd.read_csv(steps_dir / "step_states.csv", keep_default_na=False)
    summary = json.loads((steps_dir / "step_summary.json").read_text(encoding="utf-8"))
    return steps["t_ms"].to_numpy(dtype="int64"), states, summary


def count_errors(summary: dict) -> dict:
    """걸음 세기 구간(직접 센 수가 있는 것만)의 오차.

    - count_error_pct: (Σ감지 − Σ직접) ÷ Σ직접 × 100 — 부호가 있어 과대·과소 계수를 본다
    - count_abs_error_pct: 구간별 |오차 %|의 평균
    """
    rows = [c for c in summary.get("count_intervals", []) if c.get("manual_steps")]
    if not rows:
        return {"count_intervals": 0, "manual_steps": 0, "detected_steps": 0, "count_error_pct": None,
                "count_abs_error_pct": None}
    manual = sum(c["manual_steps"] for c in rows)
    detected = sum(c["detected_steps"] for c in rows)
    return {"count_intervals": len(rows), "manual_steps": manual, "detected_steps": detected,
            "count_error_pct": (detected - manual) / manual * 100,
            "count_abs_error_pct": float(np.mean([abs(c["detected_steps"] - c["manual_steps"]) / c["manual_steps"]
                                                  * 100 for c in rows]))}


def vehicle_false_steps(summary: dict) -> dict:
    """탈것 구간(board~alight)의 걸음 수 합. 정답은 0걸음이다."""
    rows = summary.get("vehicle_intervals", [])
    seconds = sum((v["alight_ms"] - v["board_ms"]) / 1000 for v in rows)
    steps = sum(v["detected_steps"] for v in rows)
    return {"vehicle_s": seconds, "vehicle_false_steps": steps if rows else None,
            "vehicle_false_steps_per_min": steps / (seconds / 60) if seconds > 0 else None}


def state_at(states: pd.DataFrame, t_ms: np.ndarray) -> np.ndarray:
    """초마다 감지기 상태(직전 상태 변화). 첫 판정 전은 'unknown'."""
    change_t = states["t_ms"].to_numpy(dtype="int64")
    names = np.array(list(states["state"]) + ["unknown"], dtype=object)
    idx = np.searchsorted(change_t, t_ms, side="right") - 1
    return names[np.where(idx >= 0, idx, len(names) - 1)]


def walking_scores(session: Session, states: pd.DataFrame, start_ms: int, end_ms: int) -> dict:
    """보행 판정 정밀도·재현율(1초 격자, 시간 기준).

    정답 보행 = 머문 곳(arrive~depart, 길이와 상관없이)과 탈것(board~alight) 밖의 모든 시각(설계 7-2).
    횡단보도에서 서 있던 몇 초도 정답에서는 보행이라, 정밀도·재현율의 상한이 1보다 조금 낮다.
    """
    grid = np.arange(start_ms, end_ms, 1000, dtype="int64")
    if len(grid) == 0:
        return {"walk_precision": None, "walk_recall": None}
    truth = ~(in_intervals(grid, stay_intervals(session)) | in_intervals(grid, vehicle_intervals(session)))
    pred = state_at(states, grid) == "walking"
    tp = int((truth & pred).sum())
    return {"walk_precision": tp / int(pred.sum()) if pred.any() else None,
            "walk_recall": tp / int(truth.sum()) if truth.any() else None}


def first_step_latency(summary: dict, step_times: np.ndarray) -> float | None:
    """걸음 세기 구간마다 count_start에서 첫 감지 걸음까지(초)의 평균. 구간 안에 걸음이 없으면 그 구간은 뺀다."""
    delays = []
    for c in summary.get("count_intervals", []):
        inside = step_times[(step_times >= c["start_ms"]) & (step_times <= c["end_ms"])]
        if len(inside):
            delays.append((int(inside.min()) - c["start_ms"]) / 1000)
    return float(np.mean(delays)) if delays else None


def step_metrics(session: Session, steps_dir: Path) -> dict:
    step_times, states, summary = read_steps_output(steps_dir)
    row = {"detector": summary.get("detector_id"), "total_steps": summary.get("total_steps")}
    row.update(count_errors(summary))
    row.update(vehicle_false_steps(summary))
    row.update(walking_scores(session, states, summary["start_ms"], summary["end_ms"]))
    row["first_step_latency_s"] = first_step_latency(summary, step_times)
    return row


def count_rows_by_carry(session: Session, summary: dict) -> list[dict]:
    """걸음 세기 구간을 휴대 위치(손·주머니·가방)별로 나눠 보고하기 위한 구간별 행."""
    return [{"carry": carry_at(session, c["start_ms"]), "start_ms": c["start_ms"], "end_ms": c["end_ms"],
             "manual_steps": c["manual_steps"], "detected_steps": c["detected_steps"], "error_pct": c["error_pct"]}
            for c in summary.get("count_intervals", []) if c.get("manual_steps")]
```

- [ ] **Step 4: 통과 확인**

Run: `.venv/Scripts/python -m pytest`
Expected: PASS — `31 passed`

- [ ] **Step 5: 커밋**

```bash
git add research/analysis/stay_metrics.py research/analysis/step_metrics.py research/tests/test_stay_metrics.py research/tests/test_step_metrics.py
git commit -m "feat(research): 머문 곳 정밀도·재현율·F1과 걸음 수 오차·탈것 가짜 걸음·보행 판정·첫 걸음 지연을 잰다"
```

---

### Task 4: 배터리 지표 — 시간당 mAh, 제외 회차, batterystats GPS 시간

**Files:**
- Create: `research/analysis/battery.py`
- Test: `research/tests/test_battery.py`

**Interfaces:**
- Consumes: Task 1의 `read_csv`, `read_meta`, `BATTERY_COLUMNS`. 정책 실행 세션의 `battery.csv`, `meta.json`(`deviceModel`, `policy{policyId, detectorId, policyParams}`, `errors`), `summary.json`(`gps_on_s`), `batterystats.txt`
- Produces:
  - `exclusion_reason(meta) -> str | None`, `longest_unplugged(battery) -> DataFrame`
  - `charge_rate(battery, align_steps=True) -> dict` 키 `rows, hours, mah_used, mah_per_h, aligned`
  - `current_rate(battery, unit="uA") -> float | None`(mA, `unit`은 `uA`·`mA`)
  - `parse_duration_ms(text) -> int`, `gps_seconds_from_batterystats(text, package=None) -> {"gps_s_total", "gps_s_app"}`
  - `method_label(policy_id, detector_id=None, params=None) -> str` — 예 `step_budget[adaptive] e_m=50`. 걸음 정책(`still_suppress`·`step_budget`)만 감지기를 붙인다. 재생 이름과 배터리 방식 이름을 잇는 열쇠다
  - `battery_run(session_dir, current_units=None, align_steps=True, package="com.travelfootsteps.app") -> dict` 키 `session, device, method, excluded, hours, mah_used, mah_per_h, aligned, current_ma, gps_s_total, gps_s_app, gps_on_s_est`
  - `battery_summary(runs: DataFrame) -> DataFrame` 열 `method, n, mah_per_h_mean, mah_per_h_std, current_ma_mean, gps_s_app_mean`

- [ ] **Step 1: 실패하는 테스트 작성**

`research/tests/test_battery.py`:

```python
import json

import pandas as pd
import pytest

from analysis.battery import (battery_run, battery_summary, charge_rate, current_rate, exclusion_reason,
                              gps_seconds_from_batterystats, longest_unplugged, method_label, parse_duration_ms)
from conftest import T0, make_session

H = 3_600_000


def _battery(rows):
    return pd.DataFrame(rows, columns=["t_ms", "charge_uah", "current_ua", "level_pct", "temp_c", "plugged"])


def test_charge_rate_raw_and_step_aligned():
    # 0분 3,700,000 → 15분 3,696,300(계단) → 45분 3,692,600(계단) → 60분 그대로
    b = _battery([[T0, 3_700_000, -150, 88, 30, 0], [T0 + H // 4, 3_696_300, -150, 88, 30, 0],
                  [T0 + 3 * H // 4, 3_692_600, -150, 88, 30, 0], [T0 + H, 3_692_600, -150, 88, 30, 0]])
    raw = charge_rate(b, align_steps=False)
    assert raw["hours"] == pytest.approx(1.0) and raw["mah_per_h"] == pytest.approx(7.4)
    aligned = charge_rate(b)
    # 15분 ~ 45분: 3.7mAh ÷ 0.5h
    assert aligned["aligned"] and aligned["hours"] == pytest.approx(0.5)
    assert aligned["mah_per_h"] == pytest.approx(7.4)


def test_charge_rate_falls_back_without_two_steps():
    b = _battery([[T0, 3_705_000, -1, 100, 30, 0], [T0 + H, 3_705_000, -1, 100, 30, 0]])
    r = charge_rate(b)
    assert not r["aligned"] and r["mah_per_h"] == 0.0
    assert charge_rate(b.iloc[:1])["mah_per_h"] is None


def test_longest_unplugged_drops_charging_rows():
    b = _battery([[T0, 1, 0, 0, 0, 1], [T0 + 1, 1, 0, 0, 0, 0], [T0 + 2, 1, 0, 0, 0, 0], [T0 + 3, 1, 0, 0, 0, 1],
                  [T0 + 4, 1, 0, 0, 0, 0]])
    assert longest_unplugged(b)["t_ms"].tolist() == [T0 + 1, T0 + 2]


def test_current_rate_units():
    b = _battery([[T0, 0, -100, 0, 0, 0], [T0 + 1, 0, -300, 0, 0, 0]])
    assert current_rate(b, "mA") == pytest.approx(200.0)
    assert current_rate(b, "uA") == pytest.approx(0.2)


def test_exclusion_reason():
    assert exclusion_reason({"errors": [{"message": "restarted by system"}]}) == "restarted by system"
    assert exclusion_reason({"errors": [{"message": "gps timeout"}]}) is None
    assert exclusion_reason({}) is None


def test_parse_batterystats_gps():
    text = """
Statistics since last charge:
  u0a12:
    Sensor GPS: 1m 2s 500ms realtime (3 times)
  u0a245:
    Apk com.travelfootsteps.app:
      Service com.pravera.flutter_foreground_task.service.ForegroundService:
    Sensor GPS: 10s 0ms realtime (2 times)
    Sensor GPS: 1h 0m 5s 0ms realtime (1 times)
"""
    assert parse_duration_ms("1h 2m 3s 456ms") == 3_723_456
    r = gps_seconds_from_batterystats(text, "com.travelfootsteps.app")
    assert r["gps_s_total"] == pytest.approx(62.5 + 10 + 3605)
    assert r["gps_s_app"] == pytest.approx(3615.0)
    assert gps_seconds_from_batterystats("nothing", "x") == {"gps_s_total": None, "gps_s_app": None}


def test_method_label():
    assert method_label("fixed_1m", "os", {}) == "fixed_1m"
    assert method_label("step_budget", "adaptive", {"e_m": "50"}) == "step_budget[adaptive] e_m=50"


def test_battery_run_and_summary(tmp_path):
    policy = {"policyId": "step_budget", "detectorId": "os", "policyParams": {"e_m": "50"}, "detectorParams": {}}
    rows = [[T0 + k * H // 2, 3_700_000 - k * 3_700, -150, 88, 30, 1 if k == 0 else 0] for k in range(4)]
    a = make_session(tmp_path, "a", battery=rows, meta={"mode": "policy", "policy": policy, "deviceModel": "X"})
    (a / "summary.json").write_text(json.dumps({"gps_on_s": 12.0}), encoding="utf-8")
    rows_b = [[T0 + k * H // 2, 3_700_000 - k * 7_400, -150, 88, 30, 0] for k in range(3)]
    b = make_session(tmp_path, "b", battery=rows_b, meta={"mode": "policy", "policy": policy, "deviceModel": "X"})
    c = make_session(tmp_path, "c", battery=rows_b, meta={"mode": "policy", "policy": policy,
                                                         "errors": [{"message": "restarted by system"}]})
    ra = battery_run(a, current_units={"X": "mA"})
    # plugged 행(0분)을 빼면 30·60·90분 행이 남고, 계단이 바뀐 행은 60·90분 → 3.7mAh ÷ 0.5h
    assert ra["method"] == "step_budget[os] e_m=50" and ra["mah_per_h"] == pytest.approx(7.4)
    assert ra["current_ma"] == pytest.approx(150.0) and ra["gps_on_s_est"] == 12.0
    runs = pd.DataFrame([ra, battery_run(b), battery_run(c)])
    assert runs["excluded"].tolist()[2] == "restarted by system"
    s = battery_summary(runs)
    assert s["n"].tolist() == [2]
    assert s["mah_per_h_mean"].iloc[0] == pytest.approx((7.4 + 14.8) / 2)
    assert s["mah_per_h_std"].iloc[0] == pytest.approx(pd.Series([7.4, 14.8]).std())
```

- [ ] **Step 2: 실패 확인**

Run: `.venv/Scripts/python -m pytest tests/test_battery.py`
Expected: FAIL — `No module named 'analysis.battery'`

- [ ] **Step 3: 구현**

`research/analysis/battery.py`:

```python
"""배터리 지표(설계 7-2, battery-experiment-guide): 정책 실행 세션의 시간당 mAh와 GPS 사용 시간."""
from __future__ import annotations

import json
import re
from pathlib import Path

import numpy as np
import pandas as pd

from .session import BATTERY_COLUMNS, read_csv, read_meta

RESTARTED = "restarted by system"


def exclusion_reason(meta: dict) -> str | None:
    """시스템이 기록 서비스를 다시 띄운 회차는 정책이 처음부터 다시 돌아 뺀다(battery-experiment-guide 5절)."""
    for e in meta.get("errors") or []:
        if RESTARTED in str(e.get("message", "")):
            return RESTARTED
    return None


def longest_unplugged(battery: pd.DataFrame) -> pd.DataFrame:
    """plugged = 0인 행이 가장 길게 이어진 묶음. 충전 중 행은 전하량이 늘어 계산에서 뺀다."""
    unplugged = (battery["plugged"].to_numpy() == 0)
    best, best_len, start = (0, 0), 0, None
    for k, flag in enumerate(list(unplugged) + [False]):
        if flag and start is None:
            start = k
        elif not flag and start is not None:
            if k - start > best_len:
                best, best_len = (start, k), k - start
            start = None
    return battery.iloc[best[0]:best[1]].reset_index(drop=True)


def charge_rate(battery: pd.DataFrame, align_steps: bool = True) -> dict:
    """시간당 mAh = 전하량 감소 ÷ 시간.

    이 기종은 전하량이 3.7mAh 계단으로 줄어든다. align_steps면 첫 계단이 바뀐 행 ~ 마지막 계단이 바뀐 행 사이로
    재 양자화 오차를 줄인다(device-check.md). 계단 변화가 두 번 미만이면 처음 ~ 끝 행으로 잰다.
    """
    out = {"rows": int(len(battery)), "hours": None, "mah_used": None, "mah_per_h": None, "aligned": False}
    if len(battery) < 2:
        return out
    t = battery["t_ms"].to_numpy(dtype="int64")
    c = battery["charge_uah"].to_numpy(dtype=float)
    i, j = 0, len(battery) - 1
    if align_steps:
        changed = np.flatnonzero(np.diff(c) != 0) + 1
        if len(changed) >= 2:
            i, j = int(changed[0]), int(changed[-1])
            out["aligned"] = True
    hours = (t[j] - t[i]) / 3_600_000
    if hours <= 0:
        return out
    out["hours"] = hours
    out["mah_used"] = (c[i] - c[j]) / 1000
    out["mah_per_h"] = out["mah_used"] / hours
    return out


def current_rate(battery: pd.DataFrame, unit: str = "uA") -> float | None:
    """전류 평균의 크기(mA) ≈ 시간당 mAh. 교차 확인용. 이 기종(SM-S911N)은 current_ua 열이 실제로 mA다."""
    if battery.empty:
        return None
    factor = {"uA": 1 / 1000, "mA": 1.0}[unit]
    return float(np.abs(battery["current_ua"].to_numpy(dtype=float)).mean() * factor)


_DURATION = re.compile(r"(\d+)(h|ms|m|s)")


def parse_duration_ms(text: str) -> int:
    """batterystats 시간 표기('1h 2m 3s 456ms')를 밀리초로."""
    scale = {"h": 3_600_000, "m": 60_000, "s": 1000, "ms": 1}
    return sum(int(n) * scale[u] for n, u in _DURATION.findall(text))


_GPS_LINE = re.compile(r"Sensor GPS:\s*((?:\d+(?:h|ms|m|s)\s*)+)")
_UID_LINE = re.compile(r"^\s*(?:Uid\s+)?(u\d+a\d+|\d+):\s*$")


def gps_seconds_from_batterystats(text: str, package: str | None = None) -> dict:
    """dumpsys batterystats 출력에서 'Sensor GPS: … realtime' 줄의 시간을 더한다(최선 노력, 형식이 기종·버전마다 다르다).

    - gps_s_total: 모든 앱의 합
    - gps_s_app: package가 든 Uid 묶음의 합(그 묶음에 'Apk <package>' 또는 패키지 이름 줄이 있을 때). 못 찾으면 None
    """
    total = 0
    per_uid: dict[str, int] = {}
    uid_packages: dict[str, set[str]] = {}
    uid = None
    for line in text.splitlines():
        m = _UID_LINE.match(line)
        if m:
            uid = m.group(1)
            continue
        if uid is not None and package and package in line:
            uid_packages.setdefault(uid, set()).add(package)
        g = _GPS_LINE.search(line)
        if g:
            ms = parse_duration_ms(g.group(1))
            total += ms
            if uid is not None:
                per_uid[uid] = per_uid.get(uid, 0) + ms
    app = None
    if package:
        uids = [u for u, pk in uid_packages.items() if package in pk]
        if uids:
            app = sum(per_uid.get(u, 0) for u in uids) / 1000
    return {"gps_s_total": total / 1000 if total else None, "gps_s_app": app}


def method_label(policy_id: str, detector_id: str | None = None, params: dict | None = None) -> str:
    """방식 이름. 재생 결과와 배터리 실험을 같은 이름으로 잇는다. 걸음 감지기는 걸음 정책일 때만 붙인다."""
    label = policy_id
    if policy_id in {"still_suppress", "step_budget"} and detector_id:
        label += f"[{detector_id}]"
    if params:
        label += " " + " ".join(f"{k}={params[k]}" for k in sorted(params))
    return label


def battery_run(session_dir: Path, current_units: dict | None = None, align_steps: bool = True,
                package: str = "com.travelfootsteps.app") -> dict:
    """배터리 실험 한 회(정책 실행 세션 폴더 하나)."""
    session_dir = Path(session_dir)
    meta = read_meta(session_dir)
    policy = meta.get("policy") or {}
    battery = read_csv(session_dir / "battery.csv", BATTERY_COLUMNS, ["t_ms", "charge_uah", "current_ua", "plugged"])
    run = longest_unplugged(battery)
    device = meta.get("deviceModel", "")
    unit = (current_units or {}).get(device, "uA")
    row = {"session": meta.get("sessionId", session_dir.name), "device": device,
           "method": method_label(policy.get("policyId", meta.get("mode", "?")), policy.get("detectorId"),
                                  policy.get("policyParams")),
           "excluded": exclusion_reason(meta)}
    rate = charge_rate(run, align_steps)
    row.update({"hours": rate["hours"], "mah_used": rate["mah_used"], "mah_per_h": rate["mah_per_h"],
                "aligned": rate["aligned"], "current_ma": current_rate(run, unit)})
    stats = session_dir / "batterystats.txt"
    if stats.exists():
        row.update(gps_seconds_from_batterystats(stats.read_text(encoding="utf-8", errors="replace"), package))
    else:
        row.update({"gps_s_total": None, "gps_s_app": None})
    summary = session_dir / "summary.json"
    if summary.exists():
        row["gps_on_s_est"] = json.loads(summary.read_text(encoding="utf-8")).get("gps_on_s")
    else:
        row["gps_on_s_est"] = None
    return row


def battery_summary(runs: pd.DataFrame) -> pd.DataFrame:
    """방식마다 평균 ± 표준편차(표본, ddof=1). 제외된 회차와 값이 없는 회차는 빼고 센다."""
    cols = ["method", "n", "mah_per_h_mean", "mah_per_h_std", "current_ma_mean", "gps_s_app_mean"]
    if runs.empty:
        return pd.DataFrame(columns=cols)
    ok = runs[runs["excluded"].isna() & runs["mah_per_h"].notna()]
    rows = []
    for method, g in ok.groupby("method", sort=True):
        rows.append({"method": method, "n": len(g), "mah_per_h_mean": g["mah_per_h"].mean(),
                     "mah_per_h_std": g["mah_per_h"].std(ddof=1) if len(g) > 1 else None,
                     "current_ma_mean": g["current_ma"].mean(),
                     "gps_s_app_mean": g["gps_s_app"].mean() if g["gps_s_app"].notna().any() else None})
    return pd.DataFrame(rows, columns=cols)
```

- [ ] **Step 4: 통과 확인**

Run: `.venv/Scripts/python -m pytest`
Expected: PASS — `39 passed`

- [ ] **Step 5: 커밋**

```bash
git add research/analysis/battery.py research/tests/test_battery.py
git commit -m "feat(research): 배터리 실험 회차의 시간당 mAh를 전하량 계단에 맞춰 재고 재시작 회차를 뺀다"
```

---

### Task 5: 재생 CLI·복원 서버 호출

**Files:**
- Create: `research/analysis/replay.py`, `research/analysis/reconstruct.py`
- Test: `research/tests/test_replay.py`, `research/tests/test_reconstruct.py`

**Interfaces:**
- Consumes: Task 4의 `method_label`. CLI `dart run footstep_core:replay --session --policy --detector --ttff --out [--param] [--detector-param] [--stay-param]`, `dart run footstep_core:steps --session --detector --out [--detector-param]`(replay-guide, steps-guide). API `POST /api/route/reconstruct`(route-guide 3절)
- Produces:
  - `RunSpec(policy, detector="os", params=(), detector_params=(), ttff=0, stay_params=())`(frozen, 튜플은 `(이름, 문자열 값)` 이름순), `.label`(예 `step_budget[adaptive] e_m=50 ttff=5 stay.use_still=false`), `.key`(결과 폴더 이름, 예 `step_budget-adaptive-e_m=50-ttff5-s.use_still=false`)
  - `replay_args(session_dir, spec, out_dir) -> list[str]`, `steps_args(session_dir, detector, out_dir, detector_params=()) -> list[str]`
  - `CliError`, `DartCli(package_dir, dart=None, run=subprocess.run)`: `replay(session_dir, spec, out_dir, force=False) -> Path`(`summary.json`이 있으면 다시 안 돎), `steps(session_dir, detector, out_dir, detector_params=(), force=False) -> Path`(`step_summary.json` 기준)
  - `read_fixes(replay_dir) -> DataFrame`, `to_points(fixes) -> list[dict]`, `to_stays(stays) -> list[dict]`
  - `build_requests(fixes, stays, method, hmm=None, max_points=2000) -> list[dict]`
  - `ServerUnavailable`, `ReconstructError`, `ReconstructClient(base_url="http://localhost:9090", token="dev-fake-token", timeout_s=120, post=…)`: `reconstruct(fixes, stays, method, hmm=None) -> list[segment]`, `.unavailable`(한 번 연결에 실패하면 True, 이후 호출은 바로 `ServerUnavailable`)

- [ ] **Step 1: 실패하는 테스트 작성**

`research/tests/test_replay.py`:

```python
from pathlib import Path
from types import SimpleNamespace

import pytest

from analysis.replay import CliError, DartCli, RunSpec, replay_args, steps_args


def test_label_and_key():
    s = RunSpec("step_budget", "adaptive", params=(("e_m", "50"),), ttff=5, stay_params=(("use_still", "false"),))
    assert s.label == "step_budget[adaptive] e_m=50 ttff=5 stay.use_still=false"
    assert s.key == "step_budget-adaptive-e_m=50-ttff5-s.use_still=false"
    assert RunSpec("fixed_1m").label == "fixed_1m"
    assert RunSpec("fixed_1m").key == "fixed_1m-os-ttff0"


def test_replay_and_steps_args():
    s = RunSpec("time_speed", "os", params=(("e_m", "25"),), detector_params=(), ttff=0.5,
                stay_params=(("min_stay_s", "300"),))
    args = replay_args(Path("S"), s, Path("O"))
    assert args == ["run", "footstep_core:replay", "--session", "S", "--policy", "time_speed", "--detector", "os",
                    "--ttff", "0.5", "--out", "O", "--param", "e_m=25", "--stay-param", "min_stay_s=300"]
    assert steps_args(Path("S"), "adaptive", Path("O"), (("n_confirm", "6"),)) == [
        "run", "footstep_core:steps", "--session", "S", "--detector", "adaptive", "--out", "O",
        "--detector-param", "n_confirm=6"]


def test_dart_cli_caches_and_reports_errors(tmp_path):
    calls = []

    def fake_run(cmd, cwd, **kw):
        calls.append((cmd, cwd))
        out = Path(cmd[cmd.index("--out") + 1])
        out.mkdir(parents=True, exist_ok=True)
        (out / "summary.json").write_text("{}")
        return SimpleNamespace(returncode=0, stderr="")

    cli = DartCli(tmp_path / "pkg", dart="dart", run=fake_run)
    out = tmp_path / "o"
    cli.replay(tmp_path, RunSpec("hourly"), out)
    cli.replay(tmp_path, RunSpec("hourly"), out)          # summary.json이 있어 다시 돌리지 않는다
    assert len(calls) == 1 and calls[0][1] == str(tmp_path / "pkg")
    cli.replay(tmp_path, RunSpec("hourly"), out, force=True)
    assert len(calls) == 2

    bad = DartCli(tmp_path, dart="dart", run=lambda *a, **k: SimpleNamespace(returncode=64, stderr="사용법"))
    with pytest.raises(CliError, match="64"):
        bad.steps(tmp_path, "os", tmp_path / "s")
```

`research/tests/test_reconstruct.py`:

```python
from types import SimpleNamespace

import pandas as pd
import pytest

from analysis.reconstruct import (ReconstructClient, ReconstructError, ServerUnavailable, build_requests, read_fixes,
                                  to_points)
from conftest import write_csv


def _fixes(n):
    return pd.DataFrame({"t_ms": range(n), "lat": [37.0] * n, "lng": [127.0] * n, "accuracy_m": [5.0] * n,
                         "steps_since_prev": [10] * n, "state": ["walking"] * n, "kind": ["single"] * n})


def test_read_fixes_and_to_points_null_fields(tmp_path):
    write_csv(tmp_path / "fixes.csv", ["t_ms", "lat", "lng", "accuracy_m", "steps_since_prev", "state", "kind"],
              [[2, 37.1, 127.1, 4.5, 64, "walking", "single"], [1, 37.0, 127.0, "", "", "", "single"]])
    pts = to_points(read_fixes(tmp_path))
    assert pts == [{"t": 1, "lat": 37.0, "lng": 127.0, "accuracy": None, "stepsSincePrev": None, "state": None},
                   {"t": 2, "lat": 37.1, "lng": 127.1, "accuracy": 4.5, "stepsSincePrev": 64, "state": "walking"}]


def test_build_requests_splits_over_limit_with_overlap():
    stays = [{"arrive_ms": 0, "leave_ms": 1, "lat": 1, "lng": 2}, {"arrive_ms": 8, "leave_ms": 9, "lat": 1, "lng": 2}]
    reqs = build_requests(_fixes(9), stays, "hmm_steps", hmm={"betaM": 5}, max_points=4)
    # 0-3, 3-6, 6-8: 앞 조각의 마지막 점을 다음 조각이 다시 쓴다
    assert [[p["t"] for p in r["points"]] for r in reqs] == [[0, 1, 2, 3], [3, 4, 5, 6], [6, 7, 8]]
    assert [len(r["stays"]) for r in reqs] == [1, 0, 1]
    assert all(r["method"] == "hmm_steps" and r["hmm"] == {"betaM": 5} for r in reqs)
    one = build_requests(_fixes(2), [], "straight")
    assert len(one) == 1 and "hmm" not in one[0]


def test_client_posts_with_token_and_joins_segments():
    sent = []

    def fake_post(url, json, headers, timeout):
        sent.append((url, json, headers))
        return SimpleNamespace(status_code=200, text="", json=lambda: {
            "method": json["method"], "segments": [{"kind": "walk", "coords": [], "fallback": True}]})

    c = ReconstructClient("http://h:1/", "tok", post=fake_post)
    segs = c.reconstruct(_fixes(3), [], "straight")
    assert sent[0][0] == "http://h:1/api/route/reconstruct"
    assert sent[0][2] == {"Authorization": "Bearer tok"}
    assert segs == [{"kind": "walk", "coords": [], "fallback": True}]


def test_client_errors():
    def down(*a, **k):
        raise ServerUnavailable("refused")

    c = ReconstructClient(post=down)
    with pytest.raises(ServerUnavailable):
        c.reconstruct(_fixes(1), [], "straight")
    assert c.unavailable
    calls = []
    c.post = lambda *a, **k: calls.append(1)
    with pytest.raises(ServerUnavailable):        # 한 번 끊기면 이후는 부르지 않는다
        c.reconstruct(_fixes(1), [], "straight")
    assert calls == []

    bad = ReconstructClient(post=lambda *a, **k: SimpleNamespace(status_code=400, text="too many", json=dict))
    with pytest.raises(ReconstructError, match="400"):
        bad.reconstruct(_fixes(1), [], "straight")


def test_default_post_turns_refused_connection_into_server_unavailable():
    c = ReconstructClient("http://127.0.0.1:9", timeout_s=5)     # 아무도 듣지 않는 포트
    with pytest.raises(ServerUnavailable):
        c.reconstruct(_fixes(1), [], "straight")
```

- [ ] **Step 2: 실패 확인**

Run: `.venv/Scripts/python -m pytest tests/test_replay.py tests/test_reconstruct.py`
Expected: FAIL — `No module named 'analysis.replay'`(그리고 `reconstruct`)

- [ ] **Step 3: 구현**

`research/analysis/replay.py`:

```python
"""footstep_core의 replay·steps CLI를 부른다(replay-guide, steps-guide). 재생은 결정적이라 결과 폴더가 있으면 다시 돌리지 않는다."""
from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from .battery import method_label


@dataclass(frozen=True)
class RunSpec:
    """재생 한 번의 설정. params·detector_params·stay_params는 (이름, 값) 튜플을 이름순으로 둔다(해시·비교용)."""
    policy: str
    detector: str = "os"
    params: tuple = ()
    detector_params: tuple = ()
    ttff: float = 0
    stay_params: tuple = ()

    @property
    def label(self) -> str:
        """그래프·표에 쓰는 이름. ttff·머문 곳 설정은 기본값이 아닐 때만 붙인다."""
        text = method_label(self.policy, self.detector, dict(self.params))
        if self.detector_params:
            text += " " + " ".join(f"{k}={v}" for k, v in self.detector_params)
        if self.ttff:
            text += f" ttff={self.ttff:g}"
        if self.stay_params:
            text += " " + " ".join(f"stay.{k}={v}" for k, v in self.stay_params)
        return text

    @property
    def key(self) -> str:
        """결과 폴더 이름(파일 이름에 쓸 수 없는 문자를 피한다)."""
        parts = [self.policy, self.detector]
        parts += [f"{k}={v}" for k, v in self.params]
        parts += [f"d.{k}={v}" for k, v in self.detector_params]
        parts.append(f"ttff{self.ttff:g}")
        parts += [f"s.{k}={v}" for k, v in self.stay_params]
        return "-".join(parts).replace("/", "_").replace(" ", "_")


def replay_args(session_dir: Path, spec: RunSpec, out_dir: Path) -> list[str]:
    args = ["run", "footstep_core:replay", "--session", str(session_dir), "--policy", spec.policy,
            "--detector", spec.detector, "--ttff", f"{spec.ttff:g}", "--out", str(out_dir)]
    for k, v in spec.params:
        args += ["--param", f"{k}={v}"]
    for k, v in spec.detector_params:
        args += ["--detector-param", f"{k}={v}"]
    for k, v in spec.stay_params:
        args += ["--stay-param", f"{k}={v}"]
    return args


def steps_args(session_dir: Path, detector: str, out_dir: Path, detector_params: tuple = ()) -> list[str]:
    args = ["run", "footstep_core:steps", "--session", str(session_dir), "--detector", detector,
            "--out", str(out_dir)]
    for k, v in detector_params:
        args += ["--detector-param", f"{k}={v}"]
    return args


class CliError(RuntimeError):
    pass


@dataclass
class DartCli:
    """packages/footstep_core에서 `dart run`을 부른다. run은 테스트에서 가짜로 바꾼다."""
    package_dir: Path
    dart: str | None = None
    run: Callable = field(default=subprocess.run)

    def _dart(self) -> str:
        found = self.dart or shutil.which("dart")
        if not found:
            raise CliError("dart를 찾을 수 없습니다(PATH 또는 experiments.yaml의 dart)")
        return found

    def _call(self, args: list[str]) -> None:
        proc = self.run([self._dart(), *args], cwd=str(self.package_dir), capture_output=True, text=True,
                        encoding="utf-8", errors="replace")
        if proc.returncode != 0:
            raise CliError(f"dart {' '.join(args[:2])} 실패({proc.returncode}): {proc.stderr.strip()[:500]}")

    def replay(self, session_dir: Path, spec: RunSpec, out_dir: Path, force: bool = False) -> Path:
        if force or not (out_dir / "summary.json").exists():
            self._call(replay_args(Path(session_dir).resolve(), spec, Path(out_dir).resolve()))
        return out_dir

    def steps(self, session_dir: Path, detector: str, out_dir: Path, detector_params: tuple = (),
              force: bool = False) -> Path:
        if force or not (out_dir / "step_summary.json").exists():
            self._call(steps_args(Path(session_dir).resolve(), detector, Path(out_dir).resolve(), detector_params))
        return out_dir
```

`research/analysis/reconstruct.py`:

```python
"""서버 경로 복원 API 호출(route-guide). 서버나 OSRM이 없어도 분석이 끝까지 돌도록 실패를 값으로 돌려준다."""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

import pandas as pd

MAX_POINTS = 2000
MAX_STAYS = 500


def _num(v):
    if v is None or (isinstance(v, float) and math.isnan(v)) or v == "":
        return None
    return v


def read_fixes(replay_dir: Path) -> pd.DataFrame:
    """재생기·정책 실행 모드의 fixes.csv(같은 형식)."""
    return pd.read_csv(Path(replay_dir) / "fixes.csv", keep_default_na=False, na_values=[""])


def to_points(fixes: pd.DataFrame) -> list[dict]:
    """fixes.csv 행 → 요청 points(t_ms→t, accuracy_m→accuracy, steps_since_prev→stepsSincePrev, state)."""
    out = []
    for r in fixes.sort_values("t_ms", kind="stable").itertuples():
        steps = _num(getattr(r, "steps_since_prev", None))
        acc = _num(getattr(r, "accuracy_m", None))
        state = _num(getattr(r, "state", None))
        out.append({"t": int(r.t_ms), "lat": float(r.lat), "lng": float(r.lng),
                    "accuracy": float(acc) if acc is not None else None,
                    "stepsSincePrev": int(steps) if steps is not None else None,
                    "state": str(state) if state is not None else None})
    return out


def to_stays(stays: list[dict]) -> list[dict]:
    return [{"arrive": s["arrive_ms"], "leave": s["leave_ms"], "lat": s["lat"], "lng": s["lng"]} for s in stays]


def build_requests(fixes: pd.DataFrame, stays: list[dict], method: str, hmm: dict | None = None,
                   max_points: int = MAX_POINTS) -> list[dict]:
    """요청 본문 목록. 점이 상한(2000)을 넘으면(연속 측위 몇 시간) 앞 조각의 마지막 점을 다음 조각의 첫 점으로
    겹쳐 나눈다 — 이어 붙인 경로가 끊기지 않는다. 머문 곳은 조각 시간 범위와 겹치는 것만 넣는다."""
    points = to_points(fixes)
    all_stays = to_stays(stays)
    chunks, k = [], 0
    while True:
        chunk = points[k:k + max_points]
        chunks.append(chunk)
        if k + max_points >= len(points):
            break
        k += max_points - 1
    out = []
    for chunk in chunks:
        lo, hi = (chunk[0]["t"], chunk[-1]["t"]) if chunk else (0, 0)
        body = {"method": method, "points": chunk,
                "stays": [s for s in all_stays if s["leave"] >= lo and s["arrive"] <= hi][:MAX_STAYS]}
        if hmm:
            body["hmm"] = hmm
        out.append(body)
    return out


class ServerUnavailable(RuntimeError):
    """서버에 연결하지 못했다. 이후 호출도 건너뛴다."""


class ReconstructError(RuntimeError):
    """서버가 200이 아닌 응답을 줬다(요청 형식·상한 문제)."""


def _default_post(*args, **kwargs):
    import requests
    try:
        return requests.post(*args, **kwargs)
    except (requests.ConnectionError, requests.Timeout) as e:
        raise ServerUnavailable(str(e)) from e


@dataclass
class ReconstructClient:
    """POST /api/route/reconstruct. local 프로필 서버는 더미 토큰 dev-fake-token을 받는다(route-guide 2절)."""
    base_url: str = "http://localhost:9090"
    token: str = "dev-fake-token"
    timeout_s: float = 120
    post: Callable = field(default=_default_post)
    unavailable: bool = False

    def reconstruct(self, fixes: pd.DataFrame, stays: list[dict], method: str,
                    hmm: dict | None = None) -> list[dict]:
        if self.unavailable:
            raise ServerUnavailable("앞선 호출에서 서버에 연결하지 못했습니다")
        segments: list[dict] = []
        for body in build_requests(fixes, stays, method, hmm):
            try:
                resp = self.post(f"{self.base_url.rstrip('/')}/api/route/reconstruct", json=body,
                                 headers={"Authorization": f"Bearer {self.token}"}, timeout=self.timeout_s)
            except ServerUnavailable:
                self.unavailable = True
                raise
            if resp.status_code != 200:
                raise ReconstructError(f"{resp.status_code}: {resp.text[:300]}")
            segments += resp.json().get("segments", [])
        return segments
```

- [ ] **Step 4: 통과 확인**

Run: `.venv/Scripts/python -m pytest`
Expected: PASS — `47 passed`. 마지막 테스트는 아무도 듣지 않는 포트(127.0.0.1:9)로 실제 `requests`를 불러 연결 거부가 `ServerUnavailable`로 바뀌는지 본다(서버가 필요 없다).

- [ ] **Step 5: 커밋**

```bash
git add research/analysis/replay.py research/analysis/reconstruct.py research/tests/test_replay.py research/tests/test_reconstruct.py
git commit -m "feat(research): 재생·걸음 CLI를 캐시하며 부르고 경로 복원 API를 2000점씩 나눠 호출한다"
```

---

### Task 6: 설정 파일과 `python -m analysis.run`

**Files:**
- Create: `research/analysis/config.py`, `research/analysis/run.py`, `research/sessions.yaml`, `research/experiments.yaml`
- Test: `research/tests/test_config.py`, `research/tests/test_run.py`

**Interfaces:**
- Consumes: Task 1~5 전부. `run.main`은 그래프가 켜져 있을 때만 Task 7의 `analysis.plots.make_all(tables, fig_dir) -> list[Path]`를 안에서 import한다(이 태스크의 테스트는 `plots: false`·`--no-plots`라 Task 7 전에도 통과한다)
- Produces:
  - `load_sessions(path) -> list[dict]`(`id, use, course, carry, note`, `use` ∈ {pilot, eval, battery}, 중복 id는 ValueError)
  - `expand_runs(runs, default_ttff) -> list[RunSpec]` — `detector`·`params`·`detector_params`·`stay_params`·`ttff`의 목록을 모두 곱하고 같은 조합은 한 번만. bool은 `true`/`false` 문자열
  - `Experiment`(dataclass) 필드: `base, sessions_file, data_dir, results_dir, package_dir, dart, uses, runs, step_detectors, truth_max_accuracy_m, truth_min_hop_m, stay_min_truth_s, stay_min_overlap, stay_max_distance_m, local_straight, reconstruct{enabled, server_url, token, timeout_s, skip_all_fallback, methods[{name, method, hmm}]}, battery{use, current_units, align_steps, package}, tune{runs, betas, sigmas}, plots`
  - `load_experiment(path, data_dir=None, results_dir=None) -> Experiment`(상대 경로는 설정 파일 폴더 기준)
  - `run_experiment(exp, cli, client, only=None, force=False) -> dict[str, DataFrame]` 키 `path_metrics, stay_metrics, step_metrics, step_counts_by_carry, battery_runs, battery_summary, skipped`
  - `write_tables(tables, results_dir)`, `main(argv) -> int`(옵션 `--config --data-dir --results-dir --session --force --no-reconstruct --no-plots`)
  - 결과 폴더: `replay/<세션>/<RunSpec.key>/`, `steps/<세션>/<감지기>/`, `recon/<세션>/<key>/<방법 이름>.json`, `*.csv`, `figures/`

- [ ] **Step 1: 설정 파일 작성**

`research/sessions.yaml`(실제 세션 하나를 pilot으로 등록한다. 세션 폴더 자체는 커밋하지 않는다):

```yaml
# 세션 목록(설계 7-1). 세션 폴더는 research/data/sessions/<id>/에 둔다(커밋하지 않는다, 팀 드라이브로 공유).
#
# use
#   pilot   — 파라미터(β·σ 하한, 감지기, E 등)를 정할 때만 쓴다
#   eval    — 평가용. 파라미터를 정할 때 보지 않는다
#   battery — 배터리 실험(정책 실행 모드) 한 회. 방식은 meta.json의 policy로 정해진다
# course: 코스 요약(도보·실내 체류·버스·지하철), carry: 주된 휴대 위치(손·주머니·가방, 섞었으면 mixed)
sessions:
  - id: 20261109-213324-groundTruth
    use: pilot
    course: 골목 도보 약 7분 + 실내 정지 약 6분 (실기기 점검, 걸음 세기·탈것 표시 없음)
    carry: hand
    note: 머문 곳 정답(10분 이상) 없음
```

`research/experiments.yaml`:

```yaml
# R6 분석 설정(설계 7장). research/에서 `.venv/Scripts/python -m analysis.run --config experiments.yaml`.
# 경로는 이 파일이 있는 폴더(research/) 기준이다.
sessions: sessions.yaml
data_dir: data/sessions
results_dir: results
footstep_core: ../packages/footstep_core
# dart: C:/flutter/bin/dart.bat   # PATH에 dart가 없을 때만

use: [pilot, eval]          # 정확도 분석에 넣을 세션 용도
ttff: 0                     # 기본 측위 지연(초). 민감도는 아래 runs에서 ttff 목록으로 따로 돈다

truth:
  max_accuracy_m: 20        # 정확도 20m 이하 1초 GPS만 정답(설계 7-2)
  min_hop_m: 10             # 정답 이동거리: 마지막으로 센 점에서 10m 이상 벗어난 점만 잇는다(서 있는 동안 흔들림 제외)

stays:
  min_truth_stay_s: 600     # arrive~depart가 10분 이상이어야 정답 머문 곳(T와 같다)
  min_overlap: 0.5          # 겹친 시간이 두 머문 곳 각각의 50% 이상
  max_distance_m: 100       # 중심 거리

runs:                       # 정책 × 설정. 목록 값은 모든 조합으로 펼친다
  - policy: hourly
  - policy: continuous_10m
  - policy: fixed_30s
  - policy: fixed_1m
  - policy: fixed_5m
  - policy: speed_adaptive
  - policy: time_speed
    params: {e_m: [25, 50, 100]}
  - policy: still_suppress
  - policy: activity_gated
  - policy: step_budget
    detector: [os, adaptive]
    params: {e_m: [25, 50, 100]}
  # 절제 실험(설계 5-3·5-6)
  - policy: step_budget
    detector: adaptive
    params: {e_m: 50, use_steps: false}
  - policy: step_budget
    detector: adaptive
    params: {e_m: 50, suppress_still: false}
  - policy: step_budget
    detector: adaptive
    params: {e_m: 50, vehicle_probe: false}
  - policy: step_budget
    detector: adaptive
    params: {e_m: 50}
    stay_params: {use_still: false}
  # 측위 지연 민감도(설계 10장 위험 4)
  - policy: step_budget
    detector: adaptive
    params: {e_m: 50}
    ttff: [5, 10]
  - policy: fixed_1m
    ttff: [5, 10]

step_detectors: [os, brajdic, adaptive]

local_straight: true        # 서버 없이 남은 점을 직선으로 잇는 기준선(항상 돈다)

reconstruct:                # 로컬 서버 복원(route-guide). 서버가 꺼져 있으면 건너뛰고 skipped.csv에 남긴다
  enabled: true
  server_url: http://localhost:9090
  token: dev-fake-token     # local 프로필 더미 토큰
  timeout_s: 120
  skip_all_fallback: true   # 도로 맞춤 방법인데 모든 구간이 fallback(OSRM 꺼짐)이면 지표를 내지 않는다
  methods:
    - straight
    - nearest
    - osrm_match
    - osrm_match_radius
    - hmm_steps             # β·σ 하한은 analysis.tune으로 정한 뒤 아래처럼 고정한다
    - {name: hmm_nosteps, method: hmm_steps, hmm: {useSteps: false}}
    # - {name: hmm_steps_tuned, method: hmm_steps, hmm: {betaM: 10, sigmaMinM: 5}}

battery:
  use: [battery]
  align_steps: true         # 전하량 계단이 바뀐 행 사이로 잰다(device-check)
  current_units:            # current_ua 열의 실제 단위(기종마다 다르다). 없으면 uA
    samsung SM-S911N: mA
  package: com.travelfootsteps.app

tune:                       # `python -m analysis.tune` — pilot 세션만 쓴다
  runs:
    - policy: step_budget
      detector: adaptive
      params: {e_m: 50}
  betas: [2, 5, 10, 20, 50]
  sigmas: [3, 5, 10]

plots: true
```

- [ ] **Step 2: 실패하는 테스트 작성**

`research/tests/test_config.py`:

```python
from pathlib import Path

import pytest

from analysis.config import expand_runs, load_experiment, load_sessions
from analysis.replay import RunSpec

RESEARCH = Path(__file__).resolve().parents[1]


def test_expand_runs_grid_and_dedup():
    runs = expand_runs([
        {"policy": "step_budget", "detector": ["os", "adaptive"], "params": {"e_m": [25, 50], "use_steps": False}},
        {"policy": "fixed_1m", "ttff": [0, 5]},
        {"policy": "fixed_1m"},                               # 앞과 같은 조합은 한 번만
    ], default_ttff=0)
    assert len(runs) == 4 + 2
    assert runs[0] == RunSpec("step_budget", "os", (("e_m", "25"), ("use_steps", "false")), (), 0.0, ())
    assert [r.ttff for r in runs[4:]] == [0.0, 5.0]


def test_load_sessions_validates(tmp_path):
    p = tmp_path / "s.yaml"
    p.write_text("sessions:\n  - {id: a, use: pilot}\n  - {id: b, use: eval, course: x}\n", encoding="utf-8")
    assert [s["use"] for s in load_sessions(p)] == ["pilot", "eval"]
    p.write_text("sessions:\n  - {id: a, use: test}\n", encoding="utf-8")
    with pytest.raises(ValueError):
        load_sessions(p)
    p.write_text("sessions:\n  - {id: a, use: pilot}\n  - {id: a, use: eval}\n", encoding="utf-8")
    with pytest.raises(ValueError):
        load_sessions(p)


def test_repo_config_files_load():
    exp = load_experiment(RESEARCH / "experiments.yaml")
    assert exp.sessions_file == RESEARCH / "sessions.yaml"
    assert exp.data_dir == RESEARCH / "data" / "sessions"
    assert exp.truth_max_accuracy_m == 20
    assert {m["name"] for m in exp.reconstruct["methods"]} >= {"straight", "osrm_match_radius", "hmm_steps"}
    assert exp.tune["betas"] == [2, 5, 10, 20, 50] and exp.tune["sigmas"] == [3, 5, 10]
    assert any(r.policy == "step_budget" and r.detector == "adaptive" for r in exp.runs)
    assert all(s["use"] in {"pilot", "eval", "battery"} for s in load_sessions(exp.sessions_file))


def test_overrides(tmp_path):
    exp = load_experiment(RESEARCH / "experiments.yaml", data_dir=tmp_path / "d", results_dir=tmp_path / "r")
    assert exp.data_dir == tmp_path / "d" and exp.results_dir == tmp_path / "r"
```

`research/tests/test_run.py`:

```python
"""run_experiment 끝까지: 가짜 재생 CLI(파일만 쓴다)와 가짜 서버로 돈다. 실제 dart·서버는 부르지 않는다."""
import json
from pathlib import Path

import pytest

from analysis.config import load_experiment
from analysis.geo import offset
from analysis.reconstruct import ServerUnavailable
from analysis.run import main, run_experiment, write_tables
from conftest import LAT0, LNG0, T0, gps_row, make_session, write_csv


class FakeCli:
    """재생: 정답과 같은 직선 위의 점 3개(0·50·100초). steps: 걸음 10개."""

    def __init__(self):
        self.calls = []

    def replay(self, session_dir, spec, out, force=False):
        self.calls.append(("replay", spec.key))
        rows = []
        for k in (0, 50, 100):
            lat, lng = offset(LAT0, LNG0, k, 0)
            rows.append([T0 + k * 1000, lat, lng, 5.0, 10, "walking", "single"])
        write_csv(out / "fixes.csv", ["t_ms", "lat", "lng", "accuracy_m", "steps_since_prev", "state", "kind"], rows)
        write_csv(out / "stays.csv", ["arrive_ms", "leave_ms", "lat", "lng", "n_points"], [])
        (out / "summary.json").write_text(json.dumps({"total_fixes": 3, "fixes_per_hour": 108.0, "gps_on_s": 3.0,
                                                      "duration_s": 100.0}))
        return out

    def steps(self, session_dir, detector, out, detector_params=(), force=False):
        write_csv(out / "steps.csv", ["t_ms", "total_steps"], [[T0 + k * 1000, k + 1] for k in range(10)])
        write_csv(out / "step_states.csv", ["t_ms", "state", "cadence_hz"], [[T0, "walking", 1.0]])
        (out / "step_summary.json").write_text(json.dumps({
            "detector_id": detector, "total_steps": 10, "start_ms": T0, "end_ms": T0 + 100_000,
            "count_intervals": [{"start_ms": T0, "end_ms": T0 + 9000, "manual_steps": 8, "detected_steps": 10,
                                 "error_pct": 25.0}], "vehicle_intervals": []}))
        return out


class FakeClient:
    """straight는 북쪽 10m 평행선, osrm_match_radius는 모두 fallback(OSRM 꺼짐 흉내), hmm_steps는 서버 끊김."""

    def __init__(self):
        self.unavailable = False

    def reconstruct(self, fixes, stays, method, hmm=None):
        if method == "hmm_steps":
            raise ServerUnavailable("refused")
        a, b = offset(LAT0, LNG0, 0, 10), offset(LAT0, LNG0, 100, 10)
        return [{"kind": "walk", "coords": [{"lat": a[0], "lng": a[1]}, {"lat": b[0], "lng": b[1]}],
                 "fallback": method != "straight"}]


@pytest.fixture
def experiment(tmp_path):
    data = tmp_path / "data"
    make_session(data, "p1", gps=[gps_row(T0 + k * 1000, k, 0) for k in range(101)])
    make_session(data, "b1", battery=[[T0, 3_700_000, -150, 88, 30, 0], [T0 + 1_800_000, 3_696_300, -150, 88, 30, 0],
                                      [T0 + 3_600_000, 3_692_600, -150, 88, 30, 0]],
                 meta={"mode": "policy", "policy": {"policyId": "fixed_1m", "detectorId": "os"}})
    (tmp_path / "sessions.yaml").write_text(
        "sessions:\n  - {id: p1, use: pilot}\n  - {id: b1, use: battery}\n  - {id: gone, use: eval}\n",
        encoding="utf-8")
    (tmp_path / "experiments.yaml").write_text("""
sessions: sessions.yaml
data_dir: data
results_dir: results
runs:
  - policy: fixed_1m
step_detectors: [os]
truth: {min_hop_m: 0}
reconstruct:
  enabled: true
  methods: [straight, osrm_match_radius, hmm_steps]
plots: false
""", encoding="utf-8")
    return load_experiment(tmp_path / "experiments.yaml")


def test_run_experiment_end_to_end_with_fakes(experiment):
    cli = FakeCli()
    t = run_experiment(experiment, cli, FakeClient())
    p = t["path_metrics"].set_index("method")
    # local_straight: 점이 정답 직선 위 → 0m. straight: 10m 평행선 → 10m
    assert list(p.index) == ["local_straight", "straight"]
    assert p.loc["local_straight", "mean_m"] == pytest.approx(0.0, abs=0.01)
    assert p.loc["straight", "p95_m"] == pytest.approx(10.0, abs=0.01)
    assert p.loc["straight", "fixes_per_hour"] == 108.0
    reasons = " ".join(t["skipped"]["reason"])
    assert "fallback" in reasons and "refused" in reasons and "폴더 없음" in reasons
    assert t["stay_metrics"]["stays_detected"].tolist() == [0]
    assert t["step_metrics"]["count_error_pct"].tolist() == [25.0]
    assert t["step_counts_by_carry"]["carry"].tolist() == ["hand"]
    assert t["battery_runs"]["method"].tolist() == ["fixed_1m"]
    assert t["battery_summary"]["mah_per_h_mean"].iloc[0] == pytest.approx(7.4)
    write_tables(t, experiment.results_dir)
    assert (experiment.results_dir / "path_metrics.csv").exists()


def test_run_without_server_reports_local_only(experiment):
    t = run_experiment(experiment, FakeCli(), client=None)
    assert t["path_metrics"]["method"].tolist() == ["local_straight"]


def test_reconstruct_cache_is_reused(experiment):
    client = FakeClient()
    run_experiment(experiment, FakeCli(), client)
    cache = experiment.results_dir / "recon" / "p1" / "fixed_1m-os-ttff0" / "straight.json"
    assert cache.exists()
    client.reconstruct = lambda *a, **k: pytest.fail("캐시가 있으면 서버를 부르지 않는다")
    experiment.reconstruct["methods"] = [{"name": "straight", "method": "straight", "hmm": None}]
    t = run_experiment(experiment, FakeCli(), client)
    assert "straight" in t["path_metrics"]["method"].tolist()


def test_main_with_no_reconstruct(experiment, monkeypatch, capsys):
    import analysis.run as run_mod
    monkeypatch.setattr(run_mod, "DartCli", lambda *a, **k: FakeCli())
    code = main(["--config", str(experiment.base / "experiments.yaml"), "--no-reconstruct", "--no-plots"])
    assert code == 0
    assert "local_straight" in capsys.readouterr().out
```

- [ ] **Step 3: 실패 확인**

Run: `.venv/Scripts/python -m pytest tests/test_config.py tests/test_run.py`
Expected: FAIL — `No module named 'analysis.config'`

- [ ] **Step 4: 구현**

`research/analysis/config.py`:

```python
"""sessions.yaml·experiments.yaml 읽기(설계 7-1). 경로는 모두 설정 파일이 있는 폴더 기준이다."""
from __future__ import annotations

import itertools
from dataclasses import dataclass, field
from pathlib import Path

import yaml

from .replay import RunSpec

USES = {"pilot", "eval", "battery"}


def load_sessions(path: Path) -> list[dict]:
    """세션 목록. use는 pilot(파라미터 정하기)·eval(평가, 파라미터를 정할 때 보지 않는다)·battery(배터리 실험)."""
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}
    out = []
    for s in data.get("sessions") or []:
        if s.get("use") not in USES:
            raise ValueError(f"세션 {s.get('id')}: use는 {sorted(USES)} 중 하나여야 합니다")
        out.append({"id": str(s["id"]), "use": s["use"], "course": s.get("course"), "carry": s.get("carry"),
                    "note": s.get("note")})
    ids = [s["id"] for s in out]
    if len(ids) != len(set(ids)):
        raise ValueError("sessions.yaml에 같은 id가 두 번 있습니다")
    return out


def _as_list(v) -> list:
    if v is None:
        return [None]
    return list(v) if isinstance(v, (list, tuple)) else [v]


def _grid(d: dict | None) -> list[tuple]:
    """{k: 값 또는 값 목록} → 모든 조합의 (이름, 값) 튜플 목록. 값은 CLI에 그대로 넘기려고 문자열로 바꾼다."""
    if not d:
        return [()]
    keys = sorted(d)
    combos = itertools.product(*[_as_list(d[k]) for k in keys])
    return [tuple((k, _str(v)) for k, v in zip(keys, combo)) for combo in combos]


def _str(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)


def expand_runs(runs: list[dict], default_ttff) -> list[RunSpec]:
    """runs 항목마다 detector·params·detector_params·stay_params·ttff의 목록을 모두 곱해 재생 설정을 만든다."""
    out: list[RunSpec] = []
    for r in runs:
        for det, p, dp, sp, ttff in itertools.product(
                _as_list(r.get("detector", "os")), _grid(r.get("params")), _grid(r.get("detector_params")),
                _grid(r.get("stay_params")), _as_list(r.get("ttff", default_ttff))):
            spec = RunSpec(r["policy"], det or "os", p, dp, float(ttff or 0), sp)
            if spec not in out:
                out.append(spec)
    return out


def _methods(items) -> list[dict]:
    """복원 방법. 문자열이면 그 method, 사전이면 {name, method, hmm}(같은 method를 조정값만 바꿔 여러 번 쓸 때)."""
    out = []
    for m in items or []:
        if isinstance(m, str):
            out.append({"name": m, "method": m, "hmm": None})
        else:
            out.append({"name": m.get("name", m["method"]), "method": m["method"], "hmm": m.get("hmm")})
    return out


@dataclass
class Experiment:
    base: Path
    sessions_file: Path
    data_dir: Path
    results_dir: Path
    package_dir: Path
    dart: str | None
    uses: list[str]
    runs: list[RunSpec]
    step_detectors: list[str]
    truth_max_accuracy_m: float = 20
    truth_min_hop_m: float = 10
    stay_min_truth_s: float = 600
    stay_min_overlap: float = 0.5
    stay_max_distance_m: float = 100
    local_straight: bool = True
    reconstruct: dict = field(default_factory=dict)
    battery: dict = field(default_factory=dict)
    tune: dict = field(default_factory=dict)
    plots: bool = True


def load_experiment(path: Path, data_dir: Path | None = None, results_dir: Path | None = None) -> Experiment:
    path = Path(path).resolve()
    base = path.parent
    c = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    truth = c.get("truth") or {}
    stays = c.get("stays") or {}
    rec = c.get("reconstruct") or {}
    bat = c.get("battery") or {}
    tune = c.get("tune") or {}
    ttff = c.get("ttff", 0)
    return Experiment(
        base=base,
        sessions_file=base / c.get("sessions", "sessions.yaml"),
        data_dir=Path(data_dir) if data_dir else base / c.get("data_dir", "data/sessions"),
        results_dir=Path(results_dir) if results_dir else base / c.get("results_dir", "results"),
        package_dir=base / c.get("footstep_core", "../packages/footstep_core"),
        dart=c.get("dart"),
        uses=list(c.get("use", ["pilot", "eval"])),
        runs=expand_runs(c.get("runs") or [], ttff),
        step_detectors=list(c.get("step_detectors", ["os", "brajdic", "adaptive"])),
        truth_max_accuracy_m=float(truth.get("max_accuracy_m", 20)),
        truth_min_hop_m=float(truth.get("min_hop_m", 10)),
        stay_min_truth_s=float(stays.get("min_truth_stay_s", 600)),
        stay_min_overlap=float(stays.get("min_overlap", 0.5)),
        stay_max_distance_m=float(stays.get("max_distance_m", 100)),
        local_straight=bool(c.get("local_straight", True)),
        reconstruct={"enabled": bool(rec.get("enabled", False)),
                     "server_url": rec.get("server_url", "http://localhost:9090"),
                     "token": rec.get("token", "dev-fake-token"),
                     "timeout_s": float(rec.get("timeout_s", 120)),
                     "skip_all_fallback": bool(rec.get("skip_all_fallback", True)),
                     "methods": _methods(rec.get("methods", ["straight", "osrm_match_radius", "hmm_steps"]))},
        battery={"use": list(bat.get("use", ["battery"])),
                 "current_units": dict(bat.get("current_units") or {}),
                 "align_steps": bool(bat.get("align_steps", True)),
                 "package": bat.get("package", "com.travelfootsteps.app")},
        tune={"runs": expand_runs(tune.get("runs") or [], ttff),
              "betas": [float(b) for b in tune.get("betas", [2, 5, 10, 20, 50])],
              "sigmas": [float(s) for s in tune.get("sigmas", [3, 5, 10])]},
        plots=bool(c.get("plots", True)),
    )
```

`research/analysis/run.py`:

```python
"""`python -m analysis.run --config experiments.yaml` (research/에서). 설계 7-1의 순서대로 돈다.

1. 세션마다 재생 CLI(정책 × 설정)와 steps CLI(감지기마다)
2. 복원: 서버 없이 local_straight, 켜 두었으면 로컬 서버 POST /api/route/reconstruct(방법마다)
3. 지표 계산 → results/*.csv, 그래프 → results/figures/
서버에 연결하지 못하면 그 뒤 복원 호출은 건너뛰고, 돈 방법의 지표만 남긴다(skipped.csv에 이유).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import pandas as pd

from .battery import battery_run, battery_summary
from .config import Experiment, load_experiment, load_sessions
from .path_metrics import local_straight, path_metrics
from .reconstruct import ReconstructClient, ReconstructError, ServerUnavailable, read_fixes
from .replay import CliError, DartCli
from .session import load_session, truth_points, vehicle_intervals
from .stay_metrics import read_stays, stay_scores, truth_stays
from .step_metrics import count_rows_by_carry, read_steps_output, step_metrics

LOCAL = "local_straight"


def _segments(method: dict, fixes, stays, client, cache: Path, force: bool) -> list[dict]:
    """복원 경로. 서버 응답은 cache(JSON)에 남겨 다음 실행에서 다시 부르지 않는다(지표만 고칠 때)."""
    if method["method"] == LOCAL:
        return local_straight(fixes)
    if cache.exists() and not force:
        return json.loads(cache.read_text(encoding="utf-8"))
    segments = client.reconstruct(fixes, stays, method["method"], method["hmm"])
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(segments), encoding="utf-8")
    return segments


def _all_fallback(method: dict, segments: list[dict]) -> bool:
    """도로에 맞추는 방법인데 모든 구간이 fallback이면 사실상 직선이다. 그 이름으로 지표를 내면 오해를 부른다."""
    return method["method"] not in (LOCAL, "straight") and bool(segments) and         all(seg.get("fallback") for seg in segments)


def run_experiment(exp: Experiment, cli: DartCli, client: ReconstructClient | None,
                   only: list[str] | None = None, force: bool = False) -> dict[str, pd.DataFrame]:
    sessions = load_sessions(exp.sessions_file)
    methods = ([{"name": LOCAL, "method": LOCAL, "hmm": None}] if exp.local_straight else []) + \
        (exp.reconstruct["methods"] if client is not None else [])
    path_rows, stay_rows, step_rows, carry_rows, skipped, battery_rows = [], [], [], [], [], []

    for s in sessions:
        if only and s["id"] not in only:
            continue
        sdir = exp.data_dir / s["id"]
        if not sdir.is_dir():
            skipped.append({"session": s["id"], "what": "session", "reason": f"폴더 없음: {sdir}"})
            continue
        if s["use"] in exp.battery["use"]:
            battery_rows.append({**battery_run(sdir, exp.battery["current_units"], exp.battery["align_steps"],
                                               exp.battery["package"]), "use": s["use"]})
        if s["use"] not in exp.uses:
            continue
        session = load_session(sdir)
        truth = truth_points(session.gps, exp.truth_max_accuracy_m)
        vehicles = vehicle_intervals(session)
        gt_stays = truth_stays(session, truth, exp.stay_min_truth_s)
        base = {"session": s["id"], "use": s["use"], "course": s["course"]}

        for spec in exp.runs:
            out = exp.results_dir / "replay" / s["id"] / spec.key
            try:
                cli.replay(sdir, spec, out, force)
            except CliError as e:
                skipped.append({"session": s["id"], "what": spec.label, "reason": str(e)})
                continue
            summary = json.loads((out / "summary.json").read_text(encoding="utf-8"))
            fixes = read_fixes(out)
            stays = read_stays(out)
            run_info = {**base, "run": spec.label, "policy": spec.policy, "detector": spec.detector,
                        "params": " ".join(f"{k}={v}" for k, v in spec.params), "ttff": spec.ttff,
                        "fixes": summary.get("total_fixes"), "fixes_per_hour": summary.get("fixes_per_hour"),
                        "gps_on_s": summary.get("gps_on_s"), "duration_s": summary.get("duration_s")}
            stay_rows.append({**run_info, **stay_scores(stays, gt_stays, exp.stay_min_overlap,
                                                        exp.stay_max_distance_m)})
            for m in methods:
                cache = exp.results_dir / "recon" / s["id"] / spec.key / f"{m['name']}.json"
                try:
                    segs = _segments(m, fixes, stays, client, cache, force)
                except (ServerUnavailable, ReconstructError) as e:
                    skipped.append({"session": s["id"], "what": f"{spec.label} / {m['name']}", "reason": str(e)})
                    continue
                if _all_fallback(m, segs) and exp.reconstruct["skip_all_fallback"]:
                    skipped.append({"session": s["id"], "what": f"{spec.label} / {m['name']}",
                                    "reason": "모든 구간이 직선 대체(fallback) — OSRM이 꺼져 있는 것 같다"})
                    continue
                path_rows.append({**run_info, "method": m["name"],
                                  **path_metrics(truth, segs, vehicles, exp.truth_min_hop_m)})

        for det in exp.step_detectors:
            out = exp.results_dir / "steps" / s["id"] / det
            try:
                cli.steps(sdir, det, out, force=force)
            except CliError as e:
                skipped.append({"session": s["id"], "what": f"steps {det}", "reason": str(e)})
                continue
            step_rows.append({**base, **step_metrics(session, out)})
            _, _, summary = read_steps_output(out)
            carry_rows += [{**base, "detector": det, **r} for r in count_rows_by_carry(session, summary)]

    runs = pd.DataFrame(battery_rows)
    return {"path_metrics": pd.DataFrame(path_rows), "stay_metrics": pd.DataFrame(stay_rows),
            "step_metrics": pd.DataFrame(step_rows), "step_counts_by_carry": pd.DataFrame(carry_rows),
            "battery_runs": runs, "battery_summary": battery_summary(runs),
            "skipped": pd.DataFrame(skipped, columns=["session", "what", "reason"])}


def write_tables(tables: dict[str, pd.DataFrame], results_dir: Path) -> None:
    results_dir.mkdir(parents=True, exist_ok=True)
    for name, df in tables.items():
        df.to_csv(results_dir / f"{name}.csv", index=False, encoding="utf-8")


def _print_summary(tables: dict[str, pd.DataFrame]) -> None:
    p = tables["path_metrics"]
    if not p.empty:
        cols = ["session", "run", "method", "fixes", "gps_on_s", "mean_m", "p95_m", "dist_err_pct", "fallback_share"]
        print(p[cols].to_string(index=False, float_format=lambda v: f"{v:.1f}"))
    for name in ["stay_metrics", "step_metrics", "battery_summary"]:
        if not tables[name].empty:
            print(f"\n[{name}] {len(tables[name])}행")
    if not tables["skipped"].empty:
        print(f"\n건너뜀 {len(tables['skipped'])}건 (skipped.csv)")


def _utf8_console() -> None:
    """Git Bash 터미널(UTF-8)에서 한글이 깨지지 않게 출력 인코딩을 UTF-8로 맞춘다."""
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m analysis.run", description="R6 분석 실행(설계 7-1)")
    ap.add_argument("--config", default="experiments.yaml")
    ap.add_argument("--data-dir", help="세션 폴더들의 상위 폴더(기본: 설정의 data_dir)")
    ap.add_argument("--results-dir", help="결과 폴더(기본: 설정의 results_dir)")
    ap.add_argument("--session", action="append", help="이 세션만(여러 번 줄 수 있다)")
    ap.add_argument("--force", action="store_true", help="재생·복원 캐시를 무시하고 다시 돈다")
    ap.add_argument("--no-reconstruct", action="store_true", help="서버 복원을 건너뛴다(local_straight만)")
    ap.add_argument("--no-plots", action="store_true")
    a = ap.parse_args(argv)
    _utf8_console()
    exp = load_experiment(Path(a.config), a.data_dir, a.results_dir)
    cli = DartCli(exp.package_dir, exp.dart)
    rec = exp.reconstruct
    client = None if a.no_reconstruct or not rec["enabled"] else \
        ReconstructClient(rec["server_url"], rec["token"], rec["timeout_s"])
    tables = run_experiment(exp, cli, client, a.session, a.force)
    write_tables(tables, exp.results_dir)
    if exp.plots and not a.no_plots:
        from .plots import make_all
        for f in make_all(tables, exp.results_dir / "figures"):
            print(f"그림: {f}")
    _print_summary(tables)
    print(f"\n결과: {exp.results_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 5: 통과 확인**

Run: `.venv/Scripts/python -m pytest`
Expected: PASS — `55 passed`

- [ ] **Step 6: 커밋**

```bash
git status --short          # research/results, research/data가 없어야 한다
git add research/analysis/config.py research/analysis/run.py research/sessions.yaml research/experiments.yaml research/tests/test_config.py research/tests/test_run.py
git commit -m "feat(research): experiments.yaml대로 재생·복원·지표를 돌리는 python -m analysis.run을 만든다"
```

---

### Task 7: β·σ 하한 격자 탐색과 그래프 5종

**Files:**
- Create: `research/analysis/tune.py`, `research/analysis/plots.py`
- Test: `research/tests/test_tune.py`, `research/tests/test_plots.py`

**Interfaces:**
- Consumes: Task 4의 `method_label`, Task 5의 `DartCli`·`ReconstructClient`·`ServerUnavailable`·`ReconstructError`·`read_fixes`, Task 3의 `read_stays`, Task 2의 `path_metrics`, Task 6의 `load_experiment`·`load_sessions`와 `run_experiment`가 돌려주는 표(열 이름: `path_metrics`의 `use, run, policy, detector, params, ttff, method, fixes_per_hour, p95_m`, `stay_metrics`의 `use, run, stay_f1`, `step_metrics`의 `use, detector, count_abs_error_pct, vehicle_false_steps`, `battery_summary`의 `method, n, mah_per_h_mean, mah_per_h_std`)
- Produces:
  - `grid_search(evaluate, betas, sigmas) -> (DataFrame[betaM, sigmaMinM, sessions, p95_mean_m], best dict)` — `evaluate(β, σ)`는 세션별 P95 목록
  - `tune.main(argv, cli=None, client=None) -> int`(0 성공, 1 pilot 없음·tune.runs 없음, 2 서버·OSRM 없음). 결과 `hmm_grid.csv`, `hmm_grid_by_session.csv`, `hmm_best.json`
  - `pick_method(df) -> str`, `family(policy, detector) -> str`, `main_runs(df) -> DataFrame`
  - `plot_tradeoff(path, out, x="fixes_per_hour", battery=None)`, `plot_battery(summary, out)`, `plot_stay_f1(stays, out)`, `plot_steps(steps, out)`, `plot_reconstruct(path, out)` — 그린 파일 경로 또는 그릴 값이 없으면 None
  - `make_all(tables, fig_dir) -> list[Path]` — `1_tradeoff_fixes.png, 1_tradeoff_mah.png, 2_battery.png, 3_stay_f1.png, 4_steps.png, 5_reconstruct.png` 중 그린 것

그래프 규칙(설계 7-3): 범주 색은 정해 둔 8색을 순서대로만 쓰고 넘치면 회색 '기타'로 묶는다. 두 값의 단위가 다르면 y축을 둘 두지 않고 그래프를 나눈다(4번). eval 행이 있으면 eval만 그리고 제목에 '평가용/예비용'을 적는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`research/tests/test_tune.py`:

```python
import json

import pandas as pd
import pytest

from analysis.geo import offset
from analysis.reconstruct import ServerUnavailable
from analysis.tune import grid_search, main
from conftest import LAT0, LNG0, T0, gps_row, make_session, write_csv


def test_grid_search_picks_min_mean_p95_and_breaks_ties_small():
    # P95 = |β − 10| + σ  → β=10, σ=3이 최소(3). 세션 둘 다 같은 값
    table, best = grid_search(lambda b, s: [abs(b - 10) + s] * 2, [2, 5, 10, 20, 50], [3, 5, 10])
    assert len(table) == 15
    assert best == {"betaM": 10.0, "sigmaMinM": 3.0, "p95_mean_m": 3.0, "sessions": 2}
    _, tie = grid_search(lambda b, s: [1.0], [5, 2], [5, 3])
    assert (tie["betaM"], tie["sigmaMinM"]) == (2.0, 3.0)
    _, none = grid_search(lambda b, s: [None], [1], [1])
    assert none == {}


class _Cli:
    def replay(self, session_dir, spec, out, force=False):
        rows = []
        for k in (0, 100):
            lat, lng = offset(LAT0, LNG0, k, 0)
            rows.append([T0 + k * 1000, lat, lng, 5.0, 100, "walking", "single"])
        write_csv(out / "fixes.csv", ["t_ms", "lat", "lng", "accuracy_m", "steps_since_prev", "state", "kind"], rows)
        return out


class _Client:
    """β가 10에서 멀수록 북쪽으로 밀린 평행선을 돌려준다 → β=10이 최선."""

    def __init__(self, fallback=False):
        self.seen, self.fallback = [], fallback

    def reconstruct(self, fixes, stays, method, hmm=None):
        self.seen.append((method, hmm))
        n = abs(hmm["betaM"] - 10) + hmm["sigmaMinM"]
        a, b = offset(LAT0, LNG0, 0, n), offset(LAT0, LNG0, 100, n)
        return [{"kind": "walk", "coords": [{"lat": a[0], "lng": a[1]}, {"lat": b[0], "lng": b[1]}],
                 "fallback": self.fallback}]


def _setup(tmp_path):
    make_session(tmp_path / "data", "p1", gps=[gps_row(T0 + k * 1000, k, 0) for k in range(101)])
    make_session(tmp_path / "data", "e1", gps=[gps_row(T0, 0, 0)])
    (tmp_path / "sessions.yaml").write_text("sessions:\n  - {id: p1, use: pilot}\n  - {id: e1, use: eval}\n",
                                            encoding="utf-8")
    (tmp_path / "experiments.yaml").write_text(
        "data_dir: data\nresults_dir: results\ntune:\n  runs:\n    - {policy: step_budget, params: {e_m: 50}}\n",
        encoding="utf-8")
    return ["--config", str(tmp_path / "experiments.yaml")]


def test_main_uses_pilot_only_and_writes_best(tmp_path):
    args = _setup(tmp_path)
    client = _Client()
    assert main(args, cli=_Cli(), client=client) == 0
    assert len(client.seen) == 15 and all(m == "hmm_steps" for m, _ in client.seen)   # pilot 1개 × 15
    best = json.loads((tmp_path / "results" / "hmm_best.json").read_text())
    assert best["betaM"] == 10.0 and best["sigmaMinM"] == 3.0
    assert best["p95_mean_m"] == pytest.approx(3.0, abs=0.01)
    by_session = pd.read_csv(tmp_path / "results" / "hmm_grid_by_session.csv")
    assert set(by_session["session"]) == {"p1"}


def test_main_refuses_when_osrm_is_down(tmp_path, capsys):
    args = _setup(tmp_path)
    assert main(args, cli=_Cli(), client=_Client(fallback=True)) == 2
    assert "fallback" in capsys.readouterr().err


def test_main_without_pilot(tmp_path):
    (tmp_path / "sessions.yaml").write_text("sessions: []\n", encoding="utf-8")
    (tmp_path / "experiments.yaml").write_text("data_dir: data\n", encoding="utf-8")
    assert main(["--config", str(tmp_path / "experiments.yaml")]) == 1
```

`research/tests/test_plots.py`:

```python
import pandas as pd

from analysis.plots import make_all, plot_reconstruct, plot_tradeoff


def _path_rows():
    rows = []
    for run, policy, params, fph in [("fixed_1m", "fixed_1m", "", 60.0),
                                     ("step_budget[os] e_m=50", "step_budget", "e_m=50", 70.0)]:
        for method, p95 in [("local_straight", 20.0), ("straight", 18.0)]:
            rows.append({"session": "p1", "use": "pilot", "run": run, "policy": policy, "detector": "os",
                         "params": params, "ttff": 0.0, "method": method, "fixes_per_hour": fph, "p95_m": p95})
    return pd.DataFrame(rows)


def _tables(**over):
    t = {"path_metrics": _path_rows(),
         "stay_metrics": pd.DataFrame([{"use": "pilot", "run": "fixed_1m", "stay_f1": 0.5}]),
         "step_metrics": pd.DataFrame([{"use": "pilot", "detector": "os", "count_abs_error_pct": 5.0,
                                        "vehicle_false_steps": None}]),
         "battery_summary": pd.DataFrame([{"method": "fixed_1m", "n": 3, "mah_per_h_mean": 180.0,
                                           "mah_per_h_std": 5.0}])}
    t.update(over)
    return t


def test_make_all_writes_six_pngs(tmp_path):
    files = make_all(_tables(), tmp_path)
    assert [f.name for f in files] == ["1_tradeoff_fixes.png", "1_tradeoff_mah.png", "2_battery.png",
                                       "3_stay_f1.png", "4_steps.png", "5_reconstruct.png"]
    assert all(f.stat().st_size > 1000 for f in files)


def test_plots_skip_when_no_data(tmp_path):
    empty = pd.DataFrame(columns=["use", "run", "policy", "detector", "params", "ttff", "method", "p95_m",
                                  "fixes_per_hour"])
    files = make_all(_tables(path_metrics=empty, stay_metrics=pd.DataFrame(columns=["use", "run", "stay_f1"]),
                             step_metrics=pd.DataFrame(), battery_summary=pd.DataFrame(columns=["method"])), tmp_path)
    assert files == []


def test_reconstruct_plot_needs_two_methods(tmp_path):
    one = _path_rows()
    one = one[one["method"] == "local_straight"]
    assert plot_reconstruct(one, tmp_path / "x.png") is None
    assert plot_tradeoff(one, tmp_path / "t.png") is not None


def test_pick_method_prefers_coverage_then_order():
    from analysis.plots import pick_method
    df = pd.DataFrame([{"run": "a", "method": "hmm_steps", "p95_m": 1.0},
                       {"run": "a", "method": "straight", "p95_m": 2.0},
                       {"run": "b", "method": "straight", "p95_m": 2.0},
                       {"run": "b", "method": "local_straight", "p95_m": 2.0},
                       {"run": "a", "method": "local_straight", "p95_m": 2.0}])
    assert pick_method(df) == "straight"          # 두 재생에 다 있는 것 중 PREFERRED가 앞선 것
    assert pick_method(df[df["run"] == "a"]) == "hmm_steps"


def test_family_and_main_runs():
    from analysis.plots import family, main_runs
    assert family("hourly", "os") == family("continuous_10m", "os") == "현재 앱"
    assert family("fixed_5m", "os") == "fixed"
    assert family("step_budget", "adaptive") == "step_budget[adaptive]"
    df = pd.DataFrame([
        {"run": "step_budget[adaptive] e_m=50", "policy": "step_budget", "detector": "adaptive", "params": "e_m=50",
         "ttff": 0.0},
        {"run": "step_budget[adaptive] e_m=50 use_steps=false", "policy": "step_budget", "detector": "adaptive",
         "params": "e_m=50 use_steps=false", "ttff": 0.0},
        {"run": "step_budget[adaptive] e_m=50 stay.use_still=false", "policy": "step_budget",
         "detector": "adaptive", "params": "e_m=50", "ttff": 0.0},
        {"run": "fixed_1m ttff=5", "policy": "fixed_1m", "detector": "os", "params": "", "ttff": 5.0},
        {"run": "fixed_1m", "policy": "fixed_1m", "detector": "os", "params": "", "ttff": 0.0},
    ])
    assert main_runs(df)["run"].tolist() == ["step_budget[adaptive] e_m=50", "fixed_1m"]
```

- [ ] **Step 2: 실패 확인**

Run: `.venv/Scripts/python -m pytest tests/test_tune.py tests/test_plots.py`
Expected: FAIL — `No module named 'analysis.tune'`(그리고 `plots`)

- [ ] **Step 3: 구현**

`research/analysis/tune.py`:

```python
"""`python -m analysis.tune --config experiments.yaml` — hmm_steps의 β·σ 하한 격자 탐색(설계 6-3, route-guide 5절).

예비용(pilot) 세션만 쓴다. 평가용(eval) 세션을 보고 고르면 결과가 부풀려진다(설계 7-1).
β ∈ {2, 5, 10, 20, 50}m × σ 하한 ∈ {3, 5, 10}m마다 복원해 경로 오차 P95(세션 평균)가 가장 작은 조합을 고른다.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Callable

import numpy as np
import pandas as pd

from .config import load_experiment, load_sessions
from .path_metrics import path_metrics
from .reconstruct import ReconstructClient, ReconstructError, ServerUnavailable, read_fixes
from .replay import DartCli
from .session import load_session, truth_points, vehicle_intervals
from .stay_metrics import read_stays


def grid_search(evaluate: Callable[[float, float], list[float]], betas: list[float],
                sigmas: list[float]) -> tuple[pd.DataFrame, dict]:
    """evaluate(β, σ)는 세션마다 P95(m) 목록을 돌려준다. 가장 작은 평균 P95, 같으면 작은 β·σ를 고른다."""
    rows = []
    for b in betas:
        for s in sigmas:
            p95s = [v for v in evaluate(b, s) if v is not None]
            rows.append({"betaM": b, "sigmaMinM": s, "sessions": len(p95s),
                         "p95_mean_m": float(np.mean(p95s)) if p95s else None})
    table = pd.DataFrame(rows)
    ok = table.dropna(subset=["p95_mean_m"])
    if ok.empty:
        return table, {}
    best = ok.sort_values(["p95_mean_m", "betaM", "sigmaMinM"], kind="stable").iloc[0]
    return table, {"betaM": float(best["betaM"]), "sigmaMinM": float(best["sigmaMinM"]),
                   "p95_mean_m": float(best["p95_mean_m"]), "sessions": int(best["sessions"])}


def _utf8_console() -> None:
    """Git Bash 터미널(UTF-8)에서 한글이 깨지지 않게 출력 인코딩을 UTF-8로 맞춘다."""
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")


def main(argv: list[str] | None = None, cli=None, client=None) -> int:
    ap = argparse.ArgumentParser(prog="python -m analysis.tune", description="hmm_steps β·σ 하한 격자 탐색(pilot만)")
    ap.add_argument("--config", default="experiments.yaml")
    ap.add_argument("--data-dir")
    ap.add_argument("--results-dir")
    a = ap.parse_args(argv)
    _utf8_console()
    exp = load_experiment(Path(a.config), a.data_dir, a.results_dir)
    pilots = [s for s in load_sessions(exp.sessions_file) if s["use"] == "pilot"
              and (exp.data_dir / s["id"]).is_dir()]
    if not pilots:
        print("pilot 세션이 없습니다(sessions.yaml의 use: pilot, 폴더 있음).", file=sys.stderr)
        return 1
    if not exp.tune["runs"]:
        print("experiments.yaml의 tune.runs가 비어 있습니다.", file=sys.stderr)
        return 1
    cli = cli or DartCli(exp.package_dir, exp.dart)
    rec = exp.reconstruct
    client = client or ReconstructClient(rec["server_url"], rec["token"], rec["timeout_s"])

    inputs = []   # (세션 id, 재생 이름, 정답, 탈것 구간, 점, 머문 곳)
    for s in pilots:
        session = load_session(exp.data_dir / s["id"])
        truth = truth_points(session.gps, exp.truth_max_accuracy_m)
        for spec in exp.tune["runs"]:
            out = cli.replay(exp.data_dir / s["id"], spec, exp.results_dir / "replay" / s["id"] / spec.key)
            inputs.append((s["id"], spec.label, truth, vehicle_intervals(session), read_fixes(out), read_stays(out)))

    detail = []

    def evaluate(beta: float, sigma: float) -> list[float]:
        out = []
        for sid, label, truth, vehicles, fixes, stays in inputs:
            segs = client.reconstruct(fixes, stays, "hmm_steps", {"betaM": beta, "sigmaMinM": sigma})
            if segs and all(seg.get("fallback") for seg in segs):
                raise ServerUnavailable("모든 구간이 fallback — OSRM이 꺼져 있어 β·σ를 비교할 수 없다")
            p95 = path_metrics(truth, segs, vehicles, exp.truth_min_hop_m)["p95_m"]
            detail.append({"session": sid, "run": label, "betaM": beta, "sigmaMinM": sigma, "p95_m": p95})
            out.append(p95)
        return out

    try:
        table, best = grid_search(evaluate, exp.tune["betas"], exp.tune["sigmas"])
    except (ServerUnavailable, ReconstructError) as e:
        print(f"복원 서버를 쓸 수 없습니다: {e}", file=sys.stderr)
        return 2
    exp.results_dir.mkdir(parents=True, exist_ok=True)
    table.to_csv(exp.results_dir / "hmm_grid.csv", index=False)
    pd.DataFrame(detail).to_csv(exp.results_dir / "hmm_grid_by_session.csv", index=False)
    (exp.results_dir / "hmm_best.json").write_text(json.dumps(best, indent=2), encoding="utf-8")
    print(table.to_string(index=False))
    print(f"\n고른 값: {best}  → experiments.yaml reconstruct.methods에 고정한다")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

`research/analysis/plots.py`:

```python
"""그래프 5종(설계 7-3). 값이 없는 그래프는 만들지 않는다. 평가용(eval) 행이 있으면 그것만, 없으면 예비용으로 그리고 제목에 적는다."""
from __future__ import annotations

import re
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import pandas as pd  # noqa: E402
from matplotlib import font_manager  # noqa: E402

from .battery import method_label  # noqa: E402

# 범주 색은 정해 둔 순서로만 쓴다(같은 방법은 그래프마다 같은 색).
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"]
OTHER = "#8a8a85"   # 8개를 넘는 계열은 새 색을 만들지 않고 '기타' 회색으로 묶는다
INK, MUTED, GRID = "#1f1f1e", "#6b6a64", "#e4e3de"
# 배터리–오차 곡선의 계열(정책 묶음). 같은 계열의 E·주기 변형을 한 선으로 잇는다.
FAMILY_ORDER = ["step_budget[adaptive]", "step_budget[os]", "현재 앱", "fixed", "time_speed", "speed_adaptive",
                "still_suppress[os]", "activity_gated"]
METHOD_ORDER = ["local_straight", "straight", "nearest", "osrm_match", "osrm_match_radius", "hmm_steps", "hmm_nosteps"]
PREFERRED = ["hmm_steps", "osrm_match_radius", "straight", "local_straight"]

# 한글 글꼴: 이 PC에 있는 것만 넣는다(없는 이름을 넣으면 그릴 때마다 경고가 난다).
_FONTS = {f.name for f in font_manager.fontManager.ttflist}
plt.rcParams.update({
    "font.family": [f for f in ["Malgun Gothic", "AppleGothic", "NanumGothic"] if f in _FONTS] + ["DejaVu Sans"],
    "axes.unicode_minus": False, "axes.edgecolor": MUTED, "axes.labelcolor": INK, "text.color": INK,
    "xtick.color": MUTED, "ytick.color": MUTED, "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.8,
    "axes.spines.top": False, "axes.spines.right": False, "figure.dpi": 120, "savefig.bbox": "tight",
})


def _scope(df: pd.DataFrame) -> tuple[pd.DataFrame, str]:
    if df.empty or "use" not in df:
        return df, ""
    if (df["use"] == "eval").any():
        return df[df["use"] == "eval"], "평가용"
    return df, "예비용"


def _color(i: int) -> str:
    return SERIES[i] if i < len(SERIES) else OTHER


def family(policy: str, detector: str) -> str:
    """현재 앱 방식(hourly·continuous_10m)과 고정 주기 셋은 한 계열로 묶는다."""
    if policy in ("hourly", "continuous_10m"):
        return "현재 앱"
    if policy.startswith("fixed_"):
        return "fixed"
    return method_label(policy, detector)


def main_runs(df: pd.DataFrame) -> pd.DataFrame:
    """곡선에는 본 실험만 넣는다: ttff 0, 파라미터가 없거나 e_m 하나뿐이고 감지기·머문 곳 설정을 바꾸지 않은 재생.
    절제 실험·ttff 민감도는 표(path_metrics.csv)로 본다."""
    def is_main(r) -> bool:
        params = r["params"] if isinstance(r["params"], str) else ""
        if r["ttff"] != 0 or not re.fullmatch(r"(e_m=\S+)?", params):
            return False
        return r["run"] == (method_label(r["policy"], r["detector"]) + (f" {params}" if params else ""))
    return df[df.apply(is_main, axis=1)] if not df.empty else df


def _save(fig, out: Path) -> Path:
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out)
    plt.close(fig)
    return out


def pick_method(df: pd.DataFrame) -> str:
    """곡선에 쓸 복원 방법: 지표가 나온 재생이 가장 많은 방법, 같으면 PREFERRED 순서(제안 → 앱 기본 → 직선)."""
    covered = df.dropna(subset=["p95_m"]).groupby("method")["run"].nunique()
    rank = {m: k for k, m in enumerate(PREFERRED)}
    return sorted(covered.index, key=lambda m: (-covered[m], rank.get(m, len(rank)), m))[0]


def plot_tradeoff(path: pd.DataFrame, out: Path, x: str = "fixes_per_hour", battery: pd.DataFrame | None = None):
    """1. 배터리–오차 곡선: 계열마다 (시간당 측위 횟수 또는 실기기 mAh, 경로 오차 P95)를 x순으로 잇는다.
    복원 방법은 하나만 쓴다(pick_method). y는 시간 단위 측위(hourly)의 수백 m와 나머지 수 m가 함께 보이게 로그 눈금이다."""
    df, scope = _scope(path)
    if df.empty or df["p95_m"].isna().all():
        return None
    method = pick_method(df)
    df = main_runs(df[df["method"] == method])
    g = df.groupby(["run", "policy", "detector"], sort=True).agg(x=(x, "mean"), y=("p95_m", "mean")).reset_index()
    xlabel = "시간당 측위 횟수"
    if battery is not None:
        if battery.empty:
            return None
        g = g.merge(battery.rename(columns={"method": "run"}), on="run")
        g["x"] = g["mah_per_h_mean"]
        xlabel = "시간당 mAh (실기기)"
    g = g.dropna(subset=["x", "y"])
    if g.empty:
        return None
    g["family"] = [family(p, d) for p, d in zip(g["policy"], g["detector"])]
    names = [f for f in FAMILY_ORDER if f in set(g["family"])] + sorted(set(g["family"]) - set(FAMILY_ORDER))
    fig, ax = plt.subplots(figsize=(8, 5))
    for i, name in enumerate(names):
        f = g[g["family"] == name].sort_values("x")
        color = _color(i)
        label = name if i < len(SERIES) else f"기타: {name}"
        # 현재 앱 계열은 서로 다른 두 방식(1시간 주기·연속)이라 선으로 잇지 않는다
        ax.plot(f["x"], f["y"], color=color, linewidth=2, linestyle="none" if name == "현재 앱" else "-", marker="o", markersize=7, markeredgecolor="white",
                markeredgewidth=1.5, label=label, zorder=3)
    ax.set_yscale("log")
    ax.set_xlabel(xlabel)
    ax.set_ylabel("경로 오차 P95 (m, 로그)")
    ax.legend(frameon=False, fontsize=8, loc="upper right")
    ax.set_title(f"수집량–경로 오차 ({method}, {scope} 세션 평균)", loc="left")
    return _save(fig, out)


def plot_battery(summary: pd.DataFrame, out: Path):
    """2. 방식별 시간당 mAh(평균 ± 표준편차, 실기기)."""
    if summary.empty:
        return None
    s = summary.sort_values("mah_per_h_mean")
    fig, ax = plt.subplots(figsize=(8, 0.5 * len(s) + 1.5))
    std = pd.to_numeric(s["mah_per_h_std"], errors="coerce").fillna(0)
    ax.barh(s["method"], s["mah_per_h_mean"], xerr=std, color=SERIES[0], height=0.6,
            error_kw={"ecolor": INK, "elinewidth": 1, "capsize": 3})
    for y, (v, n) in enumerate(zip(s["mah_per_h_mean"], s["n"])):
        ax.annotate(f"{v:.0f} (n={n})", (v, y), textcoords="offset points", xytext=(6, -3), fontsize=8, color=INK)
    ax.set_xlabel("시간당 mAh")
    ax.grid(axis="y", visible=False)
    ax.set_title("방식별 배터리 소모", loc="left")
    return _save(fig, out)


def _bars(ax, labels, values, color):
    ax.barh(labels, values, color=color, height=0.6)
    ax.grid(axis="y", visible=False)


def plot_stay_f1(stays: pd.DataFrame, out: Path):
    """3. 머문 곳 F1(방식·오류 예산별, 세션 평균)."""
    df, scope = _scope(stays)
    if df.empty or df["stay_f1"].isna().all():
        return None
    g = df.groupby("run")["stay_f1"].mean().dropna().sort_values()
    fig, ax = plt.subplots(figsize=(8, 0.4 * len(g) + 1.5))
    _bars(ax, g.index, g.values, SERIES[2])
    ax.set_xlim(0, 1)
    ax.set_xlabel("머문 곳 F1")
    ax.set_title(f"머문 곳 검출 ({scope} 세션 평균)", loc="left")
    return _save(fig, out)


def plot_steps(steps: pd.DataFrame, out: Path):
    """4. 걸음 감지 방법별 오차와 탈것 구간 가짜 걸음 수(두 값은 단위가 달라 그래프를 나눈다)."""
    df, scope = _scope(steps)
    if df.empty:
        return None
    panels = [(c, t) for c, t in [("count_abs_error_pct", "걸음 수 오차 |%|"), ("vehicle_false_steps", "탈것 구간 가짜 걸음")]
              if c in df and df[c].notna().any()]
    if not panels:
        return None
    fig, axes = plt.subplots(1, len(panels), figsize=(5 * len(panels), 3.5), squeeze=False)
    for ax, (col, title) in zip(axes[0], panels):
        g = df.groupby("detector")[col].mean().dropna()
        _bars(ax, g.index, g.values, SERIES[1])
        ax.set_title(title, loc="left")
    fig.suptitle(f"걸음 감지 방법 비교 ({scope} 세션 평균)", x=0.01, ha="left")
    return _save(fig, out)


def plot_reconstruct(path: pd.DataFrame, out: Path):
    """5. 복원 방법별 경로 오차 P95(같은 입력). 본 실험 재생 중 모든 방법이 돈 재생만 골라, 방법마다 그 재생들의
    P95 중앙값을 막대로 그린다(시간 단위 측위의 수백 m가 평균을 끌지 않게 중앙값). 방법이 하나뿐이면 그리지 않는다."""
    df, scope = _scope(path)
    if df.empty or df["p95_m"].isna().all():
        return None
    g = main_runs(df).groupby(["run", "method"])["p95_m"].mean().unstack("method")
    if g.shape[1] < 2:
        return None
    g = g.dropna()
    if g.empty:
        return None
    order = [m for m in METHOD_ORDER if m in g.columns] + sorted(m for m in g.columns if m not in METHOD_ORDER)
    med = g[order].median()
    fig, ax = plt.subplots(figsize=(8, 0.45 * len(order) + 1.5))
    ax.barh(order[::-1], med[order[::-1]].values, color=SERIES[0], height=0.6)
    for y, v in enumerate(med[order[::-1]].values):
        ax.annotate(f"{v:.1f}", (v, y), textcoords="offset points", xytext=(6, -3), fontsize=8, color=INK)
    ax.grid(axis="y", visible=False)
    ax.set_xlabel("경로 오차 P95 중앙값 (m)")
    ax.set_title(f"복원 방법별 경로 오차 (같은 재생 {len(g)}개, {scope} 세션)", loc="left")
    return _save(fig, out)


def make_all(tables: dict[str, pd.DataFrame], fig_dir: Path) -> list[Path]:
    made = [
        plot_tradeoff(tables["path_metrics"], fig_dir / "1_tradeoff_fixes.png"),
        plot_tradeoff(tables["path_metrics"], fig_dir / "1_tradeoff_mah.png", battery=tables["battery_summary"]),
        plot_battery(tables["battery_summary"], fig_dir / "2_battery.png"),
        plot_stay_f1(tables["stay_metrics"], fig_dir / "3_stay_f1.png"),
        plot_steps(tables["step_metrics"], fig_dir / "4_steps.png"),
        plot_reconstruct(tables["path_metrics"], fig_dir / "5_reconstruct.png"),
    ]
    return [p for p in made if p is not None]
```

- [ ] **Step 4: 통과 확인**

Run: `.venv/Scripts/python -m pytest`
Expected: PASS — `64 passed`(경고 없음)

- [ ] **Step 5: 커밋**

```bash
git add research/analysis/tune.py research/analysis/plots.py research/tests/test_tune.py research/tests/test_plots.py
git commit -m "feat(research): 예비용 세션으로 hmm_steps β·σ 하한을 격자 탐색하고 결과 그래프 5종을 그린다"
```

---

### Task 8: 실제 세션 확인 + 문서

**Files:**
- Create: `docs/research/analysis-guide.md`
- Modify: `docs/research/recording-guide.md`(5절 마지막 줄), `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md`(7장)

**Interfaces:**
- Consumes: Task 1~7 전부
- Produces: 문서만

- [ ] **Step 1: 실제 세션으로 확인**

로컬에 세션이 있으면 돌린다(Git Bash, `research/`에서). 결과는 임시 폴더에 쓰고 지운다. `packages/footstep_core/`에서 `dart pub get`을 한 번 해 둔다.

```bash
S=data/sessions/20261109-213324-groundTruth
O="$(mktemp -d)"
if [ -d "$S" ]; then
  .venv/Scripts/python -m analysis.run --config experiments.yaml --results-dir "$O" --no-reconstruct
  .venv/Scripts/python - "$O" <<'EOF'
import sys, pandas as pd
p = pd.read_csv(f"{sys.argv[1]}/path_metrics.csv")
for r in p.itertuples():
    print(f"{r.run:52s} {r.fixes:3d} {r.gps_on_s:6.1f} {r.mean_m:6.1f} {r.p95_m:6.1f} {r.dist_err_pct:7.1f}")
print(pd.read_csv(f"{sys.argv[1]}/step_metrics.csv")[["detector", "total_steps", "walk_precision", "walk_recall"]])
EOF
  ls "$O/figures"
else
  echo "세션 없음 — 건너뜀"
fi
rm -rf "$O"
```

Expected (세션이 있을 때): 종료 코드 0. 재생 25줄의 측위·GPS 켜짐·오차 평균·P95·이동거리 오차가 '설계 검증' 표와 **같다**(재생과 지표는 결정적이다). 걸음 수 875·922·871. 그림은 `1_tradeoff_fixes.png` 하나다(배터리·머문 곳·걸음 세기 값이 없고, 복원 방법이 `local_straight` 하나라 5번도 그리지 않는다). 출력을 태스크 보고서에 그대로 붙인다. 다르면 멈추고 보고한다.

로컬 서버가 있으면 한 번 복원까지 돌려 본다(없으면 건너뛰고 보고한다). `route-guide.md` 2절대로 서버를 띄운 뒤 `--no-reconstruct` 없이 같은 명령을 돌린다. OSRM이 없으면 `straight` P95가 표의 마지막 열과 같고 나머지 방법은 `skipped.csv`로 간다. OSRM이 있으면 `.venv/Scripts/python -m analysis.tune --config experiments.yaml --results-dir "$O"`도 돌려 `hmm_best.json`이 생기는지 본다(이 세션은 pilot이지만 걸음 세기·버스가 없어 값을 확정하지 않는다).

- [ ] **Step 2: 안내 문서 작성**

`docs/research/analysis-guide.md`:

````markdown
# 분석 실행 안내 (R6)

세션 폴더를 재생하고 복원해 지표·그래프를 만든다. 설계는 `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md` 7장이다. 재생기·걸음 감지·복원 API 안내는 `replay-guide.md`·`steps-guide.md`·`route-guide.md`에 있다.

## 1. 준비 (처음 한 번)

Git Bash에서 `research/`로 가서 가상환경을 만든다. Python 3.10 이상이면 된다.

```bash
cd research
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements.txt
.venv/Scripts/python -m pytest          # 64 passed
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
| `--session <id>` | 이 세션만(여러 번 줄 수 있다) |
| `--force` | 재생·복원 캐시를 무시하고 다시 돈다. 재생 CLI나 서버 코드를 바꾼 뒤에 쓴다 |
| `--data-dir`·`--results-dir` | 세션·결과 폴더를 바꾼다 |
| `--no-plots` | 그래프를 만들지 않는다 |

도는 순서: 세션마다 `runs`의 재생(정책 × 설정을 모두 곱한 조합) → 복원 방법마다 경로 → 지표. `step_detectors`마다 steps CLI → 걸음 지표. `battery` 세션 → 배터리 지표. 재생 결과(`results/replay/`)와 서버 응답(`results/recon/`)은 캐시라, 지표만 고쳐 다시 돌리면 몇 초 안에 끝난다. 처음에는 세션 하나에 1~2분 걸린다(재생 25개 + 걸음 감지 3개).

**복원 서버** — `route-guide.md` 1·2절대로 로컬 OSRM과 서버(`local` 프로필, `dev-fake-token`)를 띄운다. `experiments.yaml`의 `reconstruct.server_url`의 포트를 서버와 맞춘다.
- 서버에 연결하지 못하면 남은 복원 호출을 모두 건너뛰고 `skipped.csv`에 이유를 남긴다. `local_straight` 지표는 그대로 나온다.
- 서버는 떴는데 OSRM이 없으면 도로 맞춤 방법이 모두 직선 대체(`fallback: true`)가 된다. 그 결과를 방법 이름으로 내면 오해를 부르므로 `skipped.csv`로 보낸다(`skip_all_fallback: true`). 점이 하나뿐인 재생(`hourly`)은 대체할 것이 없어 그대로 남는다.
- 서버 응답은 캐시라 서버 코드나 OSRM 데이터를 바꾼 뒤에는 `--force`로 다시 돈다.

## 4. β·σ 하한 정하기 (pilot만)

```bash
.venv/Scripts/python -m analysis.tune --config experiments.yaml
```

- `tune.runs`의 재생(기본 `step_budget[adaptive] e_m=50`)을 pilot 세션마다 `hmm_steps`로 β ∈ {2, 5, 10, 20, 50}m × σ 하한 ∈ {3, 5, 10}m 복원하고, 경로 오차 P95의 세션 평균이 가장 작은 조합을 고른다(같으면 작은 β·σ).
- 결과: `results/hmm_grid.csv`, `results/hmm_grid_by_session.csv`, `results/hmm_best.json`. 고른 값을 `experiments.yaml`의 `reconstruct.methods`에 `{name: hmm_steps_tuned, method: hmm_steps, hmm: {betaM: …, sigmaMinM: …}}`로 고정하고 eval을 돌린다.
- 서버·OSRM이 없으면 종료 코드 2로 멈춘다(모든 구간이 직선이면 β·σ를 비교할 수 없다). pilot 세션이 없으면 1이다.

## 5. 결과 파일 (`research/results/`, 커밋하지 않는다)

| 파일 | 내용 |
|---|---|
| `path_metrics.csv` | 재생 × 복원 방법마다: 정답 점 수, 경로까지 거리 평균·P95(전체·도보·탈것), 복원 경로 길이·정답 이동거리·이동거리 오차 %, 측위 횟수, 시간당 측위, 추정 GPS 켜짐(초), fallback 구간 비율 |
| `stay_metrics.csv` | 재생마다: 검출·정답 머문 곳 수, 일치 수, 정밀도·재현율·F1 |
| `step_metrics.csv` | 세션 × 감지기: 총 걸음, 걸음 수 오차(Σ 기준 부호 있는 %·구간별 \|%\| 평균), 탈것 가짜 걸음(합·분당), 보행 판정 정밀도·재현율, 첫 걸음까지 지연(초) |
| `step_counts_by_carry.csv` | 걸음 세기 구간마다 휴대 위치·직접 센 수·감지 수·오차 % |
| `battery_runs.csv` | 배터리 회차마다: 방식, 제외 사유, 잰 시간, mAh, 시간당 mAh, 계단 맞춤 여부, 전류 평균(mA), batterystats GPS 시간(전체·앱), 추정 GPS 켜짐 |
| `battery_summary.csv` | 방식마다 n, 시간당 mAh 평균·표준편차, 전류 평균, 앱 GPS 시간 평균 |
| `skipped.csv` | 건너뛴 세션·재생·복원과 이유 |
| `figures/` | `1_tradeoff_fixes.png`·`1_tradeoff_mah.png`(배터리–오차 곡선), `2_battery.png`, `3_stay_f1.png`, `4_steps.png`, `5_reconstruct.png` — 값이 있는 것만 |

## 6. 지표 정의 (설계 7-2)

- **정답 경로**: `gps.csv` 중 정확도 20m 이하 행. 탈것 구간은 `board`~`alight`, 그 밖은 도보다.
- **경로 오차**: 정답 점마다 복원 경로(모든 구간)까지 가장 가까운 거리. 평균과 P95(선형 보간 백분위).
- **이동거리 오차**: (복원 경로 길이 − 정답 이동거리) ÷ 정답 이동거리. 정답 이동거리는 마지막으로 센 점에서 10m(`truth.min_hop_m`) 이상 벗어난 점만 이어 잰다 — 서 있는 동안 GPS가 몇 m씩 흔들린 것이 거리로 쌓이지 않게 하려는 것이다.
- **머문 곳**: 정답은 `arrive`~`depart` 중 10분 이상(출발을 안 눌렀으면 세션 끝까지). 겹친 시간이 두 머문 곳 **각각의** 50% 이상이고 중심이 100m 이내면 일치다. 일대일로, 겹친 시간이 긴 쌍부터 짝짓는다. 정답 구간 안에 GPS 점이 없으면 중심을 몰라 시간만 본다.
- **보행 판정**: 1초 격자. 정답 보행 = 머문 곳(길이 상관없이)과 탈것 밖. 예측 보행 = `step_states.csv`의 상태가 `walking`.
- **첫 걸음 지연**: 걸음 세기 구간마다 `count_start`에서 첫 감지 걸음까지(초)의 평균.
- **배터리**: 가장 길게 이어진 `plugged=0` 행만 쓴다. 전하량 계단이 처음 바뀐 행 ~ 마지막으로 바뀐 행 사이의 감소 ÷ 시간(계단 변화가 두 번 미만이면 처음 ~ 끝 행). `meta.json` errors에 `restarted by system`이 있는 회차는 평균에서 뺀다. 전류(`current_ua`)의 실제 단위는 기종마다 달라 `battery.current_units`에 적는다(SM-S911N은 mA).
- **batterystats GPS 시간**: `Sensor GPS: … realtime` 줄을 더한다. 앱 몫은 그 줄이 든 Uid 묶음에 패키지 이름이 보일 때만 나온다. 기종·Android 버전마다 형식이 달라 최선 노력 값이다 — 비면 `summary.json`의 추정 GPS 켜짐과 전하량만 보고한다.

## 7. 해석할 때 주의

- `local_straight`는 서버 `straight`와 달리 머문 곳 중심 치환·10분 공백(`estimated`) 처리를 하지 않는다. 서버 없이 도는 기준선이다.
- 경로 오차는 '가장 가까운 경로까지 거리'라 시간 순서를 보지 않는다. 같은 길을 되돌아온 경로에서는 오차가 실제보다 작게 나온다.
- 배터리–오차 곡선(1번 그림)은 본 실험만 그린다(ttff 0, 파라미터가 없거나 `e_m` 하나). 절제 실험·ttff 민감도는 `path_metrics.csv`로 본다. 실기기 mAh판(`1_tradeoff_mah.png`)은 배터리 방식 이름과 재생 이름이 같을 때만 점이 찍힌다(예: `step_budget[adaptive] e_m=50`).
- 정답 GPS 자체에도 오차가 있다(설계 10장 위험 7). 실내 정지 구간은 정답이 약 7초 간격이다.
- 세션 데이터(`research/data/`)와 결과(`research/results/`)는 커밋하지 않는다. 가상환경(`research/.venv/`)도 올리지 않는다.

## 8. 범위 밖 (선택 과제)

설계 7-2의 위치공유 전송량 비교(현재 5초 고정 ↔ "상태 변화·20m 이동·60초 경과 중 하나면 전송")는 이번 R6에 넣지 않았다. 같은 1초 GPS로 메시지 수와 받는 쪽 위치 오차를 재는 함수 하나(`analysis/share.py`)로 나중에 붙일 수 있다.
````

- [ ] **Step 3: 기존 문서 고치기**

`docs/research/recording-guide.md` 5절 마지막 줄을 바꾼다:

```markdown
- `research/sessions.yaml`에 세션 id, 코스, 휴대 위치, 용도(pilot/eval/battery)를 적는다. 분석 실행은 `docs/research/analysis-guide.md`.
```

설계 문서 7-1 끝에 더한다:

```markdown
- 실행은 `research/`에서 `.venv/Scripts/python -m analysis.run --config experiments.yaml`(가상환경·옵션은 `docs/research/analysis-guide.md`). 재생 결과와 서버 응답은 `research/results/`에 캐시한다.
- 서버에 연결하지 못하면 복원을 건너뛰고, 서버는 떴는데 OSRM이 없어 모든 구간이 직선 대체면 그 방법의 지표를 내지 않는다(`skipped.csv`). 서버 없이도 남은 점을 직선으로 이은 `local_straight` 지표는 늘 나온다.
- `sessions.yaml`의 용도는 `pilot`·`eval`·`battery`(배터리 실험 회차, 방식은 meta.json의 policy) 셋이다.
- β·σ 하한 격자(6-3)는 `python -m analysis.tune`이 pilot 세션만으로 고른다(세션 평균 P95 최소, 같으면 작은 값).
```

설계 문서 7-2 표 아래에 더한다:

```markdown
R6에서 정한 세부 규칙:
- 경로 오차는 정답 점마다 복원 경로 전체까지 가장 가까운 거리다(시간 순서는 보지 않는다). 정답 이동거리는 마지막으로 센 점에서 10m 이상 벗어난 점만 이어 잰다(서 있는 동안의 흔들림 제외).
- 머문 곳의 "50% 이상 겹침"은 두 머문 곳 **각각**의 50%다(하루를 덮는 머문 곳 하나가 정답 여럿과 맞는 것을 막는다). 정답은 arrive~depart 중 10분 이상, 일대일로 짝짓는다.
- 첫 걸음까지 지연은 걸음 세기 구간의 count_start에서 첫 감지 걸음까지다.
- 배터리는 가장 길게 이어진 충전기 분리 구간에서 전하량 계단이 처음·마지막으로 바뀐 행 사이로 잰다(계단 3.7mAh 양자화 오차를 줄인다). 전류 평균(기종별 단위)과 batterystats `Sensor GPS` 시간(최선 노력)을 함께 낸다.
- (선택) 위치공유 전송량은 R6 범위에서 뺐다. 필요하면 같은 1초 GPS로 함수 하나를 더한다.
```

- [ ] **Step 4: 커밋**

```bash
git add docs/research/analysis-guide.md docs/research/recording-guide.md docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md
git commit -m "docs: 분석 실행 안내를 추가하고 설계 문서에 R6 지표 세부 규칙을 적는다"
```

- [ ] **Step 5: 마무리 확인**

- `research/`: `.venv/Scripts/python -m pytest` → `64 passed`
- `git status --short`에 `research/.venv`, `research/data`, `research/results`가 없다
- `git log --format=%B route..HEAD | grep -iE "co-authored|claude"`가 빈 결과다

---

## 이후에 넘기는 것

- **pilot·eval 세션 모으기(설계 8-1).** 지금 세션은 걸음 세기·탈것·10분 넘는 머문 곳 표시가 없어 걸음 수 오차·가짜 걸음·머문 곳 F1·탈것 경로 오차가 비어 있다. 이 표시를 넣은 60~120분 코스를 모은 뒤 `sessions.yaml`에 pilot/eval로 나눠 적는다.
- **β·σ 하한 확정.** 로컬 KR OSRM(`osrm/setup.sh`)을 띄우고 pilot 세션으로 `analysis.tune`을 돌려 `experiments.yaml`에 `hmm_steps_tuned`로 고정한 뒤 eval을 돌린다. 같은 방식으로 머문 곳 R·T(`stay_params`)와 걸음 감지기 파라미터도 pilot에서만 본다.
- **배터리 실험(설계 8-2).** 정책 실행 세션을 `use: battery`로 적으면 `battery_runs.csv`·`battery_summary.csv`·2번 그림과 실기기 mAh판 곡선(`1_tradeoff_mah.png`)이 나온다. batterystats 형식이 이 파서와 다르면 `gps_s_*`가 비므로, 첫 회차 뒤 `batterystats.txt`의 GPS 줄을 보고 정규식을 맞춘다.
- **(선택) 위치공유 전송량.** 설계 7-2 마지막 줄. 범위 밖으로 두었다.
