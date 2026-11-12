"""`python -m analysis.run --config experiments.yaml` (research/에서). 설계 7-1의 순서대로 돈다.

1. 세션마다 재생 CLI(정책 × 설정)와 steps CLI(감지기마다)
2. 복원: 서버 없이 local_straight, 켜 두었으면 로컬 서버 POST /api/route/reconstruct(방법마다)
3. 지표 계산 → results/*.csv, 그래프 → results/figures/
서버에 연결하지 못하면 그 뒤 복원 호출은 건너뛰고, 돈 방법의 지표만 남긴다(skipped.csv에 이유).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import pandas as pd

from .battery import battery_run, battery_summary
from .config import Experiment, load_experiment, load_sessions
from .path_metrics import local_straight, path_metrics
from .reconstruct import ReconstructClient, ReconstructError, ServerUnavailable, read_fixes
from .replay import CliError, DartCli
from .session import load_session, truth_points, vehicle_intervals
from .stay_metrics import read_stays, stay_scores, truth_stays
from .step_metrics import count_rows_by_carry, read_steps_output, step_metrics

LOCAL = "local_straight"


def _segments(method: dict, fixes, stays, client, cache: Path, force: bool) -> list[dict]:
    """복원 경로. 서버 응답은 cache(JSON)에 남겨 다음 실행에서 다시 부르지 않는다(지표만 고칠 때)."""
    if method["method"] == LOCAL:
        return local_straight(fixes)
    if cache.exists() and not force:
        return json.loads(cache.read_text(encoding="utf-8"))
    segments = client.reconstruct(fixes, stays, method["method"], method["hmm"])
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(segments), encoding="utf-8")
    return segments


def _all_fallback(method: dict, segments: list[dict]) -> bool:
    """도로에 맞추는 방법인데 모든 구간이 fallback이면 사실상 직선이다. 그 이름으로 지표를 내면 오해를 부른다."""
    return method["method"] not in (LOCAL, "straight") and bool(segments) and \
        all(seg.get("fallback") for seg in segments)


def run_experiment(exp: Experiment, cli: DartCli, client: ReconstructClient | None,
                   only: list[str] | None = None, force: bool = False) -> dict[str, pd.DataFrame]:
    sessions = load_sessions(exp.sessions_file)
    methods = ([{"name": LOCAL, "method": LOCAL, "hmm": None}] if exp.local_straight else []) + \
        (exp.reconstruct["methods"] if client is not None else [])
    path_rows, stay_rows, step_rows, carry_rows, skipped, battery_rows = [], [], [], [], [], []

    for s in sessions:
        if only and s["id"] not in only:
            continue
        sdir = exp.data_dir / s["id"]
        if not sdir.is_dir():
            skipped.append({"session": s["id"], "what": "session", "reason": f"폴더 없음: {sdir}"})
            continue
        if s["use"] in exp.battery["use"]:
            battery_rows.append({**battery_run(sdir, exp.battery["current_units"], exp.battery["align_steps"],
                                               exp.battery["package"]), "use": s["use"]})
        if s["use"] not in exp.uses:
            continue
        session = load_session(sdir)
        truth = truth_points(session.gps, exp.truth_max_accuracy_m)
        vehicles = vehicle_intervals(session)
        gt_stays = truth_stays(session, truth, exp.stay_min_truth_s)
        base = {"session": s["id"], "use": s["use"], "course": s["course"]}

        for spec in exp.runs:
            out = exp.results_dir / "replay" / s["id"] / spec.key
            try:
                cli.replay(sdir, spec, out, force)
            except CliError as e:
                skipped.append({"session": s["id"], "what": spec.label, "reason": str(e)})
                continue
            summary = json.loads((out / "summary.json").read_text(encoding="utf-8"))
            fixes = read_fixes(out)
            stays = read_stays(out)
            run_info = {**base, "run": spec.label, "policy": spec.policy, "detector": spec.detector,
                        "params": " ".join(f"{k}={v}" for k, v in spec.params), "ttff": spec.ttff,
                        "fixes": summary.get("total_fixes"), "fixes_per_hour": summary.get("fixes_per_hour"),
                        "gps_on_s": summary.get("gps_on_s"), "duration_s": summary.get("duration_s")}
            stay_rows.append({**run_info, **stay_scores(stays, gt_stays, exp.stay_min_overlap,
                                                        exp.stay_max_distance_m)})
            for m in methods:
                cache = exp.results_dir / "recon" / s["id"] / spec.key / f"{m['name']}.json"
                try:
                    segs = _segments(m, fixes, stays, client, cache, force)
                except (ServerUnavailable, ReconstructError) as e:
                    skipped.append({"session": s["id"], "what": f"{spec.label} / {m['name']}", "reason": str(e)})
                    continue
                if _all_fallback(m, segs) and exp.reconstruct["skip_all_fallback"]:
                    skipped.append({"session": s["id"], "what": f"{spec.label} / {m['name']}",
                                    "reason": "모든 구간이 직선 대체(fallback) — OSRM이 꺼져 있는 것 같다"})
                    continue
                path_rows.append({**run_info, "method": m["name"],
                                  **path_metrics(truth, segs, vehicles, exp.truth_min_hop_m)})

        for det in exp.step_detectors:
            out = exp.results_dir / "steps" / s["id"] / det
            try:
                cli.steps(sdir, det, out, force=force)
            except CliError as e:
                skipped.append({"session": s["id"], "what": f"steps {det}", "reason": str(e)})
                continue
            step_rows.append({**base, **step_metrics(session, out)})
            _, _, summary = read_steps_output(out)
            carry_rows += [{**base, "detector": det, **r} for r in count_rows_by_carry(session, summary)]

    runs = pd.DataFrame(battery_rows)
    return {"path_metrics": pd.DataFrame(path_rows), "stay_metrics": pd.DataFrame(stay_rows),
            "step_metrics": pd.DataFrame(step_rows), "step_counts_by_carry": pd.DataFrame(carry_rows),
            "battery_runs": runs, "battery_summary": battery_summary(runs),
            "skipped": pd.DataFrame(skipped, columns=["session", "what", "reason"])}


def write_tables(tables: dict[str, pd.DataFrame], results_dir: Path) -> None:
    results_dir.mkdir(parents=True, exist_ok=True)
    for name, df in tables.items():
        df.to_csv(results_dir / f"{name}.csv", index=False, encoding="utf-8")


def _print_summary(tables: dict[str, pd.DataFrame]) -> None:
    p = tables["path_metrics"]
    if not p.empty:
        cols = ["session", "run", "method", "fixes", "gps_on_s", "mean_m", "p95_m", "dist_err_pct", "fallback_share"]
        print(p[cols].to_string(index=False, float_format=lambda v: f"{v:.1f}"))
    for name in ["stay_metrics", "step_metrics", "battery_summary"]:
        if not tables[name].empty:
            print(f"\n[{name}] {len(tables[name])}행")
    if not tables["skipped"].empty:
        print(f"\n건너뜀 {len(tables['skipped'])}건 (skipped.csv)")


def _utf8_console() -> None:
    """Git Bash 터미널(UTF-8)에서 한글이 깨지지 않게 출력 인코딩을 UTF-8로 맞춘다."""
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m analysis.run", description="R6 분석 실행(설계 7-1)")
    ap.add_argument("--config", default="experiments.yaml")
    ap.add_argument("--data-dir", help="세션 폴더들의 상위 폴더(기본: 설정의 data_dir)")
    ap.add_argument("--results-dir", help="결과 폴더(기본: 설정의 results_dir)")
    ap.add_argument("--session", action="append", help="이 세션만(여러 번 줄 수 있다)")
    ap.add_argument("--force", action="store_true", help="재생·복원 캐시를 무시하고 다시 돈다")
    ap.add_argument("--no-reconstruct", action="store_true", help="서버 복원을 건너뛴다(local_straight만)")
    ap.add_argument("--no-plots", action="store_true")
    a = ap.parse_args(argv)
    _utf8_console()
    exp = load_experiment(Path(a.config), a.data_dir, a.results_dir)
    cli = DartCli(exp.package_dir, exp.dart)
    rec = exp.reconstruct
    client = None if a.no_reconstruct or not rec["enabled"] else \
        ReconstructClient(rec["server_url"], rec["token"], rec["timeout_s"])
    tables = run_experiment(exp, cli, client, a.session, a.force)
    write_tables(tables, exp.results_dir)
    if exp.plots and not a.no_plots:
        from .plots import make_all
        for f in make_all(tables, exp.results_dir / "figures"):
            print(f"그림: {f}")
    _print_summary(tables)
    print(f"\n결과: {exp.results_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
