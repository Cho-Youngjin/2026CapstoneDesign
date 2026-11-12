"""머문 곳 지표(설계 7-2): 검출한 머문 곳(stays.csv)을 arrive~depart 표시와 견준 정밀도·재현율·F1."""
from __future__ import annotations

from pathlib import Path

import pandas as pd

from .geo import distance_m
from .session import Session, stay_intervals


def truth_stays(session: Session, truth: pd.DataFrame, min_stay_s: float = 600) -> list[dict]:
    """정답 머문 곳 = arrive~depart 중 min_stay_s 이상인 것(분석 기준 T = 10분과 같다, recording-guide).

    중심은 그 구간 안 정답 점(정확도 필터 후)의 평균이다. 점이 없으면(실내에서 GPS가 끊김) 중심을 모르므로
    None으로 두고, 짝지을 때 거리 조건을 보지 않는다.
    """
    out = []
    for iv in stay_intervals(session):
        if iv.duration_s < min_stay_s:
            continue
        inside = truth[(truth["t_ms"] >= iv.start_ms) & (truth["t_ms"] <= iv.end_ms)]
        out.append({"arrive_ms": iv.start_ms, "leave_ms": iv.end_ms,
                    "lat": float(inside["lat"].mean()) if len(inside) else None,
                    "lng": float(inside["lng"].mean()) if len(inside) else None})
    return out


def read_stays(replay_dir: Path) -> list[dict]:
    path = Path(replay_dir) / "stays.csv"
    if not path.exists():
        return []
    df = pd.read_csv(path)
    return [{"arrive_ms": int(r.arrive_ms), "leave_ms": int(r.leave_ms), "lat": float(r.lat), "lng": float(r.lng)}
            for r in df.itertuples()]


def _overlap_ms(a: dict, b: dict) -> int:
    return max(0, min(a["leave_ms"], b["leave_ms"]) - max(a["arrive_ms"], b["arrive_ms"]))


def is_match(detected: dict, truth: dict, min_overlap: float = 0.5, max_distance_m: float = 100) -> bool:
    """겹친 시간이 두 머문 곳 각각의 min_overlap 이상이고, 중심이 max_distance_m 이내면 같은 곳이다.

    '각각'으로 재는 이유: 하루를 통째로 덮는 머문 곳 하나가 그 안의 정답 여럿과 모두 맞는 것을 막는다.
    """
    ov = _overlap_ms(detected, truth)
    longest = max(detected["leave_ms"] - detected["arrive_ms"], truth["leave_ms"] - truth["arrive_ms"])
    if longest <= 0 or ov < min_overlap * longest:
        return False
    if truth.get("lat") is None:
        return True
    return distance_m(detected["lat"], detected["lng"], truth["lat"], truth["lng"]) <= max_distance_m


def stay_scores(detected: list[dict], truth: list[dict], min_overlap: float = 0.5,
                max_distance_m: float = 100) -> dict:
    """일대일로 짝짓는다(겹친 시간이 긴 쌍부터). 분모가 0인 값은 None이다."""
    pairs = [(_overlap_ms(d, t), i, j) for i, d in enumerate(detected) for j, t in enumerate(truth)
             if is_match(d, t, min_overlap, max_distance_m)]
    used_d, used_t, tp = set(), set(), 0
    for _, i, j in sorted(pairs, key=lambda p: (-p[0], p[1], p[2])):
        if i in used_d or j in used_t:
            continue
        used_d.add(i)
        used_t.add(j)
        tp += 1
    precision = tp / len(detected) if detected else None
    recall = tp / len(truth) if truth else None
    if precision is None or recall is None:
        f1 = None
    else:
        f1 = 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)
    return {"stays_detected": len(detected), "stays_truth": len(truth), "stay_tp": tp,
            "stay_precision": precision, "stay_recall": recall, "stay_f1": f1}
