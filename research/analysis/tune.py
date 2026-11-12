"""`python -m analysis.tune --config experiments.yaml` — hmm_steps의 β·σ 하한 격자 탐색(설계 6-3, route-guide 5절).

예비용(pilot) 세션만 쓴다. 평가용(eval) 세션을 보고 고르면 결과가 부풀려진다(설계 7-1).
β ∈ {2, 5, 10, 20, 50}m × σ 하한 ∈ {3, 5, 10}m마다 복원해 경로 오차 P95(세션 평균)가 가장 작은 조합을 고른다.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Callable

import numpy as np
import pandas as pd

from .config import load_experiment, load_sessions
from .path_metrics import path_metrics
from .reconstruct import ReconstructClient, ReconstructError, ServerUnavailable, read_fixes
from .replay import DartCli
from .session import load_session, truth_points, vehicle_intervals
from .stay_metrics import read_stays


def grid_search(evaluate: Callable[[float, float], list[float]], betas: list[float],
                sigmas: list[float]) -> tuple[pd.DataFrame, dict]:
    """evaluate(β, σ)는 세션마다 P95(m) 목록을 돌려준다. 가장 작은 평균 P95, 같으면 작은 β·σ를 고른다."""
    rows = []
    for b in betas:
        for s in sigmas:
            p95s = [v for v in evaluate(b, s) if v is not None]
            rows.append({"betaM": b, "sigmaMinM": s, "sessions": len(p95s),
                         "p95_mean_m": float(np.mean(p95s)) if p95s else None})
    table = pd.DataFrame(rows)
    ok = table.dropna(subset=["p95_mean_m"])
    if ok.empty:
        return table, {}
    best = ok.sort_values(["p95_mean_m", "betaM", "sigmaMinM"], kind="stable").iloc[0]
    return table, {"betaM": float(best["betaM"]), "sigmaMinM": float(best["sigmaMinM"]),
                   "p95_mean_m": float(best["p95_mean_m"]), "sessions": int(best["sessions"])}


def _utf8_console() -> None:
    """Git Bash 터미널(UTF-8)에서 한글이 깨지지 않게 출력 인코딩을 UTF-8로 맞춘다."""
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")


def main(argv: list[str] | None = None, cli=None, client=None) -> int:
    ap = argparse.ArgumentParser(prog="python -m analysis.tune", description="hmm_steps β·σ 하한 격자 탐색(pilot만)")
    ap.add_argument("--config", default="experiments.yaml")
    ap.add_argument("--data-dir")
    ap.add_argument("--results-dir")
    a = ap.parse_args(argv)
    _utf8_console()
    exp = load_experiment(Path(a.config), a.data_dir, a.results_dir)
    pilots = [s for s in load_sessions(exp.sessions_file) if s["use"] == "pilot"
              and (exp.data_dir / s["id"]).is_dir()]
    if not pilots:
        print("pilot 세션이 없습니다(sessions.yaml의 use: pilot, 폴더 있음).", file=sys.stderr)
        return 1
    if not exp.tune["runs"]:
        print("experiments.yaml의 tune.runs가 비어 있습니다.", file=sys.stderr)
        return 1
    cli = cli or DartCli(exp.package_dir, exp.dart)
    rec = exp.reconstruct
    client = client or ReconstructClient(rec["server_url"], rec["token"], rec["timeout_s"])

    inputs = []   # (세션 id, 재생 이름, 정답, 탈것 구간, 점, 머문 곳)
    for s in pilots:
        session = load_session(exp.data_dir / s["id"])
        truth = truth_points(session.gps, exp.truth_max_accuracy_m)
        for spec in exp.tune["runs"]:
            out = cli.replay(exp.data_dir / s["id"], spec, exp.results_dir / "replay" / s["id"] / spec.key)
            inputs.append((s["id"], spec.label, truth, vehicle_intervals(session), read_fixes(out), read_stays(out)))

    detail = []

    def evaluate(beta: float, sigma: float) -> list[float]:
        out = []
        for sid, label, truth, vehicles, fixes, stays in inputs:
            segs = client.reconstruct(fixes, stays, "hmm_steps", {"betaM": beta, "sigmaMinM": sigma})
            if segs and all(seg.get("fallback") for seg in segs):
                raise ServerUnavailable("모든 구간이 fallback — OSRM이 꺼져 있어 β·σ를 비교할 수 없다")
            p95 = path_metrics(truth, segs, vehicles, exp.truth_min_hop_m)["p95_m"]
            detail.append({"session": sid, "run": label, "betaM": beta, "sigmaMinM": sigma, "p95_m": p95})
            out.append(p95)
        return out

    try:
        table, best = grid_search(evaluate, exp.tune["betas"], exp.tune["sigmas"])
    except (ServerUnavailable, ReconstructError) as e:
        print(f"복원 서버를 쓸 수 없습니다: {e}", file=sys.stderr)
        return 2
    exp.results_dir.mkdir(parents=True, exist_ok=True)
    table.to_csv(exp.results_dir / "hmm_grid.csv", index=False)
    pd.DataFrame(detail).to_csv(exp.results_dir / "hmm_grid_by_session.csv", index=False)
    (exp.results_dir / "hmm_best.json").write_text(json.dumps(best, indent=2), encoding="utf-8")
    print(table.to_string(index=False))
    print(f"\n고른 값: {best}  → experiments.yaml reconstruct.methods에 고정한다")
    return 0


if __name__ == "__main__":
    sys.exit(main())
