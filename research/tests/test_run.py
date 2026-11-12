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
