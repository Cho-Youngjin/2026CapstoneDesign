"""run_experiment 끝까지: 가짜 재생 CLI(파일만 쓴다)와 가짜 서버로 돈다. 실제 dart·서버는 부르지 않는다."""
import json
from pathlib import Path

import pytest

from analysis.config import load_experiment
from analysis.geo import offset
from analysis.reconstruct import ServerUnavailable
from analysis.run import main, run_experiment, table_columns, write_tables
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


def _rewrite_sessions(experiment, text):
    experiment.sessions_file.write_text(text, encoding="utf-8")
    return load_experiment(experiment.base / "experiments.yaml")


def test_end_to_end_columns_match_fixed_headers(experiment):
    """빈 표에 쓰는 고정 머리줄(table_columns)이 실제 행의 열과 같아야 한다 — 어긋나면 빈 표와 찬 표의 열이 달라진다."""
    t = run_experiment(experiment, FakeCli(), FakeClient())
    for name, cols in table_columns().items():
        assert list(t[name].columns) == cols, name


def test_broken_session_does_not_abort_batch(experiment, tmp_path):
    data = tmp_path / "data"
    make_session(data, "badmeta", gps=[gps_row(T0 + k * 1000, k, 0) for k in range(5)])
    (data / "badmeta" / "meta.json").write_text("{bad", encoding="utf-8")
    make_session(data, "badbat", battery=[[T0, 1, 1, 1, 1, 0]])
    (data / "badbat" / "meta.json").write_text("{bad", encoding="utf-8")
    make_session(data, "nosummary", gps=[gps_row(T0 + k * 1000, k, 0) for k in range(5)])
    exp = _rewrite_sessions(experiment, "sessions:\n  - {id: badmeta, use: pilot}\n  - {id: badbat, use: battery}\n"
                                        "  - {id: nosummary, use: pilot}\n  - {id: p1, use: pilot}\n")

    class BrokenSummaryCli(FakeCli):
        def replay(self, session_dir, spec, out, force=False):
            super().replay(session_dir, spec, out, force)
            if Path(session_dir).name == "nosummary":
                (out / "summary.json").write_text("{not json", encoding="utf-8")
            return out

    t = run_experiment(exp, BrokenSummaryCli(), client=None)
    # 망가진 세션은 skipped로 가고, 멀쩡한 p1은 끝까지 돌아 지표가 나온다
    assert set(t["skipped"]["session"]) >= {"badmeta", "badbat", "nosummary"}
    assert set(t["path_metrics"]["session"]) == {"p1"}
    assert "p1" in t["step_metrics"]["session"].tolist()


def test_metric_error_is_isolated(experiment, monkeypatch):
    import analysis.run as run_mod
    real = run_mod.path_metrics
    calls = {"n": 0}

    def flaky(*a, **k):
        calls["n"] += 1
        if calls["n"] == 1:
            raise ValueError("지표 오류")
        return real(*a, **k)

    monkeypatch.setattr(run_mod, "path_metrics", flaky)
    t = run_experiment(experiment, FakeCli(), FakeClient())
    assert "지표 오류" in " ".join(t["skipped"]["reason"])
    assert "straight" in t["path_metrics"]["method"].tolist()      # 첫 방법이 실패해도 다음 방법은 돈다


class CountingClient:
    def __init__(self, fallback):
        self.fallback, self.calls = fallback, []

    def reconstruct(self, fixes, stays, method, hmm=None):
        self.calls.append((method, hmm))
        a, b = offset(LAT0, LNG0, 0, 10), offset(LAT0, LNG0, 100, 10)
        return [{"kind": "walk", "coords": [{"lat": a[0], "lng": a[1]}, {"lat": b[0], "lng": b[1]}],
                 "fallback": self.fallback}]


def test_all_fallback_response_is_not_cached(experiment):
    experiment.reconstruct["methods"] = [{"name": "osrm_match_radius", "method": "osrm_match_radius", "hmm": None}]
    down = CountingClient(fallback=True)
    run_experiment(experiment, FakeCli(), down)
    assert not list((experiment.results_dir / "recon").rglob("osrm_match_radius*.json"))
    # OSRM을 켠 뒤 다시 돌리면 서버를 다시 불러 진짜 결과를 받는다
    up = CountingClient(fallback=False)
    t = run_experiment(experiment, FakeCli(), up)
    assert up.calls and "osrm_match_radius" in t["path_metrics"]["method"].tolist()


