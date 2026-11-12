from pathlib import Path
from types import SimpleNamespace

import pytest

from analysis.replay import CliError, DartCli, RunSpec, replay_args, steps_args


def test_label_and_key():
    s = RunSpec("step_budget", "adaptive", params=(("e_m", "50"),), ttff=5, stay_params=(("use_still", "false"),))
    assert s.label == "step_budget[adaptive] e_m=50 ttff=5 stay.use_still=false"
    assert s.key == "step_budget-adaptive-e_m=50-ttff5-s.use_still=false"
    assert RunSpec("fixed_1m").label == "fixed_1m"
    assert RunSpec("fixed_1m").key == "fixed_1m-os-ttff0"


def test_replay_and_steps_args():
    s = RunSpec("time_speed", "os", params=(("e_m", "25"),), detector_params=(), ttff=0.5,
                stay_params=(("min_stay_s", "300"),))
    args = replay_args(Path("S"), s, Path("O"))
    assert args == ["run", "footstep_core:replay", "--session", "S", "--policy", "time_speed", "--detector", "os",
                    "--ttff", "0.5", "--out", "O", "--param", "e_m=25", "--stay-param", "min_stay_s=300"]
    assert steps_args(Path("S"), "adaptive", Path("O"), (("n_confirm", "6"),)) == [
        "run", "footstep_core:steps", "--session", "S", "--detector", "adaptive", "--out", "O",
        "--detector-param", "n_confirm=6"]


def test_dart_cli_caches_and_reports_errors(tmp_path):
    calls = []

    def fake_run(cmd, cwd, **kw):
        calls.append((cmd, cwd))
        out = Path(cmd[cmd.index("--out") + 1])
        out.mkdir(parents=True, exist_ok=True)
        (out / "summary.json").write_text("{}")
        return SimpleNamespace(returncode=0, stderr="")

    cli = DartCli(tmp_path / "pkg", dart="dart", run=fake_run)
    out = tmp_path / "o"
    cli.replay(tmp_path, RunSpec("hourly"), out)
    cli.replay(tmp_path, RunSpec("hourly"), out)          # summary.json이 있어 다시 돌리지 않는다
    assert len(calls) == 1 and calls[0][1] == str(tmp_path / "pkg")
    cli.replay(tmp_path, RunSpec("hourly"), out, force=True)
    assert len(calls) == 2

    bad = DartCli(tmp_path, dart="dart", run=lambda *a, **k: SimpleNamespace(returncode=64, stderr="사용법"))
    with pytest.raises(CliError, match="64"):
        bad.steps(tmp_path, "os", tmp_path / "s")
