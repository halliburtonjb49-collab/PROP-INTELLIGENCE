"""The records behind each operations tile.

The control panel reports counts. A count tells the owner that four people
signed up and nothing about who, so every number that raises a question sends
them to the database to answer it. These queries return the rows each tile
counted, using the same windows and filters, so the detail can never disagree
with the number that led to it.

Emails are masked. The owner needs to recognise an account and follow it up,
which a masked address supports; a screen that lists every address in full is
a larger exposure than the job requires, and this panel is read over the
owner's shoulder as often as not.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Mapping

from database.postgres import database_is_configured, get_database_pool
from services.launch_control_service import FAILED_PAYMENT_EVENTS
from services.supabase_account_metrics_service import (
    enrich_active_user_rows,
    supabase_account_rows,
)

# One screen of records. The tile shows the true count; this bounds what is
# transferred and rendered, and the response says when it has truncated.
DEFAULT_LIMIT = 50
MAXIMUM_LIMIT = 200


def mask_email(value: object) -> str:
    """Enough of an address to recognise an account, not enough to reuse it."""

    text = str(value or "").strip()
    if "@" not in text:
        return "--"
    local, _, domain = text.partition("@")
    if len(local) <= 2:
        visible = local[:1]
    else:
        visible = local[:2]
    return f"{visible}{'*' * max(1, len(local) - len(visible))}@{domain}"


def _isoformat(value: object) -> str | None:
    return value.isoformat() if hasattr(value, "isoformat") else None


@dataclass(frozen=True)
class DetailQuery:
    title: str
    description: str
    columns: tuple[str, ...]
    build: Callable[[object, int], list[dict[str, object]]]


def _new_signups(cursor: object, limit: int) -> list[dict[str, object]]:
    cursor.execute(
        """select coalesce(to_jsonb(profile)->>'email', ''),
                   coalesce(to_jsonb(profile)->>'display_name',
                            to_jsonb(profile)->>'full_name', ''),
                   created_at
            from public.user_profiles profile
            where created_at >= now() - interval '24 hours'
            order by created_at desc limit %s""",
        (limit,),
    )
    return [
        {"email": str(account or ""), "userId": "", "name": str(display_name or "--"),
         "member": mask_email(account), "signedUpAt": _isoformat(created_at),
         "source": "profile", "notification": "recorded"}
        for account, display_name, created_at in cursor.fetchall()
    ]


def _active_users(cursor: object, limit: int) -> list[dict[str, object]]:
    cursor.execute(
        """select actor_hash, count(*) as events, max(occurred_at) as last_seen
           from public.security_events
           where occurred_at >= now() - interval '15 minutes'
             and actor_hash is not null
             and event_type = 'protected_feature_access'
           group by actor_hash
           order by last_seen desc
           limit %s""",
        (limit,),
    )
    return [
        {
            # Already a hash upstream; shortened only so it fits a row.
            "actor": str(actor),
            "requests": int(events or 0),
            "lastSeenAt": _isoformat(last_seen),
        }
        for actor, events, last_seen in cursor.fetchall()
    ]


def _failed_payments(cursor: object, limit: int) -> list[dict[str, object]]:
    cursor.execute(
        """select occurred_at, metadata->>'eventType' as event_type,
                  actor_hash
           from public.security_events
           where occurred_at >= now() - interval '24 hours'
             and event_type = 'subscription_event_applied'
             and upper(coalesce(metadata->>'eventType', '')) = any(%s)
           order by occurred_at desc
           limit %s""",
        (list(FAILED_PAYMENT_EVENTS), limit),
    )
    return [
        {
            "occurredAt": _isoformat(occurred_at),
            "event": str(event_type or "--"),
            "actor": str(actor or "--")[:12],
        }
        for occurred_at, event_type, actor in cursor.fetchall()
    ]


def _unsettled_slips(cursor: object, limit: int) -> list[dict[str, object]]:
    cursor.execute(
        """select id, created_at, coalesce(jsonb_array_length(legs), 0) as leg_count
           from public.slips
           where status = 'active'
           order by created_at desc
           limit %s""",
        (limit,),
    )
    return [
        {
            "slipId": str(slip_id)[:12],
            "createdAt": _isoformat(created_at),
            "legs": int(leg_count or 0),
        }
        for slip_id, created_at, leg_count in cursor.fetchall()
    ]


DETAILS: Mapping[str, DetailQuery] = {
    "members": DetailQuery(
        title="All members",
        description="Every canonical Supabase member account.",
        columns=("email", "username", "userId", "name", "member", "signedUpAt", "lastUpdatedAt"),
        build=_new_signups,
    ),
    "newSignups": DetailQuery(
        title="New signups",
        description="Accounts created in the last 24 hours.",
        columns=("email", "username", "userId", "name", "member", "signedUpAt", "source"),
        build=_new_signups,
    ),
    "activeUsers": DetailQuery(
        title="Active users",
        description="Distinct users on protected features in the last 15 minutes.",
        columns=("email", "username", "userId", "name", "member", "requests", "lastSeenAt"),
        build=_active_users,
    ),
    "coreMembers": DetailQuery(
        title="Core members",
        description="Every account with active Core access.",
        columns=("email", "username", "userId", "name", "member", "signedUpAt", "lastUpdatedAt"),
        build=_new_signups,
    ),
    "proMembers": DetailQuery(
        title="Pro members",
        description="Every account with active Pro, Edge, Gold, or Founder access.",
        columns=("email", "username", "userId", "name", "member", "signedUpAt", "lastUpdatedAt"),
        build=_new_signups,
    ),
    "failedPayments": DetailQuery(
        title="Failed payments",
        description="Subscription payment failures in the last 24 hours.",
        columns=("occurredAt", "event", "actor"),
        build=_failed_payments,
    ),
    "unsettledSlips": DetailQuery(
        title="Unsettled slips",
        description="Slips still open and awaiting settlement.",
        columns=("slipId", "createdAt", "legs"),
        build=_unsettled_slips,
    ),
}


def available_details() -> list[str]:
    return sorted(DETAILS)


def operations_detail(
    metric: str,
    *,
    limit: int | None = DEFAULT_LIMIT,
) -> dict[str, object]:
    """Rows behind one tile, or an explicit reason none can be shown."""

    key = str(metric or "").strip()
    query = DETAILS.get(key)
    requested = DEFAULT_LIMIT if limit is None else int(limit)
    bounded = max(1, min(requested, MAXIMUM_LIMIT))
    if key == "members":
        bounded = MAXIMUM_LIMIT
    if key in {"members", "newSignups", "coreMembers", "proMembers"}:
        try:
            rows = supabase_account_rows(bounded)
            if rows is not None:
                if key == "coreMembers":
                    rows = [row for row in rows if str(row.get("member") or "").lower() == "core"]
                elif key == "proMembers":
                    rows = [
                        row for row in rows
                        if str(row.get("member") or "").lower()
                        in {"pro", "edge", "gold", "pro_gold", "pro-gold", "pro_founder"}
                    ]
                return {
                    "metric": key,
                    "supported": True,
                    "title": DETAILS[key].title,
                    "description": DETAILS[key].description,
                    "columns": list(DETAILS[key].columns),
                    "rows": rows,
                    "returned": len(rows),
                    "truncated": False,
                }
        except Exception:
            pass
    if key in {"providers", "propFreshness"}:
        try:
            from services.owner_command_center_service import owner_command_center_snapshot
            inventory = owner_command_center_snapshot().get("inventory") or {}
            if key == "providers":
                rows = list(inventory.get("providers") or [])[:MAXIMUM_LIMIT]
                return {"metric": key, "supported": True,
                        "title": "Provider inventory",
                        "description": "Live prop volume and quality by provider.",
                        "columns": ["provider", "status", "props", "sports", "stale", "suspicious", "lastUpdate"],
                        "rows": rows, "returned": len(rows), "truncated": False}
            rows = list(inventory.get("items") or [])[:MAXIMUM_LIMIT]
            return {"metric": key, "supported": True,
                    "title": "Prop freshness",
                    "description": "Most recent catalog records and their quality state.",
                    "columns": ["player", "sport", "market", "provider", "line", "qualityStatus", "lastUpdate"],
                    "rows": rows, "returned": len(rows),
                    "truncated": bool(inventory.get("truncated"))}
        except Exception as exc:
            return {"metric": key, "supported": True,
                    "reason": type(exc).__name__, "rows": []}
    if query is None:
        return {
            "metric": key,
            "supported": False,
            "reason": "no_detail_for_metric",
            "available": available_details(),
            "rows": [],
        }
    if not database_is_configured():
        return {
            "metric": key,
            "supported": True,
            "reason": "database_not_configured",
            "rows": [],
        }

    # An omitted limit takes the default; an explicit zero is clamped rather
    # than silently reinterpreted as "give me the default fifty".
    try:
        with get_database_pool().connection() as connection:
            with connection.cursor() as cursor:
                rows = query.build(cursor, bounded)
                if key == "activeUsers":
                    rows = enrich_active_user_rows(rows)
    except Exception as exc:
        # The tile keeps working; only its detail is unavailable.
        return {
            "metric": key,
            "supported": True,
            "reason": type(exc).__name__,
            "rows": [],
        }

    return {
        "metric": key,
        "supported": True,
        "title": query.title,
        "description": query.description,
        "columns": list(query.columns),
        "rows": rows,
        "returned": len(rows),
        "limit": bounded,
        # The tile shows the real total; this says whether the list is all of
        # it, so a screen of fifty never reads as the whole story.
        "truncated": len(rows) >= bounded,
    }
