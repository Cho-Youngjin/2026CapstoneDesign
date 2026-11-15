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


def test_charge_rate_charging_gives_no_rate():
    # 전하량이 오히려 늘었으면(충전) 음수 소모율 대신 None
    b = _battery([[T0, 3_700_000, -1, 100, 30, 0], [T0 + H, 3_707_400, -1, 100, 30, 0]])
    r = charge_rate(b, align_steps=False)
    assert r["mah_per_h"] is None and r["mah_used"] < 0


_APP = "com.travelfootsteps.app"


def test_batterystats_resets_uid_on_unmatched_header():
    # 둘째 헤더("  Uid u0a99: 1.0 (…)")는 uid 정규식에 안 맞는다. uid를 비우지 않으면 그 아래 GPS 줄이
    # 앞선 앱(u0a245)의 것으로 잘못 더해진다.
    text = f"""Statistics since last charge:
  u0a245:
    Apk {_APP}:
    Sensor GPS: 10s 0ms realtime (1 times)
  Uid u0a99: 1.0 ( cpu=1s )
    Sensor GPS: 100s 0ms realtime (1 times)
"""
    r = gps_seconds_from_batterystats(text, _APP)
    assert r["gps_s_total"] == pytest.approx(110.0)
    assert r["gps_s_app"] == pytest.approx(10.0)


def test_batterystats_app_requires_exact_apk_line():
    # 패키지 이름이 그냥 들어 있는 줄(Service …)이나 .debug 패키지의 Apk 줄로는 앱 uid가 되지 않는다.
    text = f"""Statistics since last charge:
  u0a10:
    Apk {_APP}.debug:
    Sensor GPS: 20s 0ms realtime (1 times)
  u0a11:
      Service {_APP}.Foo:
    Sensor GPS: 30s 0ms realtime (1 times)
"""
    r = gps_seconds_from_batterystats(text, _APP)
    assert r["gps_s_total"] == pytest.approx(50.0) and r["gps_s_app"] is None
    ok = text + f"  u0a12:\n    Apk {_APP}:\n    Sensor GPS: 5s 0ms realtime (1 times)\n"
    assert gps_seconds_from_batterystats(ok, _APP)["gps_s_app"] == pytest.approx(5.0)


def test_batterystats_uses_first_statistics_section_only():
    text = f"""Statistics since last charge:
  u0a12:
    Apk {_APP}:
    Sensor GPS: 10s 0ms realtime (1 times)
Statistics since last unplugged:
  u0a12:
    Apk {_APP}:
    Sensor GPS: 99s 0ms realtime (1 times)
"""
    r = gps_seconds_from_batterystats(text, _APP)
    assert r["gps_s_total"] == pytest.approx(10.0) and r["gps_s_app"] == pytest.approx(10.0)


def test_method_label():
    assert method_label("fixed_1m", "os", {}) == "fixed_1m"
    assert method_label("step_budget", "adaptive", {"e_m": "50"}) == "step_budget[adaptive] e_m=50"
    # 멈춤 감지판 time_speed는 걸음 감지기를 쓰므로 감지기를 붙이고, 기본판은 붙이지 않는다
    assert method_label("time_speed_still", "os", {"e_m": "50"}) == "time_speed_still[os] e_m=50"
    assert method_label("time_speed", "os", {"e_m": "50"}) == "time_speed e_m=50"


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
    assert s["n_aligned"].tolist() == [2]      # 두 회차 모두 계단이 두 번 이상 바뀌어 정렬됨
    assert s["mah_per_h_mean"].iloc[0] == pytest.approx((7.4 + 14.8) / 2)
    assert s["mah_per_h_std"].iloc[0] == pytest.approx(pd.Series([7.4, 14.8]).std())


def test_battery_summary_counts_aligned_runs():
    runs = pd.DataFrame({"method": ["m", "m", "m"], "excluded": [None, None, "restarted by system"],
                         "mah_per_h": [7.0, 9.0, 8.0], "current_ma": [1.0, 1.0, 1.0], "gps_s_app": [None] * 3,
                         "aligned": [True, False, True]})
    s = battery_summary(runs)
    # 제외된 회차는 n에도 n_aligned에도 안 들어간다
    assert s["n"].tolist() == [2] and s["n_aligned"].tolist() == [1]


def test_empty_current_column_keeps_charge_rows(tmp_path):
    """순간 전류를 못 재는 기종은 current_ua가 비어 있다. 그래도 전하량 행은 살려 mAh/h를 낸다."""
    rows = [[T0 + k * H // 2, 3_700_000 - k * 3_700, "", 88, 30, 0] for k in range(4)]
    d = make_session(tmp_path, "nocur", battery=rows, meta={"mode": "policy", "policy": {"policyId": "fixed_1m"}})
    r = battery_run(d)
    assert r["mah_per_h"] == pytest.approx(7.4) and r["current_ma"] is None
