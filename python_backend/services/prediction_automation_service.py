"""Create daily model snapshots from live props and grade completed basketball games."""

from __future__ import annotations

import json
from collections import Counter
from datetime import datetime, timezone
from math import sqrt
from threading import Lock

from database.postgres import database_is_configured, get_database_pool
from services.prop_service import get_props
from services.baseline_projection_service import MODEL_VERSION
from services.mlb_official_stats_service import historical_mlb_result, official_mlb_result
# The thresholds come from the module that defines the tiers, so this
# measurement can never grade a boundary the board no longer uses.
from services.prop_recommendation_service import (
    ACTIONABLE_CONFIDENCE_FLOOR,
    PREMIUM_CONFIDENCE_FLOOR,
)
from services.live_stats_service import (
    STAT_MAP,
    get_live_player_stat_snapshot,
    normalize_prop_type,
)
from services.clv_service import odds_clv_expected_value, vig_free_probability

TRACKED_SPORTS = {
    "NBA", "WNBA", "MLB", "NFL", "NHL", "SOCCER", "CFL",
}


def _specialty_market_value(sport: str, market: str, stats: object) -> float | None:
    if not isinstance(stats, dict):
        return None
    text = normalize_prop_type(market).lower().replace("_", " ")
    canonical_sport = "PGA" if sport == "GOLF" else "UFC" if sport == "MMA" else sport
    mappings = {
        "TENNIS": (
            (("double fault",), "double_faults"),
            (("breakpoint",), "breakpoints_won"),
            (("ace",), "aces"),
            (("set",), "sets_won"),
            (("game",), "games_won"),
        ),
        "PGA": (
            (("birdie",), "birdies"), (("bogey",), "bogeys"),
            (("par",), "pars"), (("eagle",), "eagles"),
            (("stroke", "round score"), "round_score"),
        ),
        "UFC": (
            (("significant strike",), "significant_strikes"),
            (("total strike",), "total_strikes"),
            (("takedown",), "takedowns"), (("knockdown",), "knockdowns"),
            (("submission",), "submission_attempts"),
            (("fight time",), "fight_time_seconds"),
        ),
        "SOCCER": (
            (("shot on target", "shots on target"), "shots_on_target"),
            (("shot",), "shots"), (("assist",), "assists"),
            (("goal",), "goals"), (("red card",), "received_red_card"),
            (("card",), "received_card"),
        ),
    }
    for tokens, stat_name in mappings.get(canonical_sport, ()):
        if any(token in text for token in tokens):
            try:
                return float(stats.get(stat_name))
            except (TypeError, ValueError):
                return None
    return None


def _snapshot_side(
    recommended_side: str,
    projection: float | None,
    line: float,
) -> str:
    side = recommended_side.upper()
    if side in {"OVER", "UNDER"}:
        return side
    if projection is None or projection == line:
        return ""
    return "OVER" if projection > line else "UNDER"


def _paper_trade_eligible(grade: str) -> bool:
    return grade.upper() in {"A", "B"}


def prediction_clv(side: str, entry_line: float, closing_line: float) -> dict[str, object]:
    movement = (
        closing_line - entry_line
        if side.upper() == "OVER"
        else entry_line - closing_line
    )
    return {
        "closingLine": closing_line,
        "lineClvPoints": round(movement, 4),
        "beatClosingLine": movement > 0,
    }


