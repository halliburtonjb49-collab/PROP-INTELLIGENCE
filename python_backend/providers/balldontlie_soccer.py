"""balldontlie soccer player-props provider.

The Odds API's soccer coverage (EPL/MLS/La Liga/Serie A/Bundesliga/Ligue 1)
has been returning zero events/props in production. balldontlie's
per-league soccer APIs expose real player prop lines
(GET /{league}/v2/odds/player_props) with an actual line value and
over/under prices, unlike balldontlie's tennis API which only has
match-winner moneyline odds.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from threading import local
import logging

import requests
from requests.adapters import HTTPAdapter

from config import BALLDONTLIE_API_KEY, HTTP_TIMEOUT_SECONDS

LOGGER = logging.getLogger(__name__)
BASE_URL = "https://api.balldontlie.io"

# league key -> (API path segment, sport_key used throughout the app)
LEAGUE_TO_SPORT = {
    "epl": "soccer_epl",
    "mls": "soccer_usa_mls",
    "ligue1": "soccer_france_ligue_one",
    "bundesliga": "soccer_germany_bundesliga",
    "seriea": "soccer_italy_serie_a",
    "laliga": "soccer_spain_la_liga",
}

# Only prop_type values that are genuine Over/Under markets with a real
# line are mapped. balldontlie's "Milestone" props (anytime_goal,
# first_goal, last_goal) are single-sided yes/no odds, not an over/under
# line, and don't fit the app's existing prop model.
_PROP_TYPE_TO_MARKET = {
    "shots": "player_shots",
    "shots_on_target": "player_shots_on_target",
    "assists": "player_assists",
    "saves": "player_goalkeeper_saves",
    "tackles": "player_tackles",
}

_http_local = local()


def _session() -> requests.Session:
    session = getattr(_http_local, "session", None)
    if session is None:
        session = requests.Session()
        adapter = HTTPAdapter(pool_maxsize=20)
        session.mount("https://", adapter)
        _http_local.session = session
    return session


def _get(path: str, params: dict[str, object]) -> dict[str, object]:
    if not BALLDONTLIE_API_KEY:
        raise RuntimeError("BALLDONTLIE_API_KEY is not configured")
    response = _session().get(
        f"{BASE_URL}/{path.lstrip('/')}",
        params=params,
        headers={"Authorization": BALLDONTLIE_API_KEY},
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()
    if not isinstance(payload, dict):
        raise RuntimeError("balldontlie returned a non-object payload")
    return payload


def fetch_upcoming_matches(league: str, *, lookahead_days: int = 5) -> list[dict[str, object]]:
    """Matches over the next few days. balldontlie's /matches has no
    started/finished filter, so callers must check `status` themselves."""
    now = datetime.now(timezone.utc)
    dates = [
        (now + timedelta(days=offset)).date().isoformat()
        for offset in range(lookahead_days + 1)
    ]
    payload = _get(f"{league}/v2/matches", {"dates": dates, "per_page": 100})
    data = payload.get("data")
    return [row for row in data if isinstance(row, dict)] if isinstance(data, list) else []


def fetch_player_props(league: str, match_id: object) -> list[dict[str, object]]:
    payload = _get(f"{league}/v2/odds/player_props", {"match_id": match_id})
    data = payload.get("data")
    return [row for row in data if isinstance(row, dict)] if isinstance(data, list) else []


def _team_name(raw_match: dict[str, object], side: str) -> str:
    team = raw_match.get(f"{side}_team")
    if isinstance(team, dict):
        return str(team.get("name") or team.get("short_name") or "").strip()
    return str(
        raw_match.get(f"{side}_team_name")
        or raw_match.get(f"{side}_team_id")
        or ""
    )


def _match_status(raw_match: dict[str, object]) -> str:
    status = str(raw_match.get("status") or "").strip().lower()
    if status in {"final", "finished", "ft", "completed"}:
        return "final"
    if status in {"live", "in_progress", "1h", "2h", "ht"}:
        return "live"
    return "scheduled"


def _number(value: object) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def normalize_match(
    raw_match: dict[str, object],
    raw_props: list[dict[str, object]],
    *,
    sport_key: str,
) -> tuple[dict[str, object], dict[str, object]]:
    match_id = str(raw_match.get("id") or "")
    home_team = _team_name(raw_match, "home")
    away_team = _team_name(raw_match, "away")
    if not home_team or not away_team:
        # Team-name field guesses came from summarized OpenAPI docs, not a
        # live response. If the real shape differs, this reveals it instead
        # of silently shipping blank matchups.
        LOGGER.warning(
            "balldontlie soccer could not resolve team names sport=%s matchID=%r rawKeys=%s",
            sport_key,
            raw_match.get("id"),
            sorted(raw_match.keys()),
        )
    event = {
        "id": f"bdl:{match_id}",
        "home_team": home_team,
        "away_team": away_team,
        "commence_time": str(raw_match.get("date") or ""),
        "status": _match_status(raw_match),
    }
    if raw_props and not any(
        _PROP_TYPE_TO_MARKET.get(str(p.get("prop_type") or "").strip().lower())
        for p in raw_props
    ):
        LOGGER.info(
            "balldontlie soccer sample prop row sport=%s sample=%r",
            sport_key,
            raw_props[0],
        )

    books: dict[str, dict[str, dict[tuple[str, float], list[dict[str, object]]]]] = {}
    unmapped_prop_types: set[str] = set()
    for raw_prop in raw_props:
        prop_type = str(raw_prop.get("prop_type") or "").strip().lower()
        market_key = _PROP_TYPE_TO_MARKET.get(prop_type)
        if market_key is None:
            unmapped_prop_types.add(prop_type)
            continue
        player = raw_prop.get("player")
        player_name = (
            str(player.get("name") or "").strip()
            if isinstance(player, dict)
            else ""
        )
        if not player_name and isinstance(player, dict):
            first = str(player.get("first_name") or "").strip()
            last = str(player.get("last_name") or "").strip()
            player_name = f"{first} {last}".strip()
        line = _number(raw_prop.get("line_value"))
        market = raw_prop.get("market")
        market_dict = market if isinstance(market, dict) else {}
        over_price = _number(market_dict.get("over_odds"))
        under_price = _number(market_dict.get("under_odds"))
        vendor = str(raw_prop.get("vendor") or "balldontlie")
        if not player_name or line is None or (over_price is None and under_price is None):
            continue
        market_groups = books.setdefault(vendor, {}).setdefault(market_key, {})
        outcomes = market_groups.setdefault((player_name, line), [])
        if over_price is not None:
            outcomes.append(
                {
                    "name": "Over",
                    "description": player_name,
                    "point": line,
                    "price": over_price,
                    "player_id": str(raw_prop.get("player_id") or ""),
                }
            )
        if under_price is not None:
            outcomes.append(
                {
                    "name": "Under",
                    "description": player_name,
                    "point": line,
                    "price": under_price,
                    "player_id": str(raw_prop.get("player_id") or ""),
                }
            )

    if raw_props and unmapped_prop_types:
        LOGGER.info(
            "balldontlie soccer skipped unmapped prop types sport=%s types=%s",
            sport_key,
            sorted(unmapped_prop_types),
        )

    bookmakers: list[dict[str, object]] = []
    for book_id, markets in books.items():
        normalized_markets = []
        for market_key, groups in markets.items():
            outcomes = [outcome for group in groups.values() for outcome in group]
            normalized_markets.append({"key": market_key, "outcomes": outcomes})
        bookmakers.append(
            {"key": book_id, "title": book_id.upper(), "markets": normalized_markets}
        )
    return event, {"bookmakers": bookmakers, "source": "balldontlie"}
