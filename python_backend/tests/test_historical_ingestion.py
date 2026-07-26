from services.historical_ingestion_service import (
    backfill_basketball_officiating,
    build_official_assignments,
    normalize_basketball_logs,
    normalize_espn_soccer_fixtures,
    normalize_sportmonks_fixtures,
    normalize_statcast,
    run_mlb_historical_backfill,
    run_daily_historical_sync,
    run_soccer_historical_backfill,
)
from providers.historical_data import MlbHistoricalProvider


def test_normalizes_basketball_game_log() -> None:
    rows = normalize_basketball_logs([{"PLAYER_ID": 7, "PLAYER_NAME": "Test", "GAME_ID": "g1",
        "PTS": 20, "REB": 8, "AST": 6, "MIN": 34}], "WNBA")
    assert len(rows) == 1
    assert rows[0]["sport"] == "WNBA"
    assert rows[0]["points"] == 20


def test_normalizes_non_finite_values_for_postgres_json() -> None:
    rows = normalize_basketball_logs([{"PLAYER_ID": 7, "PLAYER_NAME": "Test", "GAME_ID": "g1",
        "PTS": float("nan"), "FG3_PCT": float("nan")}], "WNBA")
    assert rows[0]["points"] is None
    assert rows[0]["raw"]["FG3_PCT"] is None


def test_espn_basketball_box_score_maps_to_projection_columns(
    monkeypatch,
) -> None:
    from providers.espn_basketball_statistics import (
        EspnBasketballStatisticsProvider,
    )

    provider = EspnBasketballStatisticsProvider()
    responses = [
        {
            "events": [
                {
                    "id": "game-1",
                    "name": "Away at Home",
                    "status": {"type": {"completed": True}},
                }
            ]
        },
        {
            "boxscore": {
                "players": [
                    {
                        "team": {"id": "team-1"},
                        "statistics": [
                            {
                                "keys": [
                                    "minutes",
                                    "points",
                                    "threePointFieldGoalsMade-threePointFieldGoalsAttempted",
                                    "freeThrowsMade-freeThrowsAttempted",
                                    "rebounds",
                                    "assists",
                                    "turnovers",
                                    "steals",
                                    "blocks",
                                    "fouls",
                                ],
                                "athletes": [
                                    {
                                        "athlete": {
                                            "id": "7",
                                            "displayName": "Test Player",
                                        },
                                        "stats": [
                                            "32",
                                            "24",
                                            "4-9",
                                            "6-7",
                                            "10",
                                            "8",
                                            "3",
                                            "2",
                                            "1",
                                            "4",
                                        ],
                                    }
                                ],
                            }
                        ],
                    }
                ]
            }
        },
    ]
    monkeypatch.setattr(provider, "_json", lambda *args, **kwargs: responses.pop(0))

    rows = provider.daily_game_logs(
        sport="WNBA",
        target_date=__import__("datetime").date(2026, 7, 25),
    )

    assert rows[0]["PLAYER_NAME"] == "Test Player"
    assert rows[0]["PTS"] == 24
    assert rows[0]["REB"] == 10
    assert rows[0]["AST"] == 8
    assert rows[0]["FG3M"] == 4
    assert rows[0]["FTA"] == 7
    assert rows[0]["SOURCE"] == "ESPN"


def test_espn_basketball_officiating_assignments_are_stable(
    monkeypatch,
) -> None:
    from datetime import date
    from providers.espn_basketball_statistics import (
        EspnBasketballStatisticsProvider,
    )

    provider = EspnBasketballStatisticsProvider()

    def payload(url, *, params):
        if url.endswith("/scoreboard"):
            assert params["dates"] == "20260720-20260721"
            return {
                "events": [{
                    "id": "401",
                    "date": "2026-07-20T19:00Z",
                    "status": {"type": {"completed": True}},
                }]
            }
        return {
            "gameInfo": {
                "officials": [
                    {"displayName": "Pat Ref", "position": {"name": "Referee"}}
                ]
            }
        }

    monkeypatch.setattr(provider, "_json", payload)
    rows = provider.officiating_assignments(
        sport="WNBA",
        start_date=date(2026, 7, 20),
        end_date=date(2026, 7, 21),
    )

    assert rows[0]["league_game_id"] == "401"
    assert rows[0]["official_name"] == "Pat Ref"
    assert rows[0]["official_id"].startswith("espn-")
    assert rows[0]["source"] == "ESPN"


