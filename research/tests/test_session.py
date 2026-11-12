import numpy as np
import pytest

from analysis.session import (Interval, carry_at, count_intervals, in_intervals, load_session, paired_intervals,
                              stay_intervals, truth_points, vehicle_intervals)
from conftest import T0, gps_row, make_session


def test_load_session_reads_files_and_drops_broken_rows(tmp_path):
    d = make_session(tmp_path, gps=[gps_row(T0 + 1000, 1, 0), gps_row(T0, 0, 0)],
                     meta={"startedAt": "2026-11-09T12:33:20Z", "endedAt": None})
    with (d / "gps.csv").open("a", encoding="utf-8") as f:
        f.write("123,broken\n")
    s = load_session(d)
    assert s.session_id == "s1"
    assert list(s.gps["t_ms"]) == [T0, T0 + 1000]      # 시각순, 깨진 행 버림
    assert s.start_ms == 1794227600000                 # startedAt
    assert s.end_ms == T0 + 1000                       # endedAt이 없으면 마지막 기록 시각


def test_load_session_missing_folder(tmp_path):
    with pytest.raises(FileNotFoundError):
        load_session(tmp_path / "none")


def test_truth_points_keeps_accuracy_20_or_less(walk_session):
    s = load_session(walk_session)
    assert len(s.gps) == 101
    assert len(truth_points(s.gps)) == 100
    assert len(truth_points(s.gps, max_accuracy_m=40)) == 101


def test_paired_intervals_rules(tmp_path):
    marks = [[T0, "arrive", "카페"], [T0 + 1000, "arrive", "식당"], [T0 + 5000, "depart", ""],
             [T0 + 6000, "depart", ""], [T0 + 9000, "arrive", ""]]
    s = load_session(make_session(tmp_path, gps=[gps_row(T0 + 20000, 0, 0)], marks=marks))
    # 다시 연 것(식당)이 쓰이고, 짝 없는 depart는 무시, 끝의 arrive는 세션 끝까지
    assert stay_intervals(s) == [Interval(T0 + 1000, T0 + 5000, "식당"), Interval(T0 + 9000, T0 + 20000, "")]
    assert paired_intervals(s.marks, "arrive", "depart") == [Interval(T0 + 1000, T0 + 5000, "식당")]


def test_vehicle_and_count_intervals(tmp_path):
    marks = [[T0, "board", "bus"], [T0 + 60_000, "alight", ""], [T0 + 70_000, "count_start", ""],
             [T0 + 170_000, "count_end", " 120 "], [T0 + 200_000, "board", "subway"]]
    s = load_session(make_session(tmp_path, gps=[gps_row(T0 + 300_000, 0, 0)], marks=marks))
    assert vehicle_intervals(s) == [Interval(T0, T0 + 60_000, "bus")]     # 내리지 않은 지하철은 뺀다
    assert count_intervals(s) == [Interval(T0 + 70_000, T0 + 170_000, "120")]
    assert Interval(T0, T0 + 60_000).duration_s == 60


def test_in_intervals_inclusive():
    mask = in_intervals([0, 5, 10, 11], [Interval(5, 10)])
    assert mask.tolist() == [False, True, True, False]
    assert in_intervals(np.array([1, 2]), []).tolist() == [False, False]


def test_carry_at(tmp_path):
    marks = [[T0 + 10, "carry", "pocket"], [T0 + 20, "carry", "bag"]]
    s = load_session(make_session(tmp_path, gps=[gps_row(T0, 0, 0)], marks=marks))
    assert carry_at(s, T0) == "hand"
    assert carry_at(s, T0 + 15) == "pocket"
    assert carry_at(s, T0 + 20) == "bag"
