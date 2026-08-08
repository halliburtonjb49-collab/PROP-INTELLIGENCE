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


def test_hits_runs_rbis_is_not_projected_from_hits(monkeypatch) -> None:
    """The fourth instance of one defect.

    Runs and RBIs are not in the pitch log, so this market was stored as
    hits and projected as though hits were the whole bet. A batter averaging
    one hit was projected at one against a line near three -- not a low
    projection but a different market, returning Under at high confidence
    every time.
    """

    from services.baseline_projection_service import _INDEX

    monkeypatch.setattr(_INDEX, "ensure_loaded", lambda: None)
    # A batter with a full hits history and nothing else: if the market were
    # still read as hits, this would return a projection near one.
    monkeypatch.setattr(_INDEX, "mlb", {("batter:p1", "hits"): [1, 1, 1, 1, 1]})

    assert _INDEX.project(
        sport="MLB", player="x", player_id="p1",
        market="batter_hits_runs_rbis", line=2.5,
    ) is None


def test_no_two_markets_share_a_display_label() -> None:
    """The audit that would have caught every defect in this file.

    Two markets reduced to one name is the symptom shared by the fantasy
    score read as points, four NFL reception markets read as receptions, and
    hits+runs+rbis read as rbis. The label path happens to be clean; this
    keeps it that way without anyone having to notice.
    """

    from services.formatters import format_market_label

    seen: dict[tuple[str, str], list[str]] = {}
    for sport_key, markets in SPORT_MARKETS.items():
        for market in markets:
            seen.setdefault((sport_key, format_market_label(market)), []).append(market)

    collisions = {key: value for key, value in seen.items() if len(value) > 1}
    assert collisions == {}


def test_no_label_reaches_a_reader_as_a_raw_key() -> None:
    from services.formatters import format_market_label

    raw = [
        market
        for markets in SPORT_MARKETS.values()
        for market in markets
        if "_" in format_market_label(market)
    ]
    assert raw == []
