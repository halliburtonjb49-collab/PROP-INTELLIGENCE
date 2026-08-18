import importlib.util
import json
import urllib.error
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "post_deploy_smoke",
    ROOT / "tools" / "post_deploy_smoke.py",
)
assert SPEC is not None and SPEC.loader is not None
post_deploy_smoke = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(post_deploy_smoke)


class _Response:
    status = 200

    def __init__(self, body: bytes = b"ok") -> None:
        self._body = body

    def read(self) -> bytes:
        return self._body


def _bad_gateway(url: str) -> urllib.error.HTTPError:
    return urllib.error.HTTPError(url, 502, "Bad Gateway", {}, None)


def test_request_recovers_after_extended_render_rollout(monkeypatch) -> None:
    attempts = 0
    delays: list[int] = []

    def fake_urlopen(request, timeout):
        nonlocal attempts
        attempts += 1
        if attempts <= 4:
            raise _bad_gateway(request.full_url)
        return _Response()

    monkeypatch.setattr(post_deploy_smoke.urllib.request, "urlopen", fake_urlopen)
    monkeypatch.setattr(post_deploy_smoke.time, "sleep", delays.append)

    response, body, _ = post_deploy_smoke.request("https://example.com/health")

    assert response.status == 200
    assert body == b"ok"
    assert attempts == 5
    assert delays == [2, 4, 8, 10]


def test_request_does_not_retry_authentication_failures(monkeypatch) -> None:
    attempts = 0

    def fake_urlopen(request, timeout):
        nonlocal attempts
        attempts += 1
        raise urllib.error.HTTPError(
            request.full_url,
            401,
            "Unauthorized",
            {},
            None,
        )

    monkeypatch.setattr(post_deploy_smoke.urllib.request, "urlopen", fake_urlopen)

    try:
        post_deploy_smoke.request("https://example.com/private")
    except urllib.error.HTTPError as exc:
        assert exc.code == 401
    else:
        raise AssertionError("401 response should fail immediately")

    assert attempts == 1


def test_wait_for_expected_version_polls_until_render_activates_commit(
    monkeypatch,
) -> None:
    versions = iter(["old-version", "expected-version"])
    delays: list[int] = []

    def fake_request(url, *, transient_attempts):
        body = json.dumps(
            {"status": "ok", "version": next(versions)}
        ).encode()
        return _Response(body), body, 1.0

    monkeypatch.setenv("EXPECTED_PRODUCTION_VERSION", "expected-version")
    monkeypatch.setenv("PRODUCTION_DEPLOY_WAIT_SECONDS", "60")
    monkeypatch.setattr(post_deploy_smoke, "request", fake_request)
    monkeypatch.setattr(post_deploy_smoke.time, "sleep", delays.append)

    post_deploy_smoke.wait_for_expected_version()

    assert delays == [post_deploy_smoke.DEPLOYMENT_POLL_SECONDS]


def test_readiness_waits_for_feed_to_refresh_after_deployment(monkeypatch) -> None:
    real_datetime = post_deploy_smoke.datetime
    timestamps = iter(
        [
            "2026-07-29T16:00:00Z",
            "2026-07-29T17:00:00Z",
        ]
    )
    delays: list[int] = []

    class _Now:
        @classmethod
        def now(cls, tz):
            return real_datetime.fromisoformat(
                "2026-07-29T17:30:00+00:00"
            )

        @classmethod
        def fromisoformat(cls, value):
            return real_datetime.fromisoformat(value)

    def fake_request(url):
        body = json.dumps(
            {
                "status": "ok",
                "count": 10,
                "dataProtected": True,
                "lastDataUpdatedAt": next(timestamps),
            }
        ).encode()
        return _Response(body), body, 1.0

    monkeypatch.setenv("PRODUCTION_FEED_WARMUP_SECONDS", "60")
    monkeypatch.setattr(post_deploy_smoke, "request", fake_request)
    monkeypatch.setattr(post_deploy_smoke, "datetime", _Now)
    monkeypatch.setattr(post_deploy_smoke.time, "sleep", delays.append)

    _, _, _, _, feed_age = post_deploy_smoke.read_fresh_prop_readiness()

    assert feed_age == 30
    assert delays == [post_deploy_smoke.DEPLOYMENT_POLL_SECONDS]


def test_readiness_prefers_catalog_publication_freshness(monkeypatch) -> None:
    real_datetime = post_deploy_smoke.datetime

    class _Now:
        @classmethod
        def now(cls, tz):
            return real_datetime.fromisoformat(
                "2026-07-29T17:30:00+00:00"
            )

        @classmethod
        def fromisoformat(cls, value):
            return real_datetime.fromisoformat(value)

    payload = {
        "lastDataUpdatedAt": "2026-07-29T12:00:00Z",
        "catalogPublishedAt": "2026-07-29T17:25:00Z",
    }
    monkeypatch.setattr(post_deploy_smoke, "datetime", _Now)

    assert post_deploy_smoke._feed_age_minutes(payload) == 5


def test_readiness_retries_one_cold_cache_performance_sample(monkeypatch) -> None:
    response_times = iter([11_500, 800])
    delays: list[int] = []

    def fake_request(url):
        server_ms = next(response_times)
        body = json.dumps(
            {
                "status": "ok",
                "count": 10,
                "dataProtected": True,
                "lastDataUpdatedAt": "2026-07-29T17:00:00Z",
                "responseMs": server_ms,
            }
        ).encode()
        return _Response(body), body, server_ms

    real_datetime = post_deploy_smoke.datetime

    class _Now:
        @classmethod
        def now(cls, tz):
            return real_datetime.fromisoformat(
                "2026-07-29T17:30:00+00:00"
            )

        @classmethod
        def fromisoformat(cls, value):
            return real_datetime.fromisoformat(value)

    monkeypatch.setenv("PRODUCTION_FEED_WARMUP_SECONDS", "60")
    monkeypatch.setattr(post_deploy_smoke, "request", fake_request)
    monkeypatch.setattr(post_deploy_smoke, "datetime", _Now)
    monkeypatch.setattr(post_deploy_smoke.time, "sleep", delays.append)

    _, _, props_ms, payload, _ = (
        post_deploy_smoke.read_fresh_prop_readiness()
    )

    assert payload["responseMs"] == 800
    assert props_ms == 800
    assert delays == [post_deploy_smoke.DEPLOYMENT_POLL_SECONDS]
