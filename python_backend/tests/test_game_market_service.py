from services import game_market_service


def _provider_payload():
    return [{
        "id": "game-1",
        "sport_key": "baseball_mlb",
        "sport_title": "MLB",
        "commence_time": "2026-07-19T23:10:00Z",
        "home_team": "Chicago Cubs",
        "away_team": "St. Louis Cardinals",
        "bookmakers": [{
            "key": "fanduel",
            "title": "FanDuel",
            "last_update": "2026-07-19T20:00:00Z",
            "markets": [
                {"key": "h2h", "outcomes": [
                    {"name": "Chicago Cubs", "price": -125},
                    {"name": "St. Louis Cardinals", "price": 110},
                ]},
                {"key": "spreads", "outcomes": [
                    {"name": "Chicago Cubs", "price": 145, "point": -1.5},
                    {"name": "St. Louis Cardinals", "price": -165, "point": 1.5},
                ]},
                {"key": "totals", "outcomes": [
                    {"name": "Over", "price": -108, "point": 8.5},
                    {"name": "Under", "price": -112, "point": 8.5},
                ]},
            ],
        }],
    }]


def test_game_markets_normalize_all_three_market_types():
    game_market_service._cache.clear()
    result = game_market_service.get_game_markets(
        "MLB", force=True, fetcher=lambda **_: _provider_payload()
    )
    event = result["events"][0]
    markets = event["bookmakers"][0]["markets"]
    assert set(markets) == {"h2h", "spreads", "totals"}
    assert markets["spreads"][0]["point"] == -1.5
    assert markets["totals"][0]["point"] == 8.5


def test_game_markets_reuse_cache_and_report_health():
    game_market_service._cache.clear()
    calls = []
    fetcher = lambda **_: calls.append(True) or _provider_payload()
    game_market_service.get_game_markets("MLB", force=True, fetcher=fetcher)
    result = game_market_service.get_game_markets("MLB", fetcher=fetcher)
    assert result["cached"] is True
    assert len(calls) == 1
    assert game_market_service.game_market_health()["successRate"] > 0


def test_game_markets_reject_unknown_sport():
    try:
        game_market_service.get_game_markets("UNKNOWN")
    except ValueError as exc:
        assert "Unsupported sport" in str(exc)
    else:
        raise AssertionError("unsupported sport should fail")
