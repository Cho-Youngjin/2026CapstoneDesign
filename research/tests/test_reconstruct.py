from types import SimpleNamespace

import pandas as pd
import pytest

from analysis.reconstruct import (ReconstructClient, ReconstructError, ServerUnavailable, build_requests, read_fixes,
                                  to_points)
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
