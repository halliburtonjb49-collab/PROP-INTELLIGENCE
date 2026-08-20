import pytest
import requests

import scripts.sync_pregame as pregame


def _running(**overrides):
    payload = {
        "status": "running",
        "coverageStatus": "pending",
        "sportsGameOddsStatus": "pending",
        "postProcessingStatus": "pending",
    }
    payload.update(overrides)
    return payload


def _complete():
    return {
        "status": "complete",
        "coverageStatus": "complete",
        "sportsGameOddsStatus": "complete",
        "postProcessingStatus": "complete",
    }


def test_a_temporary_502_does_not_throw_away_a_running_sync(monkeypatch):
    """The API owns the sync; this loop only watches it.

    A proxy hiccup or a deploy swapping instances makes one status read
    fail, and treating that as a failed sync discarded a cycle that was
    still running perfectly well on the other side.
    """

    monkeypatch.setattr(pregame.time, "sleep", lambda _seconds: None)
    monkeypatch.setattr(pregame, "_api_base_url", lambda: "https://api.test")

    calls = {"n": 0}

    def _request(method, url, attempts=8):
        if method == "POST":
            return _running()
        calls["n"] += 1
        if calls["n"] in (1, 2, 3):
            raise requests.HTTPError("Transient HTTP 502 from status")
        return _complete()

    monkeypatch.setattr(pregame, "_request_json_with_retry", _request)

    result = pregame.run_live_api_sync()

    assert result["status"] == "complete"
    assert calls["n"] == 4, "polling continued through the outage"


def test_a_status_endpoint_that_stays_down_is_a_failure(monkeypatch):
    monkeypatch.setattr(pregame.time, "sleep", lambda _seconds: None)
    monkeypatch.setattr(pregame, "_api_base_url", lambda: "https://api.test")

    def _request(method, url, attempts=8):
        if method == "POST":
            return _running()
        raise requests.ConnectionError("connection refused")

    monkeypatch.setattr(pregame, "_request_json_with_retry", _request)

    with pytest.raises(RuntimeError, match="remained unavailable"):
        pregame.run_live_api_sync()


def test_the_failure_count_resets_after_any_good_read(monkeypatch):
    # Nine failures spread around a success are not a dead endpoint.
    monkeypatch.setattr(pregame.time, "sleep", lambda _seconds: None)
    monkeypatch.setattr(pregame, "_api_base_url", lambda: "https://api.test")

    sequence = (
        [requests.HTTPError("502")] * 9
        + [_running()]
        + [requests.HTTPError("502")] * 9
        + [_complete()]
    )
    calls = {"n": 0}

    def _request(method, url, attempts=8):
        if method == "POST":
            return _running()
        item = sequence[calls["n"]]
        calls["n"] += 1
        if isinstance(item, Exception):
            raise item
        return item

    monkeypatch.setattr(pregame, "_request_json_with_retry", _request)

    assert pregame.run_live_api_sync()["status"] == "complete"


def test_a_terminal_api_failure_is_still_an_error(monkeypatch):
    """Tolerating an unreachable status endpoint must not tolerate a sync
    that actually reported failure."""

    monkeypatch.setattr(pregame.time, "sleep", lambda _seconds: None)
    monkeypatch.setattr(pregame, "_api_base_url", lambda: "https://api.test")

    def _request(method, url, attempts=8):
        if method == "POST":
            return _running()
        return _running(status="failed", error="provider quota exhausted")

    monkeypatch.setattr(pregame, "_request_json_with_retry", _request)

    with pytest.raises(RuntimeError, match="provider quota exhausted"):
        pregame.run_live_api_sync()
