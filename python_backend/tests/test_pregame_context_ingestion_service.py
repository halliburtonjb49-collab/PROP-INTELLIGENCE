from datetime import date

from services.pregame_context_ingestion_service import (
    _inside_starter_window,
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
                         "Position": "CF", "Starting": True}],
        "AwayLineup": [{"PlayerID": 2, "Name": "Away Batter", "BattingOrder": 2,
                         "Position": "SS", "Starting": True}],
    }])
    assert len(rows) == 2
    assert rows[0]["confirmed"] is True
    assert rows[0]["status"] == "CONFIRMED_STARTER"
    assert rows[0]["payload"]["battingOrder"] == 1
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
