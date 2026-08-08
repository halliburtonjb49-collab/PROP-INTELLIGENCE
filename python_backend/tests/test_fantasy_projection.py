from services.baseline_projection_service import basketball_market_value


def _row(points, rebounds, assists, steals, blocks, turnovers, threes=0.0):
    return (points, rebounds, assists, steals, blocks, turnovers, threes)


def test_a_fantasy_market_is_not_valued_as_raw_scoring() -> None:
    """The defect behind the board disagreeing with PrizePicks.

    "player fantasy points" contains "point", so every shorter test below it
    matched and the market was valued at raw scoring. A player averaging 14
    points was projected at 14 against a fantasy line near 37, which returns
    Under every time -- the systematic Under bias seen across the board.
    """

    row = _row(14, 12.6, 3.7, 1.0, 0.6, 2.5)

    assert basketball_market_value("player_fantasy_points", row) != 14.0
    assert basketball_market_value("player_points", row) == 14.0


def test_it_reproduces_a_real_posted_line() -> None:
    # Angel Reese's component averages against the 36.5 fantasy line
    # PrizePicks actually posted, with a last-five average of 38.9.
    value = basketball_market_value("player_fantasy_points", _row(14, 12.6, 3.7, 1.0, 0.6, 2.5))

    assert 35.0 < value < 39.0


def test_every_component_moves_the_score() -> None:
    base = _row(10, 10, 10, 1, 1, 1)
    for index, weight in ((0, 1.0), (1, 1.2), (2, 1.5), (3, 2.0), (4, 2.0)):
        bumped = list(base)
        bumped[index] += 1
        gain = (
            basketball_market_value("player_fantasy_points", tuple(bumped))
            - basketball_market_value("player_fantasy_points", base)
        )
        assert abs(gain - weight) < 1e-9, index


def test_a_turnover_costs_rather_than_earns() -> None:
    clean = _row(20, 5, 5, 1, 1, 0)
    loose = _row(20, 5, 5, 1, 1, 4)

    assert basketball_market_value("player_fantasy_points", loose) < (
        basketball_market_value("player_fantasy_points", clean)
    )


def test_the_ordinary_markets_are_untouched() -> None:
    row = _row(20, 10, 5, 2, 1, 3, 4)

    assert basketball_market_value("player_points", row) == 20
    assert basketball_market_value("player_rebounds", row) == 10
    assert basketball_market_value("player_assists", row) == 5
    assert basketball_market_value("player_points_rebounds_assists", row) == 35
    assert basketball_market_value("player_threes", row) == 4
