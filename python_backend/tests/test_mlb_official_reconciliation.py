from datetime import datetime, timedelta, timezone

from models.slip import LegResultUpdate, SlipCreate, SlipLeg
from services import mlb_official_stats_service, result_reconciliation_service, slip_service
from services.mlb_official_stats_service import OfficialMlbResult


def test_mlb_event_date_uses_eastern_scheduling_day() -> None:
    assert mlb_official_stats_service._event_date("2026-08-03T01:10:00Z") == "2026-08-02"


def test_schedule_window_is_independent_of_user_timezone() -> None:
    assert mlb_official_stats_service._schedule_window("2026-08-03T02:10:00Z") == (
        "2026-08-02", "2026-08-04",
    )


def test_official_mlb_result_resolves_final_game_and_pitcher_stat(monkeypatch) -> None:
    def fake_get(path, params=None):
        if path == "/v1/schedule":
            assert params["startDate"] == "2026-07-25"
            assert params["endDate"] == "2026-07-27"
            return {
                "dates": [{
                    "games": [{
                        "gamePk": 42,
                        "status": {"abstractGameState": "Final"},
                        "teams": {
                            "away": {"team": {"name": "Toronto Blue Jays"}},
                            "home": {"team": {"name": "Boston Red Sox"}},
                        },
                    }]
                }]
            }
        assert path == "/v1/game/42/boxscore"
        return {
            "teams": {
                "home": {
                    "players": {
                        "ID1": {
                            "person": {"fullName": "Ranger Suárez"},
                            "stats": {"pitching": {"strikeOuts": 6}},
                        }
                    }
                },
                "away": {"players": {}},
            }
        }

    monkeypatch.setattr(mlb_official_stats_service, "_get_json", fake_get)
    result = mlb_official_stats_service.official_mlb_result(
        player_name="Ranger Suarez",
        market="Pitcher Strikeouts",
        matchup="Toronto Blue Jays @ Boston Red Sox",
        game_start_time="2026-07-26T18:00:00Z",
    )
    assert result is not None
    assert result.value == 6
    assert result.source == "mlb-stats-api"


def test_game_resolution_accepts_team_abbreviations_and_chooses_closest(monkeypatch) -> None:
    monkeypatch.setattr(
        mlb_official_stats_service,
        "_get_json",
        lambda _path, _params=None: {"dates": [{"games": [
            {
                "gamePk": 40, "gameDate": "2026-08-02T17:00:00Z",
                "status": {"abstractGameState": "Final"},
                "teams": {
                    "away": {"team": {"name": "Toronto Blue Jays", "abbreviation": "TOR"}},
                    "home": {"team": {"name": "Boston Red Sox", "abbreviation": "BOS"}},
                },
            },
            {
                "gamePk": 42, "gameDate": "2026-08-02T23:00:00Z",
                "status": {"abstractGameState": "Final"},
                "teams": {
                    "away": {"team": {"name": "Toronto Blue Jays", "abbreviation": "TOR"}},
                    "home": {"team": {"name": "Boston Red Sox", "abbreviation": "BOS"}},
                },
            },
        ]}]},
    )
    assert mlb_official_stats_service._final_game_pk(
        game_start_time="2026-08-02T22:55:00Z", matchup="TOR @ BOS",
        api_sports_game_id="",
    ) == "42"


def test_statcast_fallback_grades_single_game_total_bases(monkeypatch) -> None:
    class Cursor:
        def __enter__(self): return self
        def __exit__(self, *_args): return False
        def execute(self, _query, params):
            assert params == ("123", "2026-08-02", "2026-08-04")
        def fetchall(self):
            return [(42, "single"), (42, "double"), (42, "field_out")]

    class Connection:
        def __enter__(self): return self
        def __exit__(self, *_args): return False
        def cursor(self): return Cursor()

    class Pool:
        def connection(self): return Connection()

    monkeypatch.setattr(mlb_official_stats_service, "database_is_configured", lambda: True)
    monkeypatch.setattr(mlb_official_stats_service, "get_database_pool", lambda: Pool())
    monkeypatch.setattr(mlb_official_stats_service, "mlb_player_id", lambda _name: 123)
    result = mlb_official_stats_service.historical_mlb_result(
        player_name="Test Batter", market="Total Bases",
        game_start_time="2026-08-03T01:10:00Z",
    )
    assert result == OfficialMlbResult(3.0, "42", "statcast-history")


