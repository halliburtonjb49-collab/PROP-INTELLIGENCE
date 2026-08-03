from datetime import date

from scripts import sync_other_historical_daily


def test_specialty_window_accumulates_recent_days(monkeypatch) -> None:
    monkeypatch.setenv("SPECIALTY_HISTORY_LOOKBACK_DAYS", "3")
    seen = []

    def fake_sync(day):
        seen.append(day)
        return {
            "fetched": 2, "upserted": 2,
            "bySport": {"TENNIS": 1, "PGA": 1, "UFC": 0},
        }

    monkeypatch.setattr(sync_other_historical_daily, "_sync_specialty_history", fake_sync)
    result = sync_other_historical_daily._sync_specialty_history_window(date(2026, 8, 2))

    assert seen == [date(2026, 8, 2), date(2026, 8, 1), date(2026, 7, 31)]
    assert result["lookbackDays"] == 3
    assert result["fetched"] == 6
    assert result["bySport"] == {"TENNIS": 3, "PGA": 3, "UFC": 0}


def test_specialty_window_caps_provider_lookback(monkeypatch) -> None:
    monkeypatch.setenv("SPECIALTY_HISTORY_LOOKBACK_DAYS", "1000")
    monkeypatch.setattr(
        sync_other_historical_daily,
        "_sync_specialty_history",
        lambda _day: {"fetched": 0, "upserted": 0, "bySport": {}},
    )
    result = sync_other_historical_daily._sync_specialty_history_window(date(2026, 8, 2))
    assert result["lookbackDays"] == 30
    assert len(result["daily"]) == 30
