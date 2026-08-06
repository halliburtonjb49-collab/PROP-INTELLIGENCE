from datetime import date

import pytest

from providers.espn_box_score_statistics import (
    LEAGUES,
    NFL_SECTIONS,
    _minutes_from_clock,
    extract_section_stats,
    parse_event_summary,
)
from services.historical_ingestion_service import normalize_espn_box_score_logs


def _nfl_summary() -> dict:
    return {
        "boxscore": {
            "players": [
                {
                    "team": {"id": "12"},
                    "statistics": [
                        {
                            "name": "passing",
                            "keys": [
                                "completions/passingAttempts",
                                "passingYards",
                                "passingTouchdowns",
                                "interceptions",
                            ],
                            "athletes": [
                                {
                                    "athlete": {"id": "1", "displayName": "QB One"},
                                    "stats": ["23/35", "268", "2", "1"],
                                }
                            ],
                        },
                        {
                            "name": "rushing",
                            "keys": [
                                "rushingAttempts",
                                "rushingYards",
                                "rushingTouchdowns",
                            ],
                            "athletes": [
                                {
                                    "athlete": {"id": "1", "displayName": "QB One"},
                                    "stats": ["4", "22", "0"],
                                },
                                {
                                    "athlete": {"id": "2", "displayName": "RB Two"},
                                    "stats": ["18", "84", "1"],
                                },
                                {
                                    "athlete": {"id": "9", "displayName": "Scratch"},
                                    "didNotPlay": True,
                                    "stats": ["0", "0", "0"],
                                },
                            ],
                        },
                        {
                            "name": "receiving",
                            "keys": [
                                "receptions",
                                "receivingYards",
                                "receivingTouchdowns",
                                "receivingTargets",
                            ],
                            "athletes": [
                                {
                                    "athlete": {"id": "3", "displayName": "WR Three"},
                                    "stats": ["7", "96", "1", "11"],
                                }
                            ],
                        },
                    ],
                }
            ]
        }
    }


def _nhl_summary() -> dict:
    return {
        "boxscore": {
            "players": [
                {
                    "team": {"id": "5"},
                    "statistics": [
                        {
                            "name": "forwards",
                            "keys": [
                                "goals", "assists", "points", "shotsTotal",
                                "timeOnIce", "powerPlayTimeOnIce",
                            ],
                            "athletes": [
                                {
                                    "athlete": {"id": "21", "displayName": "Winger"},
                                    "stats": ["1", "2", "3", "5", "18:24", "3:30"],
                                }
                            ],
                        },
                        {
                            "name": "goalies",
                            "keys": [
                                "saves", "shotsAgainst", "goalsAgainst", "timeOnIce",
                            ],
                            "athletes": [
                                {
                                    "athlete": {"id": "30", "displayName": "Netminder"},
                                    "stats": ["29", "31", "2", "60:00"],
                                }
                            ],
                        },
                    ],
                }
            ]
        }
    }


def test_both_leagues_are_configured() -> None:
    assert set(LEAGUES) == {"NFL", "NHL"}
    assert LEAGUES["NFL"].path == "football/nfl"
    assert LEAGUES["NHL"].path == "hockey/nhl"


def test_ice_time_parses_to_decimal_minutes() -> None:
    assert _minutes_from_clock("18:24") == pytest.approx(18.4, abs=1e-3)
    assert _minutes_from_clock("60:00") == 60.0
    assert _minutes_from_clock("") is None


def test_completion_pairs_split_into_completions_and_attempts() -> None:
    section = _nfl_summary()["boxscore"]["players"][0]["statistics"][0]
    stats = extract_section_stats(section, NFL_SECTIONS["passing"])

    assert stats["1"]["completions"] == 23
    assert stats["1"]["pass_attempts"] == 35
    assert stats["1"]["passing_yards"] == 268


def test_players_who_did_not_play_are_omitted_not_zeroed() -> None:
    section = _nfl_summary()["boxscore"]["players"][0]["statistics"][1]
    stats = extract_section_stats(section, NFL_SECTIONS["rushing"])

    # A scratch is missing data; recording zeros would drag every rate down.
    assert "9" not in stats
    assert set(stats) == {"1", "2"}


def test_a_quarterback_who_passes_and_runs_yields_one_merged_row() -> None:
    rows = parse_event_summary(_nfl_summary(), sport="NFL")
    by_id = {row["player_id"]: row for row in rows}

    assert set(by_id) == {"1", "2", "3"}
    quarterback = by_id["1"]["stats"]
    assert quarterback["pass_attempts"] == 35
    assert quarterback["carries"] == 4
    assert quarterback["rushing_yards"] == 22


def test_receiving_targets_are_captured_for_the_opportunity_model() -> None:
    rows = parse_event_summary(_nfl_summary(), sport="NFL")
    receiver = next(row for row in rows if row["player_id"] == "3")

    assert receiver["stats"]["targets"] == 11
    assert receiver["stats"]["receptions"] == 7
    assert receiver["stats"]["receiving_yards"] == 96


def test_skaters_and_goalies_are_both_parsed() -> None:
    rows = parse_event_summary(_nhl_summary(), sport="NHL")
    by_id = {row["player_id"]: row["stats"] for row in rows}

    assert by_id["21"]["shots_on_goal"] == 5
    assert by_id["21"]["time_on_ice"] == pytest.approx(18.4, abs=1e-3)
    assert by_id["21"]["power_play_time_on_ice"] == pytest.approx(3.5, abs=1e-3)
    assert by_id["30"]["saves"] == 29
    assert by_id["30"]["shots_against"] == 31


def test_defencemen_share_the_skater_mapping() -> None:
    summary = _nhl_summary()
    summary["boxscore"]["players"][0]["statistics"][0]["name"] = "defenses"
    rows = parse_event_summary(summary, sport="NHL")
    assert any(row["stats"].get("shots_on_goal") == 5 for row in rows)


def test_unknown_sport_parses_to_nothing() -> None:
    assert parse_event_summary(_nfl_summary(), sport="CRICKET") == []


def test_normalizer_produces_storable_game_logs() -> None:
    rows = parse_event_summary(_nfl_summary(), sport="NFL")
    for row in rows:
        row.update({
            "sport": "NFL", "event_id": "401", "game_date": "2026-09-13",
            "source": "ESPN",
        })

    logs = normalize_espn_box_score_logs(rows)

    assert len(logs) == 3
    first = logs[0]
    assert first["sport"] == "NFL"
    assert first["game_date"] == date(2026, 9, 13)
    assert isinstance(first["stats"], dict)
    # Ids are stable, so re-ingesting a game updates rather than duplicates.
    assert normalize_espn_box_score_logs(rows)[0]["id"] == first["id"]


def test_normalizer_rejects_rows_missing_identity_or_stats() -> None:
    assert normalize_espn_box_score_logs([
        {
            "sport": "NFL", "event_id": "", "player_id": "1",
            "player_name": "X", "stats": {"targets": 3},
            "game_date": "2026-09-13",
        },
        {
            "sport": "NFL", "event_id": "401", "player_id": "1",
            "player_name": "X", "stats": {}, "game_date": "2026-09-13",
        },
    ]) == []
