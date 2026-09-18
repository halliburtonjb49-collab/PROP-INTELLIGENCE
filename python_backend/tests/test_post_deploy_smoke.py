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
    def __init__(self, body: bytes = b"ok", status: int = 200) -> None:
        self._body = body
        self.status = status

    def read(self) -> bytes:
        return self._body


def test_customer_journey_checks_capabilities_and_scoreboard(monkeypatch) -> None:
    calls: list[str] = []

    def fake_request(url):
        calls.append(url)
        if url.endswith("/api/scoreboard"):
            body = json.dumps({"games": []}).encode()
        else:
            body = json.dumps(
                {
                    "status": "ok",
                    "checks": {
                        "inventory": True,
                        "playerSearch": True,
                        "categoryFilter": True,
                        "gameTimes": True,
                        "playerPhotos": True,
                    },
                    "samplePlayer": "Sample Player",
                    "sampleCategory": "POINTS",
                    "modelLearning": {
                        "status": "ready",
                        "checks": {"captureObserved": True},
                    },
                }
            ).encode()
        return _Response(body), body, 125.0

    monkeypatch.setattr(post_deploy_smoke, "request", fake_request)

    result = post_deploy_smoke.verify_customer_journey()

    assert result["checks"]["playerSearch"] is True
    assert result["samplePlayer"] == "Sample Player"
    assert result["sampleCategory"] == "POINTS"
    assert result["modelLearning"]["status"] == "ready"
    assert calls[0].endswith("/api/operations/customer-journey-readiness")
    assert calls[-1].endswith("/api/scoreboard")


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


def test_release_gate_allows_feed_stale_only_when_billing_is_ready(monkeypatch) -> None:
    body = json.dumps(
        {
            "releaseReady": False,
            "acceptanceStatus": "critical",
            "billingReady": True,
            "criticalIssueCount": 1,
            "criticalIssueCodes": ["feed_stale"],
        }
    ).encode()

    monkeypatch.setattr(
        post_deploy_smoke,
        "request",
        lambda url: (_Response(body), body, 1.0),
    )

    post_deploy_smoke.verify_release_gate()


def test_release_gate_allows_normalized_feed_stale_code(monkeypatch) -> None:
    body = json.dumps(
        {
            "releaseReady": False,
            "acceptanceStatus": "critical",
            "billingReady": True,
            "criticalIssueCount": 1,
            "criticalIssueCodes": [" FEED_STALE "],
        }
    ).encode()

    monkeypatch.setattr(
        post_deploy_smoke,
        "request",
        lambda url: (_Response(body), body, 1.0),
    )

    post_deploy_smoke.verify_release_gate()


def test_release_gate_rejects_other_critical_issues(monkeypatch) -> None:
    body = json.dumps(
        {
            "releaseReady": False,
            "acceptanceStatus": "critical",
            "billingReady": True,
            "criticalIssueCount": 2,
            "criticalIssueCodes": ["feed_stale", "products_unconfigured"],
        }
    ).encode()

    monkeypatch.setattr(
        post_deploy_smoke,
        "request",
        lambda url: (_Response(body), body, 1.0),
    )

    try:
        post_deploy_smoke.verify_release_gate()
    except RuntimeError as exc:
        assert "Promotion blocked by production certification" in str(exc)
    else:
        raise AssertionError("non-feed-stale critical issues must fail the gate")


def test_release_gate_rejects_duplicate_feed_stale_issues(monkeypatch) -> None:
    body = json.dumps(
        {
            "releaseReady": False,
            "acceptanceStatus": "critical",
            "billingReady": True,
            "criticalIssueCount": 2,
            "criticalIssueCodes": ["feed_stale", "feed_stale"],
        }
    ).encode()

    monkeypatch.setattr(
        post_deploy_smoke,
        "request",
        lambda url: (_Response(body), body, 1.0),
    )

    try:
        post_deploy_smoke.verify_release_gate()
    except RuntimeError as exc:
        assert "Promotion blocked by production certification" in str(exc)
    else:
        raise AssertionError("duplicate feed_stale issues must fail the gate")


def test_release_gate_rejects_feed_stale_when_critical_count_is_not_one(monkeypatch) -> None:
    body = json.dumps(
        {
            "releaseReady": False,
            "acceptanceStatus": "critical",
            "billingReady": True,
            "criticalIssueCount": 2,
            "criticalIssueCodes": ["feed_stale"],
        }
    ).encode()

    monkeypatch.setattr(
        post_deploy_smoke,
        "request",
        lambda url: (_Response(body), body, 1.0),
    )

    try:
        post_deploy_smoke.verify_release_gate()
    except RuntimeError as exc:
        assert "Promotion blocked by production certification" in str(exc)
    else:
        raise AssertionError("feed_stale bypass requires exactly one critical issue")


def test_release_gate_reports_unavailable_before_parsing_body(monkeypatch) -> None:
    monkeypatch.setattr(
        post_deploy_smoke,
        "request",
        lambda url: (_Response(b"not-json", status=503), b"not-json", 1.0),
    )

    try:
        post_deploy_smoke.verify_release_gate()
    except RuntimeError as exc:
        assert str(exc) == "Production release gate is unavailable"
    else:
        raise AssertionError("non-200 release gate responses must fail")


def test_release_gate_reports_malformed_json_on_200_response(monkeypatch) -> None:
    monkeypatch.setattr(
        post_deploy_smoke,
        "request",
        lambda url: (_Response(b"not-json", status=200), b"not-json", 1.0),
    )

    try:
        post_deploy_smoke.verify_release_gate()
    except RuntimeError as exc:
        assert str(exc) == "Production release gate returned malformed JSON"
    else:
        raise AssertionError("malformed release gate payload must fail")
