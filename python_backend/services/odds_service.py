from typing import Any
from datetime import datetime, timezone
from threading import Lock, local

import requests
from requests.adapters import HTTPAdapter

from config import (
    BASE_URL,
    HTTP_TIMEOUT_SECONDS,
    ODDS_API_KEY,
    ODDS_API_KEY_SECONDARY,
    ODDS_REGIONS,
    ODDS_API_LOW_QUOTA_THRESHOLD,
    ODDS_API_QUOTA_RESERVE,
    MISSING_BOOKMAKERS_RESTORED,
    PREFERRED_BOOKMAKERS,
    RETIRED_BOOKMAKERS_DROPPED,
    PREFERRED_BOOKMAKERS_CSV,
)

_quota_lock = Lock()
_http_local = local()
_quota_state: dict[str, object] = {
    "remaining": None, "used": None, "lastRequestCost": None,
    "lastResponseAt": None, "lowQuota": False,
    "lowQuotaThreshold": ODDS_API_LOW_QUOTA_THRESHOLD,
}

# Once a key comes back 401/429 (out of usage credits, or otherwise
# rejected), permanently move on to the next configured key for the rest
# of this process's lifetime rather than retrying the dead one on every
# call. Resets to the primary key on the next deploy/restart.
_ODDS_API_KEYS = [key for key in (ODDS_API_KEY, ODDS_API_KEY_SECONDARY) if key]
_QUOTA_EXHAUSTED_STATUS_CODES = {401, 429}
_key_state_lock = Lock()
_active_key_index = 0


def _current_api_key() -> str:
    with _key_state_lock:
        if not _ODDS_API_KEYS:
            return ""
        return _ODDS_API_KEYS[_active_key_index]


def _advance_to_next_key() -> bool:
    """Switches to the next configured key. Returns False if there isn't
    another one to fall back to."""
    global _active_key_index
    with _key_state_lock:
        if _active_key_index + 1 >= len(_ODDS_API_KEYS):
            return False
        _active_key_index += 1
        return True


def active_key_snapshot() -> dict[str, object]:
    with _key_state_lock:
        return {
            "activeKeyIndex": _active_key_index,
            "configuredKeyCount": len(_ODDS_API_KEYS),
        }


def _http_session() -> requests.Session:
    """Reuse TLS connections inside each sync worker thread."""
    session = getattr(_http_local, "session", None)
    if session is None:
        session = requests.Session()
        adapter = HTTPAdapter(pool_connections=8, pool_maxsize=8, max_retries=0)
        session.mount("https://", adapter)
        session.mount("http://", adapter)
        _http_local.session = session
    return session


def _header_int(headers: object, name: str) -> int | None:
    try:
        raw = headers.get(name)  # type: ignore[attr-defined]
    except AttributeError:
        return None
    try:
        return int(raw) if raw is not None else None
    except (TypeError, ValueError):
        return None


def record_quota_headers(headers: object) -> dict[str, object]:
    remaining = _header_int(headers, "x-requests-remaining")
    used = _header_int(headers, "x-requests-used")
    last = _header_int(headers, "x-requests-last")
    with _quota_lock:
        _quota_state.update({
            "remaining": remaining, "used": used, "lastRequestCost": last,
            "lastResponseAt": datetime.now(timezone.utc).isoformat(),
            "lowQuota": remaining is not None and remaining <= ODDS_API_LOW_QUOTA_THRESHOLD,
            "lowQuotaThreshold": ODDS_API_LOW_QUOTA_THRESHOLD,
        })
        return dict(_quota_state)


def quota_snapshot() -> dict[str, object]:
    with _quota_lock:
        return dict(_quota_state)


def estimate_event_odds_cost(markets: list[str]) -> int:
    regions = [region for region in ODDS_REGIONS.split(",") if region.strip()]
    return len(set(markets)) * max(1, len(regions))


def quota_allows(estimated_cost: int) -> dict[str, object]:
    quota = quota_snapshot()
    remaining = quota.get("remaining")

    # The reserve guard exists to avoid fully draining the *only* key we
    # have. If there's an untried backup key still queued up, that risk
    # doesn't apply - a rejected request on the current key just triggers
    # _request_with_failover() to move on to it, at no extra cost (the
    # provider doesn't charge for a rejected over-quota call).
    keys = active_key_snapshot()
    has_backup_key = keys["activeKeyIndex"] + 1 < keys["configuredKeyCount"]

    allowed = (
        has_backup_key
        or not isinstance(remaining, int)
        or (remaining - max(0, estimated_cost) >= ODDS_API_QUOTA_RESERVE)
    )
    return {
        "allowed": allowed,
        "estimatedCost": max(0, estimated_cost),
        "remaining": remaining,
        "reserve": ODDS_API_QUOTA_RESERVE,
        "reason": None if allowed else "provider quota reserve would be breached",
    }


