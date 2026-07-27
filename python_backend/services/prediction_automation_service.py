"""Create daily model snapshots from live props and grade completed basketball games."""

from __future__ import annotations

import json
from datetime import datetime, timezone

from database.postgres import database_is_configured, get_database_pool
from services.prop_service import get_props
from services.baseline_projection_service import MODEL_VERSION
from services.mlb_official_stats_service import official_mlb_result
from services.live_stats_service import (
    STAT_MAP,
    get_live_player_stat_snapshot,
    normalize_prop_type,
)

TRACKED_SPORTS = {"NBA", "WNBA", "MLB", "NFL", "NHL", "PGA", "GOLF"}


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
            cursor.execute(
                """update prediction_snapshots set inputs=inputs || %s::jsonb
                where id=%s""",
                (json.dumps(clv), identifier),
            )
            updated += 1
        connection.commit()
    return {"updated": updated}


def snapshot_live_predictions(model_version: str = MODEL_VERSION) -> dict[str, object]:
    if not database_is_configured():
        return {"created": 0, "reason": "DATABASE_URL is not configured"}
    created = 0
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        for prop in get_props():
            if prop.dataStale:
                continue
            snapshot_model_version = prop.projectionModelVersion or model_version
            side = prop.recommendedSide.upper()
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
            probability = (
                float(prop.fairProbability)
                if prop.fairProbability is not None
                else max(.5, min(.95, prop.confidence / 100))
            )
            cursor.execute("""select 1 from prediction_snapshots where prop_id=%s and model_version=%s
                and snapshot_date=(now() at time zone 'UTC')::date limit 1""", (prop.id, snapshot_model_version))
            if cursor.fetchone():
                continue
            cursor.execute("""insert into prediction_snapshots
                (prop_id,player_id,sport,market,side,line,projection,hit_probability,
                 model_version,inputs,event_time) values(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb,%s)""",
                (prop.id, prop.canonicalPlayerId or prop.playerId, prop.sport.upper(), prop.market,
                 side, prop.line, projection, probability, snapshot_model_version,
                 json.dumps({"playerName": prop.player, "sportsbook": prop.sportsbook,
                             "matchup": prop.matchup, "confidence": prop.confidence,
                             "edge": prop.recommendationEdge,
                             "modelProbability": prop.modelProbability,
                             "marketProbability": prop.marketProbability,
                             "pushProbability": prop.pushProbability,
                             "probabilityMethod": prop.probabilityMethod,
                             "marketBlendWeight": prop.probabilityMarketWeight,
                             "calibrationAdjustment": prop.probabilityCalibrationAdjustment,
                             "calibrationSampleSize": prop.probabilityCalibrationSampleSize,
                             "expectedValuePercentage": prop.evPercentage,
                             "entryOdds": prop.overOdds if side == "OVER" else prop.underOdds,
                             "openingLine": prop.openingLine,
                             "currentLine": prop.currentLine}), event_time))
            created += 1
        connection.commit()
    return {"created": created, "modelVersion": model_version}


def grade_completed_predictions() -> dict[str, object]:
    if not database_is_configured():
        return {"graded": 0, "reason": "DATABASE_URL is not configured"}
    graded, unsupported = 0, 0
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""select id,sport,market,side,line,event_time,inputs->>'playerName',
            player_id,inputs->>'matchup'
            from prediction_snapshots where graded_at is null and event_time < now() - interval '3 hours'
            and created_at < event_time - interval '5 minutes'
            order by event_time limit 5000""")
        pending = cursor.fetchall()
        for identifier, sport, market, side, line, event_time, player_name, player_id, matchup in pending:
            if sport not in TRACKED_SPORTS or not player_name or event_time is None:
                unsupported += 1
                continue
            if sport == "MLB":
                official = official_mlb_result(
                    player_name=str(player_name),
                    market=str(market),
                    matchup=str(matchup or ""),
                    game_start_time=event_time.isoformat(),
                )
                actual = official.value if official is not None else None
            elif sport in {"NBA", "WNBA"}:
                cursor.execute("""select points,rebounds,assists,steals,blocks,turnovers,threes
                    from historical_basketball_game_logs where sport=%s and lower(player_name)=lower(%s)
                    and game_date=%s order by updated_at desc limit 1""",
                    (sport, player_name, event_time.date()))
                row = cursor.fetchone()
                if row is None:
                    continue
                actual = _market_value(str(market), row)
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
            if actual is None:
                unsupported += 1
                continue
            hit = actual > float(line) if side == "OVER" else actual < float(line)
            cursor.execute("""update prediction_snapshots set actual_value=%s,hit=%s,graded_at=now(),
                inputs=jsonb_set(inputs,'{resultSource}',to_jsonb(%s::text),true)
                where id=%s""", (
                    actual,
                    hit,
                    (
                        "mlb-stats-api"
                        if sport == "MLB"
                        else "historical-game-logs"
                        if sport in {"NBA", "WNBA"}
                        else "sportsdataio"
                    ),
                    identifier,
                ))
            graded += 1
        connection.commit()
    return {"graded": graded, "pendingChecked": len(pending), "unsupported": unsupported,
            "gradedAt": datetime.now(timezone.utc).isoformat()}


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
    if "points rebounds assists" in text or "pra" in text: return points + rebounds + assists
    if "points rebounds" in text: return points + rebounds
    if "points assists" in text: return points + assists
    if "rebounds assists" in text: return rebounds + assists
    if "three" in text or "3 pointer" in text: return threes
    if "rebound" in text: return rebounds
    if "assist" in text: return assists
    if "steal" in text: return steals
    if "block" in text: return blocks
    if "turnover" in text: return turnovers
    if "point" in text: return points
    return None