def test_wnba_officiating_falls_back_to_espn_when_nba_stats_fails(
    monkeypatch,
) -> None:
    from contextlib import contextmanager
    from datetime import date

    class NbaProvider:
        def league_schedule(self, **kwargs):
            raise TimeoutError("NBA Stats timed out")

    class EspnProvider:
        def officiating_assignments(self, **kwargs):
            return [{
                "league_game_id": "espn-game",
                "official_id": "espn-ref",
                "official_name": "Pat Ref",
                "game_date": date.today(),
                "raw": {"displayName": "Pat Ref"},
            }]

    class Cursor:
        def __init__(self):
            self._rows = []

        def execute(self, query, params):
            if "historical_basketball_game_logs" in query:
                self._rows = [("espn-game", date.today(), 30, 20)]
            else:
                self._rows = []

        def fetchall(self):
            return self._rows

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

    class Connection:
        def cursor(self):
            return Cursor()

    class Pool:
        @contextmanager
        def connection(self):
            yield Connection()

    monkeypatch.setattr(
        "services.historical_ingestion_service.database_is_configured",
        lambda: True,
    )
    monkeypatch.setattr(
        "services.historical_ingestion_service.NbaHistoricalProvider",
        NbaProvider,
    )
    monkeypatch.setattr(
        "services.historical_ingestion_service.EspnBasketballStatisticsProvider",
        EspnProvider,
    )
    monkeypatch.setattr(
        "services.historical_ingestion_service.get_database_pool",
        Pool,
    )
    captured = []
    monkeypatch.setattr(
        "services.historical_ingestion_service.persist_basketball_assignments",
        lambda rows: captured.extend(rows) or len(rows),
    )
    monkeypatch.setattr(
        "services.historical_ingestion_service.refresh_basketball_profiles",
        lambda sport: 1,
    )

    result = backfill_basketball_officiating(
        sport="WNBA",
        season="2026",
        days=14,
    )

    assert result["source"] == "ESPN"
    assert result["assignments"] == 1
    assert result["primaryProviderError"] == "NBA Stats timed out"
    assert captured[0]["official_id"] == "espn-ref"


def test_daily_basketball_sync_falls_back_to_espn(monkeypatch) -> None:
    class FailingNbaProvider:
        def league_game_logs(self, **kwargs):
            raise TimeoutError("NBA Stats timeout")

    class EspnProvider:
        def daily_game_logs(self, *, sport, target_date):
            return [
                {
                    "PLAYER_ID": f"{sport}-7",
                    "PLAYER_NAME": "Fallback Player",
                    "TEAM_ID": "team-1",
                    "GAME_ID": f"{sport}-game",
                    "GAME_DATE": target_date.isoformat(),
                    "PTS": 20,
                    "REB": 8,
                    "AST": 6,
                    "SOURCE": "ESPN",
                }
            ]

    class SportmonksProvider:
        def completed_fixtures(self, *, target_date):
            return []

    class Repository:
        def upsert_basketball_logs(self, rows):
            return len(rows)

        def upsert_player_game_logs(self, rows):
            return len(rows)

    monkeypatch.setattr(
        "services.historical_ingestion_service.NbaHistoricalProvider",
        FailingNbaProvider,
    )
    monkeypatch.setattr(
        "services.historical_ingestion_service.EspnBasketballStatisticsProvider",
        EspnProvider,
    )
    monkeypatch.setattr(
        "services.historical_ingestion_service.SportmonksStatisticsProvider",
        SportmonksProvider,
    )
    monkeypatch.setattr(
        "services.historical_ingestion_service.HistoricalRepository",
        Repository,
    )

    result = run_daily_historical_sync(
        target_date=__import__("datetime").date(2026, 7, 25),
        include_mlb=False,
    )

    assert result["NBA"]["source"] == "ESPN"
    assert result["NBA"]["upserted"] == 1
    assert result["WNBA"]["source"] == "ESPN"
    assert result["WNBA"]["upserted"] == 1


def test_normalizes_statcast_pitch() -> None:
    rows = normalize_statcast([{"game_pk": 1, "at_bat_number": 2, "pitch_number": 3,
        "pitcher": 9, "batter": 10, "plate_x": .2, "description": "called_strike"}])
    assert len(rows) == 1
    assert rows[0]["pitcher_id"] == "9"
    assert rows[0]["plate_x"] == .2


