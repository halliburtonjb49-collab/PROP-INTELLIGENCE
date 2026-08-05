from fastapi import APIRouter, Depends, HTTPException
from uuid import UUID

from models.intelligence import (
    AlertSnapshotRequest, CompoundAlertRequest, CorrelationRequest, DatabaseSimilarityRequest, FatigueRequest, GameScriptRequest,
    ContextResearchRequest, DixonColesRequest, HistoricalFeatureRequest, MatchupRequest, OfficiatingRequest, PropIntelligenceRequest,
    ScheduleFatigueRequest, WowyUsageRequest, ClosingLineValueRequest, PredictionGradeRequest, PredictionSnapshotRequest,
    SentimentBatchRequest, SentimentEvent, SimilarityRequest,
)
from services.intelligence_service import (
    correlation_matrix, derive_schedule_fatigue, evaluate_alert, fatigue_index, matchup_adjustment,
    officiating_adjustment, sentiment_score, similarity_matches, simulate_game_script,
)
from services.prediction_tracking_service import (
    calibration_summary, grade_prediction, historical_features, save_prediction,
)
from services.baseline_projection_service import MODEL_VERSION
from services.api_auth_service import require_pro, require_user_id
from services.compound_alert_service import create_alert, delete_alert, evaluate_user_alerts, list_alerts, list_deliveries
from routers.realtime import hub as realtime_hub
from services.engagement_service import record_engagement, sentiment_rollup
from services.vector_similarity_service import database_similarity
from services.officiating_profile_service import (
    get_officiating_profile,
    list_officiating_tracker,
)
from services.matchup_profile_service import get_matchup_profile
from services.context_research_service import context_research
from services.score_probability_service import dixon_coles_totals
from services.clv_service import closing_line_value
from services.wowy_usage_service import UsageTotals, analyze_wowy_usage
from services.model_performance_service import model_performance, operations_summary
from services.prop_intelligence_service import analyze_prop
from services.api_auth_service import require_admin

router = APIRouter(
    prefix="/api/intelligence",
    tags=["intelligence"],
    dependencies=[Depends(require_pro)],
)


@router.post("/fatigue")
def calculate_fatigue(request: FatigueRequest) -> dict[str, object]:
    return fatigue_index(request)


@router.post("/fatigue/from-schedule")
def calculate_schedule_fatigue(request: ScheduleFatigueRequest) -> dict[str, object]:
    return derive_schedule_fatigue(request)


@router.post("/officiating")
def calculate_officiating(request: OfficiatingRequest) -> dict[str, object]:
    return officiating_adjustment(request)


@router.get("/officiating/{sport}/{official_id}")
def get_automatic_officiating(sport: str, official_id: str, market: str = "strikeouts",
                              baseline: float = 0) -> dict[str, object]:
    profile = get_officiating_profile(sport, official_id)
    if profile is None:
        raise HTTPException(status_code=404, detail="Officiating profile not found")
    if sport.upper() == "MLB":
        adjustment = officiating_adjustment(OfficiatingRequest(
            sport="MLB", market=market, baseline=baseline,
            strike_zone_width_index=float(profile["tendencyIndex"])))
    else:
        adjustment = officiating_adjustment(OfficiatingRequest(
            sport="NBA", market=market, baseline=baseline,
            crew_whistle_rate_index=float(profile["tendencyIndex"])))
    return {"profile": profile, "adjustment": adjustment}


@router.get("/officiating-tracker")
def get_officiating_tracker(sport: str = "WNBA", limit: int = 100) -> dict[str, object]:
    return list_officiating_tracker(sport, limit)


@router.post("/matchup")
def calculate_matchup(request: MatchupRequest) -> dict[str, object]:
    return matchup_adjustment(request)


@router.post("/context-research")
def calculate_context_research(request: ContextResearchRequest) -> dict[str, object]:
    return context_research(request)


