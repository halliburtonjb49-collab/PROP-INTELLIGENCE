"""Closed-loop prop learning snapshots, grading, and performance summaries."""

from __future__ import annotations

import json
from collections import Counter
from datetime import datetime, timezone

from database.postgres import database_is_configured, get_database_pool
from services.baseline_projection_service import MODEL_VERSION
from services.live_stats_service import get_live_player_stat_snapshot, normalize_prop_type
from services.mlb_official_stats_service import historical_mlb_result, official_mlb_result
from services.prop_service import get_props


_TRACKED_SPORTS = {
    "NBA", "WNBA", "MLB", "NFL", "NHL", "SOCCER",
}


def _snapshot_side(prop: object, *, line_override: float | None = None) -> str:
    side = str(getattr(prop, "recommendedSide", "") or "").upper()
    if side in {"OVER", "UNDER"}:
        return side
    line = line_override if line_override is not None else getattr(prop, "line", None)
    projection = getattr(prop, "projection", None)
    if projection is None or line in (None, ""):
        return ""
    try:
        projection_value = float(projection)
        line_value = float(line)
    except (TypeError, ValueError):
        return ""
    if projection_value > line_value:
        return "OVER"
    if projection_value < line_value:
        return "UNDER"
    return ""


def _snapshot_probability(prop: object) -> float:
    for attr in ("uncertaintyAdjustedProbability", "fairProbability",
                 "modelProbability", "marketProbability"):
        value = getattr(prop, attr, None)
        if value is None:
            continue
        try:
            candidate = float(value)
        except (TypeError, ValueError):
            continue
        if 0 <= candidate <= 1:
            return candidate
        if 0 <= candidate <= 100:
            return candidate / 100
    confidence = float(getattr(prop, "confidence", 0) or 0)
    if confidence <= 0:
        return 0.5
    return max(0.01, min(0.99, confidence / 100))


def _safe_float(value: object) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _extract_result_value(payload: object, *, key: str = "value") -> float | None:
    if isinstance(payload, dict):
        return _safe_float(payload.get(key))
    return _safe_float(getattr(payload, key, None))


def _extract_result_source(payload: object, *, default: str = "") -> str:
    if isinstance(payload, dict):
        value = payload.get("source")
    else:
        value = getattr(payload, "source", default)
    return str(value or default)


def _safe_datetime(value: object) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed


def _market_value_snapshot(market: str, row: tuple[object, ...]) -> float | None:
    text = str(market or "").lower().replace("_", " ")
    try:
        points, rebounds, assists, steals, blocks, turnovers, threes = [
            float(value or 0) for value in row
        ]
    except (TypeError, ValueError):
        return None
    if "fantasy" in text:
        return None
    if "points rebounds assists" in text or "pra" in text:
        return points + rebounds + assists
    if "points rebounds" in text:
        return points + rebounds
    if "points assists" in text:
        return points + assists
    if "rebounds assists" in text:
        return rebounds + assists
    if "blocks steals" in text or "steals blocks" in text:
        return blocks + steals
    if "three" in text or "3 pointer" in text:
        return threes
    if "rebound" in text:
        return rebounds
    if "assist" in text:
        return assists
    if "steal" in text:
        return steals
    if "block" in text:
        return blocks
    if "turnover" in text:
        return turnovers
    if "point" in text:
        return points
    return None


def _specialty_market_value(sport: str, market: str, stats: object) -> float | None:
    if not isinstance(stats, dict):
        return None
    text = normalize_prop_type(str(market)).lower().replace("_", " ")
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
            value = stats.get(stat_name)
            try:
                return float(value)
            except (TypeError, ValueError):
                return None
    return None


