from services.live_stats_service import (
    SPORT_CONFIG,
    _espn_snapshot_from_logs,
    _golf_round_value,
    extract_prop_value,
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
    assert snapshot.source == "espn"


def test_espn_completed_boxscore_grades_combination_and_double_double() -> None:
    logs = [{
        "PLAYER_NAME": "Aliyah Boston",
        "GAME_ID": "401857107",
        "MATCHUP": "Indiana Fever at Minnesota Lynx",
        "PTS": 15,
        "REB": 11,
        "AST": 4,
        "STL": 1,
        "BLK": 2,
    }]
    points_rebounds = _espn_snapshot_from_logs(
        logs=logs,
        player_name="Aliyah Boston",
        prop_type="Player Points Rebounds",
        event_id="401857107",
    )
    double_double = _espn_snapshot_from_logs(
        logs=logs,
        player_name="Aliyah Boston",
        prop_type="Player Double Double",
        event_id="401857107",
    )

    assert points_rebounds.value == 26
    assert double_double.value == 1
    assert double_double.completed is True


def test_espn_in_progress_boxscore_updates_combo_market() -> None:
    snapshot = _espn_snapshot_from_logs(
        logs=[{
            "PLAYER_NAME": "Ariel Atkins",
            "GAME_ID": "live-game",
            "MATCHUP": "Golden State Valkyries at Los Angeles Sparks",
            "PTS": 8,
            "REB": 4,
            "AST": 2,
            "GAME_STATUS": "Live",
            "GAME_COMPLETED": False,
        }],
        player_name="Ariel Atkins",
        prop_type="Player Points Rebounds",
        event_id="live-game",
    )

    assert snapshot.value == 12
    assert snapshot.completed is False
    assert snapshot.status == "Live"


def test_live_boxscore_extracts_prefixed_basketball_markets() -> None:
    row = {"Points": 10, "Rebounds": 5, "Assists": 3}

    assert extract_prop_value(row, "Player Points") == 10
    assert extract_prop_value(row, "Player Points Rebounds") == 15
    assert extract_prop_value(row, "Player Points Assists") == 13
    assert extract_prop_value(row, "Player Rebounds Assists") == 8
    assert extract_prop_value(row, "Player Points Rebounds Assists") == 18
    assert extract_prop_value(row, "PTS+REBS+ASTS") == 18


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