def capture_prediction_closing_lines() -> dict[str, object]:
    """Attach the latest pregame line to auditable model snapshots."""
    if not database_is_configured():
        return {"updated": 0, "reason": "DATABASE_URL is not configured"}
    props = {prop.id: prop for prop in get_props() if not prop.dataStale}
    updated = 0
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select id,prop_id,side,line from prediction_snapshots
            where event_time > now() and event_time <= now() + interval '20 minutes'
            and graded_at is null"""
        )
        for identifier, prop_id, side, entry_line in cursor.fetchall():
            prop = props.get(str(prop_id))
            if prop is None:
                continue
            closing_line = float(prop.currentLine or prop.line)
            clv = prediction_clv(str(side), float(entry_line), closing_line)
            side_upper = str(side).upper()
            closing_side_odds = prop.overOdds if side_upper == "OVER" else prop.underOdds
            closing_opposite_odds = prop.underOdds if side_upper == "OVER" else prop.overOdds
            odds_clv: dict[str, object] = {}
            cursor.execute("select inputs->>'entryOdds' from prediction_snapshots where id=%s", (identifier,))
            entry_odds_raw = cursor.fetchone()[0]
            if entry_odds_raw and closing_side_odds and closing_opposite_odds:
                entry_odds = int(float(entry_odds_raw))
                side_close = int(float(closing_side_odds))
                opposite_close = int(float(closing_opposite_odds))
                odds_clv = {
                    "closingOdds": side_close,
                    "closingOppositeOdds": opposite_close,
                    "closingNoVigProbability": round(
                        vig_free_probability(side_close, opposite_close), 6
                    ),
                    "oddsClvExpectedValuePercent": round(
                        odds_clv_expected_value(entry_odds, side_close, opposite_close) * 100,
                        4,
                    ),
                    "oddsClvMethod": "proportional-no-vig",
                }
            cursor.execute(
                """update prediction_snapshots set inputs=inputs || %s::jsonb
                where id=%s""",
                (json.dumps({**clv, **odds_clv}), identifier),
            )
            updated += 1
        connection.commit()
    return {"updated": updated}


def snapshot_probability(prop: object) -> tuple[float, str]:
    """The number recorded as hit_probability, and where it came from.

    Extracted so the diagnostic below cannot drift from what is actually
    written. The fallback is the reason this exists: confidence is not a
    probability, and storing it as one makes every later measurement -- win
    rate by tier, calibration, closing-line value -- a statement about a
    quantity nobody modelled.
    """

    value = getattr(prop, "uncertaintyAdjustedProbability", None)
    if value is not None:
        return float(value), "uncertaintyAdjusted"
    value = getattr(prop, "fairProbability", None)
    if value is not None:
        return float(value), "fair"
    confidence = float(getattr(prop, "confidence", 0) or 0)
    return max(.5, min(.95, confidence / 100)), "confidenceFallback"


# What the last snapshot run actually recorded, by source and by tier.
#
# Accumulated while that run is already walking the props rather than
# recomputed on demand: reading it used to call get_props() inline on the
# operations endpoint, which walks thousands of props and took the request
# past the proxy timeout, so the one page meant to explain failures became a
# 502 itself.
_probability_source_lock = Lock()
_probability_sources: dict[str, int] = {}
_probability_tiers: dict[str, int] = {}
_probability_skipped: dict[str, int] = {}
_probability_observed_at = ""


def _record_probability_source(probability: float, source: str) -> None:
    with _probability_source_lock:
        _probability_sources[source] = _probability_sources.get(source, 0) + 1
        tier = (
            "HIGH" if probability >= .7
            else "MEDIUM" if probability >= .6
            else "BASELINE"
        )
        _probability_tiers[tier] = _probability_tiers.get(tier, 0) + 1


_PROBABILITY_SOURCES_KEY = "diagnostics:snapshot-probability-sources"
_PROBABILITY_SOURCES_TTL_SECONDS = 60 * 60 * 24


def _publish_probability_sources() -> None:
    """Share this instance's view so any other can report it.

    The snapshot runs on the worker and the operations endpoint is answered
    by the web instance. Process memory cannot cross that gap -- the sport
    counters learned this the hard way and left every sport reading as never
    fetched, and holding these counts in module state repeated it exactly:
    the distribution read back empty while the run that produced it had
    already finished somewhere else.
    """

    try:
        from services.distributed_cache_service import set_json

        with _probability_source_lock:
            payload = {
                "observedAt": _probability_observed_at,
                "sources": dict(_probability_sources),
                "tiers": dict(_probability_tiers),
                "skipped": dict(_probability_skipped),
            }
        set_json(
            _PROBABILITY_SOURCES_KEY,
            payload,
            ttl_seconds=_PROBABILITY_SOURCES_TTL_SECONDS,
        )
    except Exception as exc:
        # Never breaks the run, but never silent either.
        logger.warning("probability source publish failed error=%s", exc)


def _read_probability_sources() -> dict[str, object]:
    try:
        from services.distributed_cache_service import get_json

        value = get_json(_PROBABILITY_SOURCES_KEY)
    except Exception:
        return {}
    return value if isinstance(value, dict) else {}


def snapshot_probability_sources() -> dict[str, object]:
    """Which source the last snapshot run drew from, and which tier it hit.

    409 graded picks landed 408 in BASELINE while the board showed props at
    58 to 74 percent. Either the board and the record disagree about what a
    probability is, or about which props get one. This says which, without
    needing database access to find out.
    """

    with _probability_source_lock:
        local = {
            "observedAt": _probability_observed_at,
            "sources": dict(_probability_sources),
            "tiers": dict(_probability_tiers),
            # Not written, and why. A record that shrank must be able to say
            # it was pruned rather than look like a feed that dried up.
            "skipped": dict(_probability_skipped),
        }
    shared = _read_probability_sources()
    # Prefer whichever view has actually seen a run, so the web instance
    # reports the worker's observation rather than its own blank slate.
    chosen = local if local["sources"] or not shared else shared
    sources = chosen.get("sources") or {}
    return {
        "observedAt": chosen.get("observedAt") or "",
        "props": sum(int(value) for value in sources.values()),
        "sources": sources,
        "tiers": chosen.get("tiers") or {},
        "skipped": chosen.get("skipped") or {},
    }


def snapshot_live_predictions(model_version: str = MODEL_VERSION) -> dict[str, object]:
    if not database_is_configured():
        return {"created": 0, "reason": "DATABASE_URL is not configured"}
    created = 0
    skipped_without_probability = 0
    global _probability_observed_at
    with _probability_source_lock:
        _probability_sources.clear()
        _probability_tiers.clear()
        _probability_skipped.clear()
        _probability_observed_at = datetime.now(timezone.utc).isoformat()
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        # Snapshotting used to issue this existence check once per live prop.
        # A normal board contains more than ten thousand rows, so an otherwise
        # no-op repeat sync spent minutes making thousands of database round
        # trips. Fetch today's keys once and keep the same append-only behavior
        # with an in-memory membership test.
        cursor.execute(
            """select prop_id,model_version from prediction_snapshots
               where snapshot_date=(now() at time zone 'UTC')::date"""
        )
        existing_snapshots = {
            (str(prop_id), str(existing_model_version))
            for prop_id, existing_model_version in cursor.fetchall()
        }
        for prop in get_props():
            if prop.dataStale:
                continue
            snapshot_model_version = prop.projectionModelVersion or model_version
            side = _snapshot_side(prop.recommendedSide, prop.projection, prop.line)
            if prop.sport.upper() not in TRACKED_SPORTS:
                continue
            if side not in {"OVER", "UNDER"} or not prop.startTimeUtc:
                continue
            try:
                event_time = datetime.fromisoformat(prop.startTimeUtc.replace("Z", "+00:00"))
                if event_time.tzinfo is None:
                    event_time = event_time.replace(tzinfo=timezone.utc)
            except ValueError:
                continue
            if event_time <= datetime.now(timezone.utc):
                continue
            projection = prop.projection
            if projection is None:
                signed = prop.edgeSigned or (prop.recommendationEdge if side == "OVER" else -prop.recommendationEdge)
                projection = prop.line + signed
            probability, probability_source = snapshot_probability(prop)
            _record_probability_source(probability, probability_source)
            # A prop the model produced no probability for is not a model
            # prediction, and recording confidence in the probability column
            # does not make it one. Every measurement downstream -- win rate
            # by tier, calibration, closing-line value -- reads that column
            # as a modelled probability, so a placeholder there does not
            # merely add noise, it changes what those numbers are about.
            #
            # Skipping costs sample size. Keeping costs the meaning of the
            # sample, which is the more expensive of the two: a smaller
            # honest record can be acted on and a large meaningless one
            # cannot.
            if probability_source == "confidenceFallback":
                skipped_without_probability += 1
                with _probability_source_lock:
                    _probability_skipped["confidenceFallback"] = (
                        _probability_skipped.get("confidenceFallback", 0) + 1
                    )
                continue
            snapshot_key = (str(prop.id), str(snapshot_model_version))
            if snapshot_key in existing_snapshots:
                continue
            cursor.execute("""insert into prediction_snapshots
                (prop_id,player_id,sport,market,side,line,projection,hit_probability,
                 model_version,inputs,event_time) values(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb,%s)
                 returning id""",
                (prop.id, prop.canonicalPlayerId or prop.playerId, prop.sport.upper(), prop.market,
                 side, prop.line, projection, probability, snapshot_model_version,
                 json.dumps({"playerName": prop.player, "sportsbook": prop.sportsbook,
                             "eventId": prop.eventId,
                             "marketKey": prop.marketKey,
                             "probabilitySource": probability_source,
                             "commenceTime": prop.startTimeUtc,
                             "matchup": prop.matchup, "confidence": prop.confidence,
                             "edge": prop.recommendationEdge,
                             "modelProbability": prop.modelProbability,
                             "marketProbability": prop.marketProbability,
                             "pushProbability": prop.pushProbability,
                             "probabilityMethod": prop.probabilityMethod,
                             "marketBlendWeight": prop.probabilityMarketWeight,
                             "calibrationAdjustment": prop.probabilityCalibrationAdjustment,
                             "calibrationSampleSize": prop.probabilityCalibrationSampleSize,
                             "projectedOpportunity": prop.projectedOpportunity,
                             "opportunityUnit": prop.opportunityUnit,
                             "opportunitySampleSize": prop.opportunitySampleSize,
                             "opportunityVolatility": prop.opportunityVolatility,
                             "opportunityMultiplier": prop.opportunityMultiplier,
                             "opportunityConfidence": prop.opportunityConfidence,
                             "opportunitySource": prop.opportunitySource,
                             "roleStatus": prop.roleStatus,
                             "roleChange": prop.roleChange,
                             "wowyMultiplier": prop.wowyMultiplier,
                             "gameScriptMultiplier": prop.gameScriptMultiplier,
                             "projectedMinutes": prop.projectedMinutes,
                             "projectionSampleSize": prop.projectionSampleSize,
                             "projectionVolatility": prop.projectionVolatility,
                             "projectionSource": prop.projectionSource,
                             "injuryStatus": prop.injuryStatus,
                             "lineupStatus": prop.lineupStatus,
                             "pregameAvailability": prop.pregameAvailability,
                             "matchupContext": prop.matchupContext,
                             "matchupMultiplier": prop.matchupMultiplier,
                             "usageMultiplier": prop.usageMultiplier,
                             "homeAwayMultiplier": prop.homeAwayMultiplier,
                             "lastUpdatedUtc": prop.lastUpdatedUtc,
                             "sourceUpdatedUtc": prop.sourceUpdatedUtc,
                             "dataAgeSeconds": prop.dataAgeSeconds,
                             "dataQualityScore": prop.dataQualityScore,
                             "dataQualityReasons": prop.dataQualityReasons,
                             "recommendationExplanation": prop.recommendationExplanation,
                             "recommendationExplainability": prop.recommendationExplainability,
                             "researchCapsule": prop.researchCapsule,
                             "pickGrade": prop.pickGrade,
                             "pickGradeExplanation": prop.pickGradeExplanation,
                             "expectedValuePercentage": prop.evPercentage,
                             "entryOdds": prop.overOdds if side == "OVER" else prop.underOdds,
                             "openingLine": prop.openingLine,
                             "currentLine": prop.currentLine,
                             "strikeoutModelMethod": getattr(prop, "strikeoutModelMethod", ""),
                             "strikeoutSkillSource": getattr(prop, "strikeoutSkillSource", ""),
                             "strikeoutProjectedBattersFaced": getattr(prop, "strikeoutProjectedBattersFaced", None),
                             "strikeoutUsedFallbackPitcherRate": getattr(prop, "strikeoutUsedFallbackPitcherRate", False),
                             "strikeoutUsedFallbackLineupRate": getattr(prop, "strikeoutUsedFallbackLineupRate", False),
                             "strikeoutUsedFallbackTbf": getattr(prop, "strikeoutUsedFallbackTbf", False),
                             "strikeoutUsedMarketBlend": getattr(prop, "strikeoutUsedMarketBlend", False),
                             "strikeoutExplainability": getattr(prop, "recommendationExplanation", "")} ), event_time))
            snapshot_id = cursor.fetchone()[0]
            feature_payload = {
                "opponentAllowanceByPosition": getattr(prop, "opponentAllowanceByPosition", None),
                "opponentAllowanceLeagueAverage": getattr(prop, "opponentAllowanceLeagueAverage", None),
                "opponentPosition": getattr(prop, "opponentPosition", ""),
                "defensiveScheme": getattr(prop, "defensiveScheme", ""),
                "paceMultiplier": prop.paceMultiplier,
                "directMatchupAverage": getattr(prop, "directMatchupAverage", None),
                "directMatchupSampleSize": getattr(prop, "directMatchupSampleSize", 0),
                "expectedPrimaryDefender": getattr(prop, "expectedPrimaryDefender", ""),
                "expectedPrimaryDefenderConfidence": getattr(prop, "expectedPrimaryDefenderConfidence", None),
                "expectedPrimaryDefenderSampleSize": getattr(prop, "expectedPrimaryDefenderSampleSize", None),
                "mlbProjectedLineupMatchup": getattr(prop, "mlbProjectedLineupMatchup", None),
                "isHome": getattr(prop, "isHome", None),
                "restDays": prop.restDays,
                "travelMiles": prop.travelMiles,
                "timezoneChangeHours": prop.timezoneChangeHours,
                "fatigueMultiplier": prop.fatigueMultiplier,
                "projectedOpportunity": prop.projectedOpportunity,
                "opportunityUnit": prop.opportunityUnit,
                "roleStatus": prop.roleStatus,
                "roleChange": prop.roleChange,
                "wowyMultiplier": prop.wowyMultiplier,
                "gameScriptMultiplier": prop.gameScriptMultiplier,
                "contextDataQualityScore": prop.contextDataQualityScore,
                "contextPresentFields": prop.contextPresentFields,
                "contextMissingFields": prop.contextMissingFields,
                "contextEvidenceProvenance": prop.contextEvidenceProvenance,
                "contextEvidenceConflicts": prop.contextEvidenceConflicts,
            }
            cursor.execute(
                """insert into matchup_feature_snapshots
                    (prediction_snapshot_id,prop_id,player_id,sport,market,event_time,features,source_versions)
                    values(%s,%s,%s,%s,%s,%s,%s::jsonb,%s::jsonb)
                    on conflict(prediction_snapshot_id) do nothing""",
                (snapshot_id, prop.id, prop.canonicalPlayerId or prop.playerId,
                 prop.sport.upper(), prop.market, event_time,
                 json.dumps(feature_payload), json.dumps({
                     "projection": snapshot_model_version,
                     "opportunity": prop.opportunitySource,
                     "selection": prop.selectionMethod,
                     "provider": prop.sourceProvider,
                     "weather": prop.weatherSource,
                 })),
            )
            if _paper_trade_eligible(prop.pickGrade):
                cursor.execute(
                    """insert into paper_trade_entries
                        (prediction_snapshot_id,prop_id,player_id,sport,market,side,grade,line,
                         projection,confidence,model_version,sportsbook,event_time,decision_inputs)
                        values(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb)
                        on conflict(prediction_snapshot_id) do nothing""",
                    (snapshot_id, prop.id, prop.canonicalPlayerId or prop.playerId,
                     prop.sport.upper(), prop.market, side, prop.pickGrade, prop.line,
                     projection, prop.confidence, snapshot_model_version, prop.sportsbook,
                     event_time, json.dumps(feature_payload)),
                )
            created += 1
            existing_snapshots.add(snapshot_key)
        connection.commit()
    _publish_probability_sources()
    return {"created": created, "modelVersion": model_version}


# One cycle serves both ends of the queue. Servicing only the newest -- the
# previous behaviour -- meant the rows closest to falling out of the
# fourteen day window were graded last, so the oldest expired ungraded even
# while throughput was sufficient to clear the backlog. Servicing only the
# oldest would be worse: rows that can never resolve (no game match, no
# player match) would sit at the head of the queue and be retried every
# cycle for a fortnight, starving everything behind them. Splitting the
# batch bounds what a stuck cohort can consume to its own half.
_GRADING_BATCH_HALF = 100
_ELIGIBLE_PREDICATE = """
    and event_time < now() - interval '3 hours'
    and created_at < event_time - interval '5 minutes'
    and event_time >= now() - interval '14 days'
    and sport not in ('NBA','WNBA')
