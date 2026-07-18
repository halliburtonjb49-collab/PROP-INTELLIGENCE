import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from threading import Lock
from typing import Callable

from config import DB_PATH
from database.cache import PropCache
from services.market_config import markets_for_sport
from services.odds_service import (
    estimate_event_odds_cost, fetch_event_odds, fetch_events, quota_allows,
)
from services.prop_processor import process_and_cache_props
from services.prediction_automation_service import snapshot_live_predictions
from services.compound_alert_service import evaluate_all_alerts
from services.prop_service import get_props

cache = PropCache(DB_PATH)
logger = logging.getLogger(__name__)

DEFAULT_SYNC_SPORTS = (
    "baseball_mlb",
    "basketball_wnba",
    "basketball_nba",
    "americanfootball_nfl",
    "icehockey_nhl",
    "soccer_epl",
    "soccer_usa_mls",
    "soccer_france_ligue_one",
    "soccer_germany_bundesliga",
    "soccer_italy_serie_a",
    "soccer_spain_la_liga",
)

DEFAULT_FAST_SYNC_SPORTS = (
    "baseball_mlb",
    "basketball_wnba",
    "basketball_nba",
    "americanfootball_nfl",
)
_coverage_lock = Lock()
_last_coverage_sync_monotonic: float | None = None


def configured_sync_sports() -> list[str]:
    configured = os.getenv("PROP_SYNC_SPORTS", "").strip()
    candidates = configured.split(",") if configured else DEFAULT_SYNC_SPORTS
    return list(dict.fromkeys(value.strip() for value in candidates if value.strip()))


def partition_sync_sports(sports: list[str]) -> tuple[list[str], list[str]]:
    configured = os.getenv("PROP_FAST_SYNC_SPORTS", "").strip()
    candidates = configured.split(",") if configured else DEFAULT_FAST_SYNC_SPORTS
    fast_set = {value.strip() for value in candidates if value.strip()}
    return (
        [sport for sport in sports if sport in fast_set],
        [sport for sport in sports if sport not in fast_set],
    )


def _coverage_sync_due(now: float | None = None) -> bool:
    current = time.monotonic() if now is None else now
    interval = max(300, int(os.getenv("PROP_COVERAGE_SYNC_SECONDS", "1800")))
    with _coverage_lock:
        return (
            _last_coverage_sync_monotonic is None
            or current - _last_coverage_sync_monotonic >= interval
        )


def _mark_coverage_synced(now: float | None = None) -> None:
    global _last_coverage_sync_monotonic
    with _coverage_lock:
        _last_coverage_sync_monotonic = time.monotonic() if now is None else now


def _with_retries(operation, *, attempts: int = 3, label: str = "provider call"):
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            return operation()
        except Exception as exc:
            last_error = exc
            logger.warning("%s failed attempt=%s/%s error=%s", label, attempt, attempts, exc)
            if attempt < attempts:
                time.sleep(2 ** (attempt - 1))
    assert last_error is not None
    raise last_error


def _event_start(event: dict[str, object]) -> datetime:
    raw = event.get("commence_time") or event.get("commenceTime")
    try:
        parsed = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return datetime.max.replace(tzinfo=timezone.utc)
    return parsed if parsed.tzinfo is not None else parsed.replace(tzinfo=timezone.utc)


def prioritize_events(events: list[dict[str, object]]) -> list[dict[str, object]]:
    """Order valid events by start time so limited quota serves the nearest slate."""
    return sorted(events, key=lambda event: (_event_start(event), str(event.get("id", ""))))


