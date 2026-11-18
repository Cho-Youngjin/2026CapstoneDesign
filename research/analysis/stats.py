"""세션 단위 짝 비교(설계 7-3 보강, 2026-11-18).

같은 정답 기록을 모든 방식이 재생하므로, 방식끼리는 세션마다 짝을 지어 비교할 수 있다. 세션 사이 차이(코스·날씨·
사람)가 짝 안에서 지워져, 세션 수가 적어도 평균만 견주는 것보다 차이를 분명히 볼 수 있다.

- 이긴 세션 수: 기준 방식보다 지표가 낮은(좋은) 세션 수. 같으면 무승부.
- 부호 검정: 무승부를 뺀 이긴·진 세션 수로 정확 이항 검정(양측). 분포를 가정하지 않는다.
- 부트스트랩 95% 구간: 세션을 복원 추출해 '제안 ÷ 기준' 평균 비율과 중앙값 차이의 구간을 낸다(시드 고정).
"""
from __future__ import annotations

from math import comb

import numpy as np
import pandas as pd

LOWER_IS_BETTER = {"p95_m", "mean_m", "gps_on_s", "fixes", "fixes_per_hour", "walk_p95_m", "vehicle_p95_m",
                   "abs_dist_err_pct"}

PAIRED_COLS = ["method", "target", "baseline", "metric", "n", "wins", "losses", "ties", "sign_p",
               "target_mean", "baseline_mean", "ratio", "ratio_lo", "ratio_hi",
               "median_diff", "diff_lo", "diff_hi"]


def sign_test_p(wins: int, losses: int) -> float:
    """정확 이항 부호 검정(양측). 무승부는 미리 뺀다. 표본이 없으면 1."""
    n = wins + losses
    if n == 0:
        return 1.0
    k = min(wins, losses)
    tail = sum(comb(n, i) for i in range(k + 1)) / 2 ** n
    return float(min(1.0, 2 * tail))


def _bootstrap(idx_count: int, stat, reps: int, seed: int) -> tuple[float, float]:
    """세션 번호를 복원 추출해 stat(뽑힌 번호 배열)의 2.5%·97.5% 분위수. 값을 못 내는 표본은 버린다."""
    if idx_count < 2 or reps <= 0:
        return (np.nan, np.nan)
    rng = np.random.default_rng(seed)
    vals = []
    for _ in range(reps):
        v = stat(rng.integers(0, idx_count, idx_count))
        if np.isfinite(v):
            vals.append(v)
    if not vals:
        return (np.nan, np.nan)
    return (float(np.percentile(vals, 2.5)), float(np.percentile(vals, 97.5)))


def paired_stats(path: pd.DataFrame, target: str, uses: list[str], metrics: list[str],
                 reps: int = 2000, seed: int = 0) -> pd.DataFrame:
    """복원 방법(method)마다 target 재생과 다른 모든 재생(ttff 0)을 세션 단위로 짝지어 비교한다."""
    rows = []
    if path.empty or "run" not in path:
        return pd.DataFrame(columns=PAIRED_COLS)
    p = path[(path["use"].isin(uses)) & (path["ttff"].fillna(0) == 0)].copy()
    if "dist_err_pct" in p and "abs_dist_err_pct" in metrics:
        p["abs_dist_err_pct"] = p["dist_err_pct"].abs()
    for method, g in p.groupby("method", sort=True):
        t = g[g["run"] == target].set_index("session")
        if t.empty:
            continue
        for base, b in g[g["run"] != target].groupby("run", sort=True):
            b = b.set_index("session")
            common = t.index.intersection(b.index)
            for metric in metrics:
                if metric not in g:
                    continue
                tv = pd.to_numeric(t.loc[common, metric], errors="coerce")
                bv = pd.to_numeric(b.loc[common, metric], errors="coerce")
                ok = tv.notna() & bv.notna()
                tv, bv = tv[ok].to_numpy(float), bv[ok].to_numpy(float)
                n = len(tv)
                if n == 0:
                    continue
                sign = 1 if metric in LOWER_IS_BETTER else -1
                d = (bv - tv) * sign            # 양수 = 제안(target)이 좋다
                wins, losses = int((d > 0).sum()), int((d < 0).sum())

                def ratio(ix, tv=tv, bv=bv):
                    den = bv[ix].mean()
                    return tv[ix].mean() / den if den else np.nan

                def mdiff(ix, d=d):
                    return float(np.median(d[ix]))

                r_lo, r_hi = _bootstrap(n, ratio, reps, seed)
                d_lo, d_hi = _bootstrap(n, mdiff, reps, seed)
                rows.append({"method": method, "target": target, "baseline": base, "metric": metric, "n": n,
                             "wins": wins, "losses": losses, "ties": n - wins - losses,
                             "sign_p": sign_test_p(wins, losses),
                             "target_mean": float(tv.mean()), "baseline_mean": float(bv.mean()),
                             "ratio": ratio(np.arange(n)), "ratio_lo": r_lo, "ratio_hi": r_hi,
                             "median_diff": mdiff(np.arange(n)), "diff_lo": d_lo, "diff_hi": d_hi})
    return pd.DataFrame(rows, columns=PAIRED_COLS)