"""


def grade_completed_predictions() -> dict[str, object]:
    if not database_is_configured():
        return {"graded": 0, "reason": "DATABASE_URL is not configured"}
    graded, unsupported = 0, 0
    pending_reasons: Counter[str] = Counter()
    pending_sports: Counter[str] = Counter()
    pending_markets: Counter[str] = Counter()
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""with latest_logs as (
              select distinct on (sport,lower(player_name),game_date)
                sport,lower(player_name) player_name,game_date,
                coalesce(points,0)::double precision points,
                coalesce(rebounds,0)::double precision rebounds,
                coalesce(assists,0)::double precision assists,
                coalesce(steals,0)::double precision steals,
                coalesce(blocks,0)::double precision blocks,
                coalesce(turnovers,0)::double precision turnovers,
                coalesce(threes,0)::double precision threes
              from historical_basketball_game_logs
              order by sport,lower(player_name),game_date,updated_at desc
            ), observed as (
              select p.id,p.side,p.line,
                case
                  when lower(p.market) like '%fantasy%' then null
                  when lower(p.market) like '%points%rebounds%assists%' or lower(p.market) like '%pra%'
                    then l.points+l.rebounds+l.assists
                  when lower(p.market) like '%points%rebounds%' then l.points+l.rebounds
                  when lower(p.market) like '%points%assists%' then l.points+l.assists
                  when lower(p.market) like '%rebounds%assists%' then l.rebounds+l.assists
                  when lower(p.market) like '%blocks%steals%' or lower(p.market) like '%steals%blocks%'
                    then l.blocks+l.steals
                  when lower(p.market) like '%three%' then l.threes
                  when lower(p.market) like '%rebound%' then l.rebounds
                  when lower(p.market) like '%assist%' then l.assists
                  when lower(p.market) like '%steal%' then l.steals
                  when lower(p.market) like '%block%' then l.blocks
                  when lower(p.market) like '%turnover%' then l.turnovers
                  when lower(p.market) like '%point%' then l.points
                end actual
              from prediction_snapshots p join latest_logs l
                on l.sport=p.sport and l.player_name=lower(p.inputs->>'playerName')
                and l.game_date=(p.event_time at time zone 'America/New_York')::date
              where p.graded_at is null and p.sport in ('NBA','WNBA')
                and p.event_time < now()-interval '3 hours'
                and p.event_time >= now()-interval '14 days'
                and p.created_at < p.event_time-interval '5 minutes'
            )
            update prediction_snapshots p set actual_value=o.actual,
              hit=case when p.side='OVER' then o.actual>p.line else o.actual<p.line end,
              graded_at=now(),
              inputs=jsonb_set(p.inputs,'{resultSource}',to_jsonb('historical-game-logs'::text),true)
            from observed o where p.id=o.id and o.actual is not null""")
        graded += cursor.rowcount
        connection.commit()
        cursor.execute(
            f"""with eligible as (
              select id,sport,market,side,line,event_time,
                     inputs->>'playerName' player_name,
                     player_id,inputs->>'matchup' matchup
                from prediction_snapshots
               where graded_at is null {_ELIGIBLE_PREDICATE}
            ),
            expiring as (
              select * from eligible order by event_time asc limit %s
            ),
            freshest as (
              select * from eligible order by event_time desc limit %s
            )
            select id,sport,market,side,line,event_time,player_name,
                   player_id,matchup
              from (select * from expiring union select * from freshest) batch
             order by event_time asc""",
            (_GRADING_BATCH_HALF, _GRADING_BATCH_HALF),
        )
        pending = cursor.fetchall()
        cursor.execute(
            f"""select count(*),min(event_time),
                   count(*) filter (
                     where event_time < now() - interval '13 days'
                   )
              from prediction_snapshots
             where graded_at is null {_ELIGIBLE_PREDICATE}"""
        )
        backlog_total, backlog_oldest, backlog_expiring = (
            cursor.fetchone() or (0, None, 0)
        )
        for identifier, sport, market, side, line, event_time, player_name, player_id, matchup in pending:
            result_source = ""
            if sport not in TRACKED_SPORTS or not player_name or event_time is None:
                unsupported += 1
                pending_reasons["invalid_or_untracked_prediction"] += 1
                pending_sports[str(sport or "UNKNOWN")] += 1
                pending_markets[f"{sport or 'UNKNOWN'}|{market or 'UNKNOWN'}"] += 1
                continue
            if sport == "MLB":
                official = official_mlb_result(
                    player_name=str(player_name),
                    market=str(market),
                    matchup=str(matchup or ""),
                    game_start_time=event_time.isoformat(),
                )
                if official is None:
                    official = historical_mlb_result(
                        player_name=str(player_name), market=str(market),
                        game_start_time=event_time.isoformat(),
                        player_id=str(player_id or ""),
                        matchup=str(matchup or ""),
                    )
                actual = official.value if official is not None else None
                result_source = official.source if official is not None else ""
                if actual is None:
                    pending_reasons["official_mlb_result_not_found"] += 1
            elif sport in {"NBA", "WNBA"}:
                cursor.execute("""select points,rebounds,assists,steals,blocks,turnovers,threes
                    from historical_basketball_game_logs where sport=%s and lower(player_name)=lower(%s)
                    and game_date=%s order by updated_at desc limit 1""",
                    (sport, player_name, event_time.date()))
                row = cursor.fetchone()
                if row is None:
                    continue
                actual = _market_value(str(market), row)
                result_source = "historical-game-logs"
            elif sport in {"TENNIS", "PGA", "GOLF", "UFC", "MMA", "SOCCER"}:
                history_sport = "PGA" if sport == "GOLF" else "UFC" if sport == "MMA" else sport
                cursor.execute("""select stats from historical_player_game_logs
                    where sport=%s and lower(player_name)=lower(%s)
                    and game_date=(%s at time zone 'America/New_York')::date
                    order by updated_at desc limit 1""",
                    (history_sport, player_name, event_time))
                row = cursor.fetchone()
                actual = (
                    _specialty_market_value(str(sport), str(market), row[0])
                    if row is not None else None
                )
                result_source = "historical-specialty-logs"
                if row is None:
                    pending_reasons["specialty_player_result_not_found"] += 1
                elif actual is None:
                    pending_reasons["specialty_market_not_mapped"] += 1
            else:
                snapshot = get_live_player_stat_snapshot(
                    player_name=str(player_name),
                    team="",
                    prop_type=str(market),
                    sport=str(sport),
                    season=str(event_time.year),
                    event_id="",
                    matchup=str(matchup or ""),
                    game_start_time=event_time.isoformat(),
                )
                actual = snapshot.value if snapshot.completed else None
                result_source = snapshot.source or "sportsdataio"
                if actual is None:
                    pending_reasons[f"live_result_{snapshot.status or 'not_available'}"] += 1
            if actual is None:
                unsupported += 1
                pending_sports[str(sport)] += 1
                pending_markets[f"{sport}|{market}"] += 1
                continue
            hit = actual > float(line) if side == "OVER" else actual < float(line)
            cursor.execute("""update prediction_snapshots set actual_value=%s,hit=%s,graded_at=now(),
                inputs=jsonb_set(inputs,'{resultSource}',to_jsonb(%s::text),true)
                where id=%s""", (
                    actual,
                    hit,
                    result_source,
                    identifier,
                ))
            graded += 1
            if graded % 250 == 0:
                connection.commit()
        connection.commit()
        cursor.execute(
            """insert into paper_trade_results
                (paper_trade_id,actual_value,hit,closing_line,closing_no_vig_probability,
                 odds_clv_expected_value_percent,graded_at,result_source)
                select e.id,p.actual_value,p.hit,
                    nullif(p.inputs->>'closingLine','')::double precision,
                    nullif(p.inputs->>'closingNoVigProbability','')::double precision,
                    nullif(p.inputs->>'oddsClvExpectedValuePercent','')::double precision,
                    p.graded_at,coalesce(p.inputs->>'resultSource','')
                from paper_trade_entries e join prediction_snapshots p
                  on p.id=e.prediction_snapshot_id
                where p.graded_at is not null and p.actual_value is not null and p.hit is not null
                on conflict(paper_trade_id) do nothing"""
        )
        connection.commit()
    return {"graded": graded, "pendingChecked": len(pending), "unsupported": unsupported,
            "pendingReasons": dict(pending_reasons.most_common()),
            "pendingBySport": dict(pending_sports.most_common()),
            "pendingByMarket": dict(pending_markets.most_common(25)),
            # Without these the queue depth was invisible: a cycle reporting
            # a healthy graded count looks identical whether ten rows remain
            # or twenty thousand do.
            "backlogTotal": int(backlog_total or 0),
            "backlogOldestEventTime": (
                backlog_oldest.isoformat() if backlog_oldest else None
            ),
            "backlogExpiringWithin24h": int(backlog_expiring or 0),
            "gradedAt": datetime.now(timezone.utc).isoformat()}


