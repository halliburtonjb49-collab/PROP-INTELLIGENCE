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
from services.prop_intelligence_service import analyze_prop
from services.projection_formula_service import blend_projection_with_market
from services.opportunity_gate_service import evaluate_opportunity_gate
from services.opportunity_projection_service import basketball_opportunities
from services.basketball_matchup_ingestion_service import enrich_basketball_matchups
from services.context_quality_service import evaluate_context_quality
from services.mlb_strikeout_enrichment_service import enrich_mlb_strikeout_props
from services.pregame_context_ingestion_service import apply_latest_pregame_context
from services.strikeout_quality_service import (
    build_explainability_snippet,
    evaluate_release_gate,
    get_strikeout_release_controls,
    strikeout_probability_adjustment,
)

logger = logging.getLogger(__name__)


def _apply_strikeout_release_gate(prop: object) -> bool:
    market_key_text = " ".join((
        str(getattr(prop, "marketKey", "") or ""),
        str(getattr(prop, "market", "") or ""),
        str(getattr(prop, "category", "") or ""),
    )).lower()
    if not (
        str(getattr(prop, "sport", "") or "").strip().upper() == "MLB"
        and "strikeout" in market_key_text
    ):
        return False

    controls = get_strikeout_release_controls()
    control_values = controls.get("controls") if isinstance(controls, dict) else None
    gate = evaluate_release_gate(
        prop,
        control_values if isinstance(control_values, dict) else None,
    )
    if not gate.blocked:
        return False
    reason = gate.reason or "strikeout_quality_gate_blocked"

    prop.recommendationAvailable = False
    prop.recommendationUnavailableReason = reason
    prop.recommendedSide = "N/A"
    prop.pick = "N/A"
    prop.pickText = "No Pick"
    prop.tier = "No Pick"
    prop.confidence = 0
    prop.isPositiveEv = False
    prop.opportunityStatus = "SYSTEM_LEAN"
    if gate.details:
        prop.opportunityReasons = list(gate.details)
    return True


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
    strikeout_analysis: dict[str, object] | None = None
    market_key_text = " ".join((
        str(getattr(prop, "marketKey", "") or ""),
        str(getattr(prop, "market", "") or ""),
        str(getattr(prop, "category", "") or ""),
    )).lower()
    is_mlb_strikeout = (
        str(getattr(prop, "sport", "") or "").strip().upper() == "MLB"
        and "strikeout" in market_key_text
    )
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
        prop.pickGrade = "C"
        prop.pickGradeExplanation = (
            "Pick remains visible, but the player is currently unavailable."
        )
        return
    context = ProjectionContext(
        workload_multiplier=(
            float(getattr(prop, "fatigueMultiplier", None) or 1)
            * float(getattr(prop, "usageMultiplier", None) or 1)
            * float(getattr(prop, "wowyMultiplier", None) or 1)
            * float(getattr(prop, "opportunityMultiplier", None) or 1)
        ),
        opponent_multiplier=(
            float(getattr(prop, "matchupMultiplier", None) or 1)
            * float(getattr(prop, "opponentDefenseMultiplier", None) or 1)
            * float(getattr(prop, "paceMultiplier", None) or 1)
            * float(getattr(prop, "gameScriptMultiplier", None) or 1)
        ),
        availability_multiplier=availability,
        venue_multiplier=float(getattr(prop, "homeAwayMultiplier", None) or 1),
    )
    adjusted = contextual_projection(float(projection), context)
    line = float(getattr(prop, "line", 0))

    if is_mlb_strikeout and projection is not None:
        strikeout_analysis = analyze_prop(
            player=str(getattr(prop, "player", "") or ""),
            sport=str(getattr(prop, "sport", "") or ""),
            market=str(getattr(prop, "marketKey", "") or getattr(prop, "market", "") or ""),
            line=line,
            projected_mean=float(projection),
            projected_std_dev=float(getattr(prop, "projectionVolatility", None) or 1.0),
            sharp_over_odds=getattr(prop, "overDecimalOdds", None),
            sharp_under_odds=getattr(prop, "underDecimalOdds", None),
            retail_over_odds=getattr(prop, "overDecimalOdds", None),
            retail_under_odds=getattr(prop, "underDecimalOdds", None),
            pitcher_k_pct=getattr(prop, "pitcherKPercent", None),
            lineup_k_pct=getattr(prop, "lineupKPercent", None),
            pitches_per_start=getattr(prop, "pitchesPerStart", None),
            pitches_per_batter=getattr(prop, "pitchesPerBatter", None),
            pitcher_csw=getattr(prop, "pitcherCsw", None),
            lineup_csw_against=getattr(prop, "lineupCswAgainst", None),
            temp_f=float(getattr(prop, "temperatureF", None) or 70.0),
            umpire_k_boost=float(getattr(prop, "umpireKBoost", None) or 0.0),
            park_k_factor=float(getattr(prop, "parkKFactor", None) or 1.0),
        )
        prop.strikeoutModelMethod = str(strikeout_analysis.get("method") or "")
        prop.strikeoutSkillSource = str(strikeout_analysis.get("skillSource") or "")
        prop.strikeoutProjectedBattersFaced = (
            int(strikeout_analysis["projectedBattersFaced"])
            if strikeout_analysis.get("projectedBattersFaced") is not None
            else None
        )
        prop.strikeoutUsedFallbackPitcherRate = bool(strikeout_analysis.get("usedFallbackPitcherRate"))
        prop.strikeoutUsedFallbackLineupRate = bool(strikeout_analysis.get("usedFallbackLineupRate"))
        prop.strikeoutUsedFallbackTbf = bool(strikeout_analysis.get("usedFallbackTbf"))
        prop.strikeoutUsedMarketBlend = bool(strikeout_analysis.get("usedMarketBlend"))
        prop.modelProbability = strikeout_analysis.get("modelOverProbability")
        prop.marketProbability = strikeout_analysis.get("marketOverProbability")
        prop.probabilityMarketWeight = float(strikeout_analysis.get("marketWeight") or 0.0)

    recommended = str((strikeout_analysis or {}).get("recommendation") or "").upper()
    side = (
        recommended
        if recommended in {"OVER", "UNDER"}
        else "OVER" if adjusted > line else "UNDER" if adjusted < line else "PASS"
    )
    prop.projection = adjusted
    prop.edgeSigned = round(adjusted - line, 4)
    prop.edge = round(abs(adjusted - line), 2)
    prop.recommendationEdge = prop.edge
    if side == "PASS":
        prop.recommendationAvailable = False
        prop.recommendedSide = "N/A"
        prop.pick = "N/A"
        prop.pickText = "No Pick"
        prop.pickGrade = "C"
        prop.pickGradeExplanation = (
            "Pick remains visible, but the projection does not separate from the line."
        )
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
    base_calibration_adjustment = float(evaluation.calibration_adjustment or 0.0)
    strikeout_adjustment = 0.0
    conservative_probability = max(
        0.0, min(1.0, probability - evaluation.uncertainty)
    )
    if is_mlb_strikeout:
        strikeout_adjustment = strikeout_probability_adjustment(side, conservative_probability)
        conservative_probability = max(0.0, min(1.0, conservative_probability + strikeout_adjustment))
        prop.recommendationExplanation = build_explainability_snippet(prop)
    prop.uncertaintyAdjustedProbability = round(conservative_probability, 6)
    prop.probabilityCalibrationAdjustment = round(base_calibration_adjustment + strikeout_adjustment, 6)
    calculated_confidence = confidence_from_probability(conservative_probability)
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
    if strikeout_analysis is not None:
        analysis_confidence = int(strikeout_analysis.get("confidence") or 0)
        if analysis_confidence > 0:
            prop.confidence = analysis_confidence
            prop.tier = (
                "Premium"
                if prop.confidence >= 65
                else "Strong"
                if prop.confidence >= 60
                else "Lean"
                if prop.confidence >= 57
                else "Pass"
            )
        prop.evPercentage = float(strikeout_analysis.get("expectedValuePercent") or prop.evPercentage or 0)
        prop.recommendationEdge = float(strikeout_analysis.get("edgePercent") or prop.recommendationEdge or 0)
        prop.edge = round(abs(prop.edgeSigned), 2) if prop.edgeSigned else prop.recommendationEdge
    if prop.tier == "Pass":
        prop.recommendationAvailable = False
        prop.isPositiveEv = False
        prop.pick = "N/A"
        prop.pickText = "No Pick"
    context_quality = evaluate_context_quality(prop)
    prop.contextDataQualityScore = context_quality.score
    prop.contextPresentFields = list(context_quality.present)
    prop.contextMissingFields = list(context_quality.missing)
    provider_quality = float(getattr(prop, "dataQualityScore", 0) or 0)
    combined_quality = provider_quality * .60 + context_quality.score * .40
    gate = evaluate_opportunity_gate(
        projection=float(getattr(prop, "projection", 0) or 0),
        line=line,
        volatility=getattr(prop, "projectionVolatility", None),
        probability=getattr(prop, "uncertaintyAdjustedProbability", None),
        sample_size=projection_sample_size,
        data_quality_score=combined_quality,
        injury_status=str(getattr(prop, "injuryStatus", "unknown")),
        lineup_status=str(getattr(prop, "lineupStatus", "unknown")),
        context_values=(
            getattr(prop, "usageMultiplier", None),
            getattr(prop, "opponentDefenseMultiplier", None),
            getattr(prop, "paceMultiplier", None),
            getattr(prop, "fatigueMultiplier", None),
            getattr(prop, "matchupMultiplier", None),
            getattr(prop, "opportunityMultiplier", None),
            getattr(prop, "wowyMultiplier", None),
            getattr(prop, "gameScriptMultiplier", None),
        ),
    )
    prop.opportunityScore = gate.score
    prop.opportunityStatus = gate.status
    prop.opportunityReasons = list(gate.reasons)
    prop.uncertaintyAdjustedEdge = gate.normalized_edge
    prop.pickGrade = gate.grade
    prop.pickGradeExplanation = gate.explanation
    if gate.adjusted_probability is not None:
        prop.uncertaintyAdjustedProbability = gate.adjusted_probability
        prop.confidence = confidence_from_probability(gate.adjusted_probability)
        if gate.actionable:
            prop.tier = (
                "Premium" if prop.confidence >= 65
                else "Strong" if prop.confidence >= 60
                else "Lean"
            )
    if not gate.actionable:
        prop.recommendationAvailable = False
        prop.recommendationUnavailableReason = gate.reasons[0]
        prop.recommendedSide = "N/A"
        prop.pick = "N/A"
        prop.pickText = "No Pick"
        prop.tier = "No Pick"
        prop.confidence = 0
    _apply_strikeout_release_gate(prop)


