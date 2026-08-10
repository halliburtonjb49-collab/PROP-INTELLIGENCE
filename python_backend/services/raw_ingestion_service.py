"""Raw provider ingestion through Redis Streams with msgspec validation."""

from __future__ import annotations

from datetime import datetime, timezone
from functools import lru_cache
import logging
import os
from typing import Any

import msgspec
from redis import Redis

from config import DB_PATH
from database.cache import PropCache
from services.job_queue_service import enqueue
from services.market_intelligence_service import (
    compute_market_intelligence,
    normalized_book_rows,
    persist_market_snapshot,
)
from services.prop_processor import process_and_cache_props

LOGGER = logging.getLogger(__name__)
REDIS_URL = os.getenv("REDIS_URL", "").strip()
STREAM_NAME = os.getenv("RAW_PROP_STREAM", "prop-intelligence:raw-feeds")
STREAM_MAXLEN = max(100, int(os.getenv("RAW_PROP_STREAM_MAXLEN", "5000")))


class RawFeedEnvelope(msgspec.Struct):
    provider: str
    sport: str
    event: dict[str, Any]
    payload: dict[str, Any]
    fetched_at: str


_encoder = msgspec.json.Encoder()
_decoder = msgspec.json.Decoder(RawFeedEnvelope)


@lru_cache(maxsize=1)
def _redis() -> Redis | None:
    if not REDIS_URL:
        return None
    return Redis.from_url(
        REDIS_URL,
        socket_connect_timeout=2,
        socket_timeout=5,
        health_check_interval=30,
    )


def health() -> dict[str, object]:
    client = _redis()
    if client is None:
        return {
            "configured": False,
            "available": False,
            "mode": "legacy-fallback",
        }
    try:
        return {
            "configured": True,
            "available": bool(client.ping()),
            "mode": "redis-stream",
            "stream": STREAM_NAME,
            "retainedRawMessages": int(client.xlen(STREAM_NAME)),
            "decoder": "msgspec",
            "compute": "polars",
        }
    except Exception as exc:
        return {
            "configured": True,
            "available": False,
            "mode": "legacy-fallback",
            "error": str(exc),
        }


def publish_raw_feed(
    *, provider: str, sport: str, event: dict[str, Any], payload: dict[str, Any],
) -> str | None:
    """Write unprocessed provider JSON to the broker, then queue normalization."""
    client = _redis()
    if client is None:
        return None
    envelope = RawFeedEnvelope(
        provider=provider,
        sport=sport,
        event=event,
        payload=payload,
        fetched_at=datetime.now(timezone.utc).isoformat(),
    )
    message_id = client.xadd(
        STREAM_NAME,
        {"payload": _encoder.encode(envelope)},
        maxlen=STREAM_MAXLEN,
        approximate=True,
    )
    message_text = (
        message_id.decode() if isinstance(message_id, bytes) else str(message_id)
    )
    queued = enqueue(
        "jobs.normalize_raw_feed",
        args=(message_text,),
        job_id=f"normalize:{message_text}",
    )
    if queued is None:
        LOGGER.warning("Raw feed published but normalization could not be queued id=%s", message_text)
    return message_text


def normalize_stream_message(message_id: str) -> dict[str, object]:
    """Decode one raw stream event, normalize it, compute it, and persist it."""
    client = _redis()
    if client is None:
        raise RuntimeError("REDIS_URL is required to normalize raw feed messages")
    messages = client.xrange(STREAM_NAME, min=message_id, max=message_id, count=1)
    if not messages:
        raise RuntimeError(f"Raw feed message {message_id} was not found")
    _, fields = messages[0]
    encoded = fields.get(b"payload") or fields.get("payload")
    if not isinstance(encoded, (bytes, bytearray)):
        raise RuntimeError(f"Raw feed message {message_id} has no payload")
    envelope = _decoder.decode(encoded)
    cache = PropCache(DB_PATH)
    props = process_and_cache_props(
        cache=cache,
        sport_key=envelope.sport,
        event=envelope.event,
        odds_payload=envelope.payload,
    )
    rows = normalized_book_rows(
        provider=envelope.provider,
        sport=envelope.sport,
        event_id=str(envelope.event.get("id") or ""),
        payload=envelope.payload,
    )
    intelligence = compute_market_intelligence(rows)
    history = persist_market_snapshot(rows, intelligence)
    # Retain raw stream records for bounded replay/audit; maxlen controls memory.
    return {
        "messageId": message_id,
        "props": props,
        "rows": len(rows),
        **history,
    }


