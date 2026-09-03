from datetime import date, datetime, timezone

import main


def test_scoreboard_requests_both_ncaa_leagues() -> None:
    assert ("NCAAF", "americanfootball_ncaaf") in main.SCOREBOARD_SPORT_KEYS
    assert ("NCAAB", "basketball_ncaab") in main.SCOREBOARD_SPORT_KEYS


def test_ncaa_scoreboard_requests_complete_college_groups(monkeypatch) -> None:
    requests: list[dict[str, object]] = []

    class Response:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict[str, object]:
            return {"events": []}

    def fake_get(*args, **kwargs):
        requests.append(kwargs["params"])
        return Response()

    monkeypatch.setattr(main.requests, "get", fake_get)

    main._espn_scoreboard_games_for_sport("NCAAF", date(2026, 9, 3))
    main._espn_scoreboard_games_for_sport("NCAAB", date(2026, 9, 3))

    assert requests == [
        {"dates": "20260903", "limit": 1000, "groups": 80},
        {"dates": "20260903", "limit": 1000, "groups": 50},
    ]


def test_scoreboard_dedupe_preserves_doubleheaders() -> None:
    early_game = {
        "id": "game-early",
        "league": "MLB",
        "away_team": "Atlanta Braves",
        "home_team": "New York Mets",
        "startTimeUtc": "2026-07-29T17:10:00Z",
    }
    late_game = {
        **early_game,
        "id": "game-late",
        "startTimeUtc": "2026-07-29T23:10:00Z",
    }

    assert main._scoreboard_dedupe_key(early_game) != main._scoreboard_dedupe_key(
        late_game
    )


def test_scoreboard_dedupe_collapses_same_fallback_event() -> None:
    provider_a = {
        "league": "MLB",
        "away_team": "Seattle Mariners",
        "home_team": "Los Angeles Dodgers",
        "startTimeUtc": "2026-07-30T02:10:00Z",
    }
    provider_b = {
        **provider_a,
        "start_time": provider_a["startTimeUtc"],
    }

    assert main._scoreboard_dedupe_key(provider_a) == main._scoreboard_dedupe_key(
        provider_b
    )


def test_espn_scoreboard_includes_broadcast_and_source(monkeypatch) -> None:
    class Response:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict[str, object]:
            return {
                "events": [
                    {
                        "id": "401",
                        "date": "2026-08-29T19:00:00Z",
                        "competitions": [
                            {
                                "broadcasts": [{"names": ["ESPN", "ABC"]}],
                                "status": {
                                    "type": {
                                        "state": "in",
                                        "shortDetail": "Q3 04:12",
                                    }
                                },
                                "competitors": [
                                    {
                                        "homeAway": "away",
                                        "score": "17",
                                        "team": {
                                            "displayName": "Away Team",
                                            "logo": "https://cdn.example/away.png",
                                        },
                                    },
                                    {
                                        "homeAway": "home",
                                        "score": "21",
                                        "team": {
                                            "displayName": "Home Team",
                                            "logo": "https://cdn.example/home.png",
                                        },
                                    },
                                ],
                            }
                        ],
                    }
                ]
            }

    monkeypatch.setattr(main.requests, "get", lambda *args, **kwargs: Response())

    games = main._espn_scoreboard_games_for_sport("NFL", date(2026, 8, 29))

    assert games[0]["status"] == "LIVE"
    assert games[0]["detail"] == "Q3 04:12"
    assert games[0]["broadcast"] == "ESPN, ABC"
    assert games[0]["source"] == "ESPN"
    assert games[0]["away_logo"] == "https://cdn.example/away.png"
    assert games[0]["home_logo"] == "https://cdn.example/home.png"


def test_scoreboard_normalization_preserves_authoritative_espn_status() -> None:
    main._espn_team_logo_catalog._cache = {"NFL": {}}
    game = main._normalize_scoreboard_game(
        {
            "id": "401",
            "away_team": "Away Team",
            "home_team": "Home Team",
            "commence_time": "2026-08-29T19:00:00Z",
            "status": "UPCOMING",
            "broadcast": "ESPN",
            "source": "ESPN",
        },
        "NFL",
        datetime(2026, 8, 29, 20, 0, tzinfo=timezone.utc),
    )

    assert game["status"] == "UPCOMING"
    assert game["broadcast"] == "ESPN"
    assert game["source"] == "ESPN"


def test_espn_team_logo_uses_alternate_logo_collection() -> None:
    assert (
        main._espn_team_logo(
            {"logos": [{"href": "https://cdn.example/alternate.png"}]}
        )
        == "https://cdn.example/alternate.png"
    )


def test_provider_scoreboard_uses_espn_team_logo_catalog() -> None:
    main._espn_team_logo_catalog._cache = {
        "MLB": {
            "bostonredsox": "https://cdn.example/bos.png",
            "newyorkyankees": "https://cdn.example/nyy.png",
        }
    }
    game = main._normalize_scoreboard_game(
        {
            "away_team": "Boston Red Sox",
            "home_team": "New York Yankees",
            "status": "UPCOMING",
        },
        "MLB",
        datetime(2026, 8, 29, tzinfo=timezone.utc),
    )

    assert game["away_logo"] == "https://cdn.example/bos.png"
    assert game["home_logo"] == "https://cdn.example/nyy.png"
