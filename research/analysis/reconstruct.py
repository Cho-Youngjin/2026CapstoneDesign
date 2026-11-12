"""서버 경로 복원 API 호출(route-guide). 서버나 OSRM이 없어도 분석이 끝까지 돌도록 실패를 값으로 돌려준다."""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

import pandas as pd

MAX_POINTS = 2000
MAX_STAYS = 500


def _num(v):
    if v is None or (isinstance(v, float) and math.isnan(v)) or v == "":
        return None
    return v


def read_fixes(replay_dir: Path) -> pd.DataFrame:
    """재생기·정책 실행 모드의 fixes.csv(같은 형식)."""
    return pd.read_csv(Path(replay_dir) / "fixes.csv", keep_default_na=False, na_values=[""])


def to_points(fixes: pd.DataFrame) -> list[dict]:
    """fixes.csv 행 → 요청 points(t_ms→t, accuracy_m→accuracy, steps_since_prev→stepsSincePrev, state)."""
    out = []
    for r in fixes.sort_values("t_ms", kind="stable").itertuples():
        steps = _num(getattr(r, "steps_since_prev", None))
        acc = _num(getattr(r, "accuracy_m", None))
        state = _num(getattr(r, "state", None))
        out.append({"t": int(r.t_ms), "lat": float(r.lat), "lng": float(r.lng),
                    "accuracy": float(acc) if acc is not None else None,
                    "stepsSincePrev": int(steps) if steps is not None else None,
                    "state": str(state) if state is not None else None})
    return out


def to_stays(stays: list[dict]) -> list[dict]:
    return [{"arrive": s["arrive_ms"], "leave": s["leave_ms"], "lat": s["lat"], "lng": s["lng"]} for s in stays]


def build_requests(fixes: pd.DataFrame, stays: list[dict], method: str, hmm: dict | None = None,
                   max_points: int = MAX_POINTS) -> list[dict]:
    """요청 본문 목록. 점이 상한(2000)을 넘으면(연속 측위 몇 시간) 앞 조각의 마지막 점을 다음 조각의 첫 점으로
    겹쳐 나눈다 — 이어 붙인 경로가 끊기지 않는다. 머문 곳은 조각 시간 범위와 겹치는 것만 넣는다."""
    points = to_points(fixes)
    all_stays = to_stays(stays)
    chunks, k = [], 0
    while True:
        chunk = points[k:k + max_points]
        chunks.append(chunk)
        if k + max_points >= len(points):
            break
        k += max_points - 1
    out = []
    for chunk in chunks:
        lo, hi = (chunk[0]["t"], chunk[-1]["t"]) if chunk else (0, 0)
        body = {"method": method, "points": chunk,
                "stays": [s for s in all_stays if s["leave"] >= lo and s["arrive"] <= hi][:MAX_STAYS]}
        if hmm:
            body["hmm"] = hmm
        out.append(body)
    return out


class ServerUnavailable(RuntimeError):
    """서버에 연결하지 못했다. 이후 호출도 건너뛴다."""


class ReconstructError(RuntimeError):
    """서버가 200이 아닌 응답을 줬다(요청 형식·상한 문제)."""


def _default_post(*args, **kwargs):
    import requests
    try:
        return requests.post(*args, **kwargs)
    except (requests.ConnectionError, requests.Timeout) as e:
        raise ServerUnavailable(str(e)) from e


@dataclass
class ReconstructClient:
    """POST /api/route/reconstruct. local 프로필 서버는 더미 토큰 dev-fake-token을 받는다(route-guide 2절)."""
    base_url: str = "http://localhost:9090"
    token: str = "dev-fake-token"
    timeout_s: float = 120
    post: Callable = field(default=_default_post)
    unavailable: bool = False

    def reconstruct(self, fixes: pd.DataFrame, stays: list[dict], method: str,
                    hmm: dict | None = None) -> list[dict]:
        if self.unavailable:
            raise ServerUnavailable("앞선 호출에서 서버에 연결하지 못했습니다")
        segments: list[dict] = []
        for body in build_requests(fixes, stays, method, hmm):
            try:
                resp = self.post(f"{self.base_url.rstrip('/')}/api/route/reconstruct", json=body,
                                 headers={"Authorization": f"Bearer {self.token}"}, timeout=self.timeout_s)
            except ServerUnavailable:
                self.unavailable = True
                raise
            if resp.status_code != 200:
                raise ReconstructError(f"{resp.status_code}: {resp.text[:300]}")
            segments += resp.json().get("segments", [])
        return segments
