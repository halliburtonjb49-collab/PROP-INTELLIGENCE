from datetime import datetime, timezone

from services.sync_certification_service import sync_certification


def _healthy_inputs() -> dict[str, object]:
    return {
        "feed": {"healthy": True},
        "queue": {
            "available": True,
            "workers": 1,
            "failed": 0,
            "queued": 0,
            "retryPolicy": {
                "maxAttempts": 4,
                "retryIntervalsSeconds": [30, 120, 300],
            },
        },
        "keys": {"configuredKeyCount": 2, "usableKeyCount": 2},
        "coverage": {
            "configured": ["baseball_mlb", "basketball_wnba"],
            "neverFetched": [],
            "starvedByQuota": [],
            "results": {
                "baseball_mlb": {"lastError": ""},
                "basketball_wnba": {"lastError": ""},
            },
        },
    }


def test_sync_certification_passes_only_a_complete_healthy_system() -> None:
    report = sync_certification(
        **_healthy_inputs(),
        now_utc=datetime(2026, 8, 10, tzinfo=timezone.utc),
    )

    assert report["status"] == "PASSED"
    assert report["automaticRetries"] is True
    assert report["needsAttention"] is False
    assert {check["status"] for check in report["checks"]} == {"PASSED"}


def test_unfetched_broad_sports_are_pending_not_silently_passed() -> None:
    inputs = _healthy_inputs()
    inputs["coverage"]["neverFetched"] = ["basketball_wnba"]

    report = sync_certification(**inputs)

    assert report["status"] == "PENDING"
    assert report["pendingSports"] == ["basketball_wnba"]


def test_dead_keys_or_unavailable_worker_fail_certification() -> None:
    inputs = _healthy_inputs()
    inputs["keys"] = {"configuredKeyCount": 2, "usableKeyCount": 0}
    inputs["queue"]["available"] = False

    report = sync_certification(**inputs)

    assert report["status"] == "FAILED"
    failed = {
        check["key"] for check in report["checks"]
        if check["status"] == "FAILED"
    }
    assert failed == {"queue", "provider_keys"}


def test_exhausted_retries_or_provider_errors_are_warnings() -> None:
    inputs = _healthy_inputs()
    inputs["queue"]["failed"] = 2
    inputs["coverage"]["results"]["baseball_mlb"] = {
        "lastError": "HTTP 503"
    }

    report = sync_certification(**inputs)

    assert report["status"] == "WARNING"
    assert report["needsAttention"] is True