def test_normalizes_sportmonks_player_fixture_stats() -> None:
    rows = normalize_sportmonks_fixtures([{
        "id": 55,
        "league_id": 8,
        "starting_at": "2026-07-24 19:00:00",
        "lineups": [{
            "player_id": 7,
            "player_name": "Test Striker",
            "team_id": 9,
            "details": [
                {"type_id": 42, "data": {"value": 4}},
                {"type_id": 86, "data": {"value": 2}},
                {"type_id": 52, "data": {"value": 1}},
            ],
        }],
    }])

    assert len(rows) == 1
    assert rows[0]["sport"] == "SOCCER"
    assert rows[0]["league"] == "8"
    assert rows[0]["stats"]["shots"] == 4
    assert rows[0]["stats"]["shots_on_target"] == 2
    assert rows[0]["stats"]["assists"] == 0
    assert rows[0]["stats"]["received_card"] == 0


def test_normalizes_espn_soccer_player_fixture_stats() -> None:
    rows = normalize_espn_soccer_fixtures([{
        "id": "event-1",
        "league_id": "779",
        "starting_at": "2026-07-24T19:00Z",
        "rosters": [{
            "team": {"id": "team-1"},
            "roster": [
                {
                    "athlete": {"id": "7", "displayName": "Test Striker"},
                    "stats": [
                        {"name": "appearances", "value": 1},
                        {"name": "totalShots", "value": 4},
                        {"name": "shotsOnTarget", "value": 2},
                        {"name": "totalGoals", "value": 1},
                        {"name": "yellowCards", "value": 1},
                    ],
                },
                {
                    "athlete": {"id": "8", "displayName": "Unused Substitute"},
                    "stats": [{"name": "appearances", "value": 0}],
                },
            ],
        }],
    }])

    assert len(rows) == 1
    assert rows[0]["source"] == "ESPN"
    assert rows[0]["league"] == "779"
    assert rows[0]["stats"]["shots"] == 4
    assert rows[0]["stats"]["shots_on_target"] == 2
    assert rows[0]["stats"]["goals"] == 1
    assert rows[0]["stats"]["received_card"] == 1


def test_builds_basketball_official_assignment_context() -> None:
    logs = normalize_basketball_logs([
        {"PLAYER_ID": 1, "PLAYER_NAME": "A", "GAME_ID": "g", "GAME_DATE": "2026-01-01", "PF": 3, "FTA": 5},
        {"PLAYER_ID": 2, "PLAYER_NAME": "B", "GAME_ID": "g", "GAME_DATE": "2026-01-01", "PF": 2, "FTA": 7},
    ], "NBA")
    rows = build_official_assignments(logs, {"g": [{"PERSON_ID": 9, "FIRST_NAME": "Pat", "LAST_NAME": "Ref"}]}, "NBA")
    assert rows[0]["official_name"] == "Pat Ref"
    assert rows[0]["total_fouls"] == 5
    assert rows[0]["total_free_throw_attempts"] == 12


def test_mlb_provider_extracts_home_plate_assignment(monkeypatch) -> None:
    class Response:
        def raise_for_status(self): pass
        def json(self):
            return {"dates": [{"date": "2026-07-17", "games": [{"gamePk": 1,
                "officialDate": "2026-07-17", "officials": [
                    {"officialType": "First Base", "official": {"id": 2, "fullName": "Other"}},
                    {"officialType": "Home Plate", "official": {"id": 9, "fullName": "Pat Ump"}},
                ]}]}]}
    monkeypatch.setattr("providers.historical_data.requests.get", lambda *args, **kwargs: Response())
    rows = MlbHistoricalProvider().umpire_assignments(
        start=__import__("datetime").date(2026, 7, 17),
        end=__import__("datetime").date(2026, 7, 17),
    )
    assert rows == [{"game_pk": "1", "game_date": "2026-07-17", "official_id": "9",
                     "official_name": "Pat Ump", "source": "MLB Stats API",
                     "raw": {"officialType": "Home Plate", "official": {"id": 9, "fullName": "Pat Ump"}}}]


