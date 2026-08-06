"""Fixtures below mirror live NHL API responses field for field."""

import pytest

from providers.nhl_official_statistics import (
    COMPLETED_GAME_STATES,
    parse_boxscore,
    parse_goalie,
    parse_schedule,
    parse_skater,
)


def _boxscore() -> dict:
    return {
        "awayTeam": {"id": 23},
        "homeTeam": {"id": 21},
        "playerByGameStats": {
            "awayTeam": {
                "forwards": [
                    {
                        "playerId": 8478444,
                        "name": {"default": "B. Boeser"},
                        "position": "R",
                        "goals": 3,
                        "assists": 1,
                        "points": 4,
                        "sog": 4,
                        "hits": 0,
                        "blockedShots": 0,
                        "powerPlayGoals": 0,
                        "pim": 0,
                        "shifts": 25,
                        "giveaways": 1,
                        "takeaways": 0,
                        "toi": "18:57",
                    }
                ],
                "defense": [
                    {
                        "playerId": 8480012,
                        "name": {"default": "Q. Hughes"},
                        "position": "D",
                        "goals": 0,
                        "assists": 2,
                        "points": 2,
                        "sog": 2,
                        "toi": "24:12",
                    }
                ],
                "goalies": [
                    {
                        "playerId": 8478406,
                        "name": {"default": "K. Lankinen"},
                        "position": "G",
                        "saves": 24,
                        "shotsAgainst": 30,
                        "goalsAgainst": 6,
                        "toi": "60:00",
                        "evenStrengthShotsAgainst": "20/26",
                        "powerPlayShotsAgainst": "3/3",
                        "shorthandedShotsAgainst": "1/1",
                        "starter": True,
                    }
                ],
            }
        },
    }


def test_completed_states_cover_both_final_labels() -> None:
    assert COMPLETED_GAME_STATES == {"OFF", "FINAL"}


def test_schedule_keeps_only_finished_games_and_carries_game_type() -> None:
    payload = {
        "gameWeek": [
            {
                "date": "2026-04-01",
                "games": [
                    {"id": 1, "gameState": "OFF", "gameDate": "2026-04-01", "gameType": 2},
                    {"id": 2, "gameState": "FUT", "gameDate": "2026-04-01", "gameType": 2},
                    {"id": 3, "gameState": "OFF", "gameDate": "2026-04-01", "gameType": 3},
                ],
            }
        ]
    }
    games = parse_schedule(payload)

    assert [game.game_id for game in games] == ["1", "3"]
    # Postseason is type 3 and is carried through rather than discarded.
    assert games[1].game_type == 3


def test_ice_time_becomes_decimal_minutes() -> None:
    assert parse_skater({"toi": "18:57"})["time_on_ice"] == pytest.approx(
        18.95, abs=1e-3
    )
    assert parse_skater({"toi": "24:12"})["time_on_ice"] == pytest.approx(
        24.2, abs=1e-3
    )


def test_goalie_strength_splits_are_parsed_from_saves_over_shots() -> None:
    stats = parse_goalie(_boxscore()["playerByGameStats"]["awayTeam"]["goalies"][0])

    assert stats["saves"] == 24
    assert stats["shots_against"] == 30
    # The shots-faced model varies on these, and no aggregate provides them.
    assert stats["even_strength_shots_against"] == 26
    assert stats["power_play_shots_against"] == 3
    assert stats["short_handed_shots_against"] == 1
    assert stats["even_strength_saves"] == 20


def test_strength_split_shots_reconcile_with_the_total() -> None:
    stats = parse_goalie(_boxscore()["playerByGameStats"]["awayTeam"]["goalies"][0])
    split_total = (
        stats["even_strength_shots_against"]
        + stats["power_play_shots_against"]
        + stats["short_handed_shots_against"]
    )
    assert split_total == stats["shots_against"]


def test_forwards_and_defencemen_are_both_ingested() -> None:
    rows = parse_boxscore(_boxscore(), game_id="2025021188", game_date="2026-04-01")
    names = {row["player_name"] for row in rows}

    assert names == {"B. Boeser", "Q. Hughes", "K. Lankinen"}
    defenceman = next(row for row in rows if row["player_name"] == "Q. Hughes")
    assert defenceman["stats"]["shots_on_goal"] == 2


def test_names_are_read_from_the_nested_default_field() -> None:
    # Names arrive as {"default": "..."}, not as a bare string.
    rows = parse_boxscore(_boxscore(), game_id="1", game_date="2026-04-01")
    assert all(row["player_name"] and "{" not in row["player_name"] for row in rows)


def test_rows_carry_the_identity_the_log_table_needs() -> None:
    rows = parse_boxscore(_boxscore(), game_id="2025021188", game_date="2026-04-01")
    first = rows[0]

    assert first["sport"] == "NHL"
    assert first["event_id"] == "2025021188"
    assert first["game_date"] == "2026-04-01"
    assert first["source"] == "NHL"
    assert first["team_id"] == "23"


def test_a_malformed_payload_yields_nothing_rather_than_raising() -> None:
    assert parse_boxscore({}, game_id="1", game_date="2026-04-01") == []
    assert parse_boxscore(
        {"playerByGameStats": {"awayTeam": {"forwards": ["junk"]}}},
        game_id="1",
        game_date="2026-04-01",
    ) == []
