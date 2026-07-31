from services import formatters
from services.formatters import format_sport_label, market_to_category
from services.market_config import markets_for_sport


def test_professional_sports_have_prop_market_definitions():
    for sport in (
        "baseball_mlb", "basketball_nba", "basketball_wnba",
        "americanfootball_nfl", "icehockey_nhl", "soccer_epl",
        "soccer_usa_mls", "soccer_france_ligue_one",
        "soccer_germany_bundesliga", "soccer_italy_serie_a",
        "soccer_spain_la_liga",
    ):
        assert markets_for_sport(sport), sport


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
    assert format_sport_label("icehockey_nhl") == "NHL"
    assert format_sport_label("soccer_epl") == "SOCCER"


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
