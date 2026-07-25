from services.historical_ingestion_service import (
    build_official_assignments,
    normalize_basketball_logs,
    normalize_sportmonks_fixtures,
    normalize_statcast,
    run_mlb_historical_backfill,
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
    calls = {}

    class Provider:
        def statcast(self, *, start, end):
            calls["range"] = (start, end)
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

    assert calls["range"] == (
        __import__("datetime").date(2026, 7, 4),
        __import__("datetime").date(2026, 7, 24),
    )
    assert result["startDate"] == "2026-07-04"
    assert result["endDate"] == "2026-07-24"