def enrich_props(props: list[object]) -> None:
    if not props:
        return
    if not database_is_configured():
        for prop in props:
            apply_projection_context(prop)
        return
    apply_latest_pregame_context(props)
    enrich_mlb_strikeout_props(props)
    enrich_basketball_matchups(props)
    player_ids = sorted({str(getattr(prop, "playerId", "")) for prop in props if getattr(prop, "playerId", "")})
    prop_ids = sorted({str(getattr(prop, "id", "")) for prop in props if getattr(prop, "id", "")})
    fatigue: dict[str, list[tuple[datetime, tuple[object, ...]]]] = {}
    sentiment: dict[str, tuple[object, ...]] = {}
    opportunities: dict[tuple[str, str], object] = {}
    for sport in {str(getattr(prop, "sport", "")).upper() for prop in props}:
        if sport not in {"NBA", "WNBA"}:
            continue
        names = sorted({str(getattr(prop, "player", "")) for prop in props if str(getattr(prop, "sport", "")).upper() == sport})
        for name, opportunity in basketball_opportunities(names, sport).items():
            opportunities[(sport, name)] = opportunity
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
        opportunity = opportunities.get((
            str(getattr(prop, "sport", "")).upper(),
            str(getattr(prop, "player", "")).lower(),
        ))
        if opportunity is not None:
            prop.projectedOpportunity = opportunity.projected_volume
            prop.opportunityUnit = opportunity.unit
            prop.opportunitySampleSize = opportunity.sample_size
            prop.opportunityVolatility = opportunity.volatility
            prop.opportunityMultiplier = opportunity.multiplier
            prop.opportunityConfidence = opportunity.confidence
            prop.opportunitySource = opportunity.source
            prop.roleStatus = opportunity.role
            prop.roleChange = opportunity.role_change
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
