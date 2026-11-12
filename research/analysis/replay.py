"""footstep_core의 replay·steps CLI를 부른다(replay-guide, steps-guide). 재생은 결정적이라 결과 폴더가 있으면 다시 돌리지 않는다."""
from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from .battery import method_label


@dataclass(frozen=True)
class RunSpec:
    """재생 한 번의 설정. params·detector_params·stay_params는 (이름, 값) 튜플을 이름순으로 둔다(해시·비교용)."""
    policy: str
    detector: str = "os"
    params: tuple = ()
    detector_params: tuple = ()
    ttff: float = 0
    stay_params: tuple = ()

    @property
    def label(self) -> str:
        """그래프·표에 쓰는 이름. ttff·머문 곳 설정은 기본값이 아닐 때만 붙인다."""
        text = method_label(self.policy, self.detector, dict(self.params))
        if self.detector_params:
            text += " " + " ".join(f"{k}={v}" for k, v in self.detector_params)
        if self.ttff:
            text += f" ttff={self.ttff:g}"
        if self.stay_params:
            text += " " + " ".join(f"stay.{k}={v}" for k, v in self.stay_params)
        return text

    @property
    def key(self) -> str:
        """결과 폴더 이름(파일 이름에 쓸 수 없는 문자를 피한다)."""
        parts = [self.policy, self.detector]
        parts += [f"{k}={v}" for k, v in self.params]
        parts += [f"d.{k}={v}" for k, v in self.detector_params]
        parts.append(f"ttff{self.ttff:g}")
        parts += [f"s.{k}={v}" for k, v in self.stay_params]
        return "-".join(parts).replace("/", "_").replace(" ", "_")


def replay_args(session_dir: Path, spec: RunSpec, out_dir: Path) -> list[str]:
    args = ["run", "footstep_core:replay", "--session", str(session_dir), "--policy", spec.policy,
            "--detector", spec.detector, "--ttff", f"{spec.ttff:g}", "--out", str(out_dir)]
    for k, v in spec.params:
        args += ["--param", f"{k}={v}"]
    for k, v in spec.detector_params:
        args += ["--detector-param", f"{k}={v}"]
    for k, v in spec.stay_params:
        args += ["--stay-param", f"{k}={v}"]
    return args


def steps_args(session_dir: Path, detector: str, out_dir: Path, detector_params: tuple = ()) -> list[str]:
    args = ["run", "footstep_core:steps", "--session", str(session_dir), "--detector", detector,
            "--out", str(out_dir)]
    for k, v in detector_params:
        args += ["--detector-param", f"{k}={v}"]
    return args


class CliError(RuntimeError):
    pass


@dataclass
class DartCli:
    """packages/footstep_core에서 `dart run`을 부른다. run은 테스트에서 가짜로 바꾼다."""
    package_dir: Path
    dart: str | None = None
    run: Callable = field(default=subprocess.run)

    def _dart(self) -> str:
        found = self.dart or shutil.which("dart")
        if not found:
            raise CliError("dart를 찾을 수 없습니다(PATH 또는 experiments.yaml의 dart)")
        return found

    def _call(self, args: list[str]) -> None:
        proc = self.run([self._dart(), *args], cwd=str(self.package_dir), capture_output=True, text=True,
                        encoding="utf-8", errors="replace")
        if proc.returncode != 0:
            raise CliError(f"dart {' '.join(args[:2])} 실패({proc.returncode}): {proc.stderr.strip()[:500]}")

    def replay(self, session_dir: Path, spec: RunSpec, out_dir: Path, force: bool = False) -> Path:
        if force or not (out_dir / "summary.json").exists():
            self._call(replay_args(Path(session_dir).resolve(), spec, Path(out_dir).resolve()))
        return out_dir

    def steps(self, session_dir: Path, detector: str, out_dir: Path, detector_params: tuple = (),
              force: bool = False) -> Path:
        if force or not (out_dir / "step_summary.json").exists():
            self._call(steps_args(Path(session_dir).resolve(), detector, Path(out_dir).resolve(), detector_params))
        return out_dir
