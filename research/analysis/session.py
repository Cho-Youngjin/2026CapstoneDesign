"""R1 세션 폴더 읽기(설계 4-2)와 관찰 표시(marks.csv)로 만드는 정답 구간."""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

GPS_COLUMNS = ["t_ms", "fix_t_ms", "lat", "lng", "accuracy_m", "speed_mps", "bearing_deg", "altitude_m"]
MARK_COLUMNS = ["t_ms", "kind", "value"]
BATTERY_COLUMNS = ["t_ms", "charge_uah", "current_ua", "level_pct", "temp_c", "plugged"]


@dataclass(frozen=True)
class Interval:
    """[start_ms, end_ms] 구간. value는 여는 표시의 값(장소 이름, 탈것 종류 등)."""
    start_ms: int
    end_ms: int
    value: str = ""

    @property
    def duration_s(self) -> float:
        return (self.end_ms - self.start_ms) / 1000


@dataclass
class Session:
    session_id: str
    path: Path
    meta: dict
    gps: pd.DataFrame
    marks: pd.DataFrame
    start_ms: int
    end_ms: int
    extra: dict = field(default_factory=dict)


def read_csv(path: Path, columns: list[str], numeric: list[str]) -> pd.DataFrame:
    """헤더 있는 CSV를 읽는다. 파일이 없으면 빈 표, 깨진 행(서비스 강제 종료 등)은 버린다."""
    if not path.exists():
        return pd.DataFrame(columns=columns)
    df = pd.read_csv(path, dtype=str, keep_default_na=False, on_bad_lines="skip")
    for c in columns:
        if c not in df.columns:
            df[c] = ""
    df = df[columns].copy()
    for c in numeric:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    df = df.dropna(subset=numeric).reset_index(drop=True)
    if "t_ms" in numeric:
        df["t_ms"] = df["t_ms"].astype("int64")
        df = df.sort_values("t_ms", kind="stable").reset_index(drop=True)
    return df


def _iso_ms(value: str | None) -> int | None:
    if not value:
        return None
    return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000)


def read_meta(path: Path) -> dict:
    meta_path = path / "meta.json"
    return json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.exists() else {}


def load_session(path: Path) -> Session:
    path = Path(path)
    if not path.is_dir():
        raise FileNotFoundError(f"세션 폴더가 없습니다: {path}")
    meta = read_meta(path)
    gps = read_csv(path / "gps.csv", GPS_COLUMNS, ["t_ms", "lat", "lng", "accuracy_m"])
    marks = read_csv(path / "marks.csv", MARK_COLUMNS, ["t_ms"])
    times = list(gps["t_ms"]) + list(marks["t_ms"])
    start = _iso_ms(meta.get("startedAt")) or (min(times) if times else 0)
    end = _iso_ms(meta.get("endedAt")) or (max(times) if times else start)
    return Session(meta.get("sessionId", path.name), path, meta, gps, marks, int(start), int(end))


def truth_points(gps: pd.DataFrame, max_accuracy_m: float = 20.0) -> pd.DataFrame:
    """1초 정답 경로 — 정확도가 max_accuracy_m 이하인 GPS 행만 쓴다(설계 7-2, 10장 위험 7)."""
    return gps[gps["accuracy_m"] <= max_accuracy_m].reset_index(drop=True)


def paired_intervals(marks: pd.DataFrame, open_kind: str, close_kind: str,
                     end_ms: int | None = None) -> list[Interval]:
    """여는 표시 다음의 닫는 표시를 짝짓는다. 닫기 전에 또 열면 나중 것을 쓴다(steps CLI와 같은 규칙).

    end_ms를 주면 끝까지 닫지 않은 구간을 end_ms에서 닫는다(기록 끝까지 머문 곳). 안 주면 버린다(끝을 모른다).
    """
    out: list[Interval] = []
    opened: tuple[int, str] | None = None
    for t, kind, value in zip(marks["t_ms"], marks["kind"], marks["value"]):
        if kind == open_kind:
            opened = (int(t), str(value))
        elif kind == close_kind and opened is not None:
            out.append(Interval(opened[0], int(t), opened[1]))
            opened = None
    if opened is not None and end_ms is not None and end_ms > opened[0]:
        out.append(Interval(opened[0], int(end_ms), opened[1]))
    return out


def stay_intervals(session: Session) -> list[Interval]:
    """arrive~depart. 끝까지 출발하지 않았으면 세션 끝까지 머문 것으로 본다."""
    return paired_intervals(session.marks, "arrive", "depart", end_ms=session.end_ms)


def vehicle_intervals(session: Session) -> list[Interval]:
    """board~alight. 내리기 전에 끝난 탑승은 끝을 몰라 뺀다(steps CLI와 같다)."""
    return paired_intervals(session.marks, "board", "alight")


def count_intervals(session: Session) -> list[Interval]:
    """count_start~count_end. value는 count_end에 적은 직접 센 걸음 수(문자열)."""
    out: list[Interval] = []
    start: int | None = None
    for t, kind, value in zip(session.marks["t_ms"], session.marks["kind"], session.marks["value"]):
        if kind == "count_start":
            start = int(t)
        elif kind == "count_end" and start is not None:
            out.append(Interval(start, int(t), str(value).strip()))
            start = None
    return out


def in_intervals(t_ms, intervals: list[Interval]) -> np.ndarray:
    """시각마다 구간(양 끝 포함) 안이면 True."""
    t = np.asarray(t_ms, dtype="int64")
    mask = np.zeros(len(t), dtype=bool)
    for iv in intervals:
        mask |= (t >= iv.start_ms) & (t <= iv.end_ms)
    return mask


def carry_at(session: Session, t_ms: int) -> str:
    """t_ms 시점의 휴대 위치. t_ms 이전 마지막 carry 표시, 없으면 meta의 carryInitial."""
    carry = session.meta.get("carryInitial") or "unknown"
    for t, kind, value in zip(session.marks["t_ms"], session.marks["kind"], session.marks["value"]):
        if t > t_ms:
            break
        if kind == "carry" and value:
            carry = str(value)
    return carry
