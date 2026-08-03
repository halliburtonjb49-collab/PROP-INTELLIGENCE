"""Quota-safe ingestion of The Odds API historical player-prop snapshots."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
from typing import Any, Iterable

from config import BASE_URL, ODDS_REGIONS, PREFERRED_BOOKMAKERS_CSV
from database.postgres import database_is_configured, get_database_pool
from services.market_intelligence_service import (
    compute_market_intelligence,
    normalized_book_rows,
    persist_market_snapshot,
)
from services.odds_service import _request_with_failover, quota_snapshot
from services.clv_service import odds_clv_expected_value, vig_free_probability

HISTORICAL_PLAYER_PROPS_START = datetime(2023, 5, 3, 5, 30, tzinfo=timezone.utc)
HISTORICAL_CREDIT_MULTIPLIER = 10


def historical_credit_cost(markets: Iterable[str], regions: Iterable[str]) -> int:
    """The provider charges 10 credits per unique market per region."""
    market_count = len({item.strip() for item in markets if item.strip()})
    region_count = len({item.strip() for item in regions if item.strip()})
    return HISTORICAL_CREDIT_MULTIPLIER * market_count * max(1, region_count)


def clv_checkpoint_times(
    commence_time: datetime,
    *,
    offsets: tuple[timedelta, ...] = (
        timedelta(hours=24), timedelta(hours=6), timedelta(hours=1), timedelta(minutes=5),
    ),
) -> list[datetime]:
    """Return economical, deduplicated UTC checkpoints before an event starts."""
    if commence_time.tzinfo is None:
        commence_time = commence_time.replace(tzinfo=timezone.utc)
    return sorted({commence_time.astimezone(timezone.utc) - offset for offset in offsets})


def unwrap_historical_snapshot(payload: object) -> tuple[datetime | None, dict[str, Any]]:
    if not isinstance(payload, dict):
        return None, {"bookmakers": []}
    raw_timestamp = payload.get("timestamp")
    timestamp = None
    if isinstance(raw_timestamp, str):
        try:
            timestamp = datetime.fromisoformat(raw_timestamp.replace("Z", "+00:00"))
        except ValueError:
            timestamp = None
    data = payload.get("data")
    return timestamp, data if isinstance(data, dict) else {"bookmakers": []}


def fetch_historical_event_snapshot(
    *, sport_key: str, event_id: str, markets: list[str], requested_at: datetime,
) -> dict[str, object]:
    """Fetch one paid historical snapshot. Callers must enforce their credit budget."""
    if requested_at < HISTORICAL_PLAYER_PROPS_START:
        raise ValueError("Historical player props are unavailable before 2023-05-03T05:30:00Z")
    regions = [item.strip() for item in ODDS_REGIONS.split(",") if item.strip()]
    response = _request_with_failover(
        f"{BASE_URL}/historical/sports/{sport_key}/events/{event_id}/odds",
        {
            "regions": ",".join(regions),
            "markets": ",".join(sorted(set(markets))),
            "bookmakers": PREFERRED_BOOKMAKERS_CSV,
            "oddsFormat": "american",
            "dateFormat": "iso",
            "date": requested_at.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
        },
    )
    response.raise_for_status()
    payload = response.json()
    snapshot_at, event = unwrap_historical_snapshot(payload)
    quota = quota_snapshot()
    return {"requestedAt": requested_at, "snapshotAt": snapshot_at, "event": event, "quota": quota}


def ingest_historical_event_snapshot(
    *, sport_key: str, event_id: str, markets: list[str], requested_at: datetime,
) -> dict[str, object]:
    regions = sorted({item.strip() for item in ODDS_REGIONS.split(",") if item.strip()})
    unique_markets = sorted(set(markets))
    if database_is_configured():
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """select snapshot_at,consumed_credits,quota_remaining
                from historical_odds_backfill_jobs
                where sport=%s and event_id=%s and markets=%s and regions=%s
                  and requested_at=%s and status in ('SUCCEEDED','EMPTY')""",
                (sport_key, event_id, unique_markets, regions, requested_at),
            )
            prior = cursor.fetchone()
            if prior:
                return {"requestedAt": requested_at, "snapshotAt": prior[0],
                        "consumedCredits": prior[1], "quotaRemaining": prior[2],
                        "skipped": True, "reason": "snapshot already ingested"}
            cursor.execute(
                """insert into historical_odds_backfill_jobs
                (sport,event_id,markets,regions,requested_at,status,estimated_credits)
                values(%s,%s,%s,%s,%s,'PENDING',%s)
                on conflict (sport,event_id,markets,regions,requested_at)
                do update set status='PENDING',error=null,updated_at=now()""",
                (sport_key, event_id, unique_markets, regions, requested_at,
                 historical_credit_cost(unique_markets, regions)),
            )
            connection.commit()
    try:
        result = fetch_historical_event_snapshot(
            sport_key=sport_key, event_id=event_id, markets=unique_markets,
            requested_at=requested_at,
        )
    except Exception as error:
        _finish_job(sport_key, event_id, unique_markets, regions, requested_at,
                    status="FAILED", error=str(error))
        raise
    event = result["event"]
    assert isinstance(event, dict)
    actual_event_id = str(event.get("id") or event_id)
    rows = normalized_book_rows(
        provider="the-odds-api-historical", sport=sport_key,
        event_id=actual_event_id, payload=event,
    )
    intelligence = compute_market_intelligence(rows)
    persisted = persist_market_snapshot(
        rows, intelligence, observed_at=result["snapshotAt"] or requested_at,
    )
    quota = result.get("quota") if isinstance(result.get("quota"), dict) else {}
    _finish_job(
        sport_key, event_id, unique_markets, regions, requested_at,
        status="SUCCEEDED" if rows else "EMPTY",
        snapshot_at=result["snapshotAt"],
        consumed_credits=quota.get("lastRequestCost"),
        quota_remaining=quota.get("remaining"),
    )
    return {**result, **persisted, "rows": len(rows)}


def _finish_job(
    sport: str, event_id: str, markets: list[str], regions: list[str],
    requested_at: datetime, *, status: str, snapshot_at: object = None,
    consumed_credits: object = None, quota_remaining: object = None,
    error: str | None = None,
) -> None:
    if not database_is_configured():
        return
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """update historical_odds_backfill_jobs set status=%s,snapshot_at=%s,
            consumed_credits=%s,quota_remaining=%s,error=%s,updated_at=now()
            where sport=%s and event_id=%s and markets=%s and regions=%s and requested_at=%s""",
            (status, snapshot_at, consumed_credits, quota_remaining, error,
             sport, event_id, markets, regions, requested_at),
        )
        connection.commit()


def attach_verified_clv(event_id: str) -> dict[str, int]:
    """Attach the final stored pregame snapshot to matching model predictions."""
    if not database_is_configured():
        return {"updated": 0}
    updated = 0
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select id,side,line,inputs->>'playerName',inputs->>'marketKey',
                      inputs->>'sportsbook',inputs->>'entryOdds',event_time
               from prediction_snapshots
              where inputs->>'eventId'=%s""",
            (event_id,),
        )
        for prediction_id, side, entry_line, player, market, book, entry_odds, event_time in cursor.fetchall():
            cursor.execute(
                """select observed_at,line,over_odds,under_odds,bookmaker
                   from sportsbook_line_snapshots
                  where event_id=%s and lower(player)=lower(%s) and market=%s
                    and observed_at < %s
                    and (%s='' or lower(bookmaker)=lower(%s))
                  order by observed_at desc limit 1""",
                (event_id, player or "", market or "", event_time, book or "", book or ""),
            )
            close = cursor.fetchone()
            if close is None:
                continue
            observed_at, closing_line, over_odds, under_odds, bookmaker = close
            side_upper = str(side).upper()
            line_clv = (float(closing_line) - float(entry_line)
                        if side_upper == "OVER"
                        else float(entry_line) - float(closing_line))
            payload: dict[str, object] = {
                "closingLine": float(closing_line),
                "lineClvPoints": round(line_clv, 4),
                "beatClosingLine": line_clv > 0,
                "clvVerified": True,
                "clvSource": "the-odds-api-historical",
                "clvSnapshotAt": observed_at.isoformat(),
                "clvBookmaker": bookmaker,
            }
            side_odds = over_odds if side_upper == "OVER" else under_odds
            opposite_odds = under_odds if side_upper == "OVER" else over_odds
            if entry_odds and side_odds is not None and opposite_odds is not None:
                entry = int(float(entry_odds))
                side_close = int(float(side_odds))
                opposite_close = int(float(opposite_odds))
                payload.update({
                    "closingOdds": side_close,
                    "closingOppositeOdds": opposite_close,
                    "closingNoVigProbability": round(
                        vig_free_probability(side_close, opposite_close), 6),
                    "oddsClvExpectedValuePercent": round(
                        odds_clv_expected_value(entry, side_close, opposite_close) * 100, 4),
                    "oddsClvMethod": "proportional-no-vig",
                })
            cursor.execute(
                "update prediction_snapshots set inputs=inputs || %s::jsonb where id=%s",
                (json.dumps(payload), prediction_id),
            )
            updated += 1
        connection.commit()
    return {"updated": updated}
