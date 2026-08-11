import threading
import time

from services import sync_service
from services.sync_service import (
    configured_sync_sports, next_sgo_leagues, partition_sync_sports,
    prioritize_events,
    sgo_entity_quota_exhausted,
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
        "aussierules_afl",
        "rugbyleague_nrl",
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


def test_supplemental_leagues_rotate_without_starvation(monkeypatch) -> None:
    monkeypatch.setenv("SPORTSGAMEODDS_DISABLED_LEAGUES", "")
    monkeypatch.setattr(sync_service, "_sgo_league_cursor", 0)
    first = next_sgo_leagues(limit=1)
    second = next_sgo_leagues(limit=1)
    third = next_sgo_leagues(limit=1)
    fourth = next_sgo_leagues(limit=1)
    assert [first[0][0], second[0][0], third[0][0], fourth[0][0]] == [
        "ATP", "WTA", "PGA_MEN", "UFC",
    ]


def test_golf_is_disabled_by_default(monkeypatch) -> None:
    monkeypatch.delenv("SPORTSGAMEODDS_DISABLED_LEAGUES", raising=False)
    monkeypatch.setattr(sync_service, "_sgo_league_cursor", 0)

    selected = next_sgo_leagues(limit=4)

    assert [league for league, _ in selected] == ["ATP", "WTA", "UFC", "MLB"]


def test_default_supplemental_sync_attempts_every_enabled_league(monkeypatch) -> None:
    monkeypatch.delenv("SPORTSGAMEODDS_DISABLED_LEAGUES", raising=False)
    monkeypatch.delenv("SPORTSGAMEODDS_LEAGUES_PER_SYNC", raising=False)
    monkeypatch.setattr(sync_service, "_sgo_league_cursor", 0)

    selected = next_sgo_leagues()

    assert [league for league, _ in selected] == [
        league for league in sync_service.LEAGUE_TO_SPORT
        if league != "PGA_MEN"
    ]


def test_empty_supplemental_response_preserves_last_healthy_cache(monkeypatch) -> None:
    class Cache:
        prune_calls = 0

        def prune_provider_events(self, **_kwargs):
            self.prune_calls += 1

    fake_cache = Cache()
    monkeypatch.setattr(sync_service, "SPORTSGAMEODDS_API_KEY", "test-key")
    monkeypatch.setattr(sync_service, "cache", fake_cache)
    monkeypatch.setattr(sync_service, "fetch_sgo_account_usage", lambda: {})
    monkeypatch.setattr(sync_service, "next_sgo_leagues", lambda: [("ATP", "tennis_atp")])
    monkeypatch.setattr(sync_service, "fetch_sgo_events", lambda _league: [])

    result = sync_service.sync_sportsgameodds()

    assert result["attemptedLeagues"] == ["ATP"]
    assert result["leagueResults"] == [{"league": "ATP", "events": 0, "props": 0}]
    assert fake_cache.prune_calls == 0


def test_unavailable_supplemental_leagues_are_not_retried(monkeypatch) -> None:
    monkeypatch.setenv("SPORTSGAMEODDS_DISABLED_LEAGUES", "ATP,WTA,PGA_MEN")
    monkeypatch.setattr(sync_service, "_sgo_league_cursor", 0)

    selected = next_sgo_leagues(limit=4)

    assert [league for league, _ in selected] == ["UFC", "MLB", "NBA", "WNBA"]


def test_supplemental_entity_quota_is_detected() -> None:
    assert sgo_entity_quota_exhausted({
        "rateLimits": {"per-month": {"max-entities": 2500, "current-entities": 2536}}
    }) is True
    assert sgo_entity_quota_exhausted({
        "rateLimits": {"per-month": {"max-entities": 2500, "current-entities": 2499}}
    }) is False


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


def test_sync_prunes_expired_events_and_populates_the_new_slate(
    monkeypatch,
) -> None:
    events = [
        {"id": "new-event", "commence_time": "2026-07-27T20:00:00Z"},
    ]
    lifecycle = {"active_ids": [], "processed": []}

    class Cache:
        def prune_sport_to_event_ids(self, *, sport, active_event_ids):
            lifecycle["active_ids"] = active_event_ids

    monkeypatch.setattr(sync_service, "fetch_events", lambda _sport: events)
    monkeypatch.setattr(
        sync_service,
        "fetch_event_odds",
        lambda **_kwargs: {"bookmakers": [{"key": "test"}]},
    )
    monkeypatch.setattr(
        sync_service,
        "markets_for_sport",
        lambda _sport: ["player_points"],
    )
    monkeypatch.setattr(
        sync_service,
        "quota_allows",
        lambda _cost: {"allowed": True},
    )

    def process(**kwargs):
        lifecycle["processed"].append(kwargs["event"]["id"])
        return 3

    monkeypatch.setattr(sync_service, "process_and_cache_props", process)
    monkeypatch.setattr(sync_service, "cache", Cache())

    result = sync_service.sync_sport("basketball_wnba")

    assert lifecycle["active_ids"] == ["new-event"]
    assert lifecycle["processed"] == ["new-event"]
    assert result["fetchedEvents"] == 1
    assert result["props"] == 3


def test_complete_event_cycle_refreshes_lines_and_removes_expired_props(
    monkeypatch,
    tmp_path,
) -> None:
    from database.cache import PropCache

    cache = PropCache(tmp_path / "event-cycle.db")
    sport = "basketball_wnba"
    slate = [
        {"id": "old-event", "commence_time": "2026-07-26T16:15:00Z"},
    ]
    lines = {"old-event": 18.5}

    def process(*, cache, sport_key, event, odds_payload):
        line = float(odds_payload["line"])
        cache.replace_event_props(
            sport=sport_key,
            game={
                "id": event["id"],
                "home_team": "Home",
                "away_team": "Away",
                "commence_time": event["commence_time"],
            },
            props=[
                (
                    event["id"],
                    "Test Player",
                    "player_points",
                    line,
                    line,
                    line,
                    "2026-07-26T16:00:00Z",
                    -110,
                    -110,
                    "prizepicks",
                    "",
                    0,
                    "player-1",
                    None,
                    None,
                    None,
                    None,
                    None,
                    None,
                    None,
                    None,
                    None,
                    "2026-07-26T16:00:00Z",
                ),
            ],
        )
        return 1

    monkeypatch.setattr(sync_service, "cache", cache)
    monkeypatch.setattr(sync_service, "fetch_events", lambda _sport: slate)
    monkeypatch.setattr(
        sync_service,
        "fetch_event_odds",
        lambda **kwargs: {"line": lines[kwargs["event_id"]]},
    )
    monkeypatch.setattr(
        sync_service,
        "markets_for_sport",
        lambda _sport: ["player_points"],
    )
    monkeypatch.setattr(
        sync_service,
        "quota_allows",
        lambda _cost: {"allowed": True},
    )
    monkeypatch.setattr(sync_service, "process_and_cache_props", process)

    first = sync_service.sync_sport(sport)
    assert first["props"] == 1
    assert cache.load_props()[0]["line"] == 18.5

    lines["old-event"] = 19.5
    refreshed = sync_service.sync_sport(sport)
    assert refreshed["props"] == 1
    assert cache.load_props()[0]["line"] == 19.5

    slate[:] = [
        {"id": "new-event", "commence_time": "2026-07-27T16:15:00Z"},
    ]
    lines["new-event"] = 21.5
    replacement = sync_service.sync_sport(sport)
    rows = cache.load_props()
    assert replacement["props"] == 1
    assert [row["game_id"] for row in rows] == ["new-event"]
    assert rows[0]["line"] == 21.5


def test_sportsgameodds_contribution_separates_unique_and_overlap(monkeypatch) -> None:
    shared = {
        "sport": "basketball_wnba",
        "home_team": "Chicago Sky",
        "away_team": "Phoenix Mercury",
        "commence_time": "2026-08-11T00:00:00Z",
        "player_name": "Example Player",
        "line": 18.5,
        "bookmaker": "draftkings",
    }
    rows = [
        {
            **shared,
            "game_id": "odds-api-event",
            "prop_type": "player_points",
        },
        {
            **shared,
            "game_id": "sgo:event-overlap",
            "prop_type": "player_points",
        },
        {
            **shared,
            "game_id": "sgo:event-unique",
            "prop_type": "player_assists",
            "line": 4.5,
        },
    ]

    class FakeCache:
        def load_props(self):
            return rows

    class BoardProp:
        sourceProvider = "sportsgameodds"

    monkeypatch.setattr(sync_service, "cache", FakeCache())
    monkeypatch.setattr(sync_service, "get_props", lambda: [BoardProp()])

    contribution = sync_service._sportsgameodds_contribution()

    assert contribution == {
        "cachedRows": 2,
        "uniqueMarketRows": 1,
        "overlappingMarketRows": 1,
        "boardProps": 1,
        "uniqueBySport": {"basketball_wnba": 1},
        "overlappingBySport": {"basketball_wnba": 1},
    }
