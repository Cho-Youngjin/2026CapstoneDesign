import warnings
from types import SimpleNamespace

import pandas as pd
import pytest
import requests

from analysis import reconstruct as rc
from analysis.reconstruct import (ReconstructClient, ReconstructError, ServerUnavailable, build_requests, read_fixes,
                                  to_points, to_stays)
from conftest import write_csv


def _fixes(n):
    return pd.DataFrame({"t_ms": range(n), "lat": [37.0] * n, "lng": [127.0] * n, "accuracy_m": [5.0] * n,
                         "steps_since_prev": [10] * n, "state": ["walking"] * n, "kind": ["single"] * n})


def test_read_fixes_and_to_points_null_fields(tmp_path):
    write_csv(tmp_path / "fixes.csv", ["t_ms", "lat", "lng", "accuracy_m", "steps_since_prev", "state", "kind"],
              [[2, 37.1, 127.1, 4.5, 64, "walking", "single"], [1, 37.0, 127.0, "", "", "", "single"]])
    pts = to_points(read_fixes(tmp_path))
    assert pts == [{"t": 1, "lat": 37.0, "lng": 127.0, "accuracy": None, "stepsSincePrev": None, "state": None},
                   {"t": 2, "lat": 37.1, "lng": 127.1, "accuracy": 4.5, "stepsSincePrev": 64, "state": "walking"}]


def test_build_requests_splits_over_limit_with_overlap():
    stays = [{"arrive_ms": 0, "leave_ms": 1, "lat": 1, "lng": 2}, {"arrive_ms": 8, "leave_ms": 9, "lat": 1, "lng": 2}]
    reqs = build_requests(_fixes(9), stays, "hmm_steps", hmm={"betaM": 5}, max_points=4)
    # 0-3, 3-6, 6-8: 앞 조각의 마지막 점을 다음 조각이 다시 쓴다
    assert [[p["t"] for p in r["points"]] for r in reqs] == [[0, 1, 2, 3], [3, 4, 5, 6], [6, 7, 8]]
    assert [len(r["stays"]) for r in reqs] == [1, 0, 1]
    assert all(r["method"] == "hmm_steps" and r["hmm"] == {"betaM": 5} for r in reqs)
    one = build_requests(_fixes(2), [], "straight")
    assert len(one) == 1 and "hmm" not in one[0]


def test_client_posts_with_token_and_joins_segments():
    sent = []

    def fake_post(url, json, headers, timeout):
        sent.append((url, json, headers))
        return SimpleNamespace(status_code=200, text="", json=lambda: {
            "method": json["method"], "segments": [{"kind": "walk", "coords": [], "fallback": True}]})

    c = ReconstructClient("http://h:1/", "tok", post=fake_post)
    segs = c.reconstruct(_fixes(3), [], "straight")
    assert sent[0][0] == "http://h:1/api/route/reconstruct"
    assert sent[0][2] == {"Authorization": "Bearer tok"}
    assert segs == [{"kind": "walk", "coords": [], "fallback": True}]


def test_client_errors():
    def down(*a, **k):
        raise ServerUnavailable("refused")

    c = ReconstructClient(post=down)
    with pytest.raises(ServerUnavailable):
        c.reconstruct(_fixes(1), [], "straight")
    assert c.unavailable
    calls = []
    c.post = lambda *a, **k: calls.append(1)
    with pytest.raises(ServerUnavailable):        # 한 번 끊기면 이후는 부르지 않는다
        c.reconstruct(_fixes(1), [], "straight")
    assert calls == []

    bad = ReconstructClient(post=lambda *a, **k: SimpleNamespace(status_code=400, text="too many", json=dict))
    with pytest.raises(ReconstructError, match="400"):
        bad.reconstruct(_fixes(1), [], "straight")


def test_default_post_turns_refused_connection_into_server_unavailable():
    c = ReconstructClient("http://127.0.0.1:9", timeout_s=5)     # 아무도 듣지 않는 포트
    with pytest.raises(ServerUnavailable):
        c.reconstruct(_fixes(1), [], "straight")


def _raising_requests_post(monkeypatch, exc):
    def boom(*a, **k):
        raise exc
    monkeypatch.setattr(requests, "post", boom)


def test_connect_timeout_is_sticky_server_unavailable(monkeypatch):
    _raising_requests_post(monkeypatch, requests.ConnectTimeout("no route"))
    c = ReconstructClient()
    with pytest.raises(ServerUnavailable):
        c.reconstruct(_fixes(1), [], "straight")
    assert c.unavailable


