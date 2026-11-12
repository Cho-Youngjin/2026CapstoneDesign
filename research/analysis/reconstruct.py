"""서버 경로 복원 API 호출(route-guide). 서버나 OSRM이 없어도 분석이 끝까지 돌도록 실패를 값으로 돌려준다."""
from __future__ import annotations

import math
import warnings
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
    if max_points < 2:
        # 조각마다 마지막 점을 겹쳐 max_points-1칸씩 전진하므로 2 미만이면 k가 늘지 않아 무한 루프에 빠진다.
        raise ValueError(f"max_points는 2 이상이어야 합니다: {max_points}")
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
        in_chunk = [s for s in all_stays if s["leave"] >= lo and s["arrive"] <= hi]
        if len(in_chunk) > MAX_STAYS:
            # 서버 상한 때문에 자를 수밖에 없지만, 조용히 자르면 머문 곳이 사라진 줄 모르고 지표를 읽게 된다.
            warnings.warn(f"머문 곳 {len(in_chunk)}개가 상한 {MAX_STAYS}을 넘어 뒤쪽을 잘랐습니다", stacklevel=2)
        body = {"method": method, "points": chunk, "stays": in_chunk[:MAX_STAYS]}
        if hmm:
            body["hmm"] = hmm
        out.append(body)
    return out


class ServerUnavailable(RuntimeError):
    """서버에 연결하지 못했다. 이후 호출도 건너뛴다."""


class ReconstructError(RuntimeError):
    """서버가 200이 아닌 응답을 줬거나 읽기 시간이 초과됐거나 본문이 깨졌다. 다음 호출은 다시 서버로 보낸다."""


class ReconstructAuthError(ReconstructError):
    """401/403. 토큰이 틀린 것이라 이후 호출도 모두 실패하므로 건너뛴다. run.py·tune.py는 ReconstructError로 잡는다."""


def _default_post(*args, **kwargs):
    import requests
    try:
        return requests.post(*args, **kwargs)
    except (requests.ConnectionError, requests.ConnectTimeout) as e:
        # 연결 자체가 안 되는 경우만 "서버 꺼짐"(이후 호출 전부 건너뜀)으로 본다.
        raise ServerUnavailable(str(e)) from e
    except requests.Timeout as e:
        # ReadTimeout은 느린 hmm_steps 요청 하나가 길어진 것일 수 있다. 서버는 살아 있으니 다음 호출은 보낸다.
        raise ReconstructError(f"읽기 시간 초과: {e}") from e


@dataclass
class ReconstructClient:
    """POST /api/route/reconstruct. local 프로필 서버는 더미 토큰 dev-fake-token을 받는다(route-guide 2절)."""
    base_url: str = "http://localhost:9090"
    token: str = field(default="dev-fake-token", repr=False)    # repr·로그에 토큰이 찍히지 않게
    timeout_s: float = 120
    post: Callable = field(default=_default_post)
    unavailable: bool = False
    auth_failed: bool = False

    def reconstruct(self, fixes: pd.DataFrame, stays: list[dict], method: str,
                    hmm: dict | None = None) -> list[dict]:
        if self.unavailable:
            raise ServerUnavailable("앞선 호출에서 서버에 연결하지 못했습니다")
        if self.auth_failed:
            raise ReconstructAuthError("앞선 호출에서 인증에 실패했습니다(401/403)")
        segments: list[dict] = []
        for body in build_requests(fixes, stays, method, hmm):
            try:
                resp = self.post(f"{self.base_url.rstrip('/')}/api/route/reconstruct", json=body,
                                 headers={"Authorization": f"Bearer {self.token}"}, timeout=self.timeout_s)
            except ServerUnavailable:
                self.unavailable = True
                raise
            if resp.status_code in (401, 403):
                self.auth_failed = True
                raise ReconstructAuthError(f"{resp.status_code}: {resp.text[:300]}")
            if resp.status_code != 200:
                raise ReconstructError(f"{resp.status_code}: {resp.text[:300]}")
            try:
                data = resp.json()
            except ValueError as e:                  # 200인데 본문이 JSON이 아닌 경우(프록시 오류 페이지 등)
                raise ReconstructError(f"응답 본문이 JSON이 아닙니다: {resp.text[:300]}") from e
            if not isinstance(data, dict):
                raise ReconstructError(f"응답 본문 형식이 올바르지 않습니다: {str(data)[:300]}")
            segments += data.get("segments", [])
        return segments
