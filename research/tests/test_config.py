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
