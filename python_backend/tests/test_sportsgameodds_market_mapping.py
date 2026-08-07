from providers.sportsgameodds import _market_key
from services.market_config import SPORT_MARKETS


def key(stat, sport_key, market_name="Player Over/Under"):
    return _market_key(
        stat_id=stat, sport_key=sport_key, bet_type="ou", market_name=market_name
    )


def test_baseball_has_no_points():
    """The defect that reached the board.

    One shared table mapped stat names to markets regardless of sport, so a
    `points` stat on a baseball event produced 242 cards describing a market
    baseball does not have.
    """

    assert key("points", "baseball_mlb") is None
    assert key("rebounds", "baseball_mlb") is None
    assert key("points", "basketball_nba") == "player_points"


def test_a_stat_means_different_things_in_different_sports():
    # `shots` is a shot on goal in hockey and a shot on target in soccer; one
    # shared table can only hold one of them.
    assert key("shots", "icehockey_nhl") == "player_shots_on_goal"
    assert key("shots", "soccer_epl") == "player_shots"


def test_a_real_market_is_mapped_rather_than_dropped():
    # Rejecting the mismatch is not enough on its own: hockey shots and
    # goalkeeper saves are markets people want, and dropping them to avoid a
    # wrong label loses the prop entirely.
    assert key("saves", "icehockey_nhl") == "player_total_saves"
    assert key("saves", "soccer_epl") == "player_goalkeeper_saves"
    assert key("goals", "aussierules_afl") == "player_goals_scored_over"


def test_every_soccer_league_shares_one_mapping():
    for league in (
        "soccer_epl",
        "soccer_italy_serie_a",
        "soccer_spain_la_liga",
        "soccer_usa_mls",
    ):
        assert key("saves", league) == "player_goalkeeper_saves", league


def test_no_mapping_can_produce_a_market_its_sport_lacks():
    """The invariant, checked across every sport and stat at once."""

    from providers.sportsgameodds import _STAT_MARKETS

    for sport_key, markets in SPORT_MARKETS.items():
        known = set(markets)
        for stat in _STAT_MARKETS:
            mapped = key(stat, sport_key)
            if mapped is not None:
                assert mapped in known, f"{sport_key} {stat} -> {mapped}"


def test_an_unconfigured_sport_is_left_alone():
    # A sport with no market list must not be rejected for being new.
    assert key("points", "brand_new_league") == "player_points"
