"""Record a pregame line every time it moves, so closing value is knowable.

Closing line value is the standard check on whether picks find real value,
and it could not be computed: sportsbook_line_snapshots was empty, because
the only thing that filled it was a raw-ingestion pipeline whose entry point
is called from a test and from nowhere in production. Thirty-six percent of
graded predictions carry closing odds, all of it residue from a path that no
longer runs, and that residue skews toward smaller books -- enough bias to
make the same band of picks read as +20.7% or -11.9% depending on which
subset was asked.

Nothing here fetches anything. The live sync already holds every book's
line and price for every prop; this writes them down when they change.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from hashlib import blake2s

from database.postgres import database_is_configured, get_database_pool

LOGGER = logging.getLogger(__name__)

# A row per refresh would be two million a day for no benefit. The hash
# deliberately excludes the timestamp, so an unchanged price writes nothing
# and the table becomes a record of movement rather than of polling.
_HASH_FIELDS = (
    "event_id", "player", "market", "bookmaker", "line", "over", "under",
)


def _fingerprint(values: dict[str, object]) -> str:
    joined = "|".join(str(values.get(field, "")) for field in _HASH_FIELDS)
    return blake2s(joined.encode("utf-8"), digest_size=16).hexdigest()


def _rows_from(props: list, now: datetime) -> list[tuple]:
    rows: list[tuple] = []
    for prop in props:
        event_id = str(getattr(prop, "eventId", "") or "")
        player = str(getattr(prop, "player", "") or "")
        market = str(getattr(prop, "marketKey", "") or getattr(prop, "market", "") or "")
        book = str(getattr(prop, "sportsbook", "") or "")
        line = getattr(prop, "line", None)
        if not event_id or not player or not market or not book or line is None:
            continue
        # A price recorded after the event has started is not a pregame
        # line, and closing value measured against one means nothing.
        start = str(getattr(prop, "startTimeUtc", "") or "")
        try:
            starts_at = datetime.fromisoformat(start.replace("Z", "+00:00"))
        except ValueError:
            continue
        if starts_at.tzinfo is None:
            starts_at = starts_at.replace(tzinfo=timezone.utc)
        if starts_at <= now:
            continue
        values = {
            "event_id": event_id,
            "player": player,
            "market": market,
            "bookmaker": book,
            "line": float(line),
            "over": getattr(prop, "overOdds", None),
            "under": getattr(prop, "underOdds", None),
        }
        rows.append((
            now,
            str(getattr(prop, "sourceProvider", "") or "live-sync"),
            str(getattr(prop, "sport", "") or ""),
            event_id,
            player,
            market,
            book,
            float(line),
            values["over"],
            values["under"],
            _fingerprint(values),
        ))
    return rows


def record_line_movements(props: list) -> dict[str, int]:
    """Persist any pregame line that differs from the last one stored."""

    if not database_is_configured() or not props:
        return {"recorded": 0, "considered": 0}
    now = datetime.now(timezone.utc)
    rows = _rows_from(props, now)
    if not rows:
        return {"recorded": 0, "considered": 0}
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.executemany(
                """insert into sportsbook_line_snapshots (
                       observed_at, provider, sport, event_id, player, market,
                       bookmaker, line, over_odds, under_odds, snapshot_hash
                   ) values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                   on conflict (snapshot_hash) do nothing""",
                rows,
            )
            recorded = cursor.rowcount if cursor.rowcount and cursor.rowcount > 0 else 0
            connection.commit()
    except Exception:
        # Losing a line snapshot costs a later measurement. Taking the
        # catalog down with it would cost the board.
        LOGGER.exception("Line movement capture failed")
        return {"recorded": 0, "considered": len(rows)}
    return {"recorded": int(recorded), "considered": len(rows)}


def apply_recorded_line_history(props: list) -> dict[str, int]:
    """Apply the earliest persisted pregame line to each live prop."""

    if not database_is_configured() or not props:
        return {"hydrated": 0, "considered": len(props)}
    event_ids = sorted({
        str(getattr(prop, "eventId", "") or "").strip()
        for prop in props
        if str(getattr(prop, "eventId", "") or "").strip()
    })
    if not event_ids:
        return {"hydrated": 0, "considered": len(props)}
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """select event_id, player, market, bookmaker,
                          (array_agg(line order by observed_at asc))[1] opening_line,
                          max(observed_at) last_observed_at
                   from sportsbook_line_snapshots
                   where event_id = any(%s)
                   group by event_id, player, market, bookmaker""",
                (event_ids,),
            )
            rows = cursor.fetchall()
    except Exception:
        LOGGER.exception("Recorded line history hydration failed")
        return {"hydrated": 0, "considered": len(props)}

    history = {
        tuple(str(value or "").strip().lower() for value in row[:4]): row[4:]
        for row in rows
    }
    hydrated = 0
    for prop in props:
        key = tuple(str(value or "").strip().lower() for value in (
            getattr(prop, "eventId", ""),
            getattr(prop, "player", ""),
            getattr(prop, "marketKey", "") or getattr(prop, "market", ""),
            getattr(prop, "sportsbook", ""),
        ))
        recorded = history.get(key)
        if recorded is None:
            continue
        opening_line, last_observed_at = recorded
        current_line = getattr(prop, "line", None)
        if opening_line is None or current_line is None:
            continue
        prop.openingLine = float(opening_line)
        prop.currentLine = float(current_line)
        if abs(prop.currentLine - prop.openingLine) >= 0.01:
            prop.lineMovedAtUtc = (
                last_observed_at.isoformat()
                if hasattr(last_observed_at, "isoformat")
                else str(last_observed_at or "")
            )
            hydrated += 1
    return {"hydrated": hydrated, "considered": len(props)}
