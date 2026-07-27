from pathlib import Path

from database.cache import PropCache
from providers import sportsgameodds
from services.prop_processor import process_and_cache_props


def _event() -> dict[str, object]:
    return {
        "eventID": "NBA_LAL_BOS_2026",
        "leagueID": "NBA",
        "status": {
            "startsAt": "2026-07-28T00:00:00Z",
            "started": False,
            "ended": False,
            "finalized": False,
        },
        "teams": {
            "home": {"name": "Boston Celtics"},
            "away": {"name": "Los Angeles Lakers"},
        },
        "players": {
            "LEBRON_JAMES_1_NBA": {
                "playerID": "LEBRON_JAMES_1_NBA",
                "name": "LeBron James",
            }
        },
        "odds": {
            "points-LEBRON_JAMES_1_NBA-game-ou-over": {
                "statID": "points",
                "statEntityID": "LEBRON_JAMES_1_NBA",
                "playerID": "LEBRON_JAMES_1_NBA",
                "periodID": "game",
                "betTypeID": "ou",
                "sideID": "over",
                "bookOverUnder": "24.5",
                "byBookmaker": {
                    "draftkings": {
                        "odds": "-110",
                        "overUnder": "24.5",
                        "available": True,
                    },
                    "fanduel": {
                        "odds": "-105",
                        "overUnder": "24.5",
                        "available": True,
                    },
                },
            },
            "points-LEBRON_JAMES_1_NBA-game-ou-under": {
                "statID": "points",
                "statEntityID": "LEBRON_JAMES_1_NBA",
                "playerID": "LEBRON_JAMES_1_NBA",
                "periodID": "game",
                "betTypeID": "ou",
                "sideID": "under",
                "bookOverUnder": "24.5",
                "byBookmaker": {
                    "draftkings": {
                        "odds": "-110",
                        "overUnder": "24.5",
                        "available": True,
                    },
                    "fanduel": {
                        "odds": "-115",
                        "overUnder": "24.5",
                        "available": True,
                    },
                },
            },
        },
    }


def test_normalizes_player_props_into_existing_ingestion_shape() -> None:
    event, payload = sportsgameodds.normalize_event(
        _event(),
        sport_key="basketball_nba",
    )
    assert event["id"] == "sgo:NBA_LAL_BOS_2026"
    assert event["home_team"] == "Boston Celtics"
    assert event["away_team"] == "Los Angeles Lakers"
    assert len(payload["bookmakers"]) == 2
    draftkings = next(
        book for book in payload["bookmakers"] if book["key"] == "draftkings"
    )
    market = draftkings["markets"][0]
    assert market["key"] == "player_points"
    assert {row["name"] for row in market["outcomes"]} == {"Over", "Under"}
    assert all(row["description"] == "LeBron James" for row in market["outcomes"])


def test_normalized_payload_runs_through_real_prop_processor(tmp_path: Path) -> None:
    cache = PropCache(tmp_path / "props.db")
    event, payload = sportsgameodds.normalize_event(
        _event(),
        sport_key="basketball_nba",
    )
    inserted = process_and_cache_props(
        cache=cache,
        sport_key="basketball_nba",
        event=event,
        odds_payload=payload,
    )
    rows = cache.load_props()
    assert inserted == 2
    assert len(rows) == 2
    assert {row["bookmaker"] for row in rows} == {"DRAFTKINGS", "FANDUEL"}
    assert all(row["over_odds"] is not None for row in rows)
    assert all(row["under_odds"] is not None for row in rows)


def test_pagination_passes_opaque_cursor(monkeypatch) -> None:
    calls: list[dict[str, object]] = []

    def fake_get(_path: str, params: dict[str, object]):
        calls.append(params)
        if len(calls) == 1:
            return {"success": True, "data": [{"eventID": "one"}], "nextCursor": "opaque"}
        return {"success": True, "data": [{"eventID": "two"}]}

    monkeypatch.setattr(sportsgameodds, "_get", fake_get)
    events = sportsgameodds.fetch_upcoming_events("NBA", max_pages=3)
    assert [event["eventID"] for event in events] == ["one", "two"]
    assert calls[1]["cursor"] == "opaque"


def test_primary_pruning_preserves_supplemental_namespace(tmp_path: Path) -> None:
    cache = PropCache(tmp_path / "props.db")
    cache.replace_games(
        "basketball_nba",
        [
            {"id": "primary", "home_team": "A", "away_team": "B"},
            {"id": "sgo:backup", "home_team": "A", "away_team": "B"},
        ],
    )
    cache.prune_sport_to_event_ids(
        sport="basketball_nba",
        active_event_ids=["primary"],
    )
    with cache.connect() as connection:
        ids = {row["id"] for row in connection.execute("select id from games")}
    assert ids == {"primary", "sgo:backup"}
