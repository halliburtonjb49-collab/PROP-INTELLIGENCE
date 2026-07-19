"""Cached professional game-market aggregation for moneylines, spreads and totals."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from threading import Lock
from time import perf_counter
from typing import Any, Callable

from services.odds_service import (
    estimate_event_odds_cost,
    fetch_game_odds,
    quota_allows,
)

GAME_SPORTS: dict[str, str] = {
    "NBA": "basketball_nba",
    "WNBA": "basketball_wnba",
    "MLB": "baseball_mlb",
    "NFL": "americanfootball_nfl",
    "NHL": "icehockey_nhl",
    "EPL": "soccer_epl",
    "MLS": "soccer_usa_mls",
}
MARKETS = ("h2h", "spreads", "totals")
_cache: dict[str, tuple[datetime, list[dict[str, object]]]] = {}
_cache_lock = Lock()
_metrics_lock = Lock()
_metrics: dict[str, object] = {
    "requests": 0,
    "errors": 0,
    "emptyResponses": 0,
    "cacheHits": 0,
    "lastResponseMs": None,
    "lastSuccessfulAt": None,
    "lastEventCount": 0,
    "lastRequestSucceeded": None,
}


def _as_number(value: object) -> float | int | None:
    if isinstance(value, (int, float)):
        return value
    try:
        parsed = float(str(value))
        return int(parsed) if parsed.is_integer() else parsed
    except (TypeError, ValueError):
        return None


def _normalize_event(event: dict[str, Any], sport: str) -> dict[str, object]:
    books: list[dict[str, object]] = []
    for raw_book in event.get("bookmakers", []):
        if not isinstance(raw_book, dict):
            continue
        normalized_markets: dict[str, list[dict[str, object]]] = {}
        for raw_market in raw_book.get("markets", []):
            if not isinstance(raw_market, dict):
                continue
            key = str(raw_market.get("key") or "").lower()
            if key not in MARKETS:
                continue
            outcomes: list[dict[str, object]] = []
            for raw_outcome in raw_market.get("outcomes", []):
                if not isinstance(raw_outcome, dict):
                    continue
                name = str(raw_outcome.get("name") or "").strip()
                price = _as_number(raw_outcome.get("price"))
                if not name or price is None:
                    continue
                outcomes.append({
                    "name": name,
                    "price": price,
                    "point": _as_number(raw_outcome.get("point")),
                })
            if outcomes:
                normalized_markets[key] = outcomes
        if normalized_markets:
            books.append({
                "key": str(raw_book.get("key") or ""),
                "title": str(raw_book.get("title") or raw_book.get("key") or "Sportsbook"),
                "lastUpdate": raw_book.get("last_update"),
                "markets": normalized_markets,
            })
    return {
        "id": str(event.get("id") or ""),
        "sport": sport,
        "sportKey": str(event.get("sport_key") or GAME_SPORTS.get(sport, "")),
        "league": str(event.get("sport_title") or sport),
        "commenceTime": event.get("commence_time"),
        "homeTeam": str(event.get("home_team") or "Home"),
        "awayTeam": str(event.get("away_team") or "Away"),
        "bookmakers": books,
    }


def get_game_markets(
    sport: str,
    *,
    force: bool = False,
    cache_seconds: int = 45,
    fetcher: Callable[..., list[dict[str, Any]]] = fetch_game_odds,
) -> dict[str, object]:
    normalized_sport = sport.strip().upper() or "MLB"
    sport_key = GAME_SPORTS.get(normalized_sport)
    if sport_key is None:
        raise ValueError(f"Unsupported sport: {sport}")
    now = datetime.now(timezone.utc)
    with _metrics_lock:
        _metrics["requests"] = int(_metrics["requests"]) + 1
    with _cache_lock:
        cached = _cache.get(normalized_sport)
    if not force and cached and now - cached[0] <= timedelta(seconds=cache_seconds):
        with _metrics_lock:
            _metrics["cacheHits"] = int(_metrics["cacheHits"]) + 1
        return {
            "sport": normalized_sport,
            "updatedAt": cached[0].isoformat(),
            "cached": True,
            "events": cached[1],
        }
    quota = quota_allows(estimate_event_odds_cost(list(MARKETS)))
    if quota["allowed"] is not True:
        if cached:
            return {
                "sport": normalized_sport,
                "updatedAt": cached[0].isoformat(),
                "cached": True,
                "stale": True,
                "quotaProtected": True,
                "events": cached[1],
            }
        raise RuntimeError("Game-market refresh paused to protect provider quota.")
    started = perf_counter()
    try:
        raw_events = fetcher(sport_key=sport_key, markets=list(MARKETS))
        events = [_normalize_event(event, normalized_sport) for event in raw_events]
        events = [event for event in events if event["bookmakers"]]
        elapsed_ms = round((perf_counter() - started) * 1000, 1)
        with _metrics_lock:
            _metrics.update({
                "lastResponseMs": elapsed_ms,
                "lastEventCount": len(events),
                "lastSuccessfulAt": now.isoformat(),
                "emptyResponses": int(_metrics["emptyResponses"]) + (1 if not events else 0),
                "lastRequestSucceeded": True,
            })
        with _cache_lock:
            _cache[normalized_sport] = (now, events)
        return {"sport": normalized_sport, "updatedAt": now.isoformat(), "cached": False, "events": events}
    except Exception:
        with _metrics_lock:
            _metrics["errors"] = int(_metrics["errors"]) + 1
            _metrics["lastResponseMs"] = round((perf_counter() - started) * 1000, 1)
            _metrics["lastRequestSucceeded"] = False
        if cached:
            return {
                "sport": normalized_sport,
                "updatedAt": cached[0].isoformat(),
                "cached": True,
                "stale": True,
                "events": cached[1],
            }
        raise


def game_market_health() -> dict[str, object]:
    with _metrics_lock:
        snapshot = dict(_metrics)
    requests = max(1, int(snapshot["requests"]))
    errors = int(snapshot["errors"])
    checked = snapshot.get("lastRequestSucceeded") is not None
    latest_empty = checked and int(snapshot.get("lastEventCount") or 0) == 0
    return {
        "status": (
            "not_checked"
            if not checked
            else "degraded"
            if snapshot.get("lastRequestSucceeded") is False or latest_empty
            else "ok"
        ),
        "latestEmpty": latest_empty,
        "successRate": round((requests - errors) / requests, 4),
        **snapshot,
    }
