import os
import asyncio
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import main


def test_startup_recovery_skips_sync_when_props_exist(monkeypatch):
    fresh = SimpleNamespace(lastUpdatedUtc=datetime.now(timezone.utc).isoformat())
    monkeypatch.setattr(main, "get_props", lambda: [fresh])
    called = False

    def unexpected_sync():
        nonlocal called
        called = True

    monkeypatch.setattr(main, "_enqueue_prop_refresh", unexpected_sync)

    asyncio.run(main._ensure_props_available())

    assert called is False


def test_startup_recovery_queues_empty_cache_without_running_sync(monkeypatch):
    monkeypatch.setattr(main, "get_props", lambda: [])
    queued = []
    monkeypatch.setattr(
        main,
        "_enqueue_prop_refresh",
        lambda: queued.append("worker") or {"id": "refresh-1"},
    )
    monkeypatch.setattr(main, "job_queue_health", lambda: {"workers": 1})

    asyncio.run(main._ensure_props_available())

    assert queued == ["worker"]


def test_startup_recovery_queues_stale_cache_without_blocking(monkeypatch):
    stale = SimpleNamespace(
        lastUpdatedUtc=(
            datetime.now(timezone.utc) - timedelta(hours=2)
        ).isoformat()
    )
    monkeypatch.setattr(main, "get_props", lambda: [stale])
    monkeypatch.setenv("PROP_FEED_STALE_MINUTES", "45")
    queued = []
    monkeypatch.setattr(
        main,
        "_enqueue_prop_refresh",
        lambda: queued.append("worker") or {"id": "refresh-1"},
    )
    monkeypatch.setattr(main, "job_queue_health", lambda: {"workers": 1})

    asyncio.run(main._ensure_props_available())

    assert queued == ["worker"]


def test_startup_recovery_falls_back_once_without_an_active_worker(monkeypatch):
    props = []
    monkeypatch.setattr(main, "get_props", lambda: props)
    monkeypatch.setattr(main, "_enqueue_prop_refresh", lambda: {"id": "queued"})
    monkeypatch.setattr(main, "job_queue_health", lambda: {"workers": 0})

    def recover():
        props.append(
            SimpleNamespace(
                lastUpdatedUtc=datetime.now(timezone.utc).isoformat(),
                model_dump=lambda **_: {"id": "recovered"},
            )
        )
        main._sync_run_lock.release()

    monkeypatch.setattr(main, "_run_sync_background", recover)
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: props)
    monkeypatch.setattr(main, "save_catalog_snapshot", lambda _rows: True)

    asyncio.run(main._ensure_props_available())

    assert len(props) == 1


def test_prop_cache_without_update_timestamp_requires_refresh():
    assert main._prop_cache_needs_refresh(
        [SimpleNamespace(lastUpdatedUtc="")]
    )


def test_watchdog_refreshes_well_before_the_deploy_gate_rejects(monkeypatch) -> None:
    """The refresh policy must be able to satisfy the gate that checks it.

    These lived in two files with independently chosen numbers: the watchdog
    let the feed reach 180 minutes while the deploy smoke check failed at 45,
    so deploys failed on staleness the system was configured to allow.
    """

    import sys
    from pathlib import Path

    tools = Path(__file__).resolve().parents[2] / "tools"
    sys.path.insert(0, str(tools))
    try:
        import post_deploy_smoke
    finally:
        sys.path.remove(str(tools))

    monkeypatch.delenv("PROP_FEED_REFRESH_AFTER_MINUTES", raising=False)
    refresh_after = max(5, int(os.getenv("PROP_FEED_REFRESH_AFTER_MINUTES", "30")))

    assert refresh_after < post_deploy_smoke.MAX_PROP_FEED_AGE_MINUTES
    # The gate must also cover the queueing delay, not just the trigger point.
    assert post_deploy_smoke.MAX_PROP_FEED_AGE_MINUTES >= (
        refresh_after + post_deploy_smoke.PROP_FEED_REFRESH_DEDUPE_MINUTES
    )


def test_refresh_trigger_is_independent_of_the_health_alarm(monkeypatch) -> None:
    # Production sets PROP_FEED_STALE_MINUTES=180 to quiet the health report.
    # That must not push the refresh trigger out to three hours with it.
    monkeypatch.setenv("PROP_FEED_STALE_MINUTES", "180")
    monkeypatch.delenv("PROP_FEED_REFRESH_AFTER_MINUTES", raising=False)

    stale_prop = SimpleNamespace(
        lastUpdatedUtc=(
            datetime.now(timezone.utc) - timedelta(minutes=60)
        ).strftime("%Y-%m-%dT%H:%M:%SZ")
    )

    assert main._prop_cache_needs_refresh([stale_prop]) is True
