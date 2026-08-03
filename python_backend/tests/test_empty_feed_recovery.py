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

    asyncio.run(main._ensure_props_available())

    assert queued == ["worker"]


def test_prop_cache_without_update_timestamp_requires_refresh():
    assert main._prop_cache_needs_refresh(
        [SimpleNamespace(lastUpdatedUtc="")]
    )
