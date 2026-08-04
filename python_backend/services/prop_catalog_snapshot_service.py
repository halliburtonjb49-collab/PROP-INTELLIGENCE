"""Durable last-known-good prop catalog shared by API and workers."""

from __future__ import annotations

import gzip
import json
import logging
from datetime import datetime, timezone

from database.postgres import database_is_configured, get_database_pool

LOGGER = logging.getLogger(__name__)
_SNAPSHOT_KEY = "live-props"


def _encode_payload(rows: list[dict[str, object]]) -> bytes:
    return gzip.compress(
        json.dumps(rows, separators=(",", ":"), default=str).encode("utf-8"),
        compresslevel=5,
    )


def _decode_payload(payload: object) -> list[dict[str, object]]:
    raw = bytes(payload) if isinstance(payload, (bytes, bytearray, memoryview)) else b""
    if not raw:
        return []
    decoded = json.loads(gzip.decompress(raw).decode("utf-8"))
    if not isinstance(decoded, list):
        return []
    return [dict(row) for row in decoded if isinstance(row, dict)]


def save_catalog_snapshot(rows: list[dict[str, object]]) -> bool:
    """Atomically replace the durable snapshot; never erase it with empty data."""
    if not rows or not database_is_configured():
        return False
    payload = _encode_payload(rows)
    latest = max((str(row.get("lastUpdatedUtc") or "") for row in rows), default="")
    try:
        with get_database_pool().connection(timeout=10) as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """insert into prop_catalog_snapshots
                    (snapshot_key,payload,prop_count,data_updated_at,updated_at)
                    values (%s,%s,%s,%s,%s)
                    on conflict(snapshot_key) do update set
                    payload=excluded.payload,prop_count=excluded.prop_count,
                    data_updated_at=excluded.data_updated_at,
                    updated_at=excluded.updated_at""",
                    (_SNAPSHOT_KEY, payload, len(rows), latest or None, datetime.now(timezone.utc)),
                )
        return True
    except Exception as exc:
        LOGGER.warning("Unable to persist prop catalog snapshot: %s", type(exc).__name__)
        return False


def load_catalog_snapshot() -> list[dict[str, object]]:
    """Load the last complete catalog without making startup depend on it."""
    if not database_is_configured():
        return []
    try:
        with get_database_pool().connection(timeout=10) as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """select payload from prop_catalog_snapshots
                    where snapshot_key=%s and prop_count > 0""",
                    (_SNAPSHOT_KEY,),
                )
                row = cursor.fetchone()
        return _decode_payload(row[0]) if row else []
    except Exception as exc:
        # The table may not exist on the first deployment; the live/Redis path
        # will seed it without turning startup into a failure.
        LOGGER.info("No durable prop catalog snapshot available: %s", type(exc).__name__)
        return []
