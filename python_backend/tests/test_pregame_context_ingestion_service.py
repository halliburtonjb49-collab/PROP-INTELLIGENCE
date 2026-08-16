from datetime import date
import services.pregame_context_ingestion_service as ingestion

from services.pregame_context_ingestion_service import (
    _current_injury_matches,
    _event_scoped_lineups,
    _inside_starter_window,
    _inside_mlb_lineup_window,
    normalize_official_mlb_boxscore,
    normalize_official_mlb_schedule,
    normalize_espn_injuries,
    normalize_sportsdataio_mlb_lineups,
    normalize_sportradar_wnba_injuries,
    normalize_sportradar_wnba_starters,
)
from datetime import datetime, timezone


def test_normalizes_projected_and_confirmed_mlb_lineups() -> None:
    rows = normalize_sportsdataio_mlb_lineups([{
        "GameID": 99, "DateTime": "2026-08-02T19:00:00Z",
        "HomeTeam": "CHC", "AwayTeam": "CIN", "Confirmed": True,
        "HomeLineup": [{"PlayerID": 1, "Name": "Home Batter", "BattingOrder": 1,
                         "Position": "CF", "Starting": True, "BatHand": "L"}],
        "AwayLineup": [{"PlayerID": 2, "Name": "Away Batter", "BattingOrder": 2,
                         "Position": "SS", "Starting": True}],
    }])
    assert len(rows) == 2
    assert rows[0]["confirmed"] is True
    assert rows[0]["status"] == "CONFIRMED_STARTER"
    assert rows[0]["provider_player_id"] == "1"
    assert rows[0]["payload"]["battingOrder"] == 1
    assert rows[0]["payload"]["bats"] == "L"
    assert rows[0]["opponent"] == "CIN"


def test_normalizes_flat_mlb_projection_response() -> None:
    rows = normalize_sportsdataio_mlb_lineups([{
        "GameID": 101, "PlayerID": 3, "Name": "Projected Batter",
        "Team": "SEA", "Opponent": "TEX", "BattingOrder": 4,
        "BattingOrderConfirmed": False,
    }])
    assert rows[0]["status"] == "PROJECTED_STARTER"
    assert rows[0]["confirmed"] is False


def test_normalizes_nested_sportradar_injury_response() -> None:
    rows = normalize_sportradar_wnba_injuries({"teams": [{
        "alias": "IND", "players": [{"id": "p1", "full_name": "Test Player",
        "injuries": [{"status": "Questionable", "desc": "Ankle"}]}],
    }]}, date(2026, 8, 2))
    assert len(rows) == 1
    assert rows[0]["team"] == "IND"
    assert rows[0]["status"] == "QUESTIONABLE"


def test_normalizes_espn_injury_report_and_freshness_marker() -> None:
    rows = normalize_espn_injuries({
        "timestamp": "2026-08-03T12:00:00Z",
        "injuries": [{
            "displayName": "Indiana Fever",
            "injuries": [{
                "status": "Day-To-Day",
                "date": "2026-08-03T11:00:00Z",
                "shortComment": "Player is being evaluated.",
                "athlete": {
                    "id": "1", "displayName": "Test Player",
                    "team": {"abbreviation": "IND"},
                },
                "details": {"type": "Ankle", "side": "Left"},
            }],
        }],
    }, sport="WNBA", observed_day=date(2026, 8, 3))
    assert rows[0]["entity_type"] == "INJURY_FEED"
    assert rows[0]["status"] == "REPORT_CURRENT"
    assert rows[1]["player_name"] == "Test Player"
    assert rows[1]["team"] == "IND"
    assert rows[1]["status"] == "DAY-TO-DAY"
    assert rows[1]["payload"]["injuryType"] == "Ankle"


def test_only_latest_espn_report_can_keep_an_injury_active() -> None:
    matches = [
        {
            "provider": "ESPN",
            "entityType": "INJURY",
            "eventId": "2026-08-10",
        },
        {
            "provider": "ESPN",
            "entityType": "INJURY",
            "eventId": "2026-08-11",
        },
        {
            "provider": "SPORTRADAR",
            "entityType": "INJURY",
            "eventId": "game-1",
        },
    ]
    current = _current_injury_matches(matches, "2026-08-11")
    assert [item["eventId"] for item in current] == [
        "2026-08-11",
        "game-1",
    ]

def test_normalizes_confirmed_wnba_starters() -> None:
    rows = normalize_sportradar_wnba_starters({
        "home": {"alias": "IND", "players": [
            {"id": "p1", "full_name": "Starter One", "starter": True},
            {"id": "p2", "full_name": "Bench One", "starter": False},
        ]},
        "away": {"alias": "MIN", "players": [
            {"id": "p3", "full_name": "Starter Two", "starter": True},
        ]},
    }, "game-1", "2026-08-02T17:00:00Z")
    assert {row["player_name"] for row in rows} == {"Starter One", "Starter Two"}
    assert all(row["confirmed"] for row in rows)


