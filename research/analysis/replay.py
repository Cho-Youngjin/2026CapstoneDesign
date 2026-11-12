"""footstep_core의 replay·steps CLI를 부른다(replay-guide, steps-guide). 재생은 결정적이라 결과 폴더가 있으면 다시 돌리지 않는다."""
from __future__ import annotations

import locale
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


def decode_output(data) -> str:
    """dart의 stderr 바이트를 문자열로 푼다. Windows에서 Dart는 콘솔 코드 페이지(cp949)로 쓰므로 UTF-8로만 읽으면
    한글 오류 메시지가 깨진다. UTF-8을 엄격하게 먼저 시도하고(cp949 한글 바이트는 거의 항상 여기서 실패한다),
    안 되면 시스템 기본 인코딩, 그래도 안 되면 깨진 글자를 대체하며 UTF-8로 읽는다."""
    if data is None:
        return ""
    if isinstance(data, str):                      # 테스트의 가짜 run이 문자열을 돌려주는 경우
        return data
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        pass
    try:
        return data.decode(locale.getpreferredencoding(False))
    except (UnicodeDecodeError, LookupError):
        return data.decode("utf-8", errors="replace")


@dataclass
class DartCli:
    """packages/footstep_core에서 `dart run`을 부른다. run은 테스트에서 가짜로 바꾼다."""
    package_dir: Path
    dart: str | None = None
    run: Callable = field(default=subprocess.run)
    # 기본 None = 시간 제한 없음(기존 동작 그대로). 멈춘 dart 하나가 전체 실험을 붙잡지 않게 하고 싶을 때만 쓴다.
    timeout_s: float | None = None

    def _dart(self) -> str:
        found = self.dart or shutil.which("dart")
        if not found:
            raise CliError("dart를 찾을 수 없습니다(PATH 또는 experiments.yaml의 dart)")
        return found

    def _call(self, args: list[str]) -> None:
        # text=True를 쓰면 파이썬이 UTF-8 고정으로 풀어 버리므로 바이트로 받아 decode_output으로 직접 푼다.
        kwargs = {"cwd": str(self.package_dir), "capture_output": True}
        if self.timeout_s is not None:
            kwargs["timeout"] = self.timeout_s
        try:
            proc = self.run([self._dart(), *args], **kwargs)
        except subprocess.TimeoutExpired as e:
            # run.py는 CliError만 잡아 그 실험을 건너뛴다. TimeoutExpired를 그대로 두면 전체 분석이 죽는다.
            raise CliError(f"dart {' '.join(args[:2])} 시간 초과({self.timeout_s:g}s)") from e
        if proc.returncode != 0:
            message = decode_output(proc.stderr).strip()[:500]
            raise CliError(f"dart {' '.join(args[:2])} 실패({proc.returncode}): {message}")

    def replay(self, session_dir: Path, spec: RunSpec, out_dir: Path, force: bool = False) -> Path:
        if force or not (out_dir / "summary.json").exists():
            if force:
                # 강제 재실행이 도중에 죽으면 예전 summary.json이 남아 다음 실행이 유효한 캐시로 착각한다.
                (Path(out_dir) / "summary.json").unlink(missing_ok=True)
            self._call(replay_args(Path(session_dir).resolve(), spec, Path(out_dir).resolve()))
        return out_dir

    def steps(self, session_dir: Path, detector: str, out_dir: Path, detector_params: tuple = (),
              force: bool = False) -> Path:
        if force or not (out_dir / "step_summary.json").exists():
            if force:
                (Path(out_dir) / "step_summary.json").unlink(missing_ok=True)   # replay와 같은 이유
            self._call(steps_args(Path(session_dir).resolve(), detector, Path(out_dir).resolve(), detector_params))
        return out_dir
