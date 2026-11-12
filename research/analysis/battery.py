"""배터리 지표(설계 7-2, battery-experiment-guide): 정책 실행 세션의 시간당 mAh와 GPS 사용 시간."""
from __future__ import annotations

import json
import re
from pathlib import Path

import numpy as np
import pandas as pd

from .session import BATTERY_COLUMNS, read_csv, read_meta

RESTARTED = "restarted by system"


def exclusion_reason(meta: dict) -> str | None:
    """시스템이 기록 서비스를 다시 띄운 회차는 정책이 처음부터 다시 돌아 뺀다(battery-experiment-guide 5절)."""
    for e in meta.get("errors") or []:
        if RESTARTED in str(e.get("message", "")):
            return RESTARTED
    return None


def longest_unplugged(battery: pd.DataFrame) -> pd.DataFrame:
    """plugged = 0인 행이 가장 길게 이어진 묶음. 충전 중 행은 전하량이 늘어 계산에서 뺀다."""
    unplugged = (battery["plugged"].to_numpy() == 0)
    best, best_len, start = (0, 0), 0, None
    for k, flag in enumerate(list(unplugged) + [False]):
        if flag and start is None:
            start = k
        elif not flag and start is not None:
            if k - start > best_len:
                best, best_len = (start, k), k - start
            start = None
    return battery.iloc[best[0]:best[1]].reset_index(drop=True)


def charge_rate(battery: pd.DataFrame, align_steps: bool = True) -> dict:
    """시간당 mAh = 전하량 감소 ÷ 시간.

    이 기종은 전하량이 3.7mAh 계단으로 줄어든다. align_steps면 첫 계단이 바뀐 행 ~ 마지막 계단이 바뀐 행 사이로
    재 양자화 오차를 줄인다(device-check.md). 계단 변화가 두 번 미만이면 처음 ~ 끝 행으로 잰다.
    """
    out = {"rows": int(len(battery)), "hours": None, "mah_used": None, "mah_per_h": None, "aligned": False}
    if len(battery) < 2:
        return out
    t = battery["t_ms"].to_numpy(dtype="int64")
    c = battery["charge_uah"].to_numpy(dtype=float)
    i, j = 0, len(battery) - 1
    if align_steps:
        changed = np.flatnonzero(np.diff(c) != 0) + 1
        if len(changed) >= 2:
            i, j = int(changed[0]), int(changed[-1])
            out["aligned"] = True
    hours = (t[j] - t[i]) / 3_600_000
    if hours <= 0:
        return out
    out["hours"] = hours
    out["mah_used"] = (c[i] - c[j]) / 1000
    out["mah_per_h"] = out["mah_used"] / hours
    return out


def current_rate(battery: pd.DataFrame, unit: str = "uA") -> float | None:
    """전류 평균의 크기(mA) ≈ 시간당 mAh. 교차 확인용. 이 기종(SM-S911N)은 current_ua 열이 실제로 mA다."""
    if battery.empty:
        return None
    factor = {"uA": 1 / 1000, "mA": 1.0}[unit]
    return float(np.abs(battery["current_ua"].to_numpy(dtype=float)).mean() * factor)


_DURATION = re.compile(r"(\d+)(h|ms|m|s)")


def parse_duration_ms(text: str) -> int:
    """batterystats 시간 표기('1h 2m 3s 456ms')를 밀리초로."""
    scale = {"h": 3_600_000, "m": 60_000, "s": 1000, "ms": 1}
    return sum(int(n) * scale[u] for n, u in _DURATION.findall(text))


_GPS_LINE = re.compile(r"Sensor GPS:\s*((?:\d+(?:h|ms|m|s)\s*)+)")
_UID_LINE = re.compile(r"^\s*(?:Uid\s+)?(u\d+a\d+|\d+):\s*$")


