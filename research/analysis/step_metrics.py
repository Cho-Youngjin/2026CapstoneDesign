"""걸음 감지 지표(설계 7-2): steps CLI 출력(steps.csv·step_states.csv·step_summary.json)과 관찰 표시를 견준다."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd

from .session import Session, carry_at, in_intervals, stay_intervals, vehicle_intervals


def read_steps_output(steps_dir: Path) -> tuple[np.ndarray, pd.DataFrame, dict]:
    steps_dir = Path(steps_dir)
    steps = pd.read_csv(steps_dir / "steps.csv")
    states = pd.read_csv(steps_dir / "step_states.csv", keep_default_na=False)
    summary = json.loads((steps_dir / "step_summary.json").read_text(encoding="utf-8"))
    return steps["t_ms"].to_numpy(dtype="int64"), states, summary


def count_errors(summary: dict) -> dict:
    """걸음 세기 구간(직접 센 수가 있는 것만)의 오차.

    - count_error_pct: (Σ감지 − Σ직접) ÷ Σ직접 × 100 — 부호가 있어 과대·과소 계수를 본다
    - count_abs_error_pct: 구간별 |오차 %|의 평균
    """
    rows = [c for c in summary.get("count_intervals", []) if c.get("manual_steps")]
    if not rows:
        return {"count_intervals": 0, "manual_steps": 0, "detected_steps": 0, "count_error_pct": None,
                "count_abs_error_pct": None}
    manual = sum(c["manual_steps"] for c in rows)
    detected = sum(c["detected_steps"] for c in rows)
    return {"count_intervals": len(rows), "manual_steps": manual, "detected_steps": detected,
            "count_error_pct": (detected - manual) / manual * 100,
            "count_abs_error_pct": float(np.mean([abs(c["detected_steps"] - c["manual_steps"]) / c["manual_steps"]
                                                  * 100 for c in rows]))}


def vehicle_false_steps(summary: dict) -> dict:
    """탈것 구간(board~alight)의 걸음 수 합. 정답은 0걸음이다."""
    rows = summary.get("vehicle_intervals", [])
    seconds = sum((v["alight_ms"] - v["board_ms"]) / 1000 for v in rows)
    steps = sum(v["detected_steps"] for v in rows)
    return {"vehicle_s": seconds, "vehicle_false_steps": steps if rows else None,
            "vehicle_false_steps_per_min": steps / (seconds / 60) if seconds > 0 else None}


def state_at(states: pd.DataFrame, t_ms: np.ndarray) -> np.ndarray:
    """초마다 감지기 상태(직전 상태 변화). 첫 판정 전은 'unknown'."""
    change_t = states["t_ms"].to_numpy(dtype="int64")
    names = np.array(list(states["state"]) + ["unknown"], dtype=object)
    idx = np.searchsorted(change_t, t_ms, side="right") - 1
    return names[np.where(idx >= 0, idx, len(names) - 1)]


def walking_scores(session: Session, states: pd.DataFrame, start_ms: int, end_ms: int) -> dict:
    """보행 판정 정밀도·재현율(1초 격자, 시간 기준).

    정답 보행 = 머문 곳(arrive~depart, 길이와 상관없이)과 탈것(board~alight) 밖의 모든 시각(설계 7-2).
    횡단보도에서 서 있던 몇 초도 정답에서는 보행이라, 정밀도·재현율의 상한이 1보다 조금 낮다.
    """
    grid = np.arange(start_ms, end_ms, 1000, dtype="int64")
    if len(grid) == 0:
        return {"walk_precision": None, "walk_recall": None}
    truth = ~(in_intervals(grid, stay_intervals(session)) | in_intervals(grid, vehicle_intervals(session)))
    pred = state_at(states, grid) == "walking"
    tp = int((truth & pred).sum())
    return {"walk_precision": tp / int(pred.sum()) if pred.any() else None,
            "walk_recall": tp / int(truth.sum()) if truth.any() else None}


def first_step_latency(summary: dict, step_times: np.ndarray) -> float | None:
    """걸음 세기 구간마다 count_start에서 첫 감지 걸음까지(초)의 평균. 구간 안에 걸음이 없으면 그 구간은 뺀다."""
    delays = []
    for c in summary.get("count_intervals", []):
        inside = step_times[(step_times >= c["start_ms"]) & (step_times <= c["end_ms"])]
        if len(inside):
            delays.append((int(inside.min()) - c["start_ms"]) / 1000)
    return float(np.mean(delays)) if delays else None


def step_metrics(session: Session, steps_dir: Path) -> dict:
    step_times, states, summary = read_steps_output(steps_dir)
    row = {"detector": summary.get("detector_id"), "total_steps": summary.get("total_steps")}
    row.update(count_errors(summary))
    row.update(vehicle_false_steps(summary))
    row.update(walking_scores(session, states, summary["start_ms"], summary["end_ms"]))
    row["first_step_latency_s"] = first_step_latency(summary, step_times)
    return row


def count_rows_by_carry(session: Session, summary: dict) -> list[dict]:
    """걸음 세기 구간을 휴대 위치(손·주머니·가방)별로 나눠 보고하기 위한 구간별 행."""
    return [{"carry": carry_at(session, c["start_ms"]), "start_ms": c["start_ms"], "end_ms": c["end_ms"],
             "manual_steps": c["manual_steps"], "detected_steps": c["detected_steps"], "error_pct": c["error_pct"]}
            for c in summary.get("count_intervals", []) if c.get("manual_steps")]