def snapshot_all_props_for_learning(model_version: str = MODEL_VERSION) -> dict[str, object]:
    if not database_is_configured():
        return {"created": 0, "reason": "DATABASE_URL is not configured"}

    created = 0
    snapshot_date = datetime.now(timezone.utc).date().isoformat()
    now = datetime.now(timezone.utc)
    skipped_stale = 0
    skipped_invalid = 0

    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """
            select prop_id, model_version, source_provider, sportsbook, line, side
            from public.prop_prediction_snapshots
            where snapshot_date = (now() at time zone 'UTC')::date
            """
        )
        existing = {
            (
                str(row[0]), str(row[1]), str(row[2] or ""), str(row[3] or ""),
                float(row[4]), str(row[5])
            )
            for row in cursor.fetchall()
        }

        for prop in get_props():
            if getattr(prop, "dataStale", False):
                skipped_stale += 1
                continue

            side = _snapshot_side(prop)
            if side not in {"OVER", "UNDER"}:
                continue

            start_time = _safe_datetime(getattr(prop, "startTimeUtc", None))
            if start_time is None:
                skipped_invalid += 1
                continue
            if start_time <= now:
                continue

            line = _safe_float(getattr(prop, "line", None))
            if line is None:
                skipped_invalid += 1
                continue

            version = str(
                getattr(prop, "projectionModelVersion", None) or model_version
            )
            source_provider = str(getattr(prop, "sourceProvider", "odds-api"))
            sportsbook = str(getattr(prop, "sportsbook", ""))
            snapshot_key = (
                str(getattr(prop, "id", "")), version, source_provider, sportsbook, line, side,
            )
            if snapshot_key in existing:
                continue

            payload = {
                "playerName": getattr(prop, "player", ""),
                "eventId": getattr(prop, "eventId", ""),
                "matchup": getattr(prop, "matchup", ""),
                "marketKey": getattr(prop, "marketKey", ""),
                "sourceUpdatedUtc": getattr(prop, "sourceUpdatedUtc", ""),
                "confidence": getattr(prop, "confidence", 0),
                "edge": getattr(prop, "recommendationEdge", 0),
                "modelProbability": getattr(prop, "modelProbability", None),
                "marketProbability": getattr(prop, "marketProbability", None),
                "pushProbability": getattr(prop, "pushProbability", 0),
                "probabilityMethod": getattr(prop, "probabilityMethod", ""),
                "openingLine": getattr(prop, "openingLine", None),
                "currentLine": getattr(prop, "currentLine", None),
                "entryOdds": (
                    getattr(prop, "overOdds", None)
                    if side == "OVER" else getattr(prop, "underOdds", None)
                ),
                "projection": getattr(prop, "projection", None),
                "projectionSource": getattr(prop, "projectionSource", ""),
                "projectionSampleSize": getattr(prop, "projectionSampleSize", 0),
                "projectionVolatility": getattr(prop, "projectionVolatility", None),
                "injuryStatus": getattr(prop, "injuryStatus", ""),
                "lineupStatus": getattr(prop, "lineupStatus", ""),
            }

            cursor.execute(
                """
                insert into public.prop_prediction_snapshots
                  (prop_id, player_id, sport, market, side, line, projection,
                   hit_probability, model_version, source_provider, sportsbook,
                   event_time, inputs)
                values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::timestamptz,to_jsonb(%s::jsonb))
                returning id
                """,
                (
                    str(getattr(prop, "id", "")),
                    str(getattr(prop, "canonicalPlayerId", "") or getattr(prop, "playerId", "")),
                    str(getattr(prop, "sport", "")).upper(),
                    str(getattr(prop, "market", "")),
                    side,
                    line,
                    _safe_float(getattr(prop, "projection", None)),
                    _snapshot_probability(prop),
                    version,
                    source_provider,
                    sportsbook,
                    start_time,
                    json.dumps(payload),
                ),
            )
            snapshot_id = cursor.fetchone()[0]
            cursor.execute(
                """
                insert into public.prop_results
                  (prop_prediction_snapshot_id, grade_state, result_inputs)
                values (%s, 'PENDING', '{}'::jsonb)
                on conflict (prop_prediction_snapshot_id) do nothing
                """,
                (snapshot_id,),
            )
            existing.add(snapshot_key)
            created += 1

        connection.commit()

    return {
        "created": created,
        "snapshotDate": snapshot_date,
        "skipped": {"stale": skipped_stale, "invalid": skipped_invalid},
    }


