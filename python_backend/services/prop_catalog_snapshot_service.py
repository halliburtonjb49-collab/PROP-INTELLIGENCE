"""Durable last-known-good prop catalog shared by API and workers."""

from __future__ import annotations

import gzip
import json
import logging
from datetime import datetime, timezone

from database.postgres import database_is_configured, get_database_pool

LOGGER = logging.getLogger(__name__)
_SNAPSHOT_KEY = "live-props"

# The outcome of the last persist attempt. This write is best-effort and
# swallows its own errors, which meant a snapshot could stop updating for
# hours with nothing to show for it: the only trace was a log line naming the
# exception type. Keeping the result here lets the health endpoint say whether
# the last attempt succeeded, and why not when it did not.
_last_persist: dict[str, object] = {
    "attemptedAt": None,
    "succeeded": None,
    "error": None,
    "rows": 0,
    "payloadBytes": 0,
    "durationMs": None,
}


def catalog_snapshot_status() -> dict[str, object]:
    """What happened the last time a snapshot write was attempted."""

    return dict(_last_persist)


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
    started = datetime.now(timezone.utc)
    _last_persist.update(
        attemptedAt=started.isoformat(),
        succeeded=None,
        error=None,
        rows=len(rows),
        payloadBytes=0,
        durationMs=None,
    )
    if not rows or not database_is_configured():
        _last_persist.update(
            succeeded=False,
            error="no_rows" if not rows else "database_not_configured",
        )
        return False
    payload = _encode_payload(rows)
    _last_persist["payloadBytes"] = len(payload)
    latest = max((str(row.get("lastUpdatedUtc") or "") for row in rows), default="")
    try:
        # A catalog of several thousand props is a multi-megabyte write. Ten
        # seconds is the pool wait, not the transfer, so a slow write is not
        # cut off partway.
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
        _last_persist.update(
            succeeded=True,
            error=None,
            durationMs=round(
                (datetime.now(timezone.utc) - started).total_seconds() * 1000
            ),
        )
        return True
    except Exception as exc:
        # The message, not just the type. A bare "OperationalError" is what
        # made this failure impossible to diagnose from outside the process.
        LOGGER.warning(
            "Unable to persist prop catalog snapshot: %s: %s",
            type(exc).__name__,
            exc,
            exc_info=True,
        )
        _last_persist.update(
            succeeded=False,
            error=f"{type(exc).__name__}: {str(exc)[:300]}",
            durationMs=round(
                (datetime.now(timezone.utc) - started).total_seconds() * 1000
            ),
        )
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


def catalog_snapshot_metadata() -> dict[str, object]:
    """Age and size of the stored snapshot, without decoding its payload.

    Reading the whole catalog to answer "is this stale" would cost megabytes
    of transfer and a gzip decompress for a question two columns can settle.
    """

    if not database_is_configured():
        return {"exists": False, "reason": "database_not_configured"}
    try:
        with get_database_pool().connection(timeout=10) as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """select prop_count, data_updated_at, updated_at
                       from prop_catalog_snapshots where snapshot_key = %s""",
                    (_SNAPSHOT_KEY,),
                )
                row = cursor.fetchone()
    except Exception as exc:
        return {"exists": False, "reason": type(exc).__name__}
    if not row:
        return {"exists": False, "reason": "no_snapshot"}
    count, data_updated_at, updated_at = row
    return {
        "exists": True,
        "propCount": int(count or 0),
        "dataUpdatedAt": data_updated_at.isoformat() if data_updated_at else None,
        "writtenAt": updated_at.isoformat() if updated_at else None,
    }


def snapshot_is_behind(rows: list[dict[str, object]]) -> bool:
    """Whether these props are newer than what is stored.

    Fresh props in memory do not imply a fresh snapshot on disk. Comparing the
    two is what tells an instance it is serving data it has never recorded.
    """

    if not rows:
        return False
    stored = catalog_snapshot_metadata()
    if not stored.get("exists"):
        return True
    stored_at = str(stored.get("dataUpdatedAt") or "")
    latest = max((str(row.get("lastUpdatedUtc") or "") for row in rows), default="")
    if not latest:
        return False
    if not stored_at:
        return True
    # Both are ISO-8601 UTC, so a string comparison orders them correctly.
    return latest > stored_at