@router.post("/wowy-usage")
def calculate_wowy_usage(request: WowyUsageRequest) -> dict[str, object]:
    def totals(value: object) -> UsageTotals:
        return UsageTotals(**value.model_dump())

    return {
        "player": request.player,
        "teammate": request.teammate,
        "sport": request.sport,
        **analyze_wowy_usage(
            totals(request.on),
            totals(request.off),
            minimum_split_minutes=request.minimum_split_minutes,
        ),
        "disclosure": "WOWY is a bounded contextual input, not a standalone OVER/UNDER recommendation.",
    }


@router.post("/dixon-coles")
def calculate_dixon_coles(request: DixonColesRequest) -> dict[str, object]:
    return {
        "sport": request.sport,
        **dixon_coles_totals(
            request.home_expected_goals,
            request.away_expected_goals,
            request.rho,
            request.total_line,
            max_goals=request.max_goals,
        ),
        "disclosure": "Expected-goal inputs must come from a verified attack/defense model; they are not inferred from the sportsbook total.",
    }


@router.get("/matchup/{sport}/{team_id}")
def calculate_automatic_matchup(sport: str, team_id: str, season: str,
                                market: str = "points", baseline: float = 0) -> dict[str, object]:
    profile = get_matchup_profile(sport.upper(), team_id, season)
    if profile is None:
        raise HTTPException(status_code=404, detail="Matchup profile not found")
    adjustment = matchup_adjustment(MatchupRequest(
        market=market, baseline=baseline,
        blitz_rate=float(profile["pickRollPressureProxy"]),
        switch_rate=float(profile["switchRateProxy"]),
        defender_difficulty=float(profile["defenderDifficulty"])))
    return {"profile": profile, "adjustment": adjustment,
            "disclosure": "Pressure and switch values are inferred proxies, not observed coverage rates."}


@router.post("/correlations")
def calculate_correlations(request: CorrelationRequest) -> dict[str, object]:
    return correlation_matrix(request)


@router.post("/game-script")
def calculate_game_script(request: GameScriptRequest) -> dict[str, object]:
    return simulate_game_script(request)


@router.post("/similarity")
def calculate_similarity(request: SimilarityRequest) -> dict[str, object]:
    return similarity_matches(request)


@router.post("/similarity/database")
def calculate_database_similarity(request: DatabaseSimilarityRequest) -> dict[str, object]:
    return database_similarity(request)


@router.post("/sentiment")
def calculate_sentiment(events: list[SentimentEvent]) -> dict[str, object]:
    return sentiment_score([event.model_dump() for event in events])


@router.post("/engagement")
def save_engagement(request: SentimentBatchRequest,
                    user_id: str = Depends(require_user_id)) -> dict[str, object]:
    result = record_engagement(user_id, request.events)
    rollups = [sentiment_rollup(prop_id) for prop_id in result.get("propIds", [])]
    for rollup in rollups:
        realtime_hub.broadcast_from_thread(
            {"type": "sentiment.updated", "version": 1,
             "eventId": f"sentiment-{rollup['propId']}-{rollup.get('updatedAt', '')}",
             "occurredAt": rollup.get("updatedAt"), "data": rollup}, "sentiment")
    return {**result, "rollups": rollups}


@router.get("/sentiment/{prop_id}")
def get_prop_sentiment(prop_id: str, hours: int = 24) -> dict[str, object]:
    return sentiment_rollup(prop_id, max(1, min(hours, 168)))


@router.post("/alerts/evaluate")
def calculate_alert(request: CompoundAlertRequest) -> dict[str, object]:
    return evaluate_alert(request)


@router.post("/alerts")
def save_compound_alert(request: CompoundAlertRequest,
                        user_id: str = Depends(require_user_id)) -> dict[str, object]:
    return create_alert(user_id, request)


@router.get("/alerts")
def get_compound_alerts(user_id: str = Depends(require_user_id)) -> dict[str, object]:
    alerts = list_alerts(user_id)
    return {"count": len(alerts), "alerts": alerts}