def queue_ingestion_pipeline(
    sports: list[str], *, include_supplemental: bool = True,
) -> dict[str, object]:
    """Fan fetching out into lightweight jobs; normalization is queued later."""
    bucket = int(datetime.now(timezone.utc).timestamp() // 60)
    queued: list[str] = []
    for sport in sports:
        result = enqueue(
            "jobs.fetch_sport_raw",
            args=(sport,),
            job_id=f"fetch:{sport}:{bucket}",
        )
        if result is not None:
            queued.append(sport)
    supplemental = (
        enqueue(
            "jobs.fetch_sportsgameodds_raw",
            job_id=f"fetch:sportsgameodds:{bucket}",
        )
        if include_supplemental
        else None
    )
    return {
        "mode": "redis-stream",
        "queuedSports": queued,
        "supplementalQueued": supplemental is not None,
    }


def _claim_refresh_lane(name: str, ttl_seconds: int) -> bool:
    """Claim a distributed refresh window so deploys cannot duplicate polls."""
    client = _redis()
    if client is None:
        return True
    try:
        return bool(client.set(
            f"prop-intelligence:odds-refresh:{name}",
            datetime.now(timezone.utc).isoformat(),
            nx=True,
            ex=max(30, ttl_seconds),
        ))
    except Exception:
        LOGGER.exception("Unable to claim odds refresh lane=%s", name)
        return False


def queue_scheduled_ingestion_pipeline() -> dict[str, object]:
    """Queue fast markets often and broad coverage on a slower cadence.

    Every API request reads the last valid catalog. Provider polling happens
    only in RQ and a failed refresh therefore never erases the served feed.
    """
    from services.sync_service import (
        configured_sync_sports,
        partition_sync_sports,
    )

    fast_sports, coverage_sports = partition_sync_sports(
        configured_sync_sports(),
    )
    fast_seconds = max(60, int(os.getenv("ODDS_FAST_REFRESH_SECONDS", "120")))
    coverage_seconds = max(
        300,
        int(os.getenv("ODDS_COVERAGE_REFRESH_SECONDS", "1800")),
    )
    supplemental_seconds = max(
        120,
        int(os.getenv("ODDS_SUPPLEMENTAL_REFRESH_SECONDS", "300")),
    )

    selected: list[str] = []
    lanes: list[str] = []
    if _claim_refresh_lane("fast", fast_seconds):
        selected.extend(fast_sports)
        lanes.append("fast")
    if _claim_refresh_lane("coverage", coverage_seconds):
        selected.extend(coverage_sports)
        lanes.append("coverage")
    include_supplemental = _claim_refresh_lane(
        "supplemental",
        supplemental_seconds,
    )
    if include_supplemental:
        lanes.append("supplemental")

    result = queue_ingestion_pipeline(
        list(dict.fromkeys(selected)),
        include_supplemental=include_supplemental,
    )
    return {
        **result,
        "brokerAvailable": _redis() is not None,
        "lanes": lanes,
        "fastRefreshSeconds": fast_seconds,
        "coverageRefreshSeconds": coverage_seconds,
        "supplementalRefreshSeconds": supplemental_seconds,
    }


def fetch_sport_to_stream(sport: str) -> dict[str, object]:
    """Fetch provider payloads only; no normalization or database mutations."""
    from services.market_config import odds_api_markets_for_sport
    from services.odds_service import (
        estimate_event_odds_cost,
        fetch_event_odds,
        fetch_events,
        quota_allows,
        regions_for_sport,
    )
    from services.sync_service import _with_retries, prioritize_events

    markets = odds_api_markets_for_sport(sport)
    if not markets:
        return {"sport": sport, "events": 0, "published": 0, "skipped": "no markets"}
    events = prioritize_events(_with_retries(
        lambda: fetch_events(sport),
        label=f"raw events {sport}",
    ))
    published = 0
    skipped_for_quota = 0
    event_cost = estimate_event_odds_cost(
        markets,
        regions=regions_for_sport(sport),
    )
    for event in events:
        event_id = str(event.get("id") or "").strip()
        if not event_id:
            continue
        if quota_allows(event_cost)["allowed"] is not True:
            skipped_for_quota += 1
            continue
        payload = _with_retries(
            lambda event_id=event_id: fetch_event_odds(
                sport_key=sport,
                event_id=event_id,
                markets=markets,
            ),
            label=f"raw odds {sport} {event_id}",
        )
        if publish_raw_feed(
            provider="odds-api",
            sport=sport,
            event=event,
            payload=payload,
        ):
            published += 1
    return {
        "sport": sport,
        "events": len(events),
        "published": published,
        "skippedForQuota": skipped_for_quota,
    }


def fetch_sportsgameodds_to_stream() -> dict[str, object]:
    """Fetch raw SportsGameOdds events; convert them only in normalization jobs."""
    from config import SPORTSGAMEODDS_API_KEY
    from providers.sportsgameodds import LEAGUE_TO_SPORT, fetch_upcoming_events

    if not SPORTSGAMEODDS_API_KEY:
        return {"provider": "sportsgameodds", "published": 0, "skipped": "not configured"}
    published = 0
    failures: list[str] = []
    for league, sport in LEAGUE_TO_SPORT.items():
        try:
            for raw_event in fetch_upcoming_events(league):
                # The raw provider event remains untouched in the stream.
                if publish_raw_feed(
                    provider="sportsgameodds",
                    sport=sport,
                    event=raw_event,
                    payload={},
                ):
                    published += 1
        except Exception:
            LOGGER.exception("SportsGameOdds fetch failed league=%s", league)
            failures.append(league)
    return {
        "provider": "sportsgameodds",
        "published": published,
        "failedLeagues": failures,
    }
