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
