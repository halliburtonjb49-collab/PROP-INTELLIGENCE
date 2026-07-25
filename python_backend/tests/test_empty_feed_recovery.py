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

    monkeypatch.setattr(main, "_run_sync_background", unexpected_sync)

    asyncio.run(main._ensure_props_available())

    assert called is False


def test_startup_recovery_populates_empty_cache(monkeypatch):
    props = []
    monkeypatch.setattr(main, "get_props", lambda: props)
    monkeypatch.setenv("EMPTY_PROP_SYNC_ATTEMPTS", "1")

    def successful_sync():
        props.append(object())
        main._sync_run_lock.release()

    monkeypatch.setattr(main, "_run_sync_background", successful_sync)

    asyncio.run(main._ensure_props_available())

    assert props


def test_startup_recovery_refreshes_stale_cache(monkeypatch):
    stale = SimpleNamespace(
        lastUpdatedUtc=(
            datetime.now(timezone.utc) - timedelta(hours=2)
        ).isoformat()
    )
    fresh = SimpleNamespace(lastUpdatedUtc=datetime.now(timezone.utc).isoformat())
    props = [stale]
    monkeypatch.setattr(main, "get_props", lambda: props)
    monkeypatch.setenv("EMPTY_PROP_SYNC_ATTEMPTS", "1")
    monkeypatch.setenv("PROP_FEED_STALE_MINUTES", "45")

    def successful_sync():
        props[:] = [fresh]
        main._sync_run_lock.release()

    monkeypatch.setattr(main, "_run_sync_background", successful_sync)

    asyncio.run(main._ensure_props_available())

    assert props == [fresh]


def test_prop_cache_without_update_timestamp_requires_refresh():
    assert main._prop_cache_needs_refresh(
        [SimpleNamespace(lastUpdatedUtc="")]
    )
