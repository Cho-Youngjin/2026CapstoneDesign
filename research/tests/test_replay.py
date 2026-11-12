import locale
import subprocess
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


def test_decode_output_reads_cp949_korean(monkeypatch):
    from analysis.replay import decode_output
    monkeypatch.setattr(locale, "getpreferredencoding", lambda do_setlocale=True: "cp949")
    korean = "세션 폴더를 찾을 수 없습니다"
    assert decode_output(korean.encode("cp949")) == korean          # Windows Dart의 콘솔 인코딩
    assert decode_output(korean.encode("utf-8")) == korean          # UTF-8이면 그대로
    assert decode_output(b"") == ""


def test_decode_output_falls_back_to_replace(monkeypatch):
    from analysis.replay import decode_output
    monkeypatch.setattr(locale, "getpreferredencoding", lambda do_setlocale=True: "ascii")
    assert decode_output(b"ok \xff\xfe") == "ok \ufffd\ufffd"        # 둘 다 실패하면 깨진 글자만 대체


def test_cli_error_message_has_readable_cp949_stderr(tmp_path, monkeypatch):
    monkeypatch.setattr(locale, "getpreferredencoding", lambda do_setlocale=True: "cp949")
    korean = "사용법 오류"
    bad = DartCli(tmp_path, dart="dart",
                  run=lambda *a, **k: SimpleNamespace(returncode=64, stderr=korean.encode("cp949")))
    with pytest.raises(CliError, match=korean):
        bad.steps(tmp_path, "os", tmp_path / "s")


def test_forced_run_deletes_old_summary_even_if_it_crashes(tmp_path):
    out = tmp_path / "o"
    out.mkdir()
    (out / "summary.json").write_text("{}")
    (out / "step_summary.json").write_text("{}")
    crash = DartCli(tmp_path, dart="dart", run=lambda *a, **k: SimpleNamespace(returncode=1, stderr=b"x"))
    with pytest.raises(CliError):
        crash.replay(tmp_path, RunSpec("hourly"), out, force=True)
    with pytest.raises(CliError):
        crash.steps(tmp_path, "os", out, force=True)
    assert not (out / "summary.json").exists() and not (out / "step_summary.json").exists()


def test_timeout_is_optional_and_expiry_becomes_cli_error(tmp_path):
    seen = []

    def ok(cmd, **kw):
        seen.append(kw)
        return SimpleNamespace(returncode=0, stderr=b"")

    DartCli(tmp_path, dart="dart", run=ok).steps(tmp_path, "os", tmp_path / "a")
    assert "timeout" not in seen[0]                                  # 기본값이면 동작이 그대로다
    DartCli(tmp_path, dart="dart", run=ok, timeout_s=30).steps(tmp_path, "os", tmp_path / "b")
    assert seen[1]["timeout"] == 30

    def hang(cmd, **kw):
        raise subprocess.TimeoutExpired(cmd, kw["timeout"])

    with pytest.raises(CliError, match="시간 초과"):
        DartCli(tmp_path, dart="dart", run=hang, timeout_s=1).steps(tmp_path, "os", tmp_path / "c")