def _request_with_failover(url: str, params: dict[str, object]) -> requests.Response:
    """GETs url, automatically moving on to the next configured Odds API
    key (and retrying once) if the active one comes back exhausted/rejected.
    """
    while True:
        response = _http_session().get(
            url,
            params={**params, "apiKey": _current_api_key()},
            timeout=HTTP_TIMEOUT_SECONDS,
        )
        record_quota_headers(response.headers)
        if response.status_code in _QUOTA_EXHAUSTED_STATUS_CODES and _advance_to_next_key():
            continue
        return response


def fetch_events(sport_key: str) -> list[dict[str, Any]]:
    response = _request_with_failover(
        f"{BASE_URL}/sports/{sport_key}/events",
        {"dateFormat": "iso"},
    )
    response.raise_for_status()
    payload = response.json()

    if isinstance(payload, list):
        return [event for event in payload if isinstance(event, dict)]
    return []


def fetch_event_odds(
    *,
    sport_key: str,
    event_id: str,
    markets: list[str],
) -> dict[str, Any]:
    response = _request_with_failover(
        f"{BASE_URL}/sports/{sport_key}/events/{event_id}/odds",
        {
            "regions": ODDS_REGIONS,
            "markets": ",".join(markets),
            "bookmakers": PREFERRED_BOOKMAKERS_CSV,
            "oddsFormat": "american",
            "dateFormat": "iso",
        },
    )
    response.raise_for_status()
    payload = response.json()

    if isinstance(payload, dict):
        record_bookmakers(payload)
        return payload
    return {"bookmakers": []}


def fetch_game_odds(
    *,
    sport_key: str,
    markets: list[str] | None = None,
) -> list[dict[str, Any]]:
    """Fetch event-level moneyline, spread, and total markets in one request."""
    requested_markets = markets or ["h2h", "spreads", "totals"]
    response = _request_with_failover(
        f"{BASE_URL}/sports/{sport_key}/odds",
        {
            "regions": ODDS_REGIONS,
            "markets": ",".join(requested_markets),
            "bookmakers": PREFERRED_BOOKMAKERS_CSV,
            "oddsFormat": "american",
            "dateFormat": "iso",
        },
    )
    response.raise_for_status()
    payload = response.json()
    if isinstance(payload, list):
        events = [event for event in payload if isinstance(event, dict)]
        record_bookmakers(events)
        return events
    return []


# Which bookmakers the provider actually returned, and when each was last
# seen. Requesting a bookmaker key and receiving nothing is silent: the API
# omits unknown or uncovered books without comment, so the only way to tell
# "this book has no props right now" from "this book is not on our plan" is to
# record what came back.
_bookmakers_seen: dict[str, dict[str, object]] = {}
_bookmakers_lock = Lock()


def record_bookmakers(events: object) -> None:
    """Note every bookmaker key present in a provider response."""

    rows = events if isinstance(events, list) else [events]
    now = datetime.now(timezone.utc).isoformat()
    with _bookmakers_lock:
        for event in rows:
            if not isinstance(event, dict):
                continue
            for bookmaker in event.get("bookmakers") or []:
                if not isinstance(bookmaker, dict):
                    continue
                key = str(bookmaker.get("key") or "").strip().lower()
                if not key:
                    continue
                entry = _bookmakers_seen.setdefault(
                    key,
                    {"title": bookmaker.get("title"), "events": 0, "lastSeenAt": None},
                )
                entry["events"] = int(entry.get("events") or 0) + 1
                entry["lastSeenAt"] = now


def bookmaker_coverage() -> dict[str, object]:
    """Requested bookmakers against those actually seen in responses."""

    with _bookmakers_lock:
        seen = {key: dict(value) for key, value in _bookmakers_seen.items()}
    requested = list(PREFERRED_BOOKMAKERS)
    return {
        "requested": requested,
        "seen": seen,
        # The answer to "why is this book empty": it was asked for and the
        # provider has never once returned it.
        "requestedButNeverSeen": [key for key in requested if key not in seen],
        # Drift between the deployed environment and the repository. A key
        # dropped here was configured but cannot exist; one restored was
        # missing from a configuration that had fallen behind.
        "retiredKeysDropped": list(RETIRED_BOOKMAKERS_DROPPED),
        "missingKeysRestored": list(MISSING_BOOKMAKERS_RESTORED),
    }


