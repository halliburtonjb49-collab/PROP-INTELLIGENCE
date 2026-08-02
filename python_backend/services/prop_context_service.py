"""Batch enrichment of live props with context backed by persisted observations."""

from __future__ import annotations

from datetime import datetime, timezone

from database.postgres import database_is_configured, get_database_pool
import logging
from services.projection_calibration_service import (
    ProjectionContext,
    confidence_from_probability,
    contextual_projection,
)
from services.prop_probability_service import evaluate_market
from services.projection_formula_service import blend_projection_with_market
from services.opportunity_gate_service import evaluate_opportunity_gate

logger = logging.getLogger(__name__)


def _availability_multiplier(injury_status: object, lineup_status: object) -> float:
    injury = str(injury_status or "").strip().lower()
    lineup = str(lineup_status or "").strip().lower()
    if injury in {"out", "inactive", "injured reserve"} or lineup in {
        "out",
        "inactive",
    }:
        return 0.0
    if injury in {"doubtful"}:
        return 0.82
    if injury in {"questionable", "day-to-day", "probable"}:
        return 0.96
    return 1.0


def apply_projection_context(prop: object) -> None:
    projection = getattr(prop, "projection", None)
    if projection is None:
        return
    blend = blend_projection_with_market(
        custom_projection=float(projection),
        market_origin_line=getattr(prop, "marketOriginLine", None),
        market_book_count=int(getattr(prop, "marketBookCount", 0) or 0),
        sample_size=int(getattr(prop, "projectionSampleSize", 0) or 0),
        calibrated=bool(getattr(prop, "projectionCalibrated", False)),
    )
    prop.projectionPreMarket = float(projection)
    prop.projectionMarketWeight = blend.market_weight
    projection = blend.projection
    availability = _availability_multiplier(
        getattr(prop, "injuryStatus", ""),
        getattr(prop, "lineupStatus", ""),
    )
    if availability == 0:
        prop.recommendationAvailable = False
        prop.recommendationUnavailableReason = "player_unavailable"
        prop.recommendedSide = "N/A"
        prop.pick = "N/A"
        prop.pickText = "No Pick"
        prop.confidence = 0
        return
    context = ProjectionContext(
        workload_multiplier=(
            float(getattr(prop, "fatigueMultiplier", None) or 1)
            * float(getattr(prop, "usageMultiplier", None) or 1)
        ),
        opponent_multiplier=(
            float(getattr(prop, "matchupMultiplier", None) or 1)
            * float(getattr(prop, "opponentDefenseMultiplier", None) or 1)
            * float(getattr(prop, "paceMultiplier", None) or 1)
        ),
        availability_multiplier=availability,
        venue_multiplier=float(getattr(prop, "homeAwayMultiplier", None) or 1),
    )
    adjusted = contextual_projection(float(projection), context)
    line = float(getattr(prop, "line", 0))
    side = "OVER" if adjusted > line else "UNDER" if adjusted < line else "PASS"
    prop.projection = adjusted
    prop.edgeSigned = round(adjusted - line, 4)
    prop.edge = round(abs(adjusted - line), 2)
    prop.recommendationEdge = prop.edge
    if side == "PASS":
        prop.recommendationAvailable = False
        prop.recommendedSide = "N/A"
        prop.pick = "N/A"
        prop.pickText = "No Pick"
        return
    over_side = side == "OVER"
    projection_sample_size = max(
        0, int(getattr(prop, "projectionSampleSize", 0) or 0)
    )
    evaluation = evaluate_market(
        projection=adjusted,
        line=line,
        volatility=float(getattr(prop, "projectionVolatility", None) or 1),
        side=side,
        sample_size=max(1, projection_sample_size),
        sport=str(getattr(prop, "sport", "")),
        market=str(getattr(prop, "market", "")),
        model_calibrated=bool(getattr(prop, "projectionCalibrated", False)),
        empirical_hit_rate=(
            float(getattr(prop, "historicalHitRate")) / 100
            if getattr(prop, "historicalHitRate", None) is not None
            else None
        ),
        sharp_probability=(
            getattr(prop, "noVigOverProbability", None)
            if over_side
            else getattr(prop, "noVigUnderProbability", None)
        ),
        decimal_odds=(
            getattr(prop, "overDecimalOdds", None)
            if over_side
            else getattr(prop, "underDecimalOdds", None)
        ),
        calibration_adjustment=float(
            getattr(prop, "probabilityCalibrationAdjustment", 0) or 0
        ),
    )
    probability = evaluation.fair_probability
    prop.fairProbability = probability
    prop.modelProbability = evaluation.model_probability
    prop.marketProbability = evaluation.market_probability
    prop.pushProbability = evaluation.push_probability
    prop.lossProbability = evaluation.loss_probability
    prop.evPercentage = evaluation.ev_percentage
    prop.fairDecimalOdds = evaluation.fair_decimal_odds
    prop.isPositiveEv = evaluation.is_positive_ev
    prop.probabilityMethod = evaluation.distribution
    prop.probabilityMarketWeight = evaluation.market_weight
    prop.probabilityUncertainty = evaluation.uncertainty
    prop.probabilityCalibrationAdjustment = evaluation.calibration_adjustment
    calculated_confidence = confidence_from_probability(probability)
    prop.recommendedSide = side.title()
    prop.pick = side
    prop.pickText = f"{side.title()} {line:g}"
    # A missing sample count means the context layer has no new evidence with
    # which to replace the recommendation already verified by prop_service.
    # Treating the missing value as a one-game sample collapses every
    # probability toward 50% and incorrectly turns the whole board into PASS.
    existing_confidence = int(getattr(prop, "confidence", 0) or 0)
    existing_tier = str(getattr(prop, "tier", "") or "").strip()
    if projection_sample_size > 0 or existing_confidence <= 0:
        prop.confidence = calculated_confidence
        prop.tier = (
            "Premium"
            if prop.confidence >= 65
            else "Strong"
            if prop.confidence >= 60
            else "Lean"
            if prop.confidence >= 57
            else "Pass"
        )
    else:
        prop.confidence = existing_confidence
        prop.tier = existing_tier or "No Pick"
    if prop.tier == "Pass":
        prop.recommendationAvailable = False
        prop.isPositiveEv = False
        prop.pick = "N/A"
        prop.pickText = "No Pick"
    gate = evaluate_opportunity_gate(
        projection=float(getattr(prop, "projection", 0) or 0),
        line=line,
        volatility=getattr(prop, "projectionVolatility", None),
        probability=getattr(prop, "fairProbability", None),
        sample_size=projection_sample_size,
        data_quality_score=float(getattr(prop, "dataQualityScore", 0) or 0),
        injury_status=str(getattr(prop, "injuryStatus", "unknown")),
        lineup_status=str(getattr(prop, "lineupStatus", "unknown")),
        context_values=(
            getattr(prop, "usageMultiplier", None),
            getattr(prop, "opponentDefenseMultiplier", None),
            getattr(prop, "paceMultiplier", None),
            getattr(prop, "fatigueMultiplier", None),
        ),
    )
    prop.opportunityScore = gate.score
    prop.opportunityStatus = gate.status
    prop.opportunityReasons = list(gate.reasons)
    prop.uncertaintyAdjustedEdge = gate.normalized_edge
    if not gate.actionable:
        prop.recommendationAvailable = False
        prop.recommendationUnavailableReason = gate.reasons[0]
        prop.recommendedSide = "N/A"
        prop.pick = "N/A"
        prop.pickText = "No Pick"
        prop.tier = "No Pick"


