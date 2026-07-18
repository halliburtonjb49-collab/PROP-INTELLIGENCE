import threading
import time

from services import sync_service
from services.sync_service import (
    configured_sync_sports, partition_sync_sports, prioritize_events,
)


def test_events_are_prioritized_by_start_time_with_invalid_rows_last() -> None:
    events = [
        {"id": "late", "commence_time": "2026-07-18T02:00:00Z"},
        {"id": "missing"},
        {"id": "soon", "commence_time": "2026-07-17T20:00:00Z"},
        {"id": "middle", "commence_time": "2026-07-17T23:00:00Z"},
    ]
    assert [event["id"] for event in prioritize_events(events)] == [
        "soon", "middle", "late", "missing",
    ]


def test_equal_start_times_have_stable_id_order() -> None:
    events = [
        {"id": "b", "commence_time": "2026-07-17T20:00:00Z"},
        {"id": "a", "commence_time": "2026-07-17T20:00:00Z"},
    ]
    assert [event["id"] for event in prioritize_events(events)] == ["a", "b"]


def test_default_sync_covers_every_configured_prop_sport(monkeypatch) -> None:
    monkeypatch.delenv("PROP_SYNC_SPORTS", raising=False)
    assert configured_sync_sports() == [
        "baseball_mlb",
        "basketball_wnba",
        "basketball_nba",
        "americanfootball_nfl",
        "icehockey_nhl",
        "soccer_epl",
        "soccer_usa_mls",
        "soccer_france_ligue_one",
        "soccer_germany_bundesliga",
        "soccer_italy_serie_a",
        "soccer_spain_la_liga",
    ]


def test_sync_sports_override_is_trimmed_and_deduplicated(monkeypatch) -> None:
    monkeypatch.setenv(
        "PROP_SYNC_SPORTS",
        "basketball_nba, baseball_mlb,basketball_nba",
    )
    assert configured_sync_sports() == ["basketball_nba", "baseball_mlb"]


def test_productive_sports_are_partitioned_into_fast_lane(monkeypatch) -> None:
    monkeypatch.delenv("PROP_FAST_SYNC_SPORTS", raising=False)
    fast, coverage = partition_sync_sports(list(sync_service.DEFAULT_SYNC_SPORTS))
    assert fast == [
        "baseball_mlb", "basketball_wnba", "basketball_nba",
        "americanfootball_nfl",
    ]
    assert "icehockey_nhl" in coverage
    assert "soccer_epl" in coverage


def test_coverage_lane_uses_independent_cooldown(monkeypatch) -> None:
    monkeypatch.setenv("PROP_COVERAGE_SYNC_SECONDS", "1800")
    monkeypatch.setattr(sync_service, "_last_coverage_sync_monotonic", None)
    assert sync_service._coverage_sync_due(now=1000) is True
    sync_service._mark_coverage_synced(now=1000)
    assert sync_service._coverage_sync_due(now=1200) is False
    assert sync_service._coverage_sync_due(now=2801) is True


def test_event_odds_fetches_overlap_but_cache_processing_is_serial(monkeypatch) -> None:
    events = [
        {"id": f"event-{index}", "commence_time": f"2026-07-18T2{index}:00:00Z"}
        for index in range(6)
    ]
    active = 0
    peak = 0
    lock = threading.Lock()

    def fetch_odds(**_kwargs):
        nonlocal active, peak
        with lock:
            active += 1
            peak = max(peak, active)
        time.sleep(0.03)
        with lock:
            active -= 1
        return {"bookmakers": []}

    class Cache:
        def prune_sport_to_event_ids(self, **_kwargs):
            return None

    monkeypatch.setenv("PROP_SYNC_EVENT_WORKERS", "4")
    monkeypatch.setattr(sync_service, "fetch_events", lambda _sport: events)
    monkeypatch.setattr(sync_service, "fetch_event_odds", fetch_odds)
    monkeypatch.setattr(sync_service, "markets_for_sport", lambda _sport: ["player_points"])
    monkeypatch.setattr(sync_service, "quota_allows", lambda _cost: {"allowed": True})
    monkeypatch.setattr(sync_service, "process_and_cache_props", lambda **_kwargs: 1)
    monkeypatch.setattr(sync_service, "cache", Cache())

    result = sync_service.sync_sport("basketball_nba")

    assert peak > 1
    assert result["fetchedEvents"] == 6
    assert result["props"] == 6
    assert result["eventWorkers"] == 4