def test_statcast_fallback_refuses_ambiguous_doubleheader(monkeypatch) -> None:
    class Cursor:
        def __enter__(self): return self
        def __exit__(self, *_args): return False
        def execute(self, _query, _params): pass
        def fetchall(self): return [(41, "single"), (42, "double")]
    class Connection:
        def __enter__(self): return self
        def __exit__(self, *_args): return False
        def cursor(self): return Cursor()
    class Pool:
        def connection(self): return Connection()
    monkeypatch.setattr(mlb_official_stats_service, "database_is_configured", lambda: True)
    monkeypatch.setattr(mlb_official_stats_service, "get_database_pool", lambda: Pool())
    monkeypatch.setattr(mlb_official_stats_service, "mlb_player_id", lambda _name: 123)
    assert mlb_official_stats_service.historical_mlb_result(
        player_name="Test Batter", market="Hits",
        game_start_time="2026-08-02T20:00:00Z",
    ) is None


def test_reconciliation_corrects_already_lost_slip(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(slip_service, "DATABASE_PATH", tmp_path / "slips.db")
    selectable_game_time = (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()
    request = SlipCreate(
        legs=[
            SlipLeg(
                prop_id="ranger",
                player="Ranger Suarez",
                sport="MLB",
                matchup="Toronto Blue Jays @ Boston Red Sox",
                sportsbook="Book",
                market="Pitcher Strikeouts",
                line=4,
                side="OVER",
                game_start_time=selectable_game_time,
            ),
            SlipLeg(
                prop_id="abbott",
                player="Andrew Abbott",
                sport="MLB",
                matchup="Cincinnati Reds @ St. Louis Cardinals",
                sportsbook="Book",
                market="Pitcher Strikeouts",
                line=4,
                side="OVER",
                game_start_time=selectable_game_time,
            ),
        ],
        stake=10,
    )
    slip = slip_service.create_slip(request, user_id="owner")
    slip_service.update_slip_results(
        [LegResultUpdate(prop_id="ranger", result_value=3)],
        user_id="owner",
    )
    assert slip_service.get_slips(user_id="owner")[0].status == "lost"

    values = {"Ranger Suarez": 6.0, "Andrew Abbott": 4.0}
    monkeypatch.setattr(
        result_reconciliation_service,
        "official_mlb_result",
        lambda **kwargs: OfficialMlbResult(values[kwargs["player_name"]], "42"),
    )
    summary = result_reconciliation_service.reconcile_user_slips(user_id="owner")
    corrected = slip_service.get_slips(user_id="owner")[0]
    assert summary["values_corrected"] == 2
    assert corrected.status == "active"
    assert [leg.result_status for leg in corrected.legs] == ["won", "push"]
    assert all(leg.result_verified for leg in corrected.legs)
    assert corrected.id == slip.id


def test_slip_leg_preserves_prediction_audit_snapshot() -> None:
    leg = SlipLeg(
        prop_id="audit",
        player="Pitcher",
        sport="MLB",
        matchup="A @ B",
        sportsbook="Book",
        market="Pitcher Strikeouts",
        line=4,
        side="OVER",
        projection=5.4,
        hit_probability=.63,
        confidence=63,
        projection_model_version="baseline-v2",
        projection_sample_size=20,
        projection_volatility=1.7,
        historical_hit_rate=60,
        calculation_inputs={"opponent_multiplier": 1.08},
    )
    restored = SlipLeg.model_validate(leg.model_dump())
    assert restored.projection == 5.4
    assert restored.hit_probability == .63
    assert restored.calculation_inputs["opponent_multiplier"] == 1.08
