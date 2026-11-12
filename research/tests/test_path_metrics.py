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
    assert row["p95_m"] == pytest.approx(18.05, abs=0.01)     # 손으로 센 값: 0.95 × 19 = 18.05


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


def test_unsorted_truth_does_not_inflate_distance():
    # 같은 100m 직선 정답을 시각순과 뒤섞인 순서로 주어도 정답 이동거리는 같아야 한다.
    ordered = _truth([(T0 + k * 1000, k * 10, 0) for k in range(11)])
    shuffled = ordered.iloc[[0, 5, 2, 9, 1, 10, 3, 7, 4, 8, 6]].reset_index(drop=True)
    seg = [_seg([(0, 0), (100, 0)])]
    want = path_metrics(ordered, seg, vehicles=[], min_hop_m=0)
    got = path_metrics(shuffled, seg, vehicles=[], min_hop_m=0)
    assert want["truth_length_m"] == pytest.approx(100.0, abs=0.01)
    assert got["truth_length_m"] == pytest.approx(100.0, abs=0.01)
    assert got["dist_err_pct"] == pytest.approx(want["dist_err_pct"], abs=0.01)
    assert got["mean_m"] == pytest.approx(want["mean_m"], abs=0.01)


def test_local_straight_orders_by_time():
    fixes = pd.DataFrame({"t_ms": [2, 1], "lat": [1.0, 2.0], "lng": [3.0, 4.0]})
    seg = local_straight(fixes)
    assert seg == [{"kind": "walk", "coords": [{"lat": 2.0, "lng": 4.0}, {"lat": 1.0, "lng": 3.0}],
                    "fallback": False}]
    assert local_straight(fixes.iloc[0:0]) == []
