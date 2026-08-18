"""Track member joins and send a one-time owner notification per member."""

from __future__ import annotations

from datetime import datetime, timezone

from database.postgres import database_is_configured, get_database_pool
from services.operations_notification_service import notify_member_signup


def _ensure_member_signup_table() -> None:
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """create table if not exists member_signup_notifications (
                id bigserial primary key,
                user_id text not null unique,
                email text not null default '',
                source text not null default 'app',
                first_seen_at timestamptz not null default now(),
                last_seen_at timestamptz not null default now(),
                notified_at timestamptz,
                delivery_status text not null default 'pending'
            )"""
        )
        cursor.execute(
            """create index if not exists member_signup_notifications_first_seen_idx
               on member_signup_notifications(first_seen_at desc)"""
        )
        cursor.execute(
            "alter table member_signup_notifications enable row level security"
        )
        cursor.execute(
            "alter table member_signup_notifications force row level security"
        )
        cursor.execute(
            "revoke all on member_signup_notifications from anon, authenticated"
        )
        connection.commit()


def record_member_join(
    user_id: str,
    *,
    email: str = "",
    source: str = "app",
) -> dict[str, object]:
    normalized_user_id = user_id.strip()
    if not normalized_user_id:
        return {"recorded": False, "reason": "missing_user_id"}
    if not database_is_configured():
        return {"recorded": False, "reason": "DATABASE_URL is not configured"}

    _ensure_member_signup_table()

    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """insert into member_signup_notifications(user_id, email, source)
               values (%s, %s, %s)
               on conflict (user_id)
               do update set
                   email = excluded.email,
                   source = excluded.source,
                   last_seen_at = now()
               returning first_seen_at, notified_at, delivery_status""",
            (normalized_user_id, email.strip()[:240], source.strip()[:80] or "app"),
        )
        row = cursor.fetchone()

        delivered = False
        delivery_status = str(row[2]) if row and row[2] is not None else "pending"
        notified_at = row[1] if row else None

        if notified_at is None:
            delivered = notify_member_signup(
                user_id=normalized_user_id,
                email=email.strip(),
                source=source,
            )
            delivery_status = "delivered" if delivered else "delivery_failed"
            cursor.execute(
                """update member_signup_notifications
                   set delivery_status=%s,
                       notified_at=case when %s then now() else notified_at end,
                       last_seen_at=now()
                   where user_id=%s""",
                (delivery_status, delivered, normalized_user_id),
            )

        connection.commit()

    return {
        "recorded": True,
        "userId": normalized_user_id,
        "deliveryStatus": delivery_status,
        "alertDelivered": delivered or delivery_status == "delivered",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
