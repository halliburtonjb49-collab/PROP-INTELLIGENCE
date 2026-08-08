from types import SimpleNamespace

from services.prop_context_service import _is_unprojectable_market


def _prop(sport="WNBA", market_key="player_fantasy_points", market="Fantasy Score"):
    return SimpleNamespace(
        sport=sport, marketKey=market_key, market=market, category="",
    )


def test_a_fantasy_prop_has_no_projectable_formula() -> None:
    """The defect behind the board disagreeing with PrizePicks.

    Angel Reese was shown as POINTS 36.5 while her actual points line was 15;
    36.5 was her fantasy score. The engine projected 21.9 -- a points-like
    number -- against that fantasy line, which returns Under every time.
    """

    assert _is_unprojectable_market(_prop()) is True


def test_it_holds_however_the_market_is_spelled() -> None:
    assert _is_unprojectable_market(_prop(market_key="fantasy points")) is True
    assert _is_unprojectable_market(_prop(market_key="", market="FANTASY SCORE")) is True
    assert _is_unprojectable_market(_prop(market_key="player_fantasy_score")) is True


def test_an_ordinary_points_prop_is_untouched() -> None:
    # The engine projects points perfectly well; only the fantasy combination
    # is beyond it.
    assert _is_unprojectable_market(
        _prop(market_key="player_points", market="Points")
    ) is False


def test_other_basketball_markets_are_untouched() -> None:
    for market in ("player_rebounds", "player_assists", "player_threes"):
        assert _is_unprojectable_market(_prop(market_key=market, market="")) is False


def test_a_sport_with_a_real_fantasy_formula_is_not_caught() -> None:
    # AFL posts its own fantasy market and is not part of this defect.
    assert _is_unprojectable_market(
        _prop(sport="AFL", market_key="player_afl_fantasy_points_over")
    ) is False
