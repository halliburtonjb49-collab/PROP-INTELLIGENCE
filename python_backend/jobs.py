"""Entrypoints executed by the durable RQ worker."""

from __future__ import annotations

import logging
import os
from datetime import datetime, timezone


LOGGER = logging.getLogger(__name__)
_ESPN_REFRESH_AFTER_HOURS = max(
    2.0,
    float(os.getenv("ESPN_HEADSHOT_REFRESH_AFTER_HOURS", "8")),
)
_ESPN_REFRESH_BUCKET_HOURS = max(
    1,
    int(os.getenv("ESPN_HEADSHOT_REFRESH_BUCKET_HOURS", "4")),
)


def _enqueue_espn_headshot_refresh_if_due(
    *,
    now: datetime | None = None,
) -> dict[str, object] | None:
    """Queue a separate photo job when the shared cache is aging.

    Render cron remains the primary scheduler. This worker-side check is a
    safety net for a paused or missed cron and deliberately queues separate
    work so a prop sync never downloads thousands of photos in-process.
    """

    from services.espn_headshot_service import espn_headshot_cache_health
    from services.job_queue_service import enqueue

    health = espn_headshot_cache_health(now=now)
    age_hours = health.get("ageHours")
    refresh_due = health.get("status") != "ok" or not isinstance(
        age_hours,
        (int, float),
    ) or float(age_hours) >= _ESPN_REFRESH_AFTER_HOURS
    if not refresh_due:
        return None

    current = now or datetime.now(timezone.utc)
    if current.tzinfo is None:
        current = current.replace(tzinfo=timezone.utc)
    bucket_seconds = _ESPN_REFRESH_BUCKET_HOURS * 60 * 60
    bucket = int(current.timestamp() // bucket_seconds)
    queued = enqueue(
        "jobs.refresh_espn_headshots",
        job_id=f"headshots:espn:auto:{bucket}",
    )
    if queued is None:
        LOGGER.warning(
            "ESPN headshot refresh is due but could not be queued age_hours=%s",
            age_hours,
        )
    else:
        LOGGER.info(
            "Queued ESPN headshot refresh age_hours=%s job_id=%s",
            age_hours,
            queued.get("id"),
        )
    return queued


def run_prop_sync() -> None:
    """Run and publish recovery entirely on the dedicated RQ worker."""
    from rq import get_current_job

    import main

    current_job = get_current_job()
    main.run_queued_prop_sync(current_job.id if current_job is not None else None)
    # The worker and API have separate ephemeral disks. Publish the worker's
    # completed local catalog to Redis so API instances and devices can read it.
    props = main._cached_prop_catalog()
    main.save_catalog_snapshot(
        [prop.model_dump(mode="json") for prop in props]
    )
    _enqueue_espn_headshot_refresh_if_due()


def refresh_mlb_headshots() -> dict[str, object]:
    """Refresh MLB photos from a non-web worker or cron process."""
    from services.mlb_headshot_service import refresh_mlb_headshot_map

    return {"players": refresh_mlb_headshot_map()}


def refresh_espn_headshots() -> dict[str, object]:
    """Refresh ESPN photos from a non-web worker or cron process."""
    from services.espn_headshot_service import refresh_espn_headshot_map

    return {"leagues": refresh_espn_headshot_map()}


def fetch_sport_raw(sport: str) -> dict[str, object]:
    from services.raw_ingestion_service import fetch_sport_to_stream

    return fetch_sport_to_stream(sport)


def fetch_sportsgameodds_raw() -> dict[str, object]:
    from services.raw_ingestion_service import fetch_sportsgameodds_to_stream

    return fetch_sportsgameodds_to_stream()


def normalize_raw_feed(message_id: str) -> dict[str, object]:
    import main
    from providers.sportsgameodds import normalize_event
    from services import raw_ingestion_service

    # SportsGameOdds streams untouched provider events, so transformation
    # happens here—not in the fetch job.
    client = raw_ingestion_service._redis()
    if client is None:
        raise RuntimeError("Redis unavailable")
    messages = client.xrange(
        raw_ingestion_service.STREAM_NAME,
        min=message_id,
        max=message_id,
        count=1,
    )
    if messages:
        _, fields = messages[0]
        encoded = fields.get(b"payload") or fields.get("payload")
        envelope = raw_ingestion_service._decoder.decode(encoded)
        if envelope.provider == "sportsgameodds":
            event, payload = normalize_event(envelope.event, sport_key=envelope.sport)
            updated = raw_ingestion_service.RawFeedEnvelope(
                provider=envelope.provider,
                sport=envelope.sport,
                event=event,
                payload=payload,
                fetched_at=envelope.fetched_at,
            )
            normalized_id = client.xadd(
                raw_ingestion_service.STREAM_NAME,
                {"payload": raw_ingestion_service._encoder.encode(updated)},
                maxlen=raw_ingestion_service.STREAM_MAXLEN,
                approximate=True,
            )
            message_id = (
                normalized_id.decode()
                if isinstance(normalized_id, bytes)
                else str(normalized_id)
            )
    result = raw_ingestion_service.normalize_stream_message(message_id)
    main._invalidate_prop_catalog()
    main._cached_prop_catalog()
    return result