def test_stale_all_fallback_cache_is_ignored(experiment):
    """수정 전 실행이 남긴 전부-fallback 캐시도 믿지 않는다."""
    experiment.reconstruct["methods"] = [{"name": "osrm_match_radius", "method": "osrm_match_radius", "hmm": None}]
    cache = experiment.results_dir / "recon" / "p1" / "fixed_1m-os-ttff0" / "osrm_match_radius.json"
    cache.parent.mkdir(parents=True)
    cache.write_text(json.dumps([{"kind": "walk", "coords": [], "fallback": True}]), encoding="utf-8")
    up = CountingClient(fallback=False)
    run_experiment(experiment, FakeCli(), up)
    assert up.calls


def test_cache_key_includes_hmm_params(experiment):
    def methods(beta):
        return [{"name": "hmm_steps", "method": "hmm_steps", "hmm": {"beta": beta}}]

    client = CountingClient(fallback=False)
    experiment.reconstruct["methods"] = methods(5)
    run_experiment(experiment, FakeCli(), client)
    run_experiment(experiment, FakeCli(), client)                  # 같은 조정값: 캐시 재사용
    assert [c[1] for c in client.calls] == [{"beta": 5}]
    experiment.reconstruct["methods"] = methods(10)
    run_experiment(experiment, FakeCli(), client)                  # 조정값이 바뀌면 다시 받는다
    assert [c[1] for c in client.calls] == [{"beta": 5}, {"beta": 10}]


def test_empty_tables_keep_fixed_headers(experiment, monkeypatch):
    import pandas as pd
    import analysis.run as run_mod
    monkeypatch.setattr(run_mod, "DartCli", lambda *a, **k: FakeCli())
    code = main(["--config", str(experiment.base / "experiments.yaml"), "--no-reconstruct", "--no-plots",
                 "--session", "gone"])
    assert code == 0
    for name, cols in table_columns().items():
        df = pd.read_csv(experiment.results_dir / f"{name}.csv")
        assert df.empty and list(df.columns) == cols, name
    assert "mean_m" in pd.read_csv(experiment.results_dir / "path_metrics.csv").columns
    assert "mah_per_h" in pd.read_csv(experiment.results_dir / "battery_runs.csv").columns


def test_unknown_session_id_is_an_error(experiment, monkeypatch, capsys):
    import analysis.run as run_mod
    monkeypatch.setattr(run_mod, "DartCli", lambda *a, **k: FakeCli())
    with pytest.raises(SystemExit) as e:
        main(["--config", str(experiment.base / "experiments.yaml"), "--no-reconstruct", "--no-plots",
              "--session", "typo"])
    assert e.value.code != 0
    assert "typo" in capsys.readouterr().err


def test_help_mentions_cwd_relative_dirs(capsys):
    with pytest.raises(SystemExit):
        main(["--help"])
    out = " ".join(capsys.readouterr().out.split())
    assert out.count("현재 디렉터리 기준") >= 2


def test_force_deletes_old_cache_even_when_new_response_is_all_fallback(experiment):
    experiment.reconstruct["methods"] = [{"name": "osrm_match_radius", "method": "osrm_match_radius", "hmm": None}]
    cache = experiment.results_dir / "recon" / "p1" / "fixed_1m-os-ttff0" / "osrm_match_radius.json"
    cache.parent.mkdir(parents=True)
    cache.write_text(json.dumps([{"kind": "walk", "coords": [], "fallback": False}]), encoding="utf-8")
    up = CountingClient(fallback=True)          # 새 응답은 전부 직선 대체라 캐시에 새로 쓰지 않는다
    run_experiment(experiment, FakeCli(), up, force=True)
    assert up.calls and not cache.exists()      # 그래도 묵은 캐시는 남지 않아야 한다
