from datetime import datetime, timedelta, timezone

from models.slip import LegResultUpdate, SlipCreate, SlipLeg
from services import mlb_official_stats_service, result_reconciliation_service, slip_service
from services.mlb_official_stats_service import OfficialMlbResult


def test_official_mlb_result_resolves_final_game_and_pitcher_stat(monkeypatch) -> None:
    def fake_get(path, params=None):
        if path == "/v1/schedule":
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
    assert corrected.status == "won"
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
