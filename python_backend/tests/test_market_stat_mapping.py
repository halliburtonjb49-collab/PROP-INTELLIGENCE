from services.baseline_projection_service import _gridiron_ice_stat
from services.market_config import SPORT_MARKETS


def test_the_big_nfl_markets_are_projectable() -> None:
    """The defect: the table held written-out phrases, the feed sends
    abbreviations, so fifteen of nineteen NFL markets matched nothing and
    every one went unprojected. It looked like missing history."""

    assert _gridiron_ice_stat("NFL", "player_pass_yds") == "passing_yards"
    assert _gridiron_ice_stat("NFL", "player_rush_yds") == "rushing_yards"
    assert _gridiron_ice_stat("NFL", "player_reception_yds") == "receiving_yards"
    assert _gridiron_ice_stat("NFL", "player_pass_tds") == "passing_touchdowns"
    assert _gridiron_ice_stat("NFL", "player_rush_tds") == "rushing_touchdowns"
    assert _gridiron_ice_stat("NFL", "player_reception_tds") == "receiving_touchdowns"
    assert _gridiron_ice_stat("NFL", "player_rush_attempts") == "carries"


def test_the_written_out_spellings_still_work() -> None:
    # Other providers send readable labels; both must resolve.
    assert _gridiron_ice_stat("NFL", "Passing Yards") == "passing_yards"
    assert _gridiron_ice_stat("NFL", "Rushing Yards") == "rushing_yards"


def test_a_composite_is_not_projected_from_one_half_of_itself() -> None:
    """rush+reception yards is a sum the box score does not store.

    Matching it on "rush yds" would project one half of the bet against a
    line covering both, which is a guaranteed Under.
    """

    assert _gridiron_ice_stat("NFL", "player_rush_reception_yds") is None
    assert _gridiron_ice_stat("NFL", "player_pass_rush_yds") is None


def test_power_play_points_is_not_total_points() -> None:
    # A subset of points, not points. Matching the shorter phrase projected a
    # player's whole scoring rate against a power-play-only line.
    assert _gridiron_ice_stat("NHL", "player_power_play_points") is None
    assert _gridiron_ice_stat("NHL", "player_points") == "points"


def test_stats_nobody_ingests_stay_unprojected() -> None:
    for market in (
        "player_sacks", "player_solo_tackles", "player_tackles_assists",
        "player_anytime_td", "player_rush_longest", "player_reception_longest",
    ):
        assert _gridiron_ice_stat("NFL", market) is None, market


def test_no_nhl_market_borrows_another_market_stat() -> None:
    # Collision detection, the general form: two markets resolving to one
    # stat means one of them is being projected as something it is not.
    seen: dict[str, str] = {}
    collisions = []
    for market in sorted(SPORT_MARKETS["icehockey_nhl"]):
        stat = _gridiron_ice_stat("NHL", market)
        if stat is None:
            continue
        if stat in seen:
            collisions.append(f"{stat} <- {seen[stat]}, {market}")
        seen[stat] = market

    assert collisions == []


def test_no_nfl_market_borrows_another_market_stat() -> None:
    seen: dict[str, str] = {}
    collisions = []
    for market in sorted(SPORT_MARKETS["americanfootball_nfl"]):
        stat = _gridiron_ice_stat("NFL", market)
        if stat is None:
            continue
        if stat in seen:
            collisions.append(f"{stat} <- {seen[stat]}, {market}")
        seen[stat] = market

    assert collisions == []
