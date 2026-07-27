from datetime import datetime, timedelta, timezone

from services.prop_service import data_freshness


def test_prop_freshness_marks_recent_data_fresh(monkeypatch) -> None:
    monkeypatch.setenv("PROP_FEED_STALE_MINUTES", "45")
    now = datetime(2026, 7, 27, 18, 0, tzinfo=timezone.utc)
    age, stale = data_freshness((now - timedelta(minutes=10)).isoformat(), now)
    assert age == 600
    assert stale is False


def test_prop_freshness_fails_closed_for_old_or_missing_data(monkeypatch) -> None:
    monkeypatch.setenv("PROP_FEED_STALE_MINUTES", "45")
    now = datetime(2026, 7, 27, 18, 0, tzinfo=timezone.utc)
    assert data_freshness((now - timedelta(minutes=46)).isoformat(), now)[1] is True
    assert data_freshness("", now) == (None, True)