def gps_seconds_from_batterystats(text: str, package: str | None = None) -> dict:
    """dumpsys batterystats 출력에서 'Sensor GPS: … realtime' 줄의 시간을 더한다(최선 노력, 형식이 기종·버전마다 다르다).

    - gps_s_total: 모든 앱의 합
    - gps_s_app: package가 든 Uid 묶음의 합(그 묶음에 'Apk <package>' 또는 패키지 이름 줄이 있을 때). 못 찾으면 None
    """
    total = 0
    per_uid: dict[str, int] = {}
    uid_packages: dict[str, set[str]] = {}
    uid = None
    for line in text.splitlines():
        m = _UID_LINE.match(line)
        if m:
            uid = m.group(1)
            continue
        if uid is not None and package and package in line:
            uid_packages.setdefault(uid, set()).add(package)
        g = _GPS_LINE.search(line)
        if g:
            ms = parse_duration_ms(g.group(1))
            total += ms
            if uid is not None:
                per_uid[uid] = per_uid.get(uid, 0) + ms
    app = None
    if package:
        uids = [u for u, pk in uid_packages.items() if package in pk]
        if uids:
            app = sum(per_uid.get(u, 0) for u in uids) / 1000
    return {"gps_s_total": total / 1000 if total else None, "gps_s_app": app}


def method_label(policy_id: str, detector_id: str | None = None, params: dict | None = None) -> str:
    """방식 이름. 재생 결과와 배터리 실험을 같은 이름으로 잇는다. 걸음 감지기는 걸음 정책일 때만 붙인다."""
    label = policy_id
    if policy_id in {"still_suppress", "step_budget"} and detector_id:
        label += f"[{detector_id}]"
    if params:
        label += " " + " ".join(f"{k}={params[k]}" for k in sorted(params))
    return label


def battery_run(session_dir: Path, current_units: dict | None = None, align_steps: bool = True,
                package: str = "com.travelfootsteps.app") -> dict:
    """배터리 실험 한 회(정책 실행 세션 폴더 하나)."""
    session_dir = Path(session_dir)
    meta = read_meta(session_dir)
    policy = meta.get("policy") or {}
    battery = read_csv(session_dir / "battery.csv", BATTERY_COLUMNS, ["t_ms", "charge_uah", "current_ua", "plugged"])
    run = longest_unplugged(battery)
    device = meta.get("deviceModel", "")
    unit = (current_units or {}).get(device, "uA")
    row = {"session": meta.get("sessionId", session_dir.name), "device": device,
           "method": method_label(policy.get("policyId", meta.get("mode", "?")), policy.get("detectorId"),
                                  policy.get("policyParams")),
           "excluded": exclusion_reason(meta)}
    rate = charge_rate(run, align_steps)
    row.update({"hours": rate["hours"], "mah_used": rate["mah_used"], "mah_per_h": rate["mah_per_h"],
                "aligned": rate["aligned"], "current_ma": current_rate(run, unit)})
    stats = session_dir / "batterystats.txt"
    if stats.exists():
        row.update(gps_seconds_from_batterystats(stats.read_text(encoding="utf-8", errors="replace"), package))
    else:
        row.update({"gps_s_total": None, "gps_s_app": None})
    summary = session_dir / "summary.json"
    if summary.exists():
        row["gps_on_s_est"] = json.loads(summary.read_text(encoding="utf-8")).get("gps_on_s")
    else:
        row["gps_on_s_est"] = None
    return row


def battery_summary(runs: pd.DataFrame) -> pd.DataFrame:
    """방식마다 평균 ± 표준편차(표본, ddof=1). 제외된 회차와 값이 없는 회차는 빼고 센다."""
    cols = ["method", "n", "mah_per_h_mean", "mah_per_h_std", "current_ma_mean", "gps_s_app_mean"]
    if runs.empty:
        return pd.DataFrame(columns=cols)
    ok = runs[runs["excluded"].isna() & runs["mah_per_h"].notna()]
    rows = []
    for method, g in ok.groupby("method", sort=True):
        rows.append({"method": method, "n": len(g), "mah_per_h_mean": g["mah_per_h"].mean(),
                     "mah_per_h_std": g["mah_per_h"].std(ddof=1) if len(g) > 1 else None,
                     "current_ma_mean": g["current_ma"].mean(),
                     "gps_s_app_mean": g["gps_s_app"].mean() if g["gps_s_app"].notna().any() else None})
    return pd.DataFrame(rows, columns=cols)