def _wilson_interval(
    successes: int, total: int, z: float = 1.96
) -> tuple[float, float]:
    """95% interval for a hit rate, usable at small samples.

    The normal approximation misbehaves near 0 and 1 and at low counts,
    which is exactly where a new market or a thin tier lives.
    """

    if total <= 0:
        return (0.0, 0.0)
    proportion = successes / total
    denominator = 1 + (z * z) / total
    centre = proportion + (z * z) / (2 * total)
    spread = z * sqrt(
        (proportion * (1 - proportion) + (z * z) / (4 * total)) / total
    )
    return (
        max(0.0, (centre - spread) / denominator),
        min(1.0, (centre + spread) / denominator),
    )


def _mean_interval(
    mean: float | None, spread: float, count: int, z: float = 1.96
) -> tuple[float | None, float | None]:
    """95% interval for a mean return, or (None, None) without the sample."""

    if mean is None or count < 2 or spread <= 0:
        return (None, None)
    margin = z * (spread / sqrt(count))
    return (mean - margin, mean + margin)


def confidence_tier_calibration(
    minimum_sample: int = 50,
) -> list[dict[str, object]]:
    """Check each displayed tier against the results it actually produced.

    The board tells a user a number. This is the only measurement that asks
    whether that number was true, and it reads the confidence the card
    showed rather than the modelled probability behind it -- those are
    different columns, and only one of them is a promise made to anyone.

    It exists because the answer moved: a band claiming 57.9% delivered
    54.0% and lost 9.1% flat-staked while being labelled playable, and
    nobody knew until the question was asked by hand months in. A claim the
    product makes continuously needs checking continuously.
    """

    if not database_is_configured():
        return []
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """
            with graded as (
              select (inputs->>'confidence')::int confidence, hit,
                     nullif(inputs->>'entryOdds','')::numeric odds
                from prediction_snapshots
               where graded_at is not null and hit is not null
                 and (inputs->>'confidence') ~ '^[0-9]+$'
                 -- Confidence is floored at 50 wherever it is shown, so a
                 -- lower value means no number reached the card. Averaging
                 -- those in would compare a claim against rows that never
                 -- made one.
                 and (inputs->>'confidence')::int >= 50
            )
            select case when confidence >= %s then 'Premium'
                        when confidence >= %s then 'Strong'
                        else 'Pass' end tier,
                   count(*) sample_size,
                   avg(confidence) claimed,
                   sum(case when hit then 1 else 0 end) hits,
                   count(*) filter (
                     where odds is not null and odds <> 0
                   ) priced,
                   avg(case when hit
                         then case when odds > 0 then odds / 100.0
                                   else 100.0 / abs(odds) end
                         else -1 end
                   ) filter (where odds is not null and odds <> 0) roi,
                   stddev_samp(case when hit
                         then case when odds > 0 then odds / 100.0
                                   else 100.0 / abs(odds) end
                         else -1 end
                   ) filter (where odds is not null and odds <> 0) roi_spread
              from graded
             group by 1
            """,
            (PREMIUM_CONFIDENCE_FLOOR, ACTIONABLE_CONFIDENCE_FLOOR),
        )
        rows = cursor.fetchall()
    report: list[dict[str, object]] = []
    for tier, sample_size, claimed, hits, priced, roi, roi_spread in rows:
        total = int(sample_size or 0)
        if total < minimum_sample:
            continue
        claimed_rate = float(claimed or 0) / 100.0
        actual_rate = int(hits or 0) / total
        hit_low, hit_high = _wilson_interval(int(hits or 0), total)
        roi_value = float(roi) if roi is not None else None
        roi_low, roi_high = _mean_interval(
            roi_value, float(roi_spread or 0), int(priced or 0)
        )
        # A point estimate is not evidence. The retired band sat about five
        # standard errors below break-even; the tier beneath Premium sits
        # within noise of it. Treating those two the same would either keep
        # a loser or discard half the actionable board on a rounding error.
        if roi_low is not None and roi_low > 0:
            profitability = "proven_profitable"
        elif roi_high is not None and roi_high < 0:
            profitability = "proven_unprofitable"
        else:
            profitability = "not_distinguishable"
        report.append(
            {
                "tier": str(tier),
                "sampleSize": total,
                "claimedHitRate": round(claimed_rate, 4),
                "actualHitRate": round(actual_rate, 4),
                "hitRateLow": round(hit_low, 4),
                "hitRateHigh": round(hit_high, 4),
                # Negative means the tier promised more than it delivered.
                "claimShortfall": round(actual_rate - claimed_rate, 4),
                "flatStakeRoi": round(roi_value, 4) if roi_value is not None else None,
                "flatStakeRoiLow": round(roi_low, 4) if roi_low is not None else None,
                "flatStakeRoiHigh": round(roi_high, 4) if roi_high is not None else None,
                "pricedSampleSize": int(priced or 0),
                "profitability": profitability,
                # A tier only sold as actionable if it is one.
                "actionable": str(tier) in {"Premium", "Strong"},
                # Missing the stated rate only counts when the interval says
                # so; a point estimate a hair under its claim is noise.
                "meetsItsClaim": claimed_rate <= hit_high,
            }
        )
    report.sort(key=lambda row: -float(row["claimedHitRate"]))
    return report


