"""Privacy-conscious engagement collection and unique-user sentiment rollups."""
from datetime import datetime, timezone
import json
import threading

from database.postgres import database_is_configured, get_database_pool
from models.intelligence import SentimentEvent
from services.operations_notification_service import notify_operations_alert

_alert_lock = threading.Lock()
_last_prop_alert_at: datetime | None = None

WEIGHTS = {"VIEW": 1.0, "SEARCH": 1.5, "CLICK": 2.0, "WATCHLIST": 4.0,
           "PICK_OVER": 5.0, "PICK_UNDER": -5.0}


PRODUCT_FUNNELS = {
    "research": (
        ("App opened", "APP_OPEN"),
        ("Dashboard ready", "DASHBOARD_READY"),
        ("Prop selected", "PROP_SELECTED"),
        ("Slip locked", "SLIP_LOCKED"),
    ),
    "subscription": (
        ("Paywall viewed", "PAYWALL_VIEW"),
        ("Checkout started", "CHECKOUT_STARTED"),
        ("Purchase completed", "PURCHASE_COMPLETED"),
    ),
    "activation": (
        ("Landing page", "LANDING_VIEW"), ("Signup started", "SIGNUP_STARTED"),
        ("Email verified", "EMAIL_VERIFIED"), ("First prop", "FIRST_PROP"),
        ("PI Intelligence opened", "PI_INTELLIGENCE_OPENED"),
        ("Returned", "RETURNING_USER"),
    ),
}


def _funnel_rows(
    events: dict[str, int], unique_users: dict[str, int]
) -> dict[str, list[dict[str, object]]]:
    result: dict[str, list[dict[str, object]]] = {}
    for funnel, stages in PRODUCT_FUNNELS.items():
        previous_users: int | None = None
        rows: list[dict[str, object]] = []
        for label, event in stages:
            users = int(unique_users.get(event, 0))
            conversion = (
                round(users / previous_users, 4)
                if previous_users is not None and previous_users > 0
                else None
            )
            rows.append({
                "label": label,
                "event": event,
                "events": int(events.get(event, 0)),
                "uniqueUsers": users,
                "conversionFromPrevious": conversion,
            })
            previous_users = users
        result[funnel] = rows
    return result

def record_engagement(user_id: str, events: list[SentimentEvent]) -> dict[str, object]:
    if not database_is_configured():
        return {"recorded": 0, "reason": "DATABASE_URL is not configured"}
    rows = [(user_id, event.prop_id, event.action, event.duration_ms,
             json.dumps({str(k)[:40]: str(v)[:160] for k, v in event.metadata.items()}))
            for event in events]
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.executemany("""insert into prop_engagement_events
                (user_id,prop_id,action,duration_ms,metadata)
                values (%s,%s,%s,%s,%s::jsonb)""", rows)
            connection.commit()
    except Exception as exc:
        # Product telemetry must never interrupt authentication or the live
        # board while a schema migration is still rolling through production.
        return {"recorded": 0, "reason": f"engagement unavailable: {type(exc).__name__}"}
    _maybe_alert_prop_failures()
    return {"recorded": len(rows), "propIds": sorted({event.prop_id for event in events})}


