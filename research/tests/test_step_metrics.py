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
