from services import formatters
from services.formatters import (
    CATEGORY_LABELS,
    format_sport_label,
    market_to_category,
)
from services.market_config import (
    SPORT_MARKETS,
    markets_for_sport,
    odds_api_markets_for_sport,
)


def test_professional_sports_have_prop_market_definitions():
    for sport in (
        "baseball_mlb", "basketball_nba", "basketball_wnba",
        "americanfootball_nfl", "americanfootball_ncaaf",
        "americanfootball_cfl", "basketball_ncaab",
        "icehockey_nhl", "soccer_epl",
        "soccer_usa_mls", "soccer_france_ligue_one",
        "soccer_germany_bundesliga", "soccer_italy_serie_a",
        "soccer_spain_la_liga",
    ):
        assert markets_for_sport(sport), sport


def test_soccer_odds_api_markets_match_the_supported_provider_catalog():
    markets = odds_api_markets_for_sport("soccer_epl")
    assert "player_shots_on_target" in markets
    assert "player_shots" in markets
    assert "player_goalkeeper_saves" not in markets
    assert "player_tackles" not in markets


def test_supplemental_soccer_markets_remain_in_the_shared_catalog():
    markets = markets_for_sport("soccer_epl")
    assert "player_goalkeeper_saves" in markets
    assert "player_tackles" in markets


def test_new_markets_have_professional_category_labels():
    assert market_to_category("pitcher_outs") == "outs recorded"
    assert market_to_category("batter_hits_runs_rbis") == "hits + runs + rbis"
    assert market_to_category("player_pass_interceptions") == "passing interceptions"
    assert market_to_category("player_total_saves") == "goalie saves"
    assert market_to_category("player_shots_on_target") == "shots on target"
    assert market_to_category("player_double_double") == "double-double"
    assert market_to_category("player_anytime_td") == "anytime touchdown"
    assert market_to_category("player_goal_scorer_anytime") == "anytime goalscorer"
    assert market_to_category("player_to_receive_card") == "player card"


def test_provider_display_labels_normalize_to_canonical_categories():
    assert market_to_category("Player Assists") == "assists"
    assert market_to_category("player-assists") == "assists"
    assert market_to_category("Player Points + Assists") == "points + assists"
    assert format_sport_label("icehockey_nhl") == "NHL"
    assert format_sport_label("soccer_epl") == "SOCCER"
    assert format_sport_label("americanfootball_ncaaf") == "NCAAF"
    assert format_sport_label("basketball_ncaab") == "NCAAB"
    assert format_sport_label("americanfootball_cfl") == "CFL"


def test_every_configured_provider_market_has_an_explicit_category_label():
    missing = {
        sport: [market for market in markets if market not in CATEGORY_LABELS]
        for sport, markets in SPORT_MARKETS.items()
    }
    assert {sport: markets for sport, markets in missing.items() if markets} == {}


def test_touchdown_and_afl_scorer_markets_keep_their_full_meaning():
    assert market_to_category("player_pass_tds") == "passing touchdowns"
    assert market_to_category("player_goal_scorer_first") == "first goalscorer"
    assert market_to_category("player_goal_scorer_last") == "last goalscorer"


def test_nfl_props_resolve_through_espn_headshot_provider(monkeypatch):
    calls: list[tuple[str, str]] = []

    def fake_espn_headshot(player_name: str, sport: str) -> str:
        calls.append((player_name, sport))
        return "https://a.espncdn.com/i/headshots/nfl/players/full/1.png"

    monkeypatch.setattr(formatters, "espn_headshot_url", fake_espn_headshot)

    assert formatters.resolve_player_image("Josh Allen", "NFL").endswith(
        "/nfl/players/full/1.png"
    )
    assert calls == [("Josh Allen", "NFL")]


def test_replacement_sports_resolve_through_espn_headshot_provider(monkeypatch):
    calls: list[tuple[str, str]] = []

    def fake_espn_headshot(player_name: str, sport: str) -> str:
        calls.append((player_name, sport))
        return f"https://a.espncdn.com/i/headshots/{sport.lower()}/1.png"

    monkeypatch.setattr(formatters, "espn_headshot_url", fake_espn_headshot)

    for sport in ("NCAAF", "NCAAB", "CFL"):
        assert formatters.resolve_player_image("Test Player", sport).endswith(
            f"/{sport.lower()}/1.png"
        )

    assert calls == [
        ("Test Player", "NCAAF"),
        ("Test Player", "NCAAB"),
        ("Test Player", "CFL"),
    ]
