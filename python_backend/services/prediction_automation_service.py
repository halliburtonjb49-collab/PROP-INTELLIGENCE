"""Create daily model snapshots from live props and grade completed basketball games."""

from __future__ import annotations

import json
from datetime import datetime, timezone

from database.postgres import database_is_configured, get_database_pool
from services.prop_service import get_props


def snapshot_live_predictions(model_version: str = "intelligence-v1") -> dict[str, object]:
    if not database_is_configured():
        return {"created": 0, "reason": "DATABASE_URL is not configured"}
    created = 0
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        for prop in get_props():
            side = prop.recommendedSide.upper()
            if prop.sport.upper() not in {"NBA", "WNBA"}:
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
            probability = max(.5, min(.95, prop.confidence / 100))
            cursor.execute("""select 1 from prediction_snapshots where prop_id=%s and model_version=%s
                and snapshot_date=(now() at time zone 'UTC')::date limit 1""", (prop.id, model_version))
            if cursor.fetchone():
                continue
            cursor.execute("""insert into prediction_snapshots
                (prop_id,player_id,sport,market,side,line,projection,hit_probability,
                 model_version,inputs,event_time) values(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb,%s)""",
                (prop.id, prop.canonicalPlayerId or prop.playerId, prop.sport.upper(), prop.market,
                 side, prop.line, projection, probability, model_version,
                 json.dumps({"playerName": prop.player, "sportsbook": prop.sportsbook,
                             "matchup": prop.matchup, "confidence": prop.confidence,
                             "edge": prop.recommendationEdge}), event_time))
            created += 1
        connection.commit()
    return {"created": created, "modelVersion": model_version}


def grade_completed_predictions() -> dict[str, object]:
    if not database_is_configured():
        return {"graded": 0, "reason": "DATABASE_URL is not configured"}
    graded, unsupported = 0, 0
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""select id,sport,market,side,line,event_time,inputs->>'playerName'
            from prediction_snapshots where graded_at is null and event_time < now() - interval '3 hours'
            and created_at < event_time - interval '5 minutes'
            order by event_time limit 5000""")
        pending = cursor.fetchall()
        for identifier, sport, market, side, line, event_time, player_name in pending:
            if sport not in {"NBA", "WNBA"} or not player_name or event_time is None:
                unsupported += 1
                continue
            cursor.execute("""select points,rebounds,assists,steals,blocks,turnovers,threes
                from historical_basketball_game_logs where sport=%s and lower(player_name)=lower(%s)
                and game_date=%s order by updated_at desc limit 1""",
                (sport, player_name, event_time.date()))
            row = cursor.fetchone()
            if row is None:
                continue
            actual = _market_value(str(market), row)
            if actual is None:
                unsupported += 1
                continue
            hit = actual > float(line) if side == "OVER" else actual < float(line)
            cursor.execute("""update prediction_snapshots set actual_value=%s,hit=%s,graded_at=now()
                where id=%s""", (actual, hit, identifier))
            graded += 1
        connection.commit()
    return {"graded": graded, "pendingChecked": len(pending), "unsupported": unsupported,
            "gradedAt": datetime.now(timezone.utc).isoformat()}


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
