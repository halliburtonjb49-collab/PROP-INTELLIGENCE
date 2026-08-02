from __future__ import annotations

import hashlib
from uuid import uuid4

from database.postgres import database_is_configured, get_database_pool
from models.sync_diagnostic import TicketSyncDiagnostic
from services.security_event_service import record_security_event


def _fingerprint(value: str) -> str | None:
    normalized = value.strip()
    if not normalized:
        return None
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:16]


def record_ticket_sync_diagnostic(
    request: TicketSyncDiagnostic, *, user_id: str
) -> dict[str, object]:
    diagnostic_id = f"SYNC-{uuid4().hex[:10].upper()}"
    record_security_event(
        "ticket_sync_diagnostic",
        identity=user_id,
        route="/api/support/ticket-sync-diagnostic",
        method="POST",
        outcome=request.error_category,
        metadata={
            "diagnosticId": diagnostic_id,
            "phase": request.phase,
            "attempts": request.attempts,
            "platform": request.platform,
            "requestFingerprint": _fingerprint(request.client_request_id),
        },
    )
    return {"status": "received", "diagnosticId": diagnostic_id}


def ticket_sync_diagnostic_summary() -> dict[str, object]:
    result: dict[str, object] = {
        "databaseConfigured": database_is_configured(),
        "last24Hours": 0,
        "last7Days": 0,
        "categories": [],
    }
    if not database_is_configured():
        return result
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """
                select
                  count(*) filter(where occurred_at >= now() - interval '24 hours'),
                  count(*)
                from public.security_events
                where event_type = 'ticket_sync_diagnostic'
                  and occurred_at >= now() - interval '7 days'
                """
            )
            last_24, last_7 = cursor.fetchone()
            cursor.execute(
                """
                select outcome, count(*)
                from public.security_events
                where event_type = 'ticket_sync_diagnostic'
                  and occurred_at >= now() - interval '7 days'
                group by outcome order by count(*) desc, outcome
                """
            )
            result.update(
                last24Hours=int(last_24 or 0),
                last7Days=int(last_7 or 0),
                categories=[
                    {"category": str(category), "count": int(count)}
                    for category, count in cursor.fetchall()
                ],
            )
    except Exception as exc:
        result["error"] = type(exc).__name__
    return result
