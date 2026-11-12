"""`python -m analysis.run --config experiments.yaml` (research/에서). 설계 7-1의 순서대로 돈다.

1. 세션마다 재생 CLI(정책 × 설정)와 steps CLI(감지기마다)
2. 복원: 서버 없이 local_straight, 켜 두었으면 로컬 서버 POST /api/route/reconstruct(방법마다)
3. 지표 계산 → results/*.csv, 그래프 → results/figures/
서버에 연결하지 못하면 그 뒤 복원 호출은 건너뛰고, 돈 방법의 지표만 남긴다(skipped.csv에 이유).
"""
from __future__ import annotations

import argparse
import hashlib
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

# 세션 하나가 망가져도(깨진 meta.json, 빠진 summary.json, 지표 계산 오류 …) 나머지 세션은 계속 돌려야 한다.
# 몇 시간 걸리는 배치가 마지막 세션의 파일 하나 때문에 통째로 버려지지 않게, 예상할 수 있는 오류는 skipped.csv로 보낸다.
# (ValueError에는 JSON·pandas 파싱 오류가 들어 있다. 프로그래밍 실수까지 삼키지 않으려고 Exception 전체는 잡지 않는다.)
SESSION_ERRORS = (OSError, ValueError, KeyError, IndexError, TypeError, ArithmeticError, CliError)

# 표가 비어도 CSV 머리줄은 고정으로 쓴다. 안 그러면 한 세션도 못 돌았을 때 열이 없는 빈 파일이 나와
# 뒤 단계(그래프·다른 도구)가 열 이름을 못 찾고 죽는다. 아래는 각 행을 만드는 코드(run_experiment)가 쓰는 열이다.
_BASE_COLS = ["session", "use", "course"]
_RUN_COLS = ["run", "policy", "detector", "params", "ttff", "fixes", "fixes_per_hour", "gps_on_s", "duration_s"]
_STEP_COLS = ["detector", "total_steps", "count_intervals", "manual_steps", "detected_steps", "count_error_pct",
              "count_abs_error_pct", "vehicle_s", "vehicle_false_steps", "vehicle_false_steps_per_min",
              "walk_precision", "walk_recall", "first_step_latency_s"]
_CARRY_COLS = ["carry", "start_ms", "end_ms", "manual_steps", "detected_steps", "error_pct"]
_BATTERY_COLS = ["session", "device", "method", "excluded", "hours", "mah_used", "mah_per_h", "aligned",
                 "current_ma", "gps_s_total", "gps_s_app", "gps_on_s_est", "use"]
SKIPPED_COLS = ["session", "what", "reason"]


def table_columns() -> dict[str, list[str]]:
    """표마다 고정 열. 지표 열은 지표 함수에 빈 입력을 넣어 나온 키에서 뽑는다(열 목록을 따로 베끼면 어긋나므로)."""
    path_cols = list(path_metrics(pd.DataFrame(columns=["t_ms", "lat", "lng"]), [], []))
    stay_cols = list(stay_scores([], []))
    return {"path_metrics": _BASE_COLS + _RUN_COLS + ["method"] + path_cols,
            "stay_metrics": _BASE_COLS + _RUN_COLS + stay_cols,
            "step_metrics": _BASE_COLS + _STEP_COLS,
            "step_counts_by_carry": _BASE_COLS + ["detector"] + _CARRY_COLS,
            "battery_runs": _BATTERY_COLS}


def _frame(rows: list[dict], columns: list[str]) -> pd.DataFrame:
    """행이 있으면 그대로(새로 생긴 열도 보존), 없으면 머리줄만 있는 빈 표."""
    return pd.DataFrame(rows) if rows else pd.DataFrame(columns=columns)


