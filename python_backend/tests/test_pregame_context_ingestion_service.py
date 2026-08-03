from datetime import date

from services.pregame_context_ingestion_service import (
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
                     "probablePitcher": {"id": 1, "fullName": "Home Pitcher"}},
            "away": {"team": {"name": "Reds"},
                     "probablePitcher": {"id": 2, "fullName": "Away Pitcher"}},
        },
    }]}]})
    assert len(rows) == 2
    assert rows[0]["status"] == "PROJECTED_STARTER"
    assert rows[0]["payload"]["role"] == "PROBABLE_PITCHER"


def test_official_mlb_boxscore_marks_submitted_batting_order_confirmed() -> None:
    rows = normalize_official_mlb_boxscore({"teams": {
        "home": {"team": {"name": "Cubs"}, "players": {"ID1": {
            "person": {"id": 1, "fullName": "Leadoff Batter"},
            "battingOrder": "100", "position": {"abbreviation": "CF"},
        }}},
        "away": {"team": {"name": "Reds"}, "players": {}},
    }}, event_id="77", event_time="2026-08-02T19:00:00Z")
    assert rows[0]["confirmed"] is True
    assert rows[0]["payload"]["battingOrder"] == 1
