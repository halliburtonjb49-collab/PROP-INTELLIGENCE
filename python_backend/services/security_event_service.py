"""Best-effort structured security audit events without storing credentials."""

from __future__ import annotations

import hashlib
import base64
import json
import json
import logging

from database.postgres import database_is_configured, get_database_pool

LOGGER = logging.getLogger(__name__)


def stable_actor_identity(authorization: str, fallback: str = "") -> str:
    """Return the stable JWT subject for telemetry, never the rotating token."""

    value = str(authorization or "").strip()
    if value.lower().startswith("bearer "):
        token = value.split(" ", 1)[1].strip()
        parts = token.split(".")
        if len(parts) == 3:
            try:
                encoded = parts[1] + "=" * (-len(parts[1]) % 4)
                payload = json.loads(base64.urlsafe_b64decode(encoded))
                subject = str(payload.get("sub") or "").strip()
                if subject:
                    return subject
            except (ValueError, TypeError, json.JSONDecodeError):
                pass
    return str(fallback or value).strip()


def actor_hash(identity: str) -> str | None:
    normalized = identity.strip()
    if not normalized:
        return None
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def record_security_event(
    event_type: str,
    *,
    identity: str = "",
    route: str = "",
    method: str = "",
    outcome: str,
    metadata: dict[str, object] | None = None,
) -> None:
    """Persist a bounded event and always emit a credential-free log record."""
    safe_metadata = metadata or {}
    hashed_actor = actor_hash(identity)
    LOGGER.info(
        "security_event type=%s outcome=%s route=%s method=%s actor=%s metadata=%s",
        event_type,
        outcome,
        route,
        method,
        hashed_actor,
        json.dumps(safe_metadata, sort_keys=True, default=str)[:1000],
    )
    if not database_is_configured():
        return
    try:
        with get_database_pool().connection(timeout=2) as connection:
            connection.execute(
                """
                insert into public.security_events
                  (event_type, actor_hash, route, method, outcome, metadata)
                values (%s, %s, %s, %s, %s, %s::jsonb)
                """,
                (
                    event_type[:80],
                    hashed_actor,
                    route[:240] or None,
                    method[:12] or None,
                    outcome[:40],
                    json.dumps(safe_metadata, default=str),
                ),
            )
    except Exception:
        LOGGER.exception("Unable to persist security audit event")
