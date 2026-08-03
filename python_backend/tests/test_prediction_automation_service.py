from services.prediction_automation_service import _market_value, _specialty_market_value


def test_market_value_maps_standard_and_combo_markets() -> None:
    row = (25, 10, 8, 2, 1, 4, 3)
    assert _market_value("player_points", row) == 25
    assert _market_value("player_assists", row) == 8
    assert _market_value("points_rebounds_assists", row) == 43
    assert _market_value("three_pointers_made", row) == 3


def test_market_value_maps_each_side_to_the_same_observed_stat() -> None:
    row = (19, 7, 5, 3, 2, 4, 1)
    assert _market_value("Player Points", row) == 19
    assert _market_value("Player Points Rebounds", row) == 26
    assert _market_value("Player Blocks Steals", row) == 5
    assert _market_value("Player Fantasy Points", row) is None


def test_specialty_market_value_maps_exact_sport_statistics() -> None:
    assert _specialty_market_value("TENNIS", "Player Aces", {"aces": 9}) == 9
    assert _specialty_market_value(
        "TENNIS", "Player Double Faults", {"double_faults": 3, "faults": 99},
    ) == 3
    assert _specialty_market_value("PGA", "Player Birdies", {"birdies": 5}) == 5
    assert _specialty_market_value(
        "UFC", "Fighter Significant Strikes", {"significant_strikes": 42},
    ) == 42
    assert _specialty_market_value(
        "SOCCER", "Player Shots on Target", {"shots_on_target": 2},
    ) == 2


def test_specialty_market_value_does_not_guess_unknown_markets() -> None:
    assert _specialty_market_value("TENNIS", "Fantasy Score", {"games_won": 12}) is None