def sync_sport(sport_key: str) -> dict[str, object]:
    started_at = time.perf_counter()
    markets = markets_for_sport(sport_key)
    if not markets:
        logger.warning(
            "sync_sport skipped sport=%s reason=no_markets",
            sport_key,
        )
        return {
            "sport": sport_key,
            "events": 0,
            "props": 0,
        }

    events = prioritize_events(_with_retries(
        lambda: fetch_events(sport_key), label=f"events {sport_key}",
    ))
    active_event_ids = [
        str(event.get("id", "")).strip()
        for event in events
        if str(event.get("id", "")).strip()
    ]
    if active_event_ids:
        cache.prune_sport_to_event_ids(
            sport=sport_key,
            active_event_ids=active_event_ids,
        )
    else:
        logger.warning(
            "sync_sport preserved cache sport=%s reason=no_active_events",
            sport_key,
        )
    prop_count = 0
    fetched_events = 0
    skipped_for_quota = 0
    failed_events = 0
    estimated_event_cost = estimate_event_odds_cost(markets)

    eligible_events: list[dict[str, object]] = []
    for event in events:
        event_id = str(event.get("id", ""))
        if not event_id:
            continue

        budget = quota_allows(estimated_event_cost * (len(eligible_events) + 1))
        if budget["allowed"] is not True:
            skipped_for_quota = len(events) - len(eligible_events)
            logger.warning(
                "sync_sport quota_guard sport=%s remaining=%s estimatedCost=%s reserve=%s skipped=%s",
                sport_key, budget["remaining"], estimated_event_cost,
                budget["reserve"], skipped_for_quota,
            )
            break
        eligible_events.append(event)

    def fetch_one(event: dict[str, object]):
        event_id = str(event.get("id", ""))
        try:
            payload = _with_retries(
                lambda: fetch_event_odds(
                    sport_key=sport_key,
                    event_id=event_id,
                    markets=markets,
                ),
                label=f"odds {sport_key} {event_id}",
            )
            return event, payload, None
        except Exception as exc:
            return event, None, exc

    configured_workers = max(1, int(os.getenv("PROP_SYNC_EVENT_WORKERS", "6")))
    worker_count = min(configured_workers, max(1, len(eligible_events)))
    with ThreadPoolExecutor(max_workers=worker_count) as executor:
        fetched_payloads = executor.map(fetch_one, eligible_events)
        # Cache mutations stay serialized while network requests overlap.
        for event, odds_payload, error in fetched_payloads:
            event_id = str(event.get("id", ""))
            if error is not None or odds_payload is None:
                failed_events += 1
                logger.error(
                    "sync_event failed; preserving cached props sport=%s event=%s error=%s",
                    sport_key,
                    event_id,
                    error,
                )
                continue
            fetched_events += 1
            prop_count += process_and_cache_props(
                cache=cache,
                sport_key=sport_key,
                event=event,
                odds_payload=odds_payload,
            )

    elapsed_ms = int((time.perf_counter() - started_at) * 1000)
    logger.info(
        "sync_sport provider=odds_api sport=%s events=%s props=%s elapsedMs=%s",
        sport_key,
        len(events),
        prop_count,
        elapsed_ms,
    )

    return {
        "sport": sport_key,
        "events": len(events),
        "fetchedEvents": fetched_events,
        "skippedForQuota": skipped_for_quota,
        "failedEvents": failed_events,
        "estimatedCostPerEvent": estimated_event_cost,
        "eventWorkers": worker_count,
        "props": prop_count,
    }


def run_global_sync_pipeline(
    on_fast_lane_complete: Callable[[list[dict[str, object]]], None] | None = None,
) -> list[dict[str, object]]:
    sports = configured_sync_sports()
    fast_sports, coverage_sports = partition_sync_sports(sports)
    results: list[dict[str, object]] = []

    def sync_lane(lane_sports: list[str]) -> None:
        for sport_key in lane_sports:
            try:
                results.append(sync_sport(sport_key))
            except Exception as exc:
                logger.exception("sync_sport failed sport=%s", sport_key)
                results.append({"sport": sport_key, "events": 0, "props": 0, "error": str(exc)})

    sync_lane(fast_sports)
    if on_fast_lane_complete is not None:
        try:
            on_fast_lane_complete(list(results))
        except Exception as exc:
            logger.warning("fast lane completion callback failed error=%s", exc)

    if _coverage_sync_due():
        sync_lane(coverage_sports)
        _mark_coverage_synced()
    else:
        results.extend({
            "sport": sport_key,
            "events": 0,
            "props": 0,
            "lane": "coverage",
            "skipped": "coverage cooldown",
        } for sport_key in coverage_sports)
    snapshot = snapshot_live_predictions()
    results.append({"sport": "prediction_snapshots", "events": 0,
                    "props": int(snapshot.get("created", 0))})
    alert_snapshots = [{
        "propId": prop.id, "player": prop.player, "playerId": prop.playerId,
        "sport": prop.sport, "market": prop.market, "marketKey": prop.marketKey,
        "line": prop.line, "side": prop.recommendedSide, "confidence": prop.confidence,
        "edge": prop.recommendationEdge, "injuryStatus": prop.injuryStatus,
        "lineupStatus": prop.lineupStatus, "gameId": prop.gameId,
    } for prop in get_props()]
    deliveries = evaluate_all_alerts(alert_snapshots)
    results.append({"sport": "compound_alerts", "events": len(alert_snapshots), "props": len(deliveries)})
    logger.info(
        "sync_global fast=%s coverage=%s",
        ",".join(fast_sports),
        ",".join(coverage_sports),
    )
    return results
