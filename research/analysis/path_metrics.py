"""수집·복원 지표(설계 7-2 첫 줄): 1초 정답 점마다 복원 경로까지 거리, 이동거리 오차.

복원 경로는 서버 응답과 같은 모양의 구간 목록이다: [{"kind", "coords": [{"lat", "lng"}…], "fallback"}].
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from .geo import LocalProjection, point_to_segments_distance, polyline_length
from .session import Interval, in_intervals


def local_straight(fixes: pd.DataFrame) -> list[dict]:
    """서버 없이 쓰는 기준선: 남은 점을 시각순으로 직선으로 잇는다.

    서버 `straight`와 달리 머문 곳 중심 치환·10분 공백(estimated) 처리를 하지 않는다. 서버가 꺼져 있어도
    분석이 끝까지 돌게 하려는 것이라 결과표에는 method = local_straight로 따로 적는다.
    """
    if fixes.empty:
        return []
    f = fixes.sort_values("t_ms", kind="stable")
    coords = [{"lat": float(a), "lng": float(b)} for a, b in zip(f["lat"], f["lng"])]
    return [{"kind": "walk", "coords": coords, "fallback": False}]


def segments_to_xy(segments: list[dict], proj: LocalProjection) -> tuple[np.ndarray, np.ndarray]:
    """구간 목록을 선분 시작·끝 배열로 바꾼다. 좌표 하나짜리 구간은 길이 0 선분(점)이 된다."""
    starts, ends = [], []
    for seg in segments:
        coords = seg.get("coords") or []
        if not coords:
            continue
        xy = proj.to_xy([c["lat"] for c in coords], [c["lng"] for c in coords]).reshape(-1, 2)
        if len(xy) == 1:
            starts.append(xy)
            ends.append(xy)
        else:
            starts.append(xy[:-1])
            ends.append(xy[1:])
    if not starts:
        return np.empty((0, 2)), np.empty((0, 2))
    return np.concatenate(starts), np.concatenate(ends)


def segments_length(segments: list[dict], proj: LocalProjection) -> float:
    total = 0.0
    for seg in segments:
        coords = seg.get("coords") or []
        if len(coords) >= 2:
            total += polyline_length(proj.to_xy([c["lat"] for c in coords], [c["lng"] for c in coords]))
    return total


def truth_length(truth_xy: np.ndarray, min_hop_m: float = 10.0) -> float:
    """정답 이동거리. 마지막으로 센 점에서 min_hop_m 이상 벗어난 점만 이어, 서 있는 동안의 GPS 흔들림
    (실내 약 7초 간격, 몇 m씩)이 거리로 쌓이지 않게 한다. min_hop_m = 0이면 모든 점을 잇는다."""
    truth_xy = np.asarray(truth_xy, dtype=float).reshape(-1, 2)
    if len(truth_xy) < 2:
        return 0.0
    total = 0.0
    last = truth_xy[0]
    for p in truth_xy[1:]:
        hop = float(np.hypot(*(p - last)))
        if hop >= min_hop_m:
            total += hop
            last = p
    return total


def _stats(d: np.ndarray) -> tuple[float | None, float | None]:
    if len(d) == 0:
        return None, None
    return float(d.mean()), float(np.percentile(d, 95))


def path_metrics(truth: pd.DataFrame, segments: list[dict], vehicles: list[Interval],
                 min_hop_m: float = 10.0) -> dict:
    """정답 점(정확도 필터를 거친 gps 행) ↔ 복원 경로.

    - mean_m·p95_m: 정답 점마다 경로(모든 구간)까지 가장 가까운 거리의 평균·95백분위
    - walk_*·vehicle_*: 정답 점의 시각이 board~alight 안이면 탈것, 아니면 도보로 나눈 같은 값
    - dist_err_pct: (복원 경로 길이 − 정답 이동거리) ÷ 정답 이동거리 × 100
    - fallback_share: 서버가 직선으로 대신 채운 구간의 비율(구간 수 기준)
    """
    row: dict = {"n_truth": int(len(truth)), "n_segments": len(segments),
                 "fallback_share": (sum(bool(s.get("fallback")) for s in segments) / len(segments))
                 if segments else None}
    keys = ["mean_m", "p95_m", "walk_n", "walk_mean_m", "walk_p95_m", "vehicle_n", "vehicle_mean_m",
            "vehicle_p95_m", "path_length_m", "truth_length_m", "dist_err_pct"]
    row.update({k: None for k in keys})
    if truth.empty:
        return row
    proj = LocalProjection(float(truth["lat"].iloc[0]), float(truth["lng"].iloc[0]))
    truth_xy = proj.to_xy(truth["lat"].to_numpy(), truth["lng"].to_numpy())
    row["truth_length_m"] = truth_length(truth_xy, min_hop_m)
    starts, ends = segments_to_xy(segments, proj)
    if len(starts) == 0:
        return row
    d = point_to_segments_distance(truth_xy, starts, ends)
    is_vehicle = in_intervals(truth["t_ms"].to_numpy(), vehicles)
    row["mean_m"], row["p95_m"] = _stats(d)
    row["walk_n"] = int((~is_vehicle).sum())
    row["walk_mean_m"], row["walk_p95_m"] = _stats(d[~is_vehicle])
    row["vehicle_n"] = int(is_vehicle.sum())
    row["vehicle_mean_m"], row["vehicle_p95_m"] = _stats(d[is_vehicle])
    row["path_length_m"] = segments_length(segments, proj)
    if row["truth_length_m"] > 0:
        row["dist_err_pct"] = (row["path_length_m"] - row["truth_length_m"]) / row["truth_length_m"] * 100
    return row
