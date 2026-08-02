from services.live_stats_service import (
    SPORT_CONFIG,
    _espn_snapshot_from_logs,
    _golf_round_value,
    find_player_match_in_boxscores,
)


def test_espn_completed_boxscore_grades_wnba_pra_by_matchup() -> None:
    snapshot = _espn_snapshot_from_logs(
        logs=[{
            "PLAYER_NAME": "Aliyah Boston",
            "GAME_ID": "401857107",
            "MATCHUP": "Indiana Fever at Minnesota Lynx",
            "PTS": 18,
            "REB": 9,
            "AST": 4,
        }],
        player_name="Aliyah Boston",
        prop_type="points rebounds assists",
        event_id="different-provider-id",
        matchup="Indiana Fever @ Minnesota Lynx",
    )

    assert snapshot.value == 31
    assert snapshot.completed is True
    assert snapshot.status == "Final"


def test_nfl_live_boxscores_are_configured() -> None:
    assert SPORT_CONFIG["NFL"]["live_boxscores_path"] == "/BoxScores/{date}"


def test_golf_round_markets_derive_from_holes() -> None:
    round_row = {
        "Holes": [
            {"Par": 4, "Score": 3},
            {"Par": 4, "Score": 4},
            {"Par": 3, "Score": 4},
        ]
    }
    assert _golf_round_value(round_row, "birdies") == 1
    assert _golf_round_value(round_row, "pars") == 1
    assert _golf_round_value(round_row, "bogeys") == 1
    assert _golf_round_value(round_row, "round score") == 11


def test_boxscore_player_is_scoped_to_matchup() -> None:
    games = [
        {
            "Game": {"AwayTeam": "NY", "HomeTeam": "LA"},
            "PlayerGames": [{"Name": "Alex Smith", "Team": "NY", "Points": 10}],
        },
        {
            "Game": {"AwayTeam": "CHI", "HomeTeam": "DAL"},
            "PlayerGames": [{"Name": "Alex Smith", "Team": "CHI", "Points": 20}],
        },
    ]
    match = find_player_match_in_boxscores(
        boxscores=games,
        player_name="Alex Smith",
        matchup="CHI @ DAL",
    )
    assert match is not None
    assert match[0]["Points"] == 20


def test_ambiguous_player_without_event_context_stays_unresolved() -> None:
    games = [
        {"PlayerGames": [{"Name": "Alex Smith", "Points": 10}]},
        {"PlayerGames": [{"Name": "Alex Smith", "Points": 20}]},
    ]
    assert find_player_match_in_boxscores(
        boxscores=games,
        player_name="Alex Smith",
    ) is None
