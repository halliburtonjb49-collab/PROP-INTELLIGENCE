from services.live_stats_service import (
    _golf_round_value,
    find_player_match_in_boxscores,
)


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
