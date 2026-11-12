"""좌표 계산. 한 세션(도시 하나) 안에서는 기준 위도에서 편 평면 좌표(m)로 충분하다."""
from __future__ import annotations

import math

import numpy as np

EARTH_RADIUS_M = 6_371_000.0


class LocalProjection:
    """기준점 둘레를 평면(동쪽 x, 북쪽 y, m)으로 편다. 수 km 안에서 오차는 0.1% 미만이다."""

    def __init__(self, lat0: float, lng0: float):
        self.lat0 = lat0
        self.lng0 = lng0
        self._kx = math.radians(1) * EARTH_RADIUS_M * math.cos(math.radians(lat0))
        self._ky = math.radians(1) * EARTH_RADIUS_M

    def to_xy(self, lat, lng) -> np.ndarray:
        lat = np.asarray(lat, dtype=float)
        lng = np.asarray(lng, dtype=float)
        return np.stack([(lng - self.lng0) * self._kx, (lat - self.lat0) * self._ky], axis=-1)

    def to_latlng(self, x, y) -> tuple[np.ndarray, np.ndarray]:
        x = np.asarray(x, dtype=float)
        y = np.asarray(y, dtype=float)
        return self.lat0 + y / self._ky, self.lng0 + x / self._kx


def offset(lat: float, lng: float, east_m: float, north_m: float) -> tuple[float, float]:
    """(lat, lng)에서 동쪽·북쪽으로 몇 m 옮긴 좌표. 테스트용 합성 경로를 만들 때 쓴다."""
    proj = LocalProjection(lat, lng)
    la, ln = proj.to_latlng(east_m, north_m)
    return float(la), float(ln)


def distance_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """두 점 사이 거리(m). 기준점을 첫 점으로 한 평면 근사다."""
    xy = LocalProjection(lat1, lng1).to_xy([lat1, lat2], [lng1, lng2])
    return float(np.hypot(*(xy[1] - xy[0])))


def polyline_length(xy: np.ndarray) -> float:
    """평면 좌표 꺾은선의 길이(m)."""
    xy = np.asarray(xy, dtype=float)
    if len(xy) < 2:
        return 0.0
    return float(np.hypot(*np.diff(xy, axis=0).T).sum())


def point_to_segments_distance(points: np.ndarray, starts: np.ndarray, ends: np.ndarray,
                               chunk: int = 512) -> np.ndarray:
    """점마다 선분 묶음 중 가장 가까운 선분까지의 거리(m). 점 하나짜리 선분(start == end)은 점까지 거리다.

    정답 점(시간당 3600개)과 선분(연속 측위면 수천 개)을 한꺼번에 곱하면 메모리가 커서 점을 [chunk]개씩 나눈다.
    """
    points = np.asarray(points, dtype=float).reshape(-1, 2)
    starts = np.asarray(starts, dtype=float).reshape(-1, 2)
    ends = np.asarray(ends, dtype=float).reshape(-1, 2)
    if len(starts) == 0:
        raise ValueError("선분이 없습니다")
    d = ends - starts                       # (S, 2)
    len2 = (d ** 2).sum(axis=1)             # (S,)
    safe = np.where(len2 > 0, len2, 1.0)
    out = np.empty(len(points))
    for k in range(0, len(points), chunk):
        p = points[k:k + chunk, None, :]    # (P, 1, 2)
        t = ((p - starts) * d).sum(axis=2) / safe
        t = np.where(len2 > 0, np.clip(t, 0.0, 1.0), 0.0)
        nearest = starts + t[..., None] * d  # (P, S, 2)
        out[k:k + chunk] = np.sqrt(((p - nearest) ** 2).sum(axis=2)).min(axis=1)
    return out