def _refresh_model_metrics(
    cursor,
    *,
    window_days: int = 30,
) -> None:
    cursor.execute(
        """
        with aggregated as (
          select
            coalesce(
              date_trunc('day', r.graded_at at time zone 'UTC')::date,
              date_trunc('day', s.event_time at time zone 'UTC')::date
            ) as metric_date,
            s.model_version,
            s.sport,
            s.market,
            count(*) as sample_size,
            count(*) filter (where r.grade_state='WIN') as win_count,
            count(*) filter (where r.grade_state='LOSS') as loss_count,
            count(*) filter (where r.grade_state='PUSH') as push_count,
            count(*) filter (where r.grade_state='VOID') as void_count,
            count(*) filter (where r.grade_state='PENDING') as pending_count
          from public.prop_results r
          join public.prop_prediction_snapshots s on s.id = r.prop_prediction_snapshot_id
          where (
            (r.graded_at is not null and r.graded_at >= now() - %s::interval)
            or (
              r.graded_at is null and r.grade_state = 'PENDING'
              and s.event_time >= now() - %s::interval
            )
          )
          group by 1,2,3,4
        )
        insert into public.model_performance_metrics
          (metric_date, model_version, sport, market, sample_size,
           win_count, loss_count, push_count, void_count, pending_count,
           win_rate, push_rate, computed_at, updated_at)
        select
          metric_date, model_version, sport, market, sample_size::int,
          win_count::int, loss_count::int, push_count::int, void_count::int,
          pending_count::int,
          case when sample_size = 0 then 0 else win_count::double precision / sample_size end,
          case when sample_size = 0 then 0 else push_count::double precision / sample_size end,
          now(), now()
        from aggregated
        where metric_date is not null
        on conflict (metric_date, model_version, sport, market) do update set
          sample_size = excluded.sample_size,
          win_count = excluded.win_count,
          loss_count = excluded.loss_count,
          push_count = excluded.push_count,
          void_count = excluded.void_count,
          pending_count = excluded.pending_count,
          win_rate = excluded.win_rate,
          push_rate = excluded.push_rate,
          computed_at = excluded.computed_at,
          updated_at = excluded.updated_at
        """,
        (f"{window_days} days", f"{window_days} days"),
    )


