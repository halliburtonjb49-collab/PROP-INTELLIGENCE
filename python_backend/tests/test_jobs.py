from datetime import datetime, timezone

import jobs
from services import espn_headshot_service, job_queue_service


def test_headshot_safety_net_skips_fresh_cache(monkeypatch) -> None:
    monkeypatch.setattr(
        espn_headshot_service,
        "espn_headshot_cache_health",
        lambda **_kwargs: {"status": "ok", "ageHours": 3.5},
    )
    monkeypatch.setattr(
        job_queue_service,
        "enqueue",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError("fresh photos must not enqueue a refresh")
        ),
    )

    assert jobs._enqueue_espn_headshot_refresh_if_due() is None


def test_headshot_safety_net_queues_aging_cache_with_stable_bucket(
    monkeypatch,
) -> None:
    captured = {}
    monkeypatch.setattr(
        espn_headshot_service,
        "espn_headshot_cache_health",
        lambda **_kwargs: {"status": "ok", "ageHours": 8.1},
    )

    def fake_enqueue(function_name, *, job_id):
        captured.update(function_name=function_name, job_id=job_id)
        return {"id": job_id, "status": "queued"}

    monkeypatch.setattr(job_queue_service, "enqueue", fake_enqueue)
    now = datetime(2026, 8, 16, 16, 5, tzinfo=timezone.utc)

    result = jobs._enqueue_espn_headshot_refresh_if_due(now=now)

    assert result is not None
    assert captured["function_name"] == "jobs.refresh_espn_headshots"
    assert captured["job_id"].startswith("headshots:espn:auto:")


def test_headshot_safety_net_queues_missing_cache(monkeypatch) -> None:
    monkeypatch.setattr(
        espn_headshot_service,
        "espn_headshot_cache_health",
        lambda **_kwargs: {"status": "missing", "ageHours": None},
    )
    monkeypatch.setattr(
        job_queue_service,
        "enqueue",
        lambda function_name, *, job_id: {
            "id": job_id,
            "function": function_name,
        },
    )

    result = jobs._enqueue_espn_headshot_refresh_if_due()

    assert result is not None
    assert result["function"] == "jobs.refresh_espn_headshots"
