"""sessions.yaml·experiments.yaml 읽기(설계 7-1). 경로는 모두 설정 파일이 있는 폴더 기준이다."""
from __future__ import annotations

import itertools
import os
from dataclasses import dataclass, field
from pathlib import Path

import yaml

from .replay import RunSpec

USES = {"pilot", "eval", "battery"}


def load_sessions(path: Path) -> list[dict]:
    """세션 목록. use는 pilot(파라미터 정하기)·eval(평가, 파라미터를 정할 때 보지 않는다)·battery(배터리 실험)."""
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}
    out = []
    for s in data.get("sessions") or []:
        if s.get("use") not in USES:
            raise ValueError(f"세션 {s.get('id')}: use는 {sorted(USES)} 중 하나여야 합니다")
        out.append({"id": str(s["id"]), "use": s["use"], "course": s.get("course"), "carry": s.get("carry"),
                    "note": s.get("note")})
    ids = [s["id"] for s in out]
    if len(ids) != len(set(ids)):
        raise ValueError("sessions.yaml에 같은 id가 두 번 있습니다")
    return out


def _as_list(v) -> list:
    if v is None:
        return [None]
    return list(v) if isinstance(v, (list, tuple)) else [v]


def _grid(d: dict | None) -> list[tuple]:
    """{k: 값 또는 값 목록} → 모든 조합의 (이름, 값) 튜플 목록. 값은 CLI에 그대로 넘기려고 문자열로 바꾼다."""
    if not d:
        return [()]
    keys = sorted(d)
    combos = itertools.product(*[_as_list(d[k]) for k in keys])
    return [tuple((k, _str(v)) for k, v in zip(keys, combo)) for combo in combos]


def _str(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)


def expand_runs(runs: list[dict], default_ttff) -> list[RunSpec]:
    """runs 항목마다 detector·params·detector_params·stay_params·ttff의 목록을 모두 곱해 재생 설정을 만든다."""
    out: list[RunSpec] = []
    for r in runs:
        for det, p, dp, sp, ttff in itertools.product(
                _as_list(r.get("detector", "os")), _grid(r.get("params")), _grid(r.get("detector_params")),
                _grid(r.get("stay_params")), _as_list(r.get("ttff", default_ttff))):
            spec = RunSpec(r["policy"], det or "os", p, dp, float(ttff or 0), sp)
            if spec not in out:
                out.append(spec)
    return out


def _methods(items) -> list[dict]:
    """복원 방법. 문자열이면 그 method, 사전이면 {name, method, hmm}(같은 method를 조정값만 바꿔 여러 번 쓸 때)."""
    out = []
    for m in items or []:
        if isinstance(m, str):
            out.append({"name": m, "method": m, "hmm": None})
        else:
            out.append({"name": m.get("name", m["method"]), "method": m["method"], "hmm": m.get("hmm")})
    return out


@dataclass
class Experiment:
    base: Path
    sessions_file: Path
    data_dir: Path
    results_dir: Path
    package_dir: Path
    dart: str | None
    uses: list[str]
    runs: list[RunSpec]
    step_detectors: list[str]
    truth_max_accuracy_m: float = 20
    truth_min_hop_m: float = 10
    stay_min_truth_s: float = 600
    stay_min_overlap: float = 0.5
    stay_max_distance_m: float = 100
    local_straight: bool = True
    reconstruct: dict = field(default_factory=dict)
    battery: dict = field(default_factory=dict)
    tune: dict = field(default_factory=dict)
    plots: bool = True


def load_experiment(path: Path, data_dir: Path | None = None, results_dir: Path | None = None) -> Experiment:
    path = Path(path).resolve()
    base = path.parent
    c = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    truth = c.get("truth") or {}
    stays = c.get("stays") or {}
    rec = c.get("reconstruct") or {}
    bat = c.get("battery") or {}
    tune = c.get("tune") or {}
    ttff = c.get("ttff", 0)
    return Experiment(
        base=base,
        sessions_file=base / c.get("sessions", "sessions.yaml"),
        data_dir=Path(data_dir) if data_dir else base / c.get("data_dir", "data/sessions"),
        results_dir=Path(results_dir) if results_dir else base / c.get("results_dir", "results"),
        package_dir=base / c.get("footstep_core", "../packages/footstep_core"),
        dart=c.get("dart"),
        uses=list(c.get("use", ["pilot", "eval"])),
        runs=expand_runs(c.get("runs") or [], ttff),
        step_detectors=list(c.get("step_detectors", ["os", "brajdic", "adaptive"])),
        truth_max_accuracy_m=float(truth.get("max_accuracy_m", 20)),
        truth_min_hop_m=float(truth.get("min_hop_m", 10)),
        stay_min_truth_s=float(stays.get("min_truth_stay_s", 600)),
        stay_min_overlap=float(stays.get("min_overlap", 0.5)),
        stay_max_distance_m=float(stays.get("max_distance_m", 100)),
        local_straight=bool(c.get("local_straight", True)),
        reconstruct={"enabled": bool(rec.get("enabled", False)),
                     "server_url": rec.get("server_url", "http://localhost:9090"),
                     # 실제 토큰을 YAML(저장소에 커밋됨)에 적지 않게 환경변수가 우선한다. YAML 기본값은 로컬 더미 토큰이다.
                     "token": os.environ.get("TF_TOKEN") or rec.get("token", "dev-fake-token"),
                     "timeout_s": float(rec.get("timeout_s", 120)),
                     "skip_all_fallback": bool(rec.get("skip_all_fallback", True)),
                     "methods": _methods(rec.get("methods", ["straight", "osrm_match_radius", "hmm_steps"]))},
        battery={"use": list(bat.get("use", ["battery"])),
                 "current_units": dict(bat.get("current_units") or {}),
                 "align_steps": bool(bat.get("align_steps", True)),
                 "package": bat.get("package", "com.travelfootsteps.app")},
        tune={"runs": expand_runs(tune.get("runs") or [], ttff),
              "betas": [float(b) for b in tune.get("betas", [2, 5, 10, 20, 50])],
              "sigmas": [float(s) for s in tune.get("sigmas", [3, 5, 10])]},
        plots=bool(c.get("plots", True)),
    )
