import json

import pandas as pd
import pytest

from analysis.geo import offset
from analysis.reconstruct import ServerUnavailable
from analysis.replay import CliError
import analysis.tune as tune
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

    def __init__(self, fallback=False, mixed=False):
        self.seen, self.fallback, self.mixed = [], fallback, mixed

    def reconstruct(self, fixes, stays, method, hmm=None):
        self.seen.append((method, hmm))
        n = abs(hmm["betaM"] - 10) + hmm["sigmaMinM"]
        a, b = offset(LAT0, LNG0, 0, n), offset(LAT0, LNG0, 100, n)
        seg = {"kind": "walk", "coords": [{"lat": a[0], "lng": a[1]}, {"lat": b[0], "lng": b[1]}],
               "fallback": self.fallback}
        if self.mixed:   # 구간 둘 중 하나만 fallback
            return [{**seg, "fallback": False}, {**seg, "fallback": True}]
        return [seg]


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


def test_grid_search_never_picks_cell_with_fewer_results():
    # (β=2, σ=3)만 결과가 1개뿐이고 P95가 가장 낮다 → 표본이 모자란 칸이라 고르면 안 된다
    def evaluate(b, s):
        if (b, s) == (2, 3):
            return [0.5, None]
        return [abs(b - 10) + s] * 2
    table, best = grid_search(evaluate, [2, 10], [3, 5])
    assert (best["betaM"], best["sigmaMinM"]) == (10.0, 3.0)
    done = table.set_index(["betaM", "sigmaMinM"])["complete"]
    assert not done[(2, 3)] and done[(10, 3)] and done[(2, 5)]


def test_main_writes_complete_column(tmp_path):
    args = _setup(tmp_path)
    assert main(args, cli=_Cli(), client=_Client()) == 0
    grid = pd.read_csv(tmp_path / "results" / "hmm_grid.csv")
    assert grid["complete"].all()


def test_main_without_any_result_writes_no_best(tmp_path, capsys, monkeypatch):
    args = _setup(tmp_path)
    monkeypatch.setattr(tune, "path_metrics", lambda *a, **k: {"p95_m": None})
    assert main(args, cli=_Cli(), client=_Client()) == 1
    assert not (tmp_path / "results" / "hmm_best.json").exists()
    assert "고를 수 있는 칸이 없습니다" in capsys.readouterr().err


def test_main_replay_cli_error_exits_3(tmp_path, capsys):
    class _BadCli:
        def replay(self, *a, **k):
            raise CliError("dart를 찾을 수 없습니다")
    args = _setup(tmp_path)
    assert main(args, cli=_BadCli(), client=_Client()) == 3
    assert "dart" in capsys.readouterr().err


def test_main_records_fallback_share_for_mixed_cells(tmp_path):
    args = _setup(tmp_path)
    assert main(args, cli=_Cli(), client=_Client(mixed=True)) == 0
    grid = pd.read_csv(tmp_path / "results" / "hmm_grid.csv")
    assert (grid["fallback_share"] == 0.5).all()
    by_session = pd.read_csv(tmp_path / "results" / "hmm_grid_by_session.csv")
    assert (by_session["fallback_share"] == 0.5).all()
