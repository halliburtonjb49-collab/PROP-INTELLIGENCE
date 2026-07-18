from models.intelligence import (
    AlertCondition, CompoundAlertRequest, CorrelationRequest, FatigueRequest,
    GameScriptRequest, MatchupRequest, PropLegInput, SimilarityCandidate, SimilarityRequest, TravelLeg,
)
from services.intelligence_service import (
    correlation_matrix, derive_schedule_fatigue, evaluate_alert, fatigue_index, matchup_adjustment,
    similarity_matches, simulate_game_script,
)
from services.prediction_tracking_service import historical_features
from datetime import datetime, timedelta, timezone
from models.intelligence import HistoricalFeatureRequest, ScheduleFatigueRequest, ScheduleGame


def _leg(market: str, player: str = "Player", side: str = "OVER") -> PropLegInput:
    return PropLegInput(player=player, sport="NFL", game_id="game-1", market=market, side=side)


def test_fatigue_rises_with_travel_and_low_rest() -> None:
    rested = fatigue_index(FatigueRequest(rest_days=3))
    tired = fatigue_index(FatigueRequest(rest_days=0, consecutive_games=3,
        recent_minutes=[38, 40], travel_legs=[TravelLeg(miles=2400, timezone_change_hours=3, is_road_game=True)]))
    assert tired["score"] > rested["score"]
    assert tired["projectionMultiplier"] < rested["projectionMultiplier"]


def test_blitz_shifts_points_to_assists() -> None:
    points = matchup_adjustment(MatchupRequest(market="points", baseline=25, blitz_rate=.4))
    assists = matchup_adjustment(MatchupRequest(market="assists", baseline=8, blitz_rate=.4))
    assert points["multiplier"] < 1
    assert assists["multiplier"] > 1


def test_pass_and_receiver_overs_are_positive_correlation() -> None:
    result = correlation_matrix(CorrelationRequest(legs=[_leg("passing yards", "QB"), _leg("receiving yards", "WR")]))
    assert result["pairs"][0]["classification"] == "POSITIVE"


def test_similarity_returns_closest_stretch_and_projection() -> None:
    result = similarity_matches(SimilarityRequest(player="Current", recent_stretch=[10, 11, 12], candidates=[
        SimilarityCandidate(player="Close", stretch=[10, 11, 13], next_game_value=14),
        SimilarityCandidate(player="Far", stretch=[30, 32, 35], next_game_value=20)]))
    assert result["matches"][0]["player"] == "Close"
    assert result["analogNextGameProjection"] == 14


def test_compound_alert_requires_all_conditions() -> None:
    request = CompoundAlertRequest(name="Backup rebounds", snapshot={"starter_status": "OUT", "line": 7}, conditions=[
        AlertCondition(field="starter_status", operator="EQ", value="OUT"),
        AlertCondition(field="line", operator="LT", value=7.5)])
    assert evaluate_alert(request)["triggered"] is True


def test_monte_carlo_is_reproducible_and_prices_props() -> None:
    legs = [
        PropLegInput(player="QB", sport="NFL", game_id="g", market="passing yards",
                     side="OVER", baseline_projection=280, line=265.5, volatility=35),
        PropLegInput(player="WR", sport="NFL", game_id="g", market="receiving yards",
                     side="OVER", baseline_projection=85, line=74.5, volatility=14),
    ]
    request = GameScriptRequest(script="SHOOTOUT", sport="NFL", props=legs,
                                simulations=3000, seed=7)
    first = simulate_game_script(request)
    second = simulate_game_script(request)
    assert first == second
    assert first["method"] == "correlated-gaussian-monte-carlo"
    assert 0 < first["portfolioHitProbability"] < 1
    assert all(0 < impact["hitProbability"] < 1 for impact in first["impacts"])


def test_historical_features_recommend_calibrated_inputs() -> None:
    result = historical_features(HistoricalFeatureRequest(
        values=[18, 20, 21, 23, 24, 26], minutes=[30, 32, 32, 34, 35, 36], window=6))
    assert result["sampleSize"] == 6
    assert result["recommendedProjection"] > result["mean"]
    assert result["recommendedVolatility"] > 0
    assert result["perMinuteRate"] is not None


def test_schedule_derives_travel_and_fatigue() -> None:
    now = datetime(2026, 1, 3, 1, tzinfo=timezone.utc)
    request = ScheduleFatigueRequest(
        upcoming_game=ScheduleGame(starts_at=now, latitude=34.04, longitude=-118.27,
                                   utc_offset_hours=-8, is_road_game=True),
        previous_games=[ScheduleGame(starts_at=now - timedelta(hours=24), latitude=40.75,
                                     longitude=-73.99, utc_offset_hours=-5,
                                     is_road_game=True, minutes=39)],
    )
    result = derive_schedule_fatigue(request)
    assert result["travelMiles"] > 2000
    assert result["timezoneHours"] == 3
    assert result["score"] > 0
