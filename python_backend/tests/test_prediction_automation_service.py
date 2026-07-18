from services.prediction_automation_service import _market_value


def test_market_value_maps_standard_and_combo_markets() -> None:
    row = (25, 10, 8, 2, 1, 4, 3)
    assert _market_value("player_points", row) == 25
    assert _market_value("player_assists", row) == 8
    assert _market_value("points_rebounds_assists", row) == 43
    assert _market_value("three_pointers_made", row) == 3
