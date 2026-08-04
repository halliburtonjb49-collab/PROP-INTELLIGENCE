from providers import balldontlie_soccer


def _match() -> dict[str, object]:
    return {
        "id": 55123,
        "date": "2026-08-10T19:00:00Z",
        "status": "scheduled",
        "home_team": {"name": "Arsenal"},
        "away_team": {"name": "Chelsea"},
    }


def _props() -> list[dict[str, object]]:
    return [
        {
            "prop_type": "shots_on_target",
            "player": {"name": "Bukayo Saka"},
            "player_id": 9001,
            "line_value": "1.5",
            "vendor": "draftkings",
            "market": {"over_odds": -120, "under_odds": -110},
        },
        {
            "prop_type": "assists",
            "player": {"first_name": "Cole", "last_name": "Palmer"},
            "player_id": 9002,
            "line_value": "0.5",
            "vendor": "draftkings",
            "market": {"over_odds": 150, "under_odds": -190},
        },
        # Milestone-style market with no line/over-under shape: must be skipped, not crash.
        {
            "prop_type": "anytime_goal",
            "player": {"name": "Gabriel Jesus"},
            "player_id": 9003,
            "line_value": None,
            "vendor": "draftkings",
            "market": {"odds": -150},
        },
        # Missing price entirely: must be skipped.
        {
            "prop_type": "shots",
            "player": {"name": "No Price Guy"},
            "player_id": 9004,
            "line_value": "2.5",
            "vendor": "draftkings",
            "market": {},
        },
    ]


def test_normalize_match_maps_known_prop_types_to_over_under_outcomes():
    event, odds_payload = balldontlie_soccer.normalize_match(
        _match(), _props(), sport_key="soccer_epl"
    )

    assert event["id"] == "bdl:55123"
    assert event["home_team"] == "Arsenal"
    assert event["away_team"] == "Chelsea"
    assert event["status"] == "scheduled"

    bookmakers = odds_payload["bookmakers"]
    assert len(bookmakers) == 1
    markets = {market["key"]: market for market in bookmakers[0]["markets"]}

    assert "player_shots_on_target" in markets
    assert "player_assists" in markets
    # Milestone (no over/under shape) and missing-price rows must not appear.
    assert "player_goal_scorer_anytime" not in markets
    assert "player_shots" not in markets

    saka_outcomes = markets["player_shots_on_target"]["outcomes"]
    sides = {(o["name"], o["point"], o["price"]) for o in saka_outcomes}
    assert ("Over", 1.5, -120.0) in sides
    assert ("Under", 1.5, -110.0) in sides

    palmer_outcomes = markets["player_assists"]["outcomes"]
    assert any(o["description"] == "Cole Palmer" for o in palmer_outcomes)


def test_normalize_match_handles_no_props():
    event, odds_payload = balldontlie_soccer.normalize_match(
        _match(), [], sport_key="soccer_epl"
    )
    assert event["id"] == "bdl:55123"
    assert odds_payload["bookmakers"] == []


def test_league_to_sport_covers_expected_leagues():
    assert balldontlie_soccer.LEAGUE_TO_SPORT == {
        "epl": "soccer_epl",
        "mls": "soccer_usa_mls",
        "ligue1": "soccer_france_ligue_one",
        "bundesliga": "soccer_germany_bundesliga",
        "seriea": "soccer_italy_serie_a",
        "laliga": "soccer_spain_la_liga",
    }
