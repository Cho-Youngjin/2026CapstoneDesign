import pandas as pd
import pytest

from analysis.geo import offset
from analysis.session import load_session, truth_points
from analysis.stay_metrics import is_match, read_stays, stay_scores, truth_stays
from conftest import LAT0, LNG0, T0, gps_row, make_session, write_csv

MIN = 60_000


def _stay(a_min, l_min, east=0.0, north=0.0):
    lat, lng = offset(LAT0, LNG0, east, north)
    return {"arrive_ms": T0 + a_min * MIN, "leave_ms": T0 + l_min * MIN, "lat": lat, "lng": lng}


def test_overlap_boundary_is_inclusive_at_50_percent():
    truth = _stay(0, 20)
    assert is_match(_stay(10, 30), truth)          # 10분 겹침 = 두 머문 곳 각각의 50%
    assert not is_match(_stay(11, 31), truth)      # 9분 = 45%
    # 정답 20분 안에 든 10분짜리: 검출의 100%지만 정답의 50% → 일치
    assert is_match(_stay(5, 15), truth)
    # 하루를 덮는 검출(100분)은 정답 20분과 20%만 겹친다 → 불일치
    assert not is_match(_stay(0, 100), truth)


def test_distance_boundary_100m():
    truth = _stay(0, 20)
    assert is_match(_stay(0, 20, east=99.9), truth)
    assert not is_match(_stay(0, 20, east=100.1), truth)
    assert is_match(_stay(0, 20, east=500), {**truth, "lat": None, "lng": None})   # 중심을 모르면 시간만


def test_scores_one_to_one():
    truth = [_stay(0, 20), _stay(60, 80)]
    detected = [_stay(0, 20), _stay(1, 19), _stay(200, 220)]   # 둘째는 첫 정답과 겹치지만 이미 짝지어짐
    s = stay_scores(detected, truth)
    assert s["stay_tp"] == 1
    assert s["stay_precision"] == pytest.approx(1 / 3)
    assert s["stay_recall"] == pytest.approx(1 / 2)
    assert s["stay_f1"] == pytest.approx(2 * (1 / 3) * (1 / 2) / (1 / 3 + 1 / 2))


def test_scores_empty_sides():
    assert stay_scores([], [])["stay_f1"] is None
    s = stay_scores([], [_stay(0, 20)])
    assert s["stay_precision"] is None and s["stay_recall"] == 0.0 and s["stay_f1"] is None
    s = stay_scores([_stay(0, 20)], [_stay(100, 120)])
    assert s["stay_precision"] == 0.0 and s["stay_recall"] == 0.0 and s["stay_f1"] == 0.0


def test_truth_stays_filters_short_and_takes_center(tmp_path):
    gps = [gps_row(T0 + k * MIN, 10.0 if k % 2 else -10.0, 0) for k in range(0, 31)]
    marks = [[T0, "arrive", ""], [T0 + 3 * MIN, "depart", ""],          # 3분 → 정답 아님
             [T0 + 10 * MIN, "arrive", "카페"], [T0 + 21 * MIN, "depart", ""]]
    s = load_session(make_session(tmp_path, gps=gps, marks=marks))
    stays = truth_stays(s, truth_points(s.gps), min_stay_s=600)
    assert len(stays) == 1
    assert stays[0]["arrive_ms"] == T0 + 10 * MIN and stays[0]["leave_ms"] == T0 + 21 * MIN
    # 10~21분의 12점: 동쪽 +10, −10이 6개씩 → 중심은 원점
    assert stays[0]["lng"] == pytest.approx(LNG0, abs=1e-9)


def test_read_stays(tmp_path):
    write_csv(tmp_path / "stays.csv", ["arrive_ms", "leave_ms", "lat", "lng", "n_points"],
              [[1, 2, 37.5, 127.0, 3]])
    assert read_stays(tmp_path) == [{"arrive_ms": 1, "leave_ms": 2, "lat": 37.5, "lng": 127.0}]
    assert read_stays(tmp_path / "none") == []
