from services.prediction_automation_service import _market_value


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