# What each sport actually returned. A sport can be configured, requested and
# still yield nothing -- because the plan does not cover it, because the
# provider has no player props for it, or because it is out of season -- and
# from outside the process all three look identical: an empty rail.
_sport_results: dict[str, dict[str, object]] = {}
_sport_lock = Lock()


_SPORT_RESULTS_KEY = "odds:sport-coverage"
_SPORT_RESULTS_TTL_SECONDS = 6 * 60 * 60


def _publish_sport_results(snapshot: dict[str, dict[str, object]]) -> None:
    """Share this instance's view so any other can report it."""

    try:
        from services.distributed_cache_service import set_json

        set_json(
            _SPORT_RESULTS_KEY,
            snapshot,
            ttl_seconds=_SPORT_RESULTS_TTL_SECONDS,
        )
    except Exception:
        # Diagnostics must never break a sync.
        pass


def _read_sport_results() -> dict[str, dict[str, object]]:
    try:
        from services.distributed_cache_service import get_json

        value = get_json(_SPORT_RESULTS_KEY)
    except Exception:
        return {}
    return value if isinstance(value, dict) else {}


def record_sport_fetch(
    sport_key: str,
    *,
    events: int,
    props: int,
    error: str = "",
    fetched_events: int = 0,
    skipped_for_quota: int = 0,
    failed_events: int = 0,
) -> None:
    """Note what one sport's fetch produced, and how far it got.

    Events listed but no props can mean three unrelated things: the quota ran
    out before their odds were requested, every request failed, or the
    provider simply has no player markets for that sport. Recording only the
    event count leaves all three looking identical.
    """

    key = str(sport_key or "").strip().lower()
    if not key:
        return
    with _sport_lock:
        entry = _sport_results.setdefault(
            key,
            {
                "fetches": 0,
                "events": 0,
                "props": 0,
                "oddsFetched": 0,
                "skippedForQuota": 0,
                "failedEvents": 0,
                "lastError": "",
            },
        )
        entry["fetches"] = int(entry["fetches"]) + 1
        entry["events"] = int(entry["events"]) + int(events)
        entry["props"] = int(entry["props"]) + int(props)
        entry["oddsFetched"] = int(entry.get("oddsFetched") or 0) + int(fetched_events)
        entry["skippedForQuota"] = (
            int(entry.get("skippedForQuota") or 0) + int(skipped_for_quota)
        )
        entry["failedEvents"] = int(entry.get("failedEvents") or 0) + int(failed_events)
        entry["lastFetchedAt"] = datetime.now(timezone.utc).isoformat()
        if error:
            entry["lastError"] = error
        snapshot = {name: dict(value) for name, value in _sport_results.items()}
    # The fetch happens on the worker or on whichever instance ran the sync,
    # and the health endpoint is answered by another. Process memory cannot
    # carry this across that gap: every sport read back as never fetched,
    # including the two that were plainly producing props.
    _publish_sport_results(snapshot)


def sport_coverage() -> dict[str, object]:
    """Configured sports against what they have actually returned."""

    from services.sync_service import configured_sync_sports

    try:
        configured = configured_sync_sports()
    except Exception:
        configured = []
    with _sport_lock:
        results = {key: dict(value) for key, value in _sport_results.items()}
    shared = _read_sport_results()
    # Prefer whichever view has seen more, so a freshly restarted instance
    # reports the fleet's history rather than its own blank slate.
    for name, value in shared.items():
        current = results.get(name)
        if current is None or int(value.get("fetches") or 0) > int(current.get("fetches") or 0):
            results[name] = value
    return {
        "configured": configured,
        "results": results,
        # Requested and never once seen. Distinguishes "out of season" from
        # "we are not actually asking for it".
        "neverFetched": [key for key in configured if key not in results],
        # Fetched, returned events, and still produced no props: the provider
        # has the games but not the player markets.
        "eventsWithoutProps": [
            key
            for key, value in results.items()
            if int(value.get("events") or 0) > 0 and int(value.get("props") or 0) == 0
        ],
        # Listed events whose odds were never actually requested because the
        # quota ran out first. These are not evidence the provider lacks
        # player markets; nobody asked it.
        "starvedByQuota": [
            key
            for key, value in results.items()
            if int(value.get("skippedForQuota") or 0) > 0
        ],
        # Odds were requested and returned, and still no props came out. This
        # is the only pattern that actually indicates missing coverage.
        "fetchedButEmpty": [
            key
            for key, value in results.items()
            if int(value.get("oddsFetched") or 0) > 0 and int(value.get("props") or 0) == 0
        ],
    }
