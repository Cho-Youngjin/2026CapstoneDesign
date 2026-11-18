import math

import pandas as pd
import pytest

from analysis.stats import paired_stats, sign_test_p


def test_sign_test_exact_two_sided():
    assert sign_test_p(0, 0) == 1.0
    # 8전 8승: 2 × (1/2)^8
    assert sign_test_p(8, 0) == pytest.approx(2 / 256)
    # 6승 2패: 2 × P(X ≤ 2), X ~ Bin(8, 1/2) = 2 × 37/256
    assert sign_test_p(6, 2) == pytest.approx(2 * 37 / 256)
    assert sign_test_p(4, 4) == 1.0


def _path(rows):
    return pd.DataFrame([{"use": "eval", "ttff": 0, "method": "local_straight", **r} for r in rows])


def test_paired_stats_counts_wins_per_session_and_bootstraps_ratio():
    rows = []
    for k, (t, b) in enumerate([(5, 10), (6, 9), (8, 7), (4, 8)]):
        rows += [{"session": f"s{k}", "run": "prop", "p95_m": t, "gps_on_s": 100},
                 {"session": f"s{k}", "run": "base", "p95_m": b, "gps_on_s": 100}]
    # pilot 세션은 빼고 센다
    rows += [{"session": "p", "run": "prop", "p95_m": 99, "gps_on_s": 1, "use": "pilot"},
             {"session": "p", "run": "base", "p95_m": 1, "gps_on_s": 1, "use": "pilot"}]
    out = paired_stats(_path(rows), "prop", ["eval"], ["p95_m", "gps_on_s"], reps=200, seed=1)
    p95 = out[out.metric == "p95_m"].iloc[0]
    assert (p95.n, p95.wins, p95.losses, p95.ties) == (4, 3, 1, 0)
    assert p95.ratio == pytest.approx(23 / 34)
    assert p95.ratio_lo <= p95.ratio <= p95.ratio_hi
    assert p95.median_diff == pytest.approx(3.5)        # 기준 − 제안: 5, 3, −1, 4
    gps = out[out.metric == "gps_on_s"].iloc[0]
    assert (gps.wins, gps.losses, gps.ties) == (0, 0, 4) and gps.sign_p == 1.0


def test_paired_stats_only_pairs_sessions_both_runs_have():
    rows = [{"session": "a", "run": "prop", "p95_m": 5}, {"session": "a", "run": "base", "p95_m": 9},
            {"session": "b", "run": "prop", "p95_m": 5}]
    out = paired_stats(_path(rows), "prop", ["eval"], ["p95_m"], reps=50)
    assert out.iloc[0].n == 1 and math.isnan(out.iloc[0].ratio_lo)   # 짝 하나로는 구간을 내지 않는다
    assert paired_stats(_path(rows), "nope", ["eval"], ["p95_m"]).empty
