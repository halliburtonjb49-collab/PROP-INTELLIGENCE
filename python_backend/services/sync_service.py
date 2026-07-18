import logging
import time
from datetime import datetime, timezone

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
    cache.prune_sport_to_event_ids(
        sport=sport_key,
        active_event_ids=active_event_ids,
    )
    prop_count = 0
    fetched_events = 0
    skipped_for_quota = 0
    estimated_event_cost = estimate_event_odds_cost(markets)

    for event in events:
        event_id = str(event.get("id", ""))
        if not event_id:
            continue

        budget = quota_allows(estimated_event_cost)
        if budget["allowed"] is not True:
            skipped_for_quota = len(events) - fetched_events
            logger.warning(
                "sync_sport quota_guard sport=%s remaining=%s estimatedCost=%s reserve=%s skipped=%s",
                sport_key, budget["remaining"], estimated_event_cost,
                budget["reserve"], skipped_for_quota,
            )
            break

        odds_payload = _with_retries(
            lambda: fetch_event_odds(
                sport_key=sport_key,
                event_id=event_id,
                markets=markets,
            ),
            label=f"odds {sport_key} {event_id}",
        )
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
        "estimatedCostPerEvent": estimated_event_cost,
        "props": prop_count,
    }


def run_global_sync_pipeline() -> list[dict[str, object]]:
    sports = [
        "baseball_mlb",
        "basketball_wnba",
    ]
    results = []
    for sport_key in sports:
        try:
            results.append(sync_sport(sport_key))
        except Exception as exc:
            logger.exception("sync_sport failed sport=%s", sport_key)
            results.append({"sport": sport_key, "events": 0, "props": 0, "error": str(exc)})
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
    logger.info("sync_global sports=%s", ",".join(sports))
    return results
