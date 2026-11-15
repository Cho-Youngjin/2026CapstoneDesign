"""테스트용 가짜 세션 폴더를 만드는 도우미. 손으로 답을 셀 수 있는 작은 합성 데이터만 쓴다(설계 7-4)."""
import csv
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from analysis.geo import offset  # noqa: E402

LAT0, LNG0 = 37.5665, 126.9780
T0 = 1_794_227_600_000


def write_csv(path: Path, header: list[str], rows: list[list]):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


def gps_row(t_ms, east_m, north_m, acc=5.0):
    lat, lng = offset(LAT0, LNG0, east_m, north_m)
    return [t_ms, t_ms, lat, lng, acc, 0.0, 0.0, 0.0]


def make_session(root: Path, name="s1", gps=None, marks=None, battery=None, meta=None) -> Path:
    d = root / name
    d.mkdir(parents=True, exist_ok=True)
    write_csv(d / "gps.csv", ["t_ms", "fix_t_ms", "lat", "lng", "accuracy_m", "speed_mps", "bearing_deg",
                              "altitude_m"], gps or [])
    write_csv(d / "marks.csv", ["t_ms", "kind", "value"], marks or [])
    if battery is not None:
        write_csv(d / "battery.csv", ["t_ms", "charge_uah", "current_ua", "level_pct", "temp_c", "plugged"],
                  battery)
    m = {"sessionId": name, "mode": "groundTruth", "deviceModel": "test", "carryInitial": "hand",
         "errors": []}
    m.update(meta or {})
    (d / "meta.json").write_text(json.dumps(m), encoding="utf-8")
    return d


@pytest.fixture
def walk_session(tmp_path):
    """동쪽으로 1m/s, 100초 걷는 세션(정답 점 101개, 하나는 정확도 30m라 정답에서 빠진다)."""
    rows = [gps_row(T0 + k * 1000, k, 0.0) for k in range(101)]
    rows[50][4] = 30.0
    return make_session(tmp_path, gps=rows)