def test_starter_summary_calls_are_limited_to_pregame_window() -> None:
    now = datetime(2026, 8, 2, 12, tzinfo=timezone.utc)
    assert _inside_starter_window("2026-08-02T13:30:00Z", now)
    assert not _inside_starter_window("2026-08-02T18:00:00Z", now)
    assert _inside_mlb_lineup_window("2026-08-02T17:00:00Z", now)


def test_official_mlb_schedule_normalizes_probable_pitcher() -> None:
    rows = normalize_official_mlb_schedule({"dates": [{"games": [{
        "gamePk": 77, "gameDate": "2026-08-02T19:00:00Z", "teams": {
            "home": {"team": {"name": "Cubs"},
                     "probablePitcher": {"id": 1, "fullName": "Home Pitcher", "pitchHand": {"code": "L"}}},
            "away": {"team": {"name": "Reds"},
                     "probablePitcher": {"id": 2, "fullName": "Away Pitcher"}},
        },
    }]}]})
    assert len(rows) == 2
    assert rows[0]["status"] == "PROJECTED_STARTER"
    assert rows[0]["payload"]["role"] == "PROBABLE_PITCHER"
    assert rows[0]["payload"]["throws"] == "L"


def test_official_mlb_boxscore_marks_submitted_batting_order_confirmed() -> None:
    rows = normalize_official_mlb_boxscore({"teams": {
        "home": {"team": {"name": "Cubs"}, "players": {"ID1": {
            "person": {"id": 1, "fullName": "Leadoff Batter"},
            "battingOrder": "100", "position": {"abbreviation": "CF"},
            "batSide": {"code": "R"},
        }}},
        "away": {"team": {"name": "Reds"}, "players": {}},
    }}, event_id="77", event_time="2026-08-02T19:00:00Z")
    assert rows[0]["confirmed"] is True
    assert rows[0]["payload"]["battingOrder"] == 1
    assert rows[0]["payload"]["bats"] == "R"


def test_latest_context_lookup_index_is_registered_and_matches_query_order() -> None:
    from pathlib import Path

    from scripts.apply_supabase_migrations import MIGRATIONS

    filename = "supabase_pregame_context_lookup_index.sql"
    sql = (Path(__file__).resolve().parents[2] / filename).read_text(
        encoding="utf-8"
    ).lower()

    assert filename in MIGRATIONS
    sport_filename = "supabase_pregame_context_sport_lookup_index.sql"
    sport_sql = (
        Path(__file__).resolve().parents[2] / sport_filename
    ).read_text(encoding="utf-8")
    assert sport_filename in MIGRATIONS
    assert "sport," in sport_sql.lower()
    assert "provider," in sport_sql.lower()
    assert "entity_type," in sport_sql.lower()
    assert "pregame_context_latest_lookup_idx" in sql
    assert (
        "provider,\n    entity_type,\n    event_id,\n"
        "    lower(player_name),\n    observed_at desc"
    ) in sql


def test_reconfirmed_lineup_refreshes_observation_timestamp(monkeypatch) -> None:
    captured: dict[str, object] = {}

    class Cursor:
        rowcount = 1

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def executemany(self, statement, rows):
            captured["statement"] = statement
            captured["rows"] = rows

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def cursor(self):
            return Cursor()

        def commit(self):
            captured["committed"] = True

    class Pool:
        def connection(self):
            return Connection()

    monkeypatch.setattr(ingestion, "database_is_configured", lambda: True)
    monkeypatch.setattr(ingestion, "get_database_pool", lambda: Pool())

    persisted = ingestion.persist_pregame_observations(
        "MLB_STATS_API",
        [{
            "sport": "MLB",
            "event_id": "77",
            "entity_type": "LINEUP",
            "provider_player_id": "1",
            "player_name": "Fresh Batter",
            "team": "CHC",
            "opponent": "CIN",
            "event_time": "2026-08-15T19:00:00Z",
            "status": "CONFIRMED_STARTER",
            "confirmed": True,
            "payload": {"battingOrder": 1},
        }],
    )

    assert persisted == 1
    assert captured["committed"] is True
    statement = str(captured["statement"]).lower()
    assert "on conflict(provider,fingerprint) do update" in statement
    assert "observed_at=now()" in statement

def test_lineup_context_prefers_the_prop_event_over_older_confirmation() -> None:
    class Prop:
        eventId = "today"
        startTimeUtc = "2026-08-15T19:00:00Z"

    rows = [
        {
            "entityType": "LINEUP",
            "eventId": "yesterday",
            "eventTime": "2026-08-14T19:00:00Z",
            "confirmed": True,
        },
        {
            "entityType": "LINEUP",
            "eventId": "today",
            "eventTime": "2026-08-15T19:00:00Z",
            "confirmed": False,
        },
    ]

    scoped = _event_scoped_lineups(Prop(), rows)

    assert [row["eventId"] for row in scoped] == ["today"]