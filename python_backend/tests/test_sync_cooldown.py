from datetime import datetime, timedelta, timezone

import main


def test_sync_freshness_window_reuses_recent_provider_data(monkeypatch) -> None:
    monkeypatch.setattr(main, "LIVE_ODDS_SYNC_MIN_SECONDS", 300)
    now = datetime(2026, 7, 17, 20, 0, tzinfo=timezone.utc)
    with main._sync_state_lock:
        original = main._sync_state.get("finishedAt")
    try:
        with main._sync_state_lock:
            main._sync_state["finishedAt"] = (now - timedelta(seconds=299)).isoformat()
        assert main._sync_is_fresh(now) is True
        with main._sync_state_lock:
            main._sync_state["finishedAt"] = (now - timedelta(seconds=301)).isoformat()
        assert main._sync_is_fresh(now) is False
    finally:
        with main._sync_state_lock:
            main._sync_state["finishedAt"] = original


def test_sync_cooldown_adapts_to_provider_quota(monkeypatch) -> None:
    monkeypatch.setattr(main, "LIVE_ODDS_SYNC_MIN_SECONDS", 300)
    monkeypatch.setattr(main, "quota_snapshot", lambda: {"remaining": 500, "lowQuota": False})
    assert main._effective_sync_cooldown_seconds() == 300
    monkeypatch.setattr(main, "quota_snapshot", lambda: {"remaining": 75, "lowQuota": True})
    assert main._effective_sync_cooldown_seconds() == 1800
    monkeypatch.setattr(main, "quota_snapshot", lambda: {"remaining": 10, "lowQuota": True})
    assert main._effective_sync_cooldown_seconds() == 3600
