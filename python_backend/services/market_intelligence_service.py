"""Vectorized multi-book intelligence and append-only line history."""

from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import logging
from typing import Any

from database.postgres import database_is_configured, get_database_pool

LOGGER = logging.getLogger(__name__)


def normalized_book_rows(
    *,
    provider: str,
    sport: str,
    event_id: str,
    payload: dict[str, Any],
) -> list[dict[str, object]]:
    """Flatten a provider payload into one row per player/market/book/line."""
    rows: list[dict[str, object]] = []
    for bookmaker in payload.get("bookmakers", []):
        if not isinstance(bookmaker, dict):
            continue
        book = str(bookmaker.get("title") or bookmaker.get("key") or "unknown")
        for market in bookmaker.get("markets", []):
            if not isinstance(market, dict):
                continue
            market_key = str(market.get("key") or "")
            grouped: dict[tuple[str, float], dict[str, object]] = {}
            for outcome in market.get("outcomes", []):
                if not isinstance(outcome, dict):
                    continue
                player = str(outcome.get("description") or outcome.get("name") or "").strip()
                try:
                    line = float(outcome.get("point"))
                except (TypeError, ValueError):
                    continue
                key = (player, line)
                row = grouped.setdefault(key, {
                    "provider": provider,
                    "sport": sport,
                    "event_id": event_id,
                    "player": player,
                    "market": market_key,
                    "bookmaker": book,
                    "line": line,
                    "over_odds": None,
                    "under_odds": None,
                })
                side = str(outcome.get("name") or "").lower()
                try:
                    price = float(outcome.get("price"))
                except (TypeError, ValueError):
                    price = None
                if side == "over":
                    row["over_odds"] = price
                elif side == "under":
                    row["under_odds"] = price
            rows.extend(grouped.values())
    return rows


def compute_market_intelligence(
    rows: list[dict[str, object]],
) -> list[dict[str, object]]:
    """Calculate consensus lines and best prices as a Rust-backed batch."""
    if not rows:
        return []
    # Polars is worker-only. Keeping this import lazy prevents the Starter
    # web service from paying the native engine's memory cost on every API
    # process simply to expose read-only intelligence results.
    import polars as pl

    frame = pl.DataFrame(rows)
    result = (
        frame.group_by(["sport", "event_id", "player", "market"])
        .agg(
            pl.col("line").median().alias("consensus_line"),
            pl.col("bookmaker").n_unique().alias("book_count"),
            pl.col("over_odds").max().alias("best_over_odds"),
            pl.col("bookmaker")
            .sort_by("over_odds")
            .last()
            .alias("best_over_book"),
            pl.col("under_odds").max().alias("best_under_odds"),
            pl.col("bookmaker")
            .sort_by("under_odds")
            .last()
            .alias("best_under_book"),
        )
        .sort(["sport", "event_id", "player", "market"])
    )
    return result.to_dicts()


def persist_market_snapshot(
    rows: list[dict[str, object]],
    intelligence: list[dict[str, object]],
    *,
    observed_at: datetime | None = None,
) -> dict[str, int]:
    """Append line history and its computed cross-book intelligence to Postgres."""
    if not database_is_configured() or not rows:
        return {"lineSnapshots": 0, "intelligenceSnapshots": 0}
    timestamp = observed_at or datetime.now(timezone.utc)
    with get_database_pool().connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("""
                create table if not exists sportsbook_line_snapshots (
                    id bigserial primary key,
                    observed_at timestamptz not null,
                    provider text not null,
                    sport text not null,
                    event_id text not null,
                    player text not null,
                    market text not null,
                    bookmaker text not null,
                    line double precision not null,
                    over_odds double precision,
                    under_odds double precision,
                    snapshot_hash text not null unique
                )
            """)
            cursor.execute("""
                create index if not exists sportsbook_line_lookup_idx
                on sportsbook_line_snapshots
                (sport, event_id, player, market, observed_at desc)
            """)
            cursor.execute("""
                create table if not exists prop_market_intelligence (
                    id bigserial primary key,
                    observed_at timestamptz not null,
                    sport text not null,
                    event_id text not null,
                    player text not null,
                    market text not null,
                    consensus_line double precision,
                    book_count integer not null,
                    best_over_odds double precision,
                    best_under_odds double precision,
                    best_over_book text,
                    best_under_book text
                )
            """)
            cursor.execute("""
                alter table prop_market_intelligence
                add column if not exists best_over_book text
            """)
            cursor.execute("""
                alter table prop_market_intelligence
                add column if not exists best_under_book text
            """)
            line_values = []
            for row in rows:
                fingerprint = hashlib.sha256(
                    json.dumps([timestamp.isoformat(), row], sort_keys=True, default=str).encode()
                ).hexdigest()
                line_values.append((
                    timestamp, row["provider"], row["sport"], row["event_id"],
                    row["player"], row["market"], row["bookmaker"], row["line"],
                    row.get("over_odds"), row.get("under_odds"), fingerprint,
                ))
            cursor.executemany("""
                insert into sportsbook_line_snapshots (
                    observed_at, provider, sport, event_id, player, market,
                    bookmaker, line, over_odds, under_odds, snapshot_hash
                ) values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                on conflict (snapshot_hash) do nothing
            """, line_values)
            intelligence_values = [(
                timestamp, row["sport"], row["event_id"], row["player"],
                row["market"], row.get("consensus_line"), row["book_count"],
                row.get("best_over_odds"), row.get("best_under_odds"),
                row.get("best_over_book"), row.get("best_under_book"),
            ) for row in intelligence]
            cursor.executemany("""
                insert into prop_market_intelligence (
                    observed_at, sport, event_id, player, market, consensus_line,
                    book_count, best_over_odds, best_under_odds,
                    best_over_book, best_under_book
                ) values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """, intelligence_values)
        connection.commit()
    return {
        "lineSnapshots": len(rows),
        "intelligenceSnapshots": len(intelligence),
    }


def latest_market_intelligence(
    *, sport: str | None = None, limit: int = 250,
) -> list[dict[str, object]]:
    """Return the newest computed market view for client/API consumers."""
    if not database_is_configured():
        return []
    where = "where sport = %s" if sport else ""
    params: tuple[object, ...] = (
        (sport, max(1, min(limit, 1000)))
        if sport
        else (max(1, min(limit, 1000)),)
    )
    with get_database_pool().connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(f"""
                select distinct on (sport, event_id, player, market)
                    observed_at, sport, event_id, player, market,
                    consensus_line, book_count, best_over_odds, best_under_odds,
                    best_over_book, best_under_book
                from prop_market_intelligence
                {where}
                order by sport, event_id, player, market, observed_at desc
                limit %s
            """, params)
            columns = [description.name for description in cursor.description]
            return [dict(zip(columns, row)) for row in cursor.fetchall()]