def test_read_timeout_is_not_sticky(monkeypatch):
    _raising_requests_post(monkeypatch, requests.ReadTimeout("slow hmm_steps"))
    c = ReconstructClient()
    with pytest.raises(ReconstructError) as e:
        c.reconstruct(_fixes(1), [], "straight")
    assert not isinstance(e.value, ServerUnavailable) and not c.unavailable
    calls = []

    def ok(*a, **k):
        calls.append(1)
        return SimpleNamespace(status_code=200, text="", json=lambda: {"segments": []})

    c.post = ok
    assert c.reconstruct(_fixes(1), [], "straight") == [] and calls == [1]       # 다음 호출은 서버로 간다


@pytest.mark.parametrize("status", [401, 403])
def test_auth_failure_is_sticky(status):
    calls = []

    def deny(*a, **k):
        calls.append(1)
        return SimpleNamespace(status_code=status, text="denied", json=dict)

    c = ReconstructClient(post=deny)
    with pytest.raises(rc.ReconstructAuthError, match=str(status)):
        c.reconstruct(_fixes(1), [], "straight")
    with pytest.raises(rc.ReconstructAuthError):                 # 토큰이 틀리면 이후 호출도 모두 실패하므로 부르지 않는다
        c.reconstruct(_fixes(1), [], "straight")
    assert calls == [1] and issubclass(rc.ReconstructAuthError, ReconstructError)


def test_token_is_not_in_repr():
    assert "secret-token" not in repr(ReconstructClient(token="secret-token"))


@pytest.mark.parametrize("n", [0, 1, -3])
def test_max_points_below_two_is_rejected(n):
    with pytest.raises(ValueError):
        build_requests(_fixes(5), [], "straight", max_points=n)


def test_malformed_200_body_is_reconstruct_error():
    def bad_json():
        raise ValueError("Expecting value")

    c = ReconstructClient(post=lambda *a, **k: SimpleNamespace(status_code=200, text="<html>", json=bad_json))
    with pytest.raises(ReconstructError):
        c.reconstruct(_fixes(1), [], "straight")
    c.post = lambda *a, **k: SimpleNamespace(status_code=200, text="[]", json=lambda: [])
    with pytest.raises(ReconstructError):
        c.reconstruct(_fixes(1), [], "straight")


def test_too_many_stays_warns_instead_of_truncating_silently():
    stays = [{"arrive_ms": 0, "leave_ms": 1, "lat": 1, "lng": 2}] * (rc.MAX_STAYS + 3)
    with pytest.warns(UserWarning, match=str(rc.MAX_STAYS)):
        reqs = build_requests(_fixes(2), stays, "straight")
    assert len(reqs[0]["stays"]) == rc.MAX_STAYS
    with warnings.catch_warnings():
        warnings.simplefilter("error")                           # 상한 이하면 경고가 없다
        build_requests(_fixes(2), stays[:rc.MAX_STAYS], "straight")


def test_to_stays_key_names():
    assert to_stays([{"arrive_ms": 5, "leave_ms": 9, "lat": 1.5, "lng": 2.5, "extra": 1}]) == [
        {"arrive": 5, "leave": 9, "lat": 1.5, "lng": 2.5}]


def test_chunk_boundary_is_connected_when_endpoints_differ():
    from analysis.geo import distance_m, offset
    a_end = offset(37.5, 127.0, 0, 0)
    b_start = offset(37.5, 127.0, 5, 0)                 # 앞 조각 끝에서 5m 떨어져 시작
    answers = iter([
        [{"kind": "walk", "coords": [{"lat": a_end[0], "lng": a_end[1]}], "fallback": False}],
        [{"kind": "walk", "coords": [{"lat": b_start[0], "lng": b_start[1]}], "fallback": False}],
    ])

    def fake_post(url, json, headers, timeout):
        return SimpleNamespace(status_code=200, text="", json=lambda: {"segments": next(answers)})

    c = ReconstructClient("http://h:1", post=fake_post)
    segs = c.reconstruct(_fixes(2500), [], "straight")      # 2000점 상한을 넘어 두 조각으로 나뉜다
    assert len(segs) == 2
    assert segs[1]["coords"][0] == {"lat": a_end[0], "lng": a_end[1]}        # 앞 조각의 끝 좌표가 이음새로 붙는다
    assert len(segs[1]["coords"]) == 2 and distance_m(*a_end, segs[1]["coords"][1]["lat"], segs[1]["coords"][1]["lng"]) > 0.5


def test_chunk_boundary_within_tolerance_is_left_alone():
    p = {"lat": 37.5, "lng": 127.0}
    answers = iter([[{"kind": "walk", "coords": [p], "fallback": False}],
                    [{"kind": "walk", "coords": [dict(p)], "fallback": False}]])

    def fake_post(url, json, headers, timeout):
        return SimpleNamespace(status_code=200, text="", json=lambda: {"segments": next(answers)})

    segs = ReconstructClient("http://h:1", post=fake_post).reconstruct(_fixes(2500), [], "straight")
    assert segs[1]["coords"] == [p]
