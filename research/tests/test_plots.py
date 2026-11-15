import warnings

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
         "stay_metrics": pd.DataFrame([{"use": "pilot", "run": "fixed_1m", "policy": "fixed_1m", "detector": "os",
                                        "params": "", "ttff": 0.0, "stay_f1": 0.5}]),
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


def test_stay_f1_uses_main_runs_only(tmp_path, monkeypatch):
    from analysis import plots
    rows = [
        {"use": "pilot", "run": "fixed_1m", "policy": "fixed_1m", "detector": "os", "params": "", "ttff": 0.0,
         "stay_f1": 0.5},
        {"use": "pilot", "run": "fixed_1m ttff=5", "policy": "fixed_1m", "detector": "os", "params": "", "ttff": 5.0,
         "stay_f1": 0.9},
        {"use": "pilot", "run": "step_budget[os] e_m=50 stay.use_still=false", "policy": "step_budget",
         "detector": "os", "params": "e_m=50", "ttff": 0.0, "stay_f1": 0.1},
    ]
    seen = {}
    monkeypatch.setattr(plots, "_bars", lambda ax, labels, values, color: seen.update(labels=list(labels)))
    assert plots.plot_stay_f1(pd.DataFrame(rows), tmp_path / "s.png") is not None
    assert seen["labels"] == ["fixed_1m"]


def test_warns_when_no_korean_font(monkeypatch):
    from analysis import plots
    monkeypatch.setattr(plots, "_korean_fonts", lambda: [])
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        family = plots._font_family()
    assert family == ["DejaVu Sans"]
    assert any("한글" in str(w.message) for w in caught)
    monkeypatch.setattr(plots, "_korean_fonts", lambda: ["Malgun Gothic"])
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        assert plots._font_family() == ["Malgun Gothic", "DejaVu Sans"]


def test_reconstruct_plot_compares_methods_on_shared_sessions_only(tmp_path, monkeypatch):
    """A는 두 세션(P95 1·101), B는 쉬운 세션 하나만 성공했다. 같은 입력인 쉬운 세션만 비교해야 한다."""
    rows = []
    for session, method, p95 in [("s1", "straight", 1.0), ("s2", "straight", 101.0), ("s1", "nearest", 2.0)]:
        rows.append({"session": session, "use": "pilot", "run": "fixed_1m", "policy": "fixed_1m", "detector": "os",
                     "params": "", "ttff": 0.0, "method": method, "fixes_per_hour": 60.0, "p95_m": p95})
    shown = {}
    import matplotlib.axes
    orig = matplotlib.axes.Axes.barh

    def spy(self, y, width, *a, **k):
        shown["values"] = dict(zip(y, width))
        return orig(self, y, width, *a, **k)

    monkeypatch.setattr(matplotlib.axes.Axes, "barh", spy)
    assert plot_reconstruct(pd.DataFrame(rows), tmp_path / "r.png") is not None
    assert shown["values"] == {"straight": 1.0, "nearest": 2.0}      # 평균 51이 아니라 공유 세션 값 1


def test_make_all_removes_stale_figures_of_skipped_plots(tmp_path):
    stale = tmp_path / "5_reconstruct.png"
    stale.write_bytes(b"old")
    one_method = _path_rows()
    one_method = one_method[one_method["method"] == "local_straight"]    # 방법 하나뿐이라 5번 그래프는 건너뛴다
    files = make_all(_tables(path_metrics=one_method), tmp_path)
    assert "5_reconstruct.png" not in [f.name for f in files]
    assert not stale.exists()