def test_mlb_backfill_uses_a_rolling_window(monkeypatch) -> None:
    calls = {"ranges": []}

    class Provider:
        def statcast(self, *, start, end):
            calls["ranges"].append((start, end))
            return []

        def umpire_assignments(self, *, start, end):
            return []

    class Repository:
        def upsert_mlb_pitches(self, rows):
            return len(rows)

        def upsert_mlb_umpire_assignments(self, rows):
            return len(rows)

        def load_mlb_umpire_pitches(self):
            return []

    monkeypatch.setattr(
        "services.historical_ingestion_service.MlbHistoricalProvider",
        Provider,
    )
    monkeypatch.setattr(
        "services.historical_ingestion_service.HistoricalRepository",
        Repository,
    )
    monkeypatch.setattr(
        "services.historical_ingestion_service.persist_officiating_profiles",
        lambda rows: len(rows),
    )
    result = run_mlb_historical_backfill(
        end_date=__import__("datetime").date(2026, 7, 24),
        days=21,
    )

    assert calls["ranges"] == [
        (
            __import__("datetime").date(2026, 7, 4),
            __import__("datetime").date(2026, 7, 10),
        ),
        (
            __import__("datetime").date(2026, 7, 11),
            __import__("datetime").date(2026, 7, 17),
        ),
        (
            __import__("datetime").date(2026, 7, 18),
            __import__("datetime").date(2026, 7, 24),
        ),
    ]
    assert result["startDate"] == "2026-07-04"
    assert result["endDate"] == "2026-07-24"
    assert result["chunks"] == 3
    assert result["chunkDays"] == 7


def test_mlb_backfill_can_isolate_each_statcast_chunk(monkeypatch) -> None:
    calls = []

    class Provider:
        def umpire_assignments(self, *, start, end):
            return []

    class Repository:
        def upsert_mlb_umpire_assignments(self, rows):
            return 0

        def load_mlb_umpire_pitches(self):
            return []

    class Completed:
        stdout = "pybaseball progress\n{\"fetched\": 10, \"upserted\": 9}\n"

    def run(command, **kwargs):
        calls.append(command)
        assert kwargs["check"] is True
        assert kwargs["capture_output"] is True
        return Completed()

    monkeypatch.setattr(
        "services.historical_ingestion_service.MlbHistoricalProvider",
        Provider,
    )
    monkeypatch.setattr(
        "services.historical_ingestion_service.HistoricalRepository",
        Repository,
    )
    monkeypatch.setattr(
        "services.historical_ingestion_service.subprocess.run",
        run,
    )
    monkeypatch.setattr(
        "services.historical_ingestion_service.persist_officiating_profiles",
        lambda rows: 0,
    )

    result = run_mlb_historical_backfill(
        end_date=__import__("datetime").date(2026, 7, 24),
        days=8,
        isolate_chunks=True,
    )

    assert len(calls) == 2
    assert result["fetched"] == 20
    assert result["upserted"] == 18


def test_soccer_backfill_defaults_to_full_season_and_adds_espn_fallback(
    monkeypatch,
) -> None:
    calls = {}

    class SportmonksProvider:
        def completed_fixtures(self, *, target_date):
            calls.setdefault("sportmonks_dates", []).append(target_date)
            return []

    class EspnProvider:
        def completed_fixtures(self, *, start_date, end_date):
            calls["espn_range"] = (start_date, end_date)
            return [{
                "id": "event-1",
                "league_id": "779",
                "starting_at": "2026-07-24T19:00:00Z",
                "rosters": [{
                    "team": {"id": "team-1"},
                    "roster": [{
                        "athlete": {"id": "7", "displayName": "Test Striker"},
                        "stats": [
                            {"name": "appearances", "value": 1},
                            {"name": "totalShots", "value": 2},
                        ],
                    }],
                }],
            }]

    class Repository:
        def upsert_player_game_logs(self, rows):
            return len(rows)

    monkeypatch.setattr(
        "services.historical_ingestion_service.SportmonksStatisticsProvider",
        SportmonksProvider,
    )
    monkeypatch.setattr(
        "services.historical_ingestion_service.EspnSoccerStatisticsProvider",
        EspnProvider,
    )
    monkeypatch.setattr(
        "services.historical_ingestion_service.HistoricalRepository",
        Repository,
    )

    result = run_soccer_historical_backfill(
        end_date=__import__("datetime").date(2026, 7, 24),
    )

    expected_start = __import__("datetime").date(2025, 7, 25)
    assert calls["sportmonks_dates"][0] == expected_start
    assert len(calls["sportmonks_dates"]) == 365
    assert calls["espn_range"] == (
        expected_start,
        __import__("datetime").date(2026, 7, 24),
    )
    assert result["fetched"] == 1
    assert result["upserted"] == 1
    assert result["sources"] == {"Sportmonks": 0, "ESPN": 1}