def model_probability_reliability(
    minimum_bucket: int = 300,
) -> list[dict[str, object]]:
    """Reliability of the model's own estimate, before the safety margin.

    The groups elsewhere in this report measure hit_probability, which is
    the calibrated probability minus an uncertainty margin -- a deliberately
    conservative floor rather than an estimate of anything. Comparing a
    floor against outcomes and calling the difference calibration error
    describes the margin working as designed, not a defect, and reading it
    as one sent an afternoon chasing a problem that did not exist.

    This measures the estimate itself, which is the number that can be
    right or wrong. Its known failure is the top: props the model calls
    93% or more land nearer two thirds. Those remain profitable because the
    ordering is sound and the prices are good, so the defect is in what the
    number claims, not in which props it selects.
    """

    if not database_is_configured():
        return []
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """
            select width_bucket(
                     (inputs->>'modelProbability')::numeric, 0.3, 1.0, 7
                   ) bucket,
                   count(*) sample_size,
                   avg((inputs->>'modelProbability')::numeric) predicted,
                   avg(case when hit then 1.0 else 0.0 end) actual
              from prediction_snapshots
             where graded_at is not null and hit is not null
               and (inputs->>'modelProbability') ~ '^[0-9.]+$'
             group by 1
             having count(*) >= %s
             order by 1
            """,
            (minimum_bucket,),
        )
        rows = cursor.fetchall()
    reliability: list[dict[str, object]] = []
    for _bucket, sample_size, predicted, actual in rows:
        claimed = float(predicted or 0)
        observed = float(actual or 0)
        reliability.append(
            {
                "sampleSize": int(sample_size),
                "predictedProbability": round(claimed, 4),
                "observedHitRate": round(observed, 4),
                "overstatement": round(claimed - observed, 4),
            }
        )
    return reliability