def enrich_props(props: list[object]) -> None:
    if not props:
        return
    if not database_is_configured():
        for prop in props:
            apply_projection_context(prop)
        return
    player_ids = sorted({str(getattr(prop, "playerId", "")) for prop in props if getattr(prop, "playerId", "")})
    prop_ids = sorted({str(getattr(prop, "id", "")) for prop in props if getattr(prop, "id", "")})
    fatigue: dict[str, list[tuple[datetime, tuple[object, ...]]]] = {}
    sentiment: dict[str, tuple[object, ...]] = {}
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            if player_ids:
                cursor.execute("""select f.player_id,s.starts_at,f.fatigue_score,f.projection_multiplier,
                f.travel_miles,f.timezone_change_hours,f.rest_days,f.consecutive_road_games
                from player_fatigue_features f join team_schedule s on s.id=f.game_id
                where f.player_id=any(%s) and s.starts_at between now()-interval '1 day' and now()+interval '14 days'""",
                    (player_ids,))
                for row in cursor.fetchall():
                    fatigue.setdefault(str(row[0]), []).append((row[1], row[2:]))
            if prop_ids:
                cursor.execute("""select prop_id,count(*),
                sum(case action when 'VIEW' then 1 when 'SEARCH' then 1.5 when 'CLICK' then 2
                    when 'WATCHLIST' then 4 when 'PICK_OVER' then 5 when 'PICK_UNDER' then -5 else 0 end)
                from prop_engagement_events where prop_id=any(%s) and created_at>=now()-interval '24 hours'
                group by prop_id""", (prop_ids,))
                sentiment = {str(row[0]): row[1:] for row in cursor.fetchall()}
    except Exception as exc:
        logger.warning("prop context unavailable: %s", exc)
        for prop in props:
            apply_projection_context(prop)
        return

    for prop in props:
        start_raw = str(getattr(prop, "startTimeUtc", ""))
        try:
            start = datetime.fromisoformat(start_raw.replace("Z", "+00:00"))
            if start.tzinfo is None:
                start = start.replace(tzinfo=timezone.utc)
        except ValueError:
            start = datetime.now(timezone.utc)
        candidates = fatigue.get(str(getattr(prop, "playerId", "")), [])
        if candidates:
            _, values = min(candidates, key=lambda candidate: abs((candidate[0] - start).total_seconds()))
            score, multiplier, miles, zones, rest_days, road_games = values
            prop.fatigueIndex = float(score)
            prop.fatigueMultiplier = float(multiplier)
            prop.restDays = float(rest_days)
            prop.travelMiles = float(miles)
            prop.timezoneChangeHours = float(zones)
            prop.matchupContext = (
                f"{float(rest_days):g} rest days, {round(float(miles)):,} travel miles, "
                f"{int(road_games)} consecutive road games"
            )
        rollup = sentiment.get(str(getattr(prop, "id", "")))
        if rollup:
            count, raw_score = int(rollup[0]), float(rollup[1] or 0)
            score = max(-100.0, min(100.0, raw_score))
            prop.sentimentSampleSize = count
            prop.sentimentScore = round(score, 1)
            prop.sentimentLabel = "FOLLOW" if score >= 15 else "FADE" if score <= -15 else "NEUTRAL"
        apply_projection_context(prop)
