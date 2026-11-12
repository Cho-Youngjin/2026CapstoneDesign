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