@router.get("/alerts/deliveries")
def get_alert_deliveries(limit: int = 50, user_id: str = Depends(require_user_id)) -> dict[str, object]:
    deliveries = list_deliveries(user_id, max(1, min(limit, 100)))
    return {"count": len(deliveries), "deliveries": deliveries}


@router.delete("/alerts/{alert_id}")
def remove_compound_alert(alert_id: UUID, user_id: str = Depends(require_user_id)) -> dict[str, object]:
    if not delete_alert(user_id, alert_id):
        raise HTTPException(status_code=404, detail="Alert not found")
    return {"deleted": True, "id": str(alert_id)}


@router.post("/alerts/evaluate-snapshot")
def evaluate_saved_alerts(request: AlertSnapshotRequest,
                          user_id: str = Depends(require_user_id)) -> dict[str, object]:
    deliveries = evaluate_user_alerts(user_id, request.snapshot)
    for delivery in deliveries:
        realtime_hub.broadcast_user_from_thread(
            {"type": "alert.triggered", "version": 1, "eventId": delivery["id"],
             "occurredAt": delivery["deliveredAt"], "data": delivery}, "alerts", user_id)
    return {"count": len(deliveries), "deliveries": deliveries}


@router.post("/historical-features")
def calculate_historical_features(request: HistoricalFeatureRequest) -> dict[str, object]:
    return historical_features(request)


@router.post("/predictions")
def create_prediction_snapshot(request: PredictionSnapshotRequest) -> dict[str, object]:
    return save_prediction(request)


@router.post("/predictions/{prediction_id}/grade")
def grade_prediction_snapshot(prediction_id: UUID, request: PredictionGradeRequest) -> dict[str, object]:
    return grade_prediction(prediction_id, request.actual_value)


@router.get("/calibration")
def get_calibration(model_version: str = MODEL_VERSION) -> dict[str, object]:
    return calibration_summary(model_version)


@router.get("/performance")
def get_model_performance(model_version: str = MODEL_VERSION) -> dict[str, object]:
    return model_performance(model_version)


@router.get("/operations")
def get_operations_summary(_admin: str = Depends(require_admin)) -> dict[str, object]:
    return operations_summary()


@router.post("/closing-line-value")
def calculate_closing_line_value(request: ClosingLineValueRequest) -> dict[str, object]:
    return closing_line_value(request)


@router.post("/prop-analysis")
def analyze_prop_intelligence(request: PropIntelligenceRequest) -> dict[str, object]:
    return analyze_prop(
        player=request.player,
        sport=request.sport,
        market=request.market,
        line=request.line,
        projected_mean=request.projected_mean,
        projected_std_dev=request.projected_std_dev,
        sharp_over_odds=request.sharp_over_odds,
        sharp_under_odds=request.sharp_under_odds,
        retail_over_odds=request.retail_over_odds,
        retail_under_odds=request.retail_under_odds,
        bankroll=request.bankroll,
        kelly_fraction=request.kelly_fraction,
        simulations=request.simulations,
        seed=request.seed,
        pitcher_k_pct=request.pitcher_k_pct,
        lineup_k_pct=request.lineup_k_pct,
        pitches_per_start=request.pitches_per_start,
        pitches_per_batter=request.pitches_per_batter,
        pitcher_csw=request.pitcher_csw,
        lineup_csw_against=request.lineup_csw_against,
        temp_f=request.temp_f,
        umpire_k_boost=request.umpire_k_boost,
        park_k_factor=request.park_k_factor,
        league_avg_k_rate=request.league_avg_k_rate,
        league_avg_csw=request.league_avg_csw,
    )


@router.get("/capabilities")
def capabilities() -> dict[str, object]:
    return {"features": ["fatigue", "officiating", "matchup", "correlations",
                         "gameScript", "similarity", "sentiment", "compoundAlerts",
                         "historicalFeatures", "predictionTracking", "calibration",
                         "closingLineValue", "contextResearch", "statSlam",
                         "restSplits", "shinDevig", "dixonColes"],
            "version": "1.5.0", "explainable": True}