def grade_learning_results(*, batch_size: int = 500) -> dict[str, object]:
    if not database_is_configured():
        return {"graded": 0, "reason": "DATABASE_URL is not configured"}

    graded = 0
    pending = 0
    unsupported = 0
    errors = 0
    reason_counts: Counter[str] = Counter()
    state_counts: Counter[str] = Counter()
    batch_size = max(100, min(int(batch_size), 5000))

    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """
            select s.id, s.sport, s.market, s.side, s.line, s.event_time,
                   s.inputs->>'playerName' as player_name, s.player_id,
                   s.inputs->>'matchup' as matchup, s.inputs->>'sourceUpdatedUtc' as source_updated_utc,
                   r.id as result_id
              from public.prop_prediction_snapshots s
              join public.prop_results r on r.prop_prediction_snapshot_id = s.id
             where r.grade_state = 'PENDING'
               and s.event_time < now() - interval '3 hours'
               and s.event_time >= now() - interval '14 days'
             order by r.graded_at asc nulls first, s.event_time asc
             limit %s
            """,
            (batch_size,),
        )
        candidates = cursor.fetchall()
        pending = len(candidates)

        for (
            snapshot_id,
            sport,
            market,
            side,
            line,
            event_time,
            player_name,
            player_id,
            matchup,
            _,
            result_id,
        ) in candidates:
            sport_value = str(sport or "").upper()
            line_value = _safe_float(line)
            if not sport_value or line_value is None:
                errors += 1
                reason_counts["invalid_record"] += 1
                state_counts["ERROR"] += 1
                cursor.execute(
                    """
                    update public.prop_results
                       set grade_state='ERROR', grade_reason='invalid_record', graded_at=now()
                     where id=%s
                    """,
                    (result_id,),
                )
                continue
            if not event_time or event_time > datetime.now(timezone.utc):
                continue

            actual = None
            result_source = ""

            if sport_value == "MLB":
                official = official_mlb_result(
                    player_name=str(player_name or ""),
                    market=str(market or ""),
                    matchup=str(matchup or ""),
                    game_start_time=str(event_time),
                )
                if official is None:
                    official = historical_mlb_result(
                        player_name=str(player_name or ""),
                        market=str(market or ""),
                        game_start_time=str(event_time),
                        player_id=str(player_id or ""),
                        matchup=str(matchup or ""),
                    )
                if official is not None:
                    actual = _extract_result_value(official)
                    result_source = _extract_result_source(official, default="mlb-stats-api")
                else:
                    reason_counts["official_mlb_result_not_found"] += 1
            elif sport_value in {"NBA", "WNBA"}:
                if event_time is not None:
                    cursor.execute(
                        """
                        select points, rebounds, assists, steals, blocks, turnovers, threes
                          from public.historical_basketball_game_logs
                         where sport=%s and lower(player_name)=lower(%s)
                           and game_date=%s
                         order by updated_at desc
                         limit 1
                        """,
                        (sport_value, player_name, event_time.date()),
                    )
                    row = cursor.fetchone()
                    if row is not None:
                        actual = _market_value_snapshot(market, row)
                        result_source = "historical-game-logs"
                    else:
                        reason_counts["historical_game_log_missing"] += 1
            elif sport_value in {"TENNIS", "PGA", "GOLF", "UFC", "MMA", "SOCCER"}:
                history_sport = (
                    "PGA" if sport_value == "GOLF" else "UFC" if sport_value == "MMA" else sport_value
                )
                cursor.execute(
                    """
                    select stats from public.historical_player_game_logs
                     where sport=%s and lower(player_name)=lower(%s)
                       and game_date=(%s at time zone 'America/New_York')::date
                     order by updated_at desc
                     limit 1
                    """,
                    (history_sport, player_name, event_time),
                )
                row = cursor.fetchone()
                if row is not None:
                    actual = _specialty_market_value(sport_value, market, row[0])
                    result_source = "historical-specialty-logs"
                else:
                    reason_counts["specialty_player_result_not_found"] += 1
            else:
                snapshot = get_live_player_stat_snapshot(
                    player_name=str(player_name or ""),
                    team="",
                    prop_type=str(market or ""),
                    sport=str(sport_value),
                    season=str(event_time.year),
                    event_id="",
                    matchup=str(matchup or ""),
                    game_start_time=event_time.isoformat(),
                )
                if snapshot is not None:
                    actual = _safe_float(snapshot.value if snapshot.completed else None)
                    result_source = _extract_result_source(snapshot, default="sportsdataio")
                else:
                    reason_counts[f"live_result_not_available"] += 1

            if actual is None:
                unsupported += 1
                cursor.execute(
                    """
                    update public.prop_results
                       set grade_state='PENDING', grade_reason='awaiting_result', graded_at=now(),
                           result_inputs = jsonb_set(
                             coalesce(result_inputs, '{}'::jsonb),
                             '{resultSource}', to_jsonb('PENDING'::text), true
                           )
                     where id=%s
                    """,
                    (result_id,),
                )
                continue

            is_push = abs(float(actual) - float(line_value)) < 1e-9
            is_over = str(side).upper() == "OVER"
            if is_push:
                grade_state = "PUSH"
            else:
                hit = (actual > line_value) if is_over else (actual < line_value)
                grade_state = "WIN" if hit else "LOSS"

            cursor.execute(
                """
                update public.prop_results
                   set grade_state=%s, actual_value=%s, hit=%s,
                       result_source=%s, grade_reason=%s, graded_at=now(),
                       result_inputs = jsonb_set(
                         coalesce(result_inputs, '{}'::jsonb),
                         '{resultSource}', to_jsonb(%s::text), true
                       )
                 where id=%s
                """,
                (
                    grade_state,
                    float(actual),
                    None if is_push else (grade_state == "WIN"),
                    result_source,
                    "graded",
                    result_source,
                    result_id,
                ),
            )
            state_counts[grade_state] += 1
            graded += 1

            if graded % 100 == 0:
                connection.commit()

        connection.commit()
        _refresh_model_metrics(cursor)
        connection.commit()

        cursor.execute(
            """
            select count(*) as backlog_total,
                   min(s.event_time),
                   count(*) filter (
                     where s.event_time < now() - interval '13 days'
                   ) as backlog_expiring
              from public.prop_prediction_snapshots s
              join public.prop_results r on r.prop_prediction_snapshot_id = s.id
             where r.grade_state = 'PENDING'
               and s.event_time < now() - interval '3 hours'
               and s.event_time >= now() - interval '14 days'
            """
        )
        backlog_total, backlog_oldest, backlog_expiring = cursor.fetchone()

        cursor.execute(
            """
            select sum(sample_size) as graded_sample,
                   sum(win_count) as grade_win,
                   sum(loss_count) as grade_loss,
                   sum(push_count) as grade_push,
                   sum(void_count) as grade_void
              from public.model_performance_metrics
             where metric_date >= (now() at time zone 'UTC')::date - interval '1 day'
            """
        )
        graded_rolling = cursor.fetchone()

    return {
        "graded": graded,
        "pendingChecked": pending,
        "unsupported": unsupported,
        "errors": errors,
        "stateCounts": dict(state_counts),
        "pendingReasons": dict(reason_counts),
        "backlogTotal": int(backlog_total or 0),
        "backlogOldestEventTime": backlog_oldest.isoformat() if backlog_oldest else None,
        "backlogExpiringWithin24h": int(backlog_expiring or 0),
        "rollingSummary": {
            "sampleSize": int(graded_rolling[0] or 0),
            "wins": int(graded_rolling[1] or 0),
            "losses": int(graded_rolling[2] or 0),
            "pushes": int(graded_rolling[3] or 0),
            "voids": int(graded_rolling[4] or 0),
        },
        "gradedAt": datetime.now(timezone.utc).isoformat(),
    }


def learning_performance_summary(days: int = 30) -> dict[str, object]:
    if not database_is_configured():
        return {"windowDays": days, "available": False, "reason": "DATABASE_URL is not configured"}

    window_days = max(1, min(int(days), 365))
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """
            select metric_date, model_version, sport, market, sample_size,
                   win_count, loss_count, push_count, void_count, pending_count,
                   win_rate, push_rate
              from public.model_performance_metrics
             where metric_date >= (now() at time zone 'UTC')::date - %s::interval
             order by metric_date desc, sample_size desc
            """,
            (f"{window_days} days",),
        )
        rows = cursor.fetchall()
        cursor.execute(
            """
            select count(*) from public.prop_results r
            join public.prop_prediction_snapshots s on s.id = r.prop_prediction_snapshot_id
            where r.grade_state='PENDING'
            """,
        )
        pending_rows = cursor.fetchone()[0]

    keys = (
        "metricDate", "modelVersion", "sport", "market", "sampleSize",
        "wins", "losses", "pushes", "voids", "pending", "winRate", "pushRate",
    )
    return {
        "windowDays": window_days,
        "available": True,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "totals": {"pending": int(pending_rows or 0)},
        "metrics": [dict(zip(keys, row)) for row in rows],
    }
