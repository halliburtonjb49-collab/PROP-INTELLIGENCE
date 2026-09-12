from datetime import date, datetime, timezone

import pytest

import main


def test_scoreboard_requests_both_ncaa_leagues() -> None:
    assert ("NCAAF", "americanfootball_ncaaf") in main.SCOREBOARD_SPORT_KEYS
    assert ("NCAAB", "basketball_ncaab") in main.SCOREBOARD_SPORT_KEYS
    assert ("CFL", "americanfootball_cfl") in main.SCOREBOARD_SPORT_KEYS


def test_scoreboard_builds_verified_espn_logo_from_team_id() -> None:
    assert main._espn_team_logo_or_stable_id({"id": "79"}, "CFL") == (
        "https://a.espncdn.com/i/teamlogos/cfl/500/79.png"
    )


@pytest.mark.parametrize(
    ("league", "team", "team_id"),
    [
        ("MLS", "New York Red Bulls", "190"),
        ("MLS", "Los Angeles FC", "18966"),
        ("NCAAF", "Appalachian State Mountaineers", "2026"),
        ("NCAAF", "UMass Minutemen", "113"),
        ("NCAAF", "Southern University Jaguars", "2582"),
        ("NCAAF", "Sam Houston State Bearkats", "2534"),
        ("NCAAF", "Southern Mississippi Golden Eagles", "2572"),
        ("NCAAF", "Grambling State Tigers", "2755"),
        ("NCAAF", "San Jose State Spartans", "23"),
    ],
)
def test_scoreboard_resolves_provider_alias_to_official_espn_logo(
    league: str,
    team: str,
    team_id: str,
) -> None:
    assert main._stable_espn_team_logo(league, team).endswith(
        f"/{team_id}.png"
    )


def test_scoreboard_merges_complete_moneyline_slate_with_espn(monkeypatch) -> None:
    target = date(2026, 9, 12)
    main._espn_team_logo_catalog._cache = {"NCAAF": {}}
    monkeypatch.setattr(
        main,
        "_espn_scoreboard_games_for_sport",
        lambda *_args: [
            {
                "id": "espn-1",
                "identity": main._scoreboard_identity("Away One", "Home One"),
                "away_team": "Away One",
                "home_team": "Home One",
                "away_logo": "https://a.espncdn.com/i/teamlogos/ncaa/500/1.png",
                "home_logo": "https://a.espncdn.com/i/teamlogos/ncaa/500/2.png",
                "commence_time": "2026-09-12T18:00:00Z",
                "status": "UPCOMING",
                "scores": [],
                "source": "ESPN",
            }
        ],
    )
    monkeypatch.setattr(
        main,
        "peek_game_markets",
        lambda *_args, **_kwargs: {
            "events": [
                {
                    "id": "market-1",
                    "awayTeam": "Away One",
                    "homeTeam": "Home One",
                    "awayTeamLogo": "",
                    "homeTeamLogo": "",
                    "commenceTime": "2026-09-12T18:00:00Z",
                    "bookmakers": [
                        {
                            "title": "DraftKings",
                            "markets": {
                                "h2h": [
                                    {"name": "Away One", "price": 125},
                                    {"name": "Home One", "price": -140},
                                ]
                            },
                        }
                    ],
                },
                {
                    "id": "market-2",
                    "awayTeam": "Away Two",
                    "homeTeam": "Home Two",
                    "awayTeamLogo": "https://a.espncdn.com/i/teamlogos/ncaa/500/3.png",
                    "homeTeamLogo": "https://a.espncdn.com/i/teamlogos/ncaa/500/4.png",
                    "commenceTime": "2026-09-12T20:00:00Z",
                    "bookmakers": [],
                },
            ]
        },
    )
    monkeypatch.setattr(
        main,
        "fetch_events",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError("shared moneyline snapshot must avoid duplicate schedule fetch")
        ),
    )

    games = main._scoreboard_games_for_sport(
        league="NCAAF",
        sport_key="americanfootball_ncaaf",
        target_date=target,
        now=datetime(2026, 9, 12, 16, 0, tzinfo=timezone.utc),
    )

    assert len(games) == 2
    first = next(game for game in games if game["home_team"] == "Home One")
    assert first["away_moneyline"] == 125
    assert first["home_moneyline"] == -140
    assert first["moneyline_available"] is True
    assert first["away_logo"].endswith("/ncaa/500/1.png")
    second = next(game for game in games if game["home_team"] == "Home Two")
    assert second["away_logo"].endswith("/ncaa/500/3.png")
    assert second["moneyline_available"] is False