def prediction_calibration_report(minimum_sample: int = 20) -> dict[str, object]:
    """Out-of-sample calibration, accuracy, and flat-stake ROI by market."""
    if not database_is_configured():
        return {"sampleSize": 0, "groups": [], "reason": "DATABASE_URL is not configured"}
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select sport,market,model_version,side,line,actual_value,
                hit_probability,hit,inputs->>'entryOdds'
            from prediction_snapshots
            where graded_at is not null and actual_value is not null
            order by graded_at desc limit 50000"""
        )
        rows = cursor.fetchall()
        cursor.execute(
            """select sport,market,count(*),count(*) filter(where hit is not null)
            from prediction_snapshots group by sport,market order by sport,market"""
        )
        coverage_rows = cursor.fetchall()

    groups: dict[tuple[str, str, str], list[dict[str, float | bool | None]]] = {}
    for sport, market, version, side, line, actual, probability, hit, odds in rows:
        if float(actual) == float(line):
            continue
        try:
            american_odds = float(odds) if odds is not None else None
        except (TypeError, ValueError):
            american_odds = None
        key = (str(sport), str(market), str(version))
        groups.setdefault(key, []).append(
            {
                "probability": float(probability),
                "hit": bool(hit),
                "odds": american_odds,
            }
        )

    output: list[dict[str, object]] = []
    for (sport, market, version), observations in groups.items():
        if len(observations) < minimum_sample:
            continue
        brier = sum(
            (float(row["probability"]) - (1.0 if row["hit"] else 0.0)) ** 2
            for row in observations
        ) / len(observations)
        predicted = sum(float(row["probability"]) for row in observations) / len(observations)
        actual = sum(1 for row in observations if row["hit"]) / len(observations)
        returns: list[float] = []
        for row in observations:
            odds = row["odds"]
            if odds is None or odds == 0:
                continue
            decimal = 1 + (odds / 100 if odds > 0 else 100 / abs(odds))
            returns.append(decimal - 1 if row["hit"] else -1)
        output.append(
            {
                "sport": sport,
                "market": market,
                "modelVersion": version,
                "sampleSize": len(observations),
                "predictedHitRate": round(predicted, 4),
                "actualHitRate": round(actual, 4),
                "calibrationError": round(abs(predicted - actual), 4),
                "brierScore": round(brier, 4),
                "flatStakeRoi": (
                    round(sum(returns) / len(returns), 4) if returns else None
                ),
            }
        )
    output.sort(key=lambda group: int(group["sampleSize"]), reverse=True)
    coverage = []
    for sport, market, snapshots, graded in coverage_rows:
        sport_key = str(sport).upper()
        normalized_market = normalize_prop_type(market)
        gradeable = (
            sport_key in {"NBA", "WNBA", "MLB"}
            or (
                sport_key in {"NFL", "NHL", "PGA", "GOLF"}
                and normalized_market in STAT_MAP
            )
        )
        coverage.append(
            {
                "sport": sport_key,
                "market": str(market),
                "snapshots": int(snapshots),
                "graded": int(graded),
                "gradeable": gradeable,
                "status": (
                    "unsupported"
                    if not gradeable
                    else "ready"
                    if int(graded) >= minimum_sample
                    else "warming"
                ),
            }
        )
    return {
        "sampleSize": sum(len(values) for values in groups.values()),
        "minimumGroupSample": minimum_sample,
        "groups": output,
        # The groups above measure the modelled probability. This measures
        # the number the card actually showed, which is the claim a user
        # can hold the product to, and the two are not the same column.
        "confidenceTiers": confidence_tier_calibration(),
        # What the groups above are actually measuring. Without this the
        # numbers read as a broken model rather than a working safety
        # margin, which is a conclusion this report has already caused.
        "probabilityBasis": {
            "column": "hit_probability",
            "meaning": "calibrated probability minus an uncertainty margin",
            "isAnEstimate": False,
            "note": (
                "A conservative floor understates outcomes by design. Use "
                "modelReliability to judge the estimate, and "
                "confidenceTiers to judge what the board actually claimed."
            ),
        },
        "modelReliability": model_probability_reliability(),
        "coverage": coverage,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
    }


def _mlb_market_value(cursor, market: str, player_id: str, game_date) -> float | None:
    text = market.lower().replace("_", " ")
    if "strikeout" in text:
        cursor.execute("""select count(*) from historical_mlb_pitches
            where pitcher_id=%s and game_date=%s
            and events in ('strikeout','strikeout_double_play')""", (player_id, game_date))
        return float(cursor.fetchone()[0])
    if "total base" in text:
        cursor.execute("""select coalesce(sum(case events when 'single' then 1 when 'double' then 2
            when 'triple' then 3 when 'home_run' then 4 else 0 end),0)
            from historical_mlb_pitches where batter_id=%s and game_date=%s""", (player_id, game_date))
        return float(cursor.fetchone()[0])
    event = "home_run" if "home run" in text else None
    is_hits_market = text in {"batter hits", "player hits", "hits"}
    if event or is_hits_market:
        cursor.execute("""select count(*) from historical_mlb_pitches where batter_id=%s
            and game_date=%s and events = any(%s)""",
            (player_id, game_date, [event] if event else ["single", "double", "triple", "home_run"]))
        return float(cursor.fetchone()[0])
    return None


def _market_value(market: str, row: tuple[object, ...]) -> float | None:
    text = market.lower().replace("_", " ")
    points, rebounds, assists, steals, blocks, turnovers, threes = [float(value or 0) for value in row]
    if "fantasy" in text: return None
    if "points rebounds assists" in text or "pra" in text: return points + rebounds + assists
    if "points rebounds" in text: return points + rebounds
    if "points assists" in text: return points + assists
    if "rebounds assists" in text: return rebounds + assists
    if "blocks steals" in text or "steals blocks" in text: return blocks + steals
    if "three" in text or "3 pointer" in text: return threes
    if "rebound" in text: return rebounds
    if "assist" in text: return assists
    if "steal" in text: return steals
    if "block" in text: return blocks
    if "turnover" in text: return turnovers
    if "point" in text: return points
    return None
