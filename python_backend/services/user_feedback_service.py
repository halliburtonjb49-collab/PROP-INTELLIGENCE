"""User feedback intake and owner review utilities."""

from __future__ import annotations

from datetime import datetime, timezone
import json

from database.postgres import database_is_configured, get_database_pool


DEFAULT_CATEGORY = "suggestion"
ALLOWED_CATEGORIES = {"suggestion", "issue", "recommendation", "other"}


def _clean_category(value: object) -> str:
    text = str(value or "").strip().lower()
    return text if text in ALLOWED_CATEGORIES else DEFAULT_CATEGORY


def _clean_message(value: object) -> str:
    text = str(value or "").strip()
    return text[:4000]


def _ensure_feedback_table() -> None:
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """create table if not exists user_feedback_messages (
                id bigserial primary key,
                user_id text not null,
                category text not null,
                message text not null,
                page text not null default '',
                status text not null default 'new',
                metadata jsonb not null default '{}'::jsonb,
                created_at timestamptz not null default now(),
                reviewed_at timestamptz,
                reviewed_by text
            )"""
        )
        cursor.execute(
            """create index if not exists user_feedback_messages_created_idx
               on user_feedback_messages(created_at desc)"""
        )
        cursor.execute(
            """create index if not exists user_feedback_messages_status_idx
               on user_feedback_messages(status)"""
        )
        cursor.execute(
            "alter table user_feedback_messages enable row level security"
        )
        cursor.execute(
            "alter table user_feedback_messages force row level security"
        )
        cursor.execute(
            "revoke all on user_feedback_messages from anon, authenticated"
        )
        connection.commit()


def submit_feedback(
    user_id: str,
    *,
    category: object,
    message: object,
    page: object = "",
    metadata: dict[str, object] | None = None,
) -> dict[str, object]:
    body = _clean_message(message)
    if len(body) < 5:
        return {
            "saved": False,
            "reason": "message_too_short",
        }
    payload_metadata = metadata if isinstance(metadata, dict) else {}
    if not database_is_configured():
        return {
            "saved": False,
            "reason": "DATABASE_URL is not configured",
        }

    _ensure_feedback_table()
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """insert into user_feedback_messages
                (user_id, category, message, page, metadata)
                values (%s, %s, %s, %s, %s::jsonb)
                returning id, created_at""",
            (
                user_id,
                _clean_category(category),
                body,
                str(page or "").strip()[:120],
                json.dumps(payload_metadata),
            ),
        )
        row = cursor.fetchone()
        connection.commit()
    return {
        "saved": True,
        "id": int(row[0]) if row else None,
        "createdAt": row[1].isoformat() if row and row[1] is not None else None,
    }


def list_feedback(limit: int = 50, status: str | None = None) -> dict[str, object]:
    if not database_is_configured():
        return {
            "available": False,
            "reason": "DATABASE_URL is not configured",
            "items": [],
        }
    _ensure_feedback_table()
    bounded_limit = max(1, min(limit, 200))
    status_value = str(status or "").strip().lower()

    where_clause = ""
    params: list[object] = []
    if status_value:
        where_clause = "where status = %s"
        params.append(status_value)

    query = f"""select id, user_id, category, message, page, status, created_at,
        reviewed_at, reviewed_by
        from user_feedback_messages
        {where_clause}
        order by created_at desc
        limit %s"""
    params.append(bounded_limit)

    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(query, params)
        rows = cursor.fetchall()
        cursor.execute(
            """select
                count(*) filter(where created_at >= now() - interval '24 hours'),
                count(*) filter(where created_at >= now() - interval '7 days'),
                count(*) filter(where status = 'new'),
                count(*)
            from user_feedback_messages"""
        )
        c24h, c7d, new_count, total = cursor.fetchone()

    items = [
        {
            "id": int(row[0]),
            "userId": str(row[1]),
            "category": str(row[2]),
            "message": str(row[3]),
            "page": str(row[4] or ""),
            "status": str(row[5]),
            "createdAt": row[6].isoformat() if row[6] is not None else None,
            "reviewedAt": row[7].isoformat() if row[7] is not None else None,
            "reviewedBy": str(row[8] or ""),
        }
        for row in rows
    ]
    return {
        "available": True,
        "summary": {
            "last24Hours": int(c24h or 0),
            "last7Days": int(c7d or 0),
            "new": int(new_count or 0),
            "total": int(total or 0),
            "generatedAt": datetime.now(timezone.utc).isoformat(),
        },
        "items": items,
    }
