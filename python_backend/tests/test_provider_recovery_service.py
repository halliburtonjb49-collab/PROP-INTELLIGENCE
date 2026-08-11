from datetime import datetime, timezone

from services import provider_recovery_service as recovery


NOW = datetime(2026, 8, 11, 18, 0, tzinfo=timezone.utc)


def _availability(*, authorization="AUTHORIZED", status="PARTIAL", stale=True):
    return {
        "overallStatus": "ATTENTION",
        "sports": [
            {
                "sport": "WNBA",
                "status": status,
                "authorizationStatus": authorization,
                "stale": stale,
                "missingData": ["Latest availability data is stale."],
            },
            {
                "sport": "NFL",
                "status": "NOT_ENTITLED",
                "authorizationStatus": "NOT_ENTITLED",
                "stale": False,
                "missingData": ["Provider plan does not include this sport."],
            },
        ],
    }


def _configure(monkeypatch, *, sync=None, action=None, queue=None, availability=None):
    cache = {
        recovery._SYNC_STATE_KEY: sync or {},
        recovery._ACTION_KEY: action,
    }
    monkeypatch.setattr(recovery, "get_json", lambda key: cache.get(key))
    monkeypatch.setattr(
        recovery,
        "set_json",
        lambda key, value, **_: cache.__setitem__(key, value) or True,
    )
    monkeypatch.setattr(
        recovery,
        "provider_availability_snapshot",
        lambda **_: availability or _availability(),
    )
    monkeypatch.setattr(
        recovery,
        "queue_health",
        lambda: queue or {
            "available": True,
            "workers": 1,
            "queued": 0,
            "started": 0,
            "retryPolicy": {"maxAttempts": 4},
        },
    )
    return cache


def test_snapshot_recommends_only_authorized_stale_sports(monkeypatch) -> None:
    _configure(monkeypatch)

    result = recovery.provider_recovery_snapshot(now=NOW)

    assert result["state"] == "RECOMMENDED"
    assert result["canStartRecovery"] is True
    assert result["actionableSports"] == ["WNBA"]
    sports = {row["sport"]: row for row in result["sports"]}
    assert sports["WNBA"]["canRecover"] is True
    assert sports["NFL"]["canRecover"] is False
    assert "plan" in sports["NFL"]["reason"].lower()


def test_request_uses_automatic_deduplication_key_and_retrying_queue(monkeypatch) -> None:
    cache = _configure(monkeypatch)
    captured = {}

    def enqueue(function_name, *, job_id):
        captured.update(function=function_name, job_id=job_id)
        return {"id": job_id, "status": "queued", "queue": "prop-intelligence"}

    monkeypatch.setattr(recovery, "enqueue", enqueue)
    monkeypatch.setattr(recovery.time, "time", lambda: 1_800_000_000)
    monkeypatch.setenv("APP_VERSION", "release-abcdef123456")

    result = recovery.request_provider_recovery("WNBA", now=NOW)

    expected_bucket = int(1_800_000_000 // recovery._RECOVERY_BUCKET_SECONDS)
    assert captured["function"] == "jobs.run_prop_sync"
    assert captured["job_id"] == f"prop-freshness:release-abcd:{expected_bucket}"
    assert result["request"]["accepted"] is True
    assert result["request"]["status"] == "QUEUED"
    assert cache[recovery._ACTION_KEY]["affectedSports"] == ["WNBA"]


def test_running_recovery_is_deduplicated_without_another_enqueue(monkeypatch) -> None:
    _configure(monkeypatch, sync={"status": "running", "startedAt": NOW.isoformat()})
    monkeypatch.setattr(
        recovery,
        "enqueue",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(AssertionError("duplicate queued")),
    )

    result = recovery.request_provider_recovery("ALL", now=NOW)

    assert result["request"]["accepted"] is True
    assert result["request"]["deduplicated"] is True
    assert result["request"]["status"] == "RUNNING"


def test_configuration_problem_is_not_retried(monkeypatch) -> None:
    _configure(
        monkeypatch,
        availability=_availability(
            authorization="NOT_CONFIGURED", status="UNAVAILABLE", stale=True,
        ),
    )
    monkeypatch.setattr(
        recovery,
        "enqueue",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(AssertionError("invalid retry")),
    )

    result = recovery.request_provider_recovery("WNBA", now=NOW)

    assert result["request"]["accepted"] is False
    assert result["request"]["status"] == "BLOCKED"
    assert "configuration" in result["request"]["reason"].lower()


def test_completed_sync_marks_latest_recovery_successful(monkeypatch) -> None:
    requested = datetime(2026, 8, 11, 17, 0, tzinfo=timezone.utc)
    finished = datetime(2026, 8, 11, 17, 10, tzinfo=timezone.utc)
    _configure(
        monkeypatch,
        sync={
            "status": "complete",
            "coverageStatus": "complete",
            "postProcessingStatus": "complete",
            "finishedAt": finished.isoformat(),
        },
        action={
            "requestedAt": requested.isoformat(),
            "job": {"id": "job", "status": "finished"},
        },
        availability=_availability(status="HEALTHY", stale=False),
    )

    result = recovery.provider_recovery_snapshot(now=NOW)

    assert result["state"] == "SUCCEEDED"
    assert result["recoveryRecommended"] is False

def test_completed_sync_keeps_recovery_recommended_when_data_is_still_stale(
    monkeypatch,
) -> None:
    _configure(
        monkeypatch,
        sync={
            "status": "complete",
            "coverageStatus": "complete",
            "postProcessingStatus": "complete",
            "finishedAt": "2026-08-11T17:10:00+00:00",
        },
        action={
            "requestedAt": "2026-08-11T17:00:00+00:00",
            "job": {"id": "job", "status": "finished"},
        },
    )

    result = recovery.provider_recovery_snapshot(now=NOW)

    assert result["state"] == "RECOMMENDED"
    assert result["recoveryRecommended"] is True
    assert "still incomplete" in result["message"]

def test_finished_duplicate_is_reported_as_safety_cooldown(monkeypatch) -> None:
    _configure(monkeypatch)
    monkeypatch.setattr(recovery.time, "time", lambda: 1_800_000_000)
    monkeypatch.setattr(
        recovery,
        "enqueue",
        lambda *_args, **_kwargs: {
            "id": "existing",
            "status": "finished",
            "deduplicated": True,
        },
    )

    result = recovery.request_provider_recovery("ALL", now=NOW)

    assert result["request"]["accepted"] is False
    assert result["request"]["status"] == "COOLDOWN"
    assert result["request"]["deduplicated"] is True
    assert "15-minute" in result["request"]["reason"]