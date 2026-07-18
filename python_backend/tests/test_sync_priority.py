from services.sync_service import configured_sync_sports, prioritize_events


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
    ]


def test_sync_sports_override_is_trimmed_and_deduplicated(monkeypatch) -> None:
    monkeypatch.setenv(
        "PROP_SYNC_SPORTS",
        "basketball_nba, baseball_mlb,basketball_nba",
    )
    assert configured_sync_sports() == ["basketball_nba", "baseball_mlb"]
