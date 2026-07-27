"""Batch enrichment of live props with context backed by persisted observations."""

from __future__ import annotations

from datetime import datetime, timezone

from database.postgres import database_is_configured, get_database_pool
import logging
from services.projection_calibration_service import (
    ProjectionContext,
    calibrated_hit_probability,
    confidence_from_probability,
    contextual_projection,
)

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
        workload_multiplier=float(getattr(prop, "fatigueMultiplier", None) or 1),
        opponent_multiplier=float(getattr(prop, "matchupMultiplier", None) or 1),
        availability_multiplier=availability,
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
    probability = calibrated_hit_probability(
        projection=adjusted,
        line=line,
        volatility=float(getattr(prop, "projectionVolatility", None) or 1),
        side=side,
        sample_size=max(8, int(getattr(prop, "projectionSampleSize", 0) or 0)),
        sport=str(getattr(prop, "sport", "")),
        market=str(getattr(prop, "market", "")),
        empirical_hit_rate=(
            float(getattr(prop, "historicalHitRate")) / 100
            if getattr(prop, "historicalHitRate", None) is not None
            else None
        ),
    )
    prop.fairProbability = probability
    prop.confidence = confidence_from_probability(probability)
    prop.recommendedSide = side.title()
    prop.pick = side
    prop.pickText = f"{side.title()} {line:g}"
    prop.tier = (
        "Premium"
        if prop.confidence >= 65
        else "Strong"
        if prop.confidence >= 60
        else "Lean"
        if prop.confidence >= 57
        else "Pass"
    )
    if prop.tier == "Pass":
        prop.recommendationAvailable = False
        prop.pick = "N/A"
        prop.pickText = "No Pick"


def enrich_props(props: list[object]) -> None:
    if not props or not database_is_configured():
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