def _cache_name(method: dict) -> str:
    """캐시 파일 이름. 같은 method 이름이라도 hmm 조정값이 다르면 다른 파일이어야 한다 — 안 그러면 β·σ를 바꿔 다시
    돌려도 옛 파라미터로 받은 응답이 그대로 쓰인다. 조정값이 없고 이름이 method와 같으면 예전 이름을 그대로 쓴다."""
    if not method.get("hmm") and method["name"] == method["method"]:
        return f"{method['name']}.json"
    key = json.dumps({"method": method["method"], "hmm": method.get("hmm")}, sort_keys=True, default=str)
    return f"{method['name']}-{hashlib.sha1(key.encode('utf-8')).hexdigest()[:8]}.json"


def _segments(method: dict, fixes, stays, client, cache: Path, force: bool,
              skip_all_fallback: bool = False) -> list[dict]:
    """복원 경로. 서버 응답은 cache(JSON)에 남겨 다음 실행에서 다시 부르지 않는다(지표만 고칠 때).

    skip_all_fallback이 켜져 있으면 전부 직선 대체인 응답은 캐시에 쓰지 않는다. OSRM이 꺼진 채 받은 응답을 저장하면
    OSRM을 켠 뒤 다시 돌려도 옛 직선 응답이 재사용돼 계속 "OSRM 꺼짐"으로 건너뛰기 때문이다."""
    if method["method"] == LOCAL:
        return local_straight(fixes)
    if cache.exists() and not force:
        try:
            cached = json.loads(cache.read_text(encoding="utf-8"))
        except ValueError:
            cached = None  # 쓰다 끊긴 캐시: 오류로 멈추지 말고 다시 받는다
        # 이미 저장돼 있는 전부-fallback 캐시(이 수정 전에 만들어진 것)도 같은 이유로 믿지 않는다
        if cached is not None and not (skip_all_fallback and _all_fallback(method, cached)):
            return cached
    segments = client.reconstruct(fixes, stays, method["method"], method["hmm"])
    if skip_all_fallback and _all_fallback(method, segments):
        return segments
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
    skip_all_fallback = exp.reconstruct["skip_all_fallback"]
    path_rows, stay_rows, step_rows, carry_rows, skipped, battery_rows = [], [], [], [], [], []

    for s in sessions:
        if only and s["id"] not in only:
            continue
        sdir = exp.data_dir / s["id"]
        if not sdir.is_dir():
            skipped.append({"session": s["id"], "what": "session", "reason": f"폴더 없음: {sdir}"})
            continue
        if s["use"] in exp.battery["use"]:
            try:
                battery_rows.append({**battery_run(sdir, exp.battery["current_units"], exp.battery["align_steps"],
                                                   exp.battery["package"]), "use": s["use"]})
            except SESSION_ERRORS as e:
                skipped.append({"session": s["id"], "what": "battery", "reason": f"{type(e).__name__}: {e}"})
        if s["use"] not in exp.uses:
            continue
        try:
            session = load_session(sdir)
            truth = truth_points(session.gps, exp.truth_max_accuracy_m)
            vehicles = vehicle_intervals(session)
            gt_stays = truth_stays(session, truth, exp.stay_min_truth_s)
        except SESSION_ERRORS as e:
            skipped.append({"session": s["id"], "what": "session", "reason": f"{type(e).__name__}: {e}"})
            continue
        base = {"session": s["id"], "use": s["use"], "course": s["course"]}

        for spec in exp.runs:
            out = exp.results_dir / "replay" / s["id"] / spec.key
            try:
                cli.replay(sdir, spec, out, force)
                summary = json.loads((out / "summary.json").read_text(encoding="utf-8"))
                fixes = read_fixes(out)
                stays = read_stays(out)
                run_info = {**base, "run": spec.label, "policy": spec.policy, "detector": spec.detector,
                            "params": " ".join(f"{k}={v}" for k, v in spec.params), "ttff": spec.ttff,
                            "fixes": summary.get("total_fixes"), "fixes_per_hour": summary.get("fixes_per_hour"),
                            "gps_on_s": summary.get("gps_on_s"), "duration_s": summary.get("duration_s")}
                stay_row = {**run_info, **stay_scores(stays, gt_stays, exp.stay_min_overlap,
                                                      exp.stay_max_distance_m)}
            except SESSION_ERRORS as e:
                # summary.json이 없거나 깨졌거나 fixes.csv를 못 읽는 경우도 여기로 온다: 이 설정만 건너뛴다
                skipped.append({"session": s["id"], "what": spec.label, "reason": str(e) or type(e).__name__})
                continue
            stay_rows.append(stay_row)
            for m in methods:
                cache = exp.results_dir / "recon" / s["id"] / spec.key / _cache_name(m)
                what = f"{spec.label} / {m['name']}"
                try:
                    segs = _segments(m, fixes, stays, client, cache, force, skip_all_fallback)
                    if _all_fallback(m, segs) and skip_all_fallback:
                        skipped.append({"session": s["id"], "what": what,
                                        "reason": "모든 구간이 직선 대체(fallback) — OSRM이 꺼져 있는 것 같다"})
                        continue
                    path_rows.append({**run_info, "method": m["name"],
                                      **path_metrics(truth, segs, vehicles, exp.truth_min_hop_m)})
                except (ServerUnavailable, ReconstructError) as e:
                    skipped.append({"session": s["id"], "what": what, "reason": str(e)})
                except SESSION_ERRORS as e:
                    skipped.append({"session": s["id"], "what": what, "reason": f"{type(e).__name__}: {e}"})

        for det in exp.step_detectors:
            out = exp.results_dir / "steps" / s["id"] / det
            try:
                cli.steps(sdir, det, out, force=force)
                step_row = {**base, **step_metrics(session, out)}
                _, _, summary = read_steps_output(out)
                carry = [{**base, "detector": det, **r} for r in count_rows_by_carry(session, summary)]
            except SESSION_ERRORS as e:
                skipped.append({"session": s["id"], "what": f"steps {det}", "reason": str(e) or type(e).__name__})
                continue
            step_rows.append(step_row)
            carry_rows += carry

    cols = table_columns()
    runs = _frame(battery_rows, cols["battery_runs"])
    return {"path_metrics": _frame(path_rows, cols["path_metrics"]),
            "stay_metrics": _frame(stay_rows, cols["stay_metrics"]),
            "step_metrics": _frame(step_rows, cols["step_metrics"]),
            "step_counts_by_carry": _frame(carry_rows, cols["step_counts_by_carry"]),
            "battery_runs": runs, "battery_summary": battery_summary(runs),
            "skipped": pd.DataFrame(skipped, columns=SKIPPED_COLS)}


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
    ap.add_argument("--data-dir", help="세션 폴더들의 상위 폴더. 상대경로는 현재 디렉터리 기준이다"
                                       "(기본: 설정의 data_dir, 설정 파일이 있는 폴더 기준)")
    ap.add_argument("--results-dir", help="결과 폴더. 상대경로는 현재 디렉터리 기준이다"
                                          "(기본: 설정의 results_dir, 설정 파일이 있는 폴더 기준)")
    ap.add_argument("--session", action="append", help="이 세션만(여러 번 줄 수 있다)")
    ap.add_argument("--force", action="store_true", help="재생·복원 캐시를 무시하고 다시 돈다")
    ap.add_argument("--no-reconstruct", action="store_true", help="서버 복원을 건너뛴다(local_straight만)")
    ap.add_argument("--no-plots", action="store_true")
    a = ap.parse_args(argv)
    _utf8_console()
    exp = load_experiment(Path(a.config), a.data_dir, a.results_dir)
    if a.session:
        # 오타 낸 id로 아무것도 안 돌고 "성공"으로 끝나면 결과가 비어 있는 이유를 한참 찾게 된다. 시작 전에 막는다.
        known = {s["id"] for s in load_sessions(exp.sessions_file)}
        unknown = [i for i in a.session if i not in known]
        if unknown:
            ap.error(f"sessions.yaml에 없는 세션 id: {', '.join(unknown)} (있는 id: {', '.join(sorted(known))})")
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
