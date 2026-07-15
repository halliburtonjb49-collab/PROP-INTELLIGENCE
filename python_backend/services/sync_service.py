import logging
import time

from config import DB_PATH
from database.cache import PropCache
from services.market_config import markets_for_sport
from services.odds_service import fetch_event_odds, fetch_events
from services.prop_processor import process_and_cache_props

cache = PropCache(DB_PATH)
logger = logging.getLogger(__name__)


def sync_sport(sport_key: str) -> dict[str, int | str]:
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

    events = fetch_events(sport_key)
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

    for event in events:
        event_id = str(event.get("id", ""))
        if not event_id:
            continue

        odds_payload = fetch_event_odds(
            sport_key=sport_key,
            event_id=event_id,
            markets=markets,
        )
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
        "props": prop_count,
    }


def run_global_sync_pipeline() -> list[dict[str, int | str]]:
    sports = [
        "baseball_mlb",
        "basketball_wnba",
    ]
    results = [
        sync_sport(sport_key)
        for sport_key in sports
    ]
    logger.info("sync_global sports=%s", ",".join(sports))
    return results
