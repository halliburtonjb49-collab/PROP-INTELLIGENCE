import asyncio

import main


def test_startup_recovery_skips_sync_when_props_exist(monkeypatch):
    monkeypatch.setattr(main, "get_props", lambda: [object()])
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
