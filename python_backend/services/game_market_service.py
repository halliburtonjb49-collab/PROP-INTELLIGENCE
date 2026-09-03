"""Cached professional game-market aggregation for moneylines, spreads and totals."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from threading import Lock
from time import perf_counter
from typing import Any, Callable

import requests

from services.odds_service import (
    estimate_event_odds_cost,
    fetch_game_odds,
    quota_allows,
)
from services.prop_probability_service import shin_method_devig
from services.score_probability_service import dixon_coles_totals

GAME_SPORTS: dict[str, str] = {
    "NBA": "basketball_nba",
    "WNBA": "basketball_wnba",
    "MLB": "baseball_mlb",
    "NFL": "americanfootball_nfl",
    "NFL PRESEASON": "americanfootball_nfl_preseason",
    "NCAAF": "americanfootball_ncaaf",
    "NCAAB": "basketball_ncaab",
    "CFL": "americanfootball_cfl",
    "NHL": "icehockey_nhl",
    "EPL": "soccer_epl",
    "MLS": "soccer_usa_mls",
}
MARKETS = ("h2h", "spreads", "totals")
_cache: dict[str, tuple[datetime, list[dict[str, object]]]] = {}
_cache_lock = Lock()
_ncaaf_team_cache: tuple[datetime, dict[str, str]] | None = None
_ncaaf_team_lock = Lock()
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


def _american_implied(price: float | int) -> float:
    value = float(price)
    return 100 / (value + 100) if value > 0 else abs(value) / (abs(value) + 100)


def _median(values: list[float]) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2


def _team_key(value: object) -> str:
    return "".join(character for character in str(value or "").lower() if character.isalnum())


def _ncaaf_team_logos() -> dict[str, str]:
    """Return a cached official ESPN team-name to logo index."""
    global _ncaaf_team_cache
    now = datetime.now(timezone.utc)
    with _ncaaf_team_lock:
        if _ncaaf_team_cache and now - _ncaaf_team_cache[0] < timedelta(hours=12):
            return _ncaaf_team_cache[1]
    try:
        headers = {
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 Version/18.6 Mobile/15E148 Safari/604.1",
        }
        payload: object = None
        try:
            response = requests.get(
                "https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams",
                params={"limit": 1000}, headers=headers, timeout=5,
            )
            response.raise_for_status()
            payload = response.json()
        except (requests.RequestException, ValueError):
            response = requests.get(
                "https://site.web.api.espn.com/apis/v2/sports/football/college-football/standings",
                params={
                    "region": "us", "lang": "en", "contentorigin": "espn",
                    "type": 0, "level": 3,
                },
                headers=headers, timeout=6,
            )
            response.raise_for_status()
            payload = response.json()

        index: dict[str, str] = {}

        def add_teams(node: object) -> None:
            if isinstance(node, dict):
                team = node.get("team")
                if isinstance(team, dict):
                    logos = team.get("logos") or []
                    direct = str(team.get("logo") or "")
                    logo = direct or next((
                        str(item.get("href") or item.get("url") or "")
                        for item in logos if isinstance(item, dict)
                        and (item.get("href") or item.get("url"))
                    ), "")
                    if logo:
                        for name in (
                            team.get("displayName"), team.get("shortDisplayName"),
                            team.get("name"), team.get("location"), team.get("abbreviation"),
                            f"{team.get('location') or ''} {team.get('name') or ''}".strip(),
                        ):
                            key = _team_key(name)
                            if key:
                                index[key] = logo
                for value in node.values():
                    add_teams(value)
            elif isinstance(node, list):
                for value in node:
                    add_teams(value)

        add_teams(payload)
        with _ncaaf_team_lock:
            _ncaaf_team_cache = (now, index)
        return index
    except Exception:
        with _ncaaf_team_lock:
            return _ncaaf_team_cache[1] if _ncaaf_team_cache else {}


def _ncaaf_prediction(
    normalized: dict[str, object],
    consensus: list[dict[str, object]],
) -> dict[str, object] | None:
    """Rank an NCAAF moneyline using auditable multi-market information.

    This is a market ensemble rather than a claim to possess unavailable
    injury or weather observations. Spread and total consensus supply the
    scoring expectation; de-vigged moneylines supply win probability; book
    count and disagreement determine confidence; best price determines EV.
    """
    if len(consensus) < 2:
        return None
    books = normalized.get("bookmakers") or []
    home = str(normalized.get("homeTeam") or "Home")
    away = str(normalized.get("awayTeam") or "Away")
    spread_by_team: dict[str, list[float]] = {home: [], away: []}
    totals: list[float] = []
    for book in books:
        markets = book.get("markets", {}) if isinstance(book, dict) else {}
        for outcome in markets.get("spreads", []):
            name = str(outcome.get("name") or "")
            point = _as_number(outcome.get("point"))
            if name in spread_by_team and point is not None:
                spread_by_team[name].append(float(point))
        for outcome in markets.get("totals", []):
            point = _as_number(outcome.get("point"))
            if point is not None:
                totals.append(float(point))

    ranked = sorted(consensus, key=lambda item: float(item["fairProbability"]), reverse=True)
    pick = ranked[0]
    team = str(pick["team"])
    probability = float(pick["fairProbability"])
    best_price = int(pick["bestPrice"])
    implied = _american_implied(best_price)
    profit = best_price / 100 if best_price > 0 else 100 / abs(best_price)
    expected_value = probability * profit - (1 - probability)
    probability_spread = float(pick.get("probabilitySpread") or 0)
    book_count = int(pick.get("bookCount") or 0)
    consensus_spread = _median(spread_by_team.get(team, []))
    projected_total = _median(totals)
    home_margin = None
    if spread_by_team[home]:
        home_spread = _median(spread_by_team[home])
        home_margin = -home_spread if home_spread is not None else None
    elif spread_by_team[away]:
        away_spread = _median(spread_by_team[away])
        home_margin = away_spread if away_spread is not None else None
    projected_home = projected_away = None
    if projected_total is not None and home_margin is not None:
        projected_home = (projected_total + home_margin) / 2
        projected_away = (projected_total - home_margin) / 2

    coverage = min(1.0, book_count / 6)
    agreement = max(0.0, 1.0 - probability_spread / 0.08)
    market_strength = min(1.0, abs(probability - 0.5) / 0.18)
    completeness = (1.0 if consensus_spread is not None else 0.65) * (
        1.0 if projected_total is not None else 0.75
    )
    confidence = round(100 * (
        0.35 * coverage + 0.30 * agreement + 0.20 * market_strength + 0.15 * completeness
    ))
    confidence = max(1, min(99, confidence))
    factors = [
        f"{book_count}-book no-vig moneyline consensus",
        f"Best listed price {best_price:+d} at {pick['bestBook']}",
        f"Cross-book probability disagreement {probability_spread * 100:.1f} points",
    ]
    if consensus_spread is not None:
        factors.append(f"Consensus spread {consensus_spread:+.1f} for {team}")
    if projected_total is not None:
        factors.append(f"Consensus game total {projected_total:.1f}")
    risks = []
    if book_count < 3:
        risks.append("Limited sportsbook coverage")
    if probability_spread >= 0.05:
        risks.append("High sportsbook disagreement")
    risks.extend(["Injury feed not included", "Weather feed not included"])
    return {
        "modelVersion": "NCAAF_MARKET_ENSEMBLE_V1",
        "method": "MULTI_MARKET_CONSENSUS",
        "predictedWinner": team,
        "winProbability": round(probability, 6),
        "confidence": confidence,
        "bestPrice": best_price,
        "bestBook": pick["bestBook"],
        "expectedValue": round(expected_value, 6),
        "consensusSpread": round(consensus_spread, 2) if consensus_spread is not None else None,
        "projectedTotal": round(projected_total, 2) if projected_total is not None else None,
        "projectedScore": {
            "home": round(projected_home, 1) if projected_home is not None else None,
            "away": round(projected_away, 1) if projected_away is not None else None,
        },
        "factors": factors,
        "riskFlags": risks,
        "actionable": book_count >= 3 and confidence >= 60 and expected_value > 0,
        "disclaimer": "Market-derived research signal; not a guaranteed outcome.",
    }


def _add_shin_probabilities(outcomes: list[dict[str, object]]) -> None:
    try:
        fair = shin_method_devig(
            *[_american_implied(outcome["price"]) for outcome in outcomes]
        )
    except (KeyError, TypeError, ValueError):
        return
    for outcome, probability in zip(outcomes, fair):
        outcome["impliedProbability"] = round(
            _american_implied(outcome["price"]), 6
        )
        outcome["fairProbability"] = probability
        outcome["devigMethod"] = "shin"


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
                _add_shin_probabilities(outcomes)
                normalized_markets[key] = outcomes
        if normalized_markets:
            books.append({
                "key": str(raw_book.get("key") or ""),
                "title": str(raw_book.get("title") or raw_book.get("key") or "Sportsbook"),
                "lastUpdate": raw_book.get("last_update"),
                "markets": normalized_markets,
            })
    normalized = {
        "id": str(event.get("id") or ""),
        "sport": sport,
        "sportKey": str(event.get("sport_key") or GAME_SPORTS.get(sport, "")),
        "league": str(event.get("sport_title") or sport),
        "commenceTime": event.get("commence_time"),
        "homeTeam": str(event.get("home_team") or "Home"),
        "awayTeam": str(event.get("away_team") or "Away"),
        "bookmakers": books,
    }
    # A market-consensus signal is not a team prediction model. It summarizes
    # the no-vig probabilities already implied by independent books and pairs
    # that opinion with the best currently listed price. Keeping the label and
    # inputs explicit prevents price comparison from masquerading as an AI pick.
    consensus: list[dict[str, object]] = []
    names = {normalized["homeTeam"], normalized["awayTeam"]}
    for name in names:
        samples: list[float] = []
        prices: list[tuple[int, str]] = []
        for book in books:
            for outcome in book.get("markets", {}).get("h2h", []):
                if outcome.get("name") != name:
                    continue
                probability = _as_number(outcome.get("fairProbability"))
                price = _as_number(outcome.get("price"))
                if probability is not None:
                    samples.append(float(probability))
                if price is not None:
                    prices.append((int(price), str(book.get("title") or "Sportsbook")))
        if not samples or not prices:
            continue
        best_price, best_book = max(prices, key=lambda item: item[0])
        mean = sum(samples) / len(samples)
        spread = max(samples) - min(samples)
        consensus.append({
            "team": name,
            "fairProbability": round(mean, 6),
            "bookCount": len(samples),
            "probabilitySpread": round(spread, 6),
            "bestPrice": best_price,
            "bestBook": best_book,
            "label": "MARKET CONSENSUS",
        })
    consensus.sort(key=lambda item: float(item["fairProbability"]), reverse=True)
    normalized["marketConsensus"] = consensus
    if sport == "NCAAF":
        logos = _ncaaf_team_logos()
        normalized["homeTeamLogo"] = logos.get(_team_key(normalized["homeTeam"]), "")
        normalized["awayTeamLogo"] = logos.get(_team_key(normalized["awayTeam"]), "")
        normalized["prediction"] = _ncaaf_prediction(normalized, consensus)
    home_xg = _as_number(event.get("home_expected_goals"))
    away_xg = _as_number(event.get("away_expected_goals"))
    rho = _as_number(event.get("dixon_coles_rho"))
    total_line = _as_number(event.get("total_line"))
    if sport in {"EPL", "MLS", "NHL"} and home_xg and away_xg and rho is not None:
        try:
            normalized["dixonColes"] = dixon_coles_totals(
                float(home_xg),
                float(away_xg),
                float(rho),
                float(total_line if total_line is not None else 2.5),
            )
        except ValueError:
            pass
    return normalized


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
