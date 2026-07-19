from typing import Any
from datetime import datetime, timezone
from threading import Lock, local

import requests
from requests.adapters import HTTPAdapter

from config import (
    BASE_URL,
    HTTP_TIMEOUT_SECONDS,
    ODDS_API_KEY,
    ODDS_REGIONS,
    ODDS_API_LOW_QUOTA_THRESHOLD,
    ODDS_API_QUOTA_RESERVE,
    PREFERRED_BOOKMAKERS_CSV,
)

_quota_lock = Lock()
_http_local = local()
_quota_state: dict[str, object] = {
    "remaining": None, "used": None, "lastRequestCost": None,
    "lastResponseAt": None, "lowQuota": False,
    "lowQuotaThreshold": ODDS_API_LOW_QUOTA_THRESHOLD,
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
    allowed = not isinstance(remaining, int) or (
        remaining - max(0, estimated_cost) >= ODDS_API_QUOTA_RESERVE
    )
    return {
        "allowed": allowed,
        "estimatedCost": max(0, estimated_cost),
        "remaining": remaining,
        "reserve": ODDS_API_QUOTA_RESERVE,
        "reason": None if allowed else "provider quota reserve would be breached",
    }


def fetch_events(sport_key: str) -> list[dict[str, Any]]:
    response = _http_session().get(
        f"{BASE_URL}/sports/{sport_key}/events",
        params={
            "apiKey": ODDS_API_KEY,
            "dateFormat": "iso",
        },
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    record_quota_headers(response.headers)
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
    response = _http_session().get(
        f"{BASE_URL}/sports/{sport_key}/events/{event_id}/odds",
        params={
            "apiKey": ODDS_API_KEY,
            "regions": ODDS_REGIONS,
            "markets": ",".join(markets),
            "bookmakers": PREFERRED_BOOKMAKERS_CSV,
            "oddsFormat": "american",
            "dateFormat": "iso",
        },
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    record_quota_headers(response.headers)
    response.raise_for_status()
    payload = response.json()

    if isinstance(payload, dict):
        return payload
    return {"bookmakers": []}


def fetch_game_odds(
    *,
    sport_key: str,
    markets: list[str] | None = None,
) -> list[dict[str, Any]]:
    """Fetch event-level moneyline, spread, and total markets in one request."""
    requested_markets = markets or ["h2h", "spreads", "totals"]
    response = _http_session().get(
        f"{BASE_URL}/sports/{sport_key}/odds",
        params={
            "apiKey": ODDS_API_KEY,
            "regions": ODDS_REGIONS,
            "markets": ",".join(requested_markets),
            "bookmakers": PREFERRED_BOOKMAKERS_CSV,
            "oddsFormat": "american",
            "dateFormat": "iso",
        },
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    record_quota_headers(response.headers)
    response.raise_for_status()
    payload = response.json()
    if isinstance(payload, list):
        return [event for event in payload if isinstance(event, dict)]
    return []