def test_scoreboard_keeps_healthy_leagues_when_one_provider_fails(monkeypatch) -> None:
    monkeypatch.setattr(
        main,
        "SCOREBOARD_SPORT_KEYS",
        (("MLB", "baseball_mlb"), ("NFL", "americanfootball_nfl")),
    )
    monkeypatch.setattr(main, "get_distributed_json", lambda _key: None)
    monkeypatch.setattr(main, "set_distributed_json", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(main.realtime_hub, "broadcast_from_thread", lambda *_args: None)

    def fake_games(*, league, **_kwargs):
        if league == "NFL":
            raise RuntimeError("provider unavailable")
        return [
            {
                "id": "mlb-1",
                "sport": "MLB",
                "league": "MLB",
                "away_team": "Away",
                "home_team": "Home",
                "start_time": "2026-09-04T18:00:00Z",
            }
        ]

    monkeypatch.setattr(main, "_scoreboard_games_for_sport", fake_games)

    payload = main.scoreboard(game_date="2026-09-04")

    assert [game["id"] for game in payload["games"]] == ["mlb-1"]


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


def test_scoreboard_rejects_cross_league_team_logos() -> None:
    main._espn_team_logo_catalog._cache = {
        "NFL": {
            "sanfrancisco49ers": "https://a.espncdn.com/i/teamlogos/nfl/500/sf.png",
            "losangelesrams": "https://a.espncdn.com/i/teamlogos/nfl/500/lar.png",
        }
    }
    game = main._normalize_scoreboard_game(
        {
            "away_team": "San Francisco 49ers",
            "home_team": "Los Angeles Rams",
            "away_logo": "https://a.espncdn.com/i/teamlogos/mlb/500/tb.png",
            "home_logo": "https://a.espncdn.com/i/teamlogos/mlb/500/atl.png",
            "status": "UPCOMING",
        },
        "NFL",
        datetime(2026, 9, 10, tzinfo=timezone.utc),
    )

    assert game["away_logo"].endswith("/nfl/500/sf.png")
    assert game["home_logo"].endswith("/nfl/500/lar.png")


def test_scoreboard_uses_initials_instead_of_wrong_sport_logo() -> None:
    main._espn_team_logo_catalog._cache = {"NFL": {}}
    game = main._normalize_scoreboard_game(
        {
            "away_team": "San Francisco 49ers",
            "home_team": "Los Angeles Rams",
            "away_logo": "https://a.espncdn.com/i/teamlogos/mlb/500/tb.png",
            "home_logo": "https://a.espncdn.com/i/teamlogos/mlb/500/atl.png",
            "status": "UPCOMING",
        },
        "NFL",
        datetime(2026, 9, 10, tzinfo=timezone.utc),
    )

    assert game["away_logo"] == ""
    assert game["home_logo"] == ""


@pytest.mark.parametrize(
    ("league", "valid_marker", "wrong_marker"),
    [
        ("NBA", "nba", "nfl"),
        ("WNBA", "wnba", "mlb"),
        ("MLB", "mlb", "nhl"),
        ("NFL", "nfl", "nba"),
        ("CFL", "cfl", "mlb"),
        ("NHL", "nhl", "nfl"),
        ("NCAAF", "ncaa", "nfl"),
        ("NCAAB", "ncaa", "nba"),
        ("EPL", "soccer", "mlb"),
        ("MLS", "soccer", "nba"),
    ],
)
def test_scoreboard_logo_validation_covers_every_supported_sport(
    league: str,
    valid_marker: str,
    wrong_marker: str,
) -> None:
    valid = f"https://a.espncdn.com/i/teamlogos/{valid_marker}/500/team.png"
    wrong = f"https://a.espncdn.com/i/teamlogos/{wrong_marker}/500/team.png"

    assert main._scoreboard_logo_for_league(valid, league) == valid
    assert main._scoreboard_logo_for_league(wrong, league) == ""
