"""Privacy-conscious engagement collection and unique-user sentiment rollups."""
from datetime import datetime, timezone

from database.postgres import database_is_configured, get_database_pool
from models.intelligence import SentimentEvent

WEIGHTS = {"VIEW": 1.0, "SEARCH": 1.5, "CLICK": 2.0, "WATCHLIST": 4.0,
           "PICK_OVER": 5.0, "PICK_UNDER": -5.0}


def record_engagement(user_id: str, events: list[SentimentEvent]) -> dict[str, object]:
    if not database_is_configured():
        return {"recorded": 0, "reason": "DATABASE_URL is not configured"}
    rows = [(user_id, event.prop_id, event.action) for event in events]
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.executemany("insert into prop_engagement_events(user_id,prop_id,action) values (%s,%s,%s)", rows)
        connection.commit()
    return {"recorded": len(rows), "propIds": sorted({event.prop_id for event in events})}


def sentiment_rollup(prop_id: str, hours: int = 24) -> dict[str, object]:
    if not database_is_configured():
        return {"propId": prop_id, "score": 0, "label": "NEUTRAL", "sampleSize": 0,
                "uniqueUsers": 0, "windowHours": hours}
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        # Each user contributes at most once per action in the window, limiting click spam.
        cursor.execute("""select action,count(*) from (
            select distinct user_id,action from prop_engagement_events
            where prop_id=%s and created_at >= now()-(%s * interval '1 hour') and user_id is not null
        ) unique_actions group by action""", (prop_id, hours))
        counts = {str(action): int(count) for action, count in cursor.fetchall()}
        cursor.execute("""select count(distinct user_id) from prop_engagement_events
            where prop_id=%s and created_at >= now()-(%s * interval '1 hour')""", (prop_id, hours))
        unique_users = int(cursor.fetchone()[0])
    raw = sum(WEIGHTS.get(action, 0) * count for action, count in counts.items())
    score = max(-100.0, min(100.0, raw))
    return {"propId": prop_id, "score": round(score, 1),
            "label": "FOLLOW" if score >= 15 else "FADE" if score <= -15 else "NEUTRAL",
            "sampleSize": sum(counts.values()), "uniqueUsers": unique_users,
            "actions": counts, "windowHours": hours, "updatedAt": datetime.now(timezone.utc).isoformat()}


def product_observability(hours: int = 168) -> dict[str, object]:
    """Return aggregate product events without exposing users or raw errors."""
    window_hours = max(1, min(int(hours), 24 * 90))
    empty = {
        "windowHours": window_hours,
        "events": {},
        "uniqueUsers": {},
        "errors": {},
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
    }
    if not database_is_configured():
        return {**empty, "available": False}

    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select action,count(*),count(distinct user_id)
               from prop_engagement_events
               where prop_id='__PRODUCT__'
                 and created_at >= now()-(%s * interval '1 hour')
               group by action""",
            (window_hours,),
        )
        event_rows = cursor.fetchall()
        cursor.execute(
            """select prop_id,count(*)
               from prop_engagement_events
               where prop_id like '__ERROR__:%'
                 and created_at >= now()-(%s * interval '1 hour')
               group by prop_id order by count(*) desc limit 20""",
            (window_hours,),
        )
        error_rows = cursor.fetchall()

    return {
        **empty,
        "available": True,
        "events": {str(action): int(count) for action, count, _ in event_rows},
        "uniqueUsers": {
            str(action): int(users) for action, _, users in event_rows
        },
        "errors": {
            str(fingerprint).removeprefix("__ERROR__:"): int(count)
            for fingerprint, count in error_rows
        },
    }
