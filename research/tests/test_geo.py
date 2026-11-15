import math

import numpy as np
import pytest

from analysis.geo import LocalProjection, distance_m, offset, point_to_segments_distance, polyline_length
from conftest import LAT0, LNG0


def test_offset_and_distance_round_trip():
    lat, lng = offset(LAT0, LNG0, 30.0, 40.0)
    assert distance_m(LAT0, LNG0, lat, lng) == pytest.approx(50.0, abs=0.01)


def test_projection_round_trip():
    proj = LocalProjection(LAT0, LNG0)
    xy = proj.to_xy([LAT0, LAT0 + 0.001], [LNG0, LNG0 + 0.001])
    lat, lng = proj.to_latlng(xy[:, 0], xy[:, 1])
    assert lat[1] == pytest.approx(LAT0 + 0.001)
    assert lng[1] == pytest.approx(LNG0 + 0.001)
    # 위도 0.001도 ≈ 111.19m
    assert xy[1, 1] == pytest.approx(111.19, abs=0.01)


def test_projection_east_scale_uses_cos_lat():
    # 경도 0.001도는 위도 0.001도(111.19m)에 cos(위도)를 곱한 길이다. cos을 빼먹으면 111.19m가 되어 걸린다.
    proj = LocalProjection(LAT0, LNG0)
    xy = proj.to_xy([LAT0], [LNG0 + 0.001])
    expected = 111.19 * math.cos(math.radians(LAT0))
    assert expected == pytest.approx(88.1, abs=0.1)
    assert xy[0, 0] == pytest.approx(expected, abs=0.1)
    assert xy[0, 1] == pytest.approx(0.0, abs=1e-9)


def test_polyline_length():
    assert polyline_length(np.array([[0, 0], [3, 4], [3, 10]])) == pytest.approx(11.0)
    assert polyline_length(np.array([[1, 1]])) == 0.0


def test_point_to_segments_distance_cases():
    starts = np.array([[0, 0], [20, 20]])
    ends = np.array([[10, 0], [20, 20]])        # 둘째 선분은 점 하나
    pts = np.array([[5, 3], [-4, 0], [13, 4], [20, 25]])
    d = point_to_segments_distance(pts, starts, ends, chunk=2)
    # (5,3)→선분 안 3m, (-4,0)→끝점(0,0) 4m, (13,4)→끝점(10,0) 5m, (20,25)→점 (20,20) 5m
    assert d == pytest.approx([3.0, 4.0, 5.0, 5.0])


def test_point_to_segments_requires_segments():
    with pytest.raises(ValueError):
        point_to_segments_distance(np.array([[0, 0]]), np.empty((0, 2)), np.empty((0, 2)))