def _maybe_alert_prop_failures() -> None:
    global _last_prop_alert_at
    now = datetime.now(timezone.utc)
    with _alert_lock:
        if _last_prop_alert_at and (now - _last_prop_alert_at).total_seconds() < 900:
            return
        try:
            with get_database_pool().connection() as connection, connection.cursor() as cursor:
                cursor.execute("""select
                    count(*) filter (where action='PROP_LOAD_SUCCESS'),
                    count(*) filter (where action='PROP_LOAD_FAILURE')
                    from prop_engagement_events
                    where created_at >= now()-interval '15 minutes'""")
                successes, failures = (int(value or 0) for value in cursor.fetchone())
        except Exception:
            return
        total = successes + failures
        failure_rate = failures / total if total else 0
        if total >= 20 and failure_rate >= .10 and notify_operations_alert(
            kind="prop_load_slo",
            summary=(f"Customer prop-board failures reached {failure_rate:.1%} "
                     f"({failures} of {total} loads in 15m)"),
            details={"windowMinutes": 15, "customerLoads": total,
                     "failures": failures, "successes": successes},
        ):
            _last_prop_alert_at = now


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
        "errorUsers": {},
        "funnels": _funnel_rows({}, {}),
        "reliability": {
            "appUsers": 0,
            "errorUsers": 0,
            "errorFreeUserRate": None,
            "slowLoadUsers": 0,
            "checkoutFailures": 0,
            "apiAvailability": None, "propLoadSuccessRate": None,
            "cachedContentP95Ms": None, "liveResultsP95Ms": None,
        },
        "slos": {}, "mediaFailuresByProvider": {}, "releases": {},
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
            """select prop_id,count(*),count(distinct user_id)
               from prop_engagement_events
               where prop_id like '__ERROR__:%'
                 and created_at >= now()-(%s * interval '1 hour')
               group by prop_id order by count(*) desc limit 20""",
            (window_hours,),
        )
        error_rows = cursor.fetchall()
        cursor.execute(
            """select count(distinct user_id)
               from prop_engagement_events
               where prop_id like '__ERROR__:%'
                 and created_at >= now()-(%s * interval '1 hour')""",
            (window_hours,),
        )
        distinct_error_users = int(cursor.fetchone()[0] or 0)
        cursor.execute("""select action,count(*),
                   percentile_cont(.95) within group(order by duration_ms)
                   filter (where duration_ms is not null)
               from prop_engagement_events
               where action in ('API_SUCCESS','API_FAILURE','PROP_LOAD_SUCCESS',
                   'PROP_LOAD_FAILURE','SCREEN_TIMING','MEDIA_FAILURE','WEB_VITAL')
                 and created_at >= now()-(%s * interval '1 hour')
               group by action""", (window_hours,))
        operational_rows = cursor.fetchall()
        cursor.execute("""select coalesce(metadata->>'provider','unknown'),
                   coalesce(metadata->>'mediaType','unknown'),count(*)
               from prop_engagement_events where action='MEDIA_FAILURE'
                 and created_at >= now()-(%s * interval '1 hour')
               group by 1,2 order by 3 desc""", (window_hours,))
        media_rows = cursor.fetchall()
        cursor.execute("""select coalesce(metadata->>'release','unknown'),count(*)
               from prop_engagement_events
               where created_at >= now()-(%s * interval '1 hour')
               group by 1 order by 2 desc limit 10""", (window_hours,))
        release_rows = cursor.fetchall()
        cursor.execute("""select metadata->>'metric', metadata->>'device',
                   percentile_cont(.75) within group(order by duration_ms)
               from prop_engagement_events where action='WEB_VITAL'
                 and created_at >= now()-(%s * interval '1 hour')
               group by 1,2""", (window_hours,))
        vital_rows = cursor.fetchall()

    events = {str(action): int(count) for action, count, _ in event_rows}
    unique_users = {
        str(action): int(users) for action, _, users in event_rows
    }
    errors = {
        str(fingerprint).removeprefix("__ERROR__:"): int(count)
        for fingerprint, count, _ in error_rows
    }
    error_users = {
        str(fingerprint).removeprefix("__ERROR__:"): int(users)
        for fingerprint, _, users in error_rows
    }
    app_users = int(unique_users.get("APP_OPEN", 0))
    affected_users = min(app_users, distinct_error_users) if app_users else 0
    operational = {str(action): {"count": int(count), "p95Ms": int(p95) if p95 is not None else None}
                   for action, count, p95 in operational_rows}
    api_success = operational.get("API_SUCCESS", {}).get("count", 0)
    api_failure = operational.get("API_FAILURE", {}).get("count", 0)
    prop_success = operational.get("PROP_LOAD_SUCCESS", {}).get("count", 0)
    prop_failure = operational.get("PROP_LOAD_FAILURE", {}).get("count", 0)
    api_rate = api_success / (api_success + api_failure) if api_success + api_failure else None
    prop_rate = prop_success / (prop_success + prop_failure) if prop_success + prop_failure else None
    cached_p95 = operational.get("SCREEN_TIMING", {}).get("p95Ms")
    live_p95 = operational.get("PROP_LOAD_SUCCESS", {}).get("p95Ms")
    media = {}
    for provider, media_type, count in media_rows:
        media.setdefault(str(provider), {})[str(media_type)] = int(count)
    return {
        **empty,
        "available": True,
        "events": events,
        "uniqueUsers": unique_users,
        "errors": errors,
        "errorUsers": error_users,
        "funnels": _funnel_rows(events, unique_users),
        "reliability": {
            "appUsers": app_users,
            "errorUsers": affected_users,
            "errorFreeUserRate": (
                round((app_users - affected_users) / app_users, 4)
                if app_users else None
            ),
            "slowLoadUsers": int(unique_users.get("SLOW_LOAD", 0)),
            "checkoutFailures": int(events.get("CHECKOUT_FAILED", 0)),
            "apiAvailability": round(api_rate, 4) if api_rate is not None else None,
            "propLoadSuccessRate": round(prop_rate, 4) if prop_rate is not None else None,
            "cachedContentP95Ms": cached_p95, "liveResultsP95Ms": live_p95,
        },
        "slos": {
            "apiAvailability": {"target": .999, "actual": round(api_rate, 4) if api_rate is not None else None},
            "propBoardLoads": {"target": .99, "actual": round(prop_rate, 4) if prop_rate is not None else None},
            "cachedContentMs": {"target": 2000, "actual": cached_p95},
            "liveResultsMs": {"target": 5000, "actual": live_p95},
        },
        "mediaFailuresByProvider": media,
        "releases": {str(release): int(count) for release, count in release_rows},
        "webVitalsP75": {
            f"{metric}:{device}": int(value) if value is not None else None
            for metric, device, value in vital_rows
        },
    }
