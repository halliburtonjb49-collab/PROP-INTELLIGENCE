"""SportsGameOdds v2 supplemental player-prop provider."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import re
from threading import Lock, local
from typing import Any

import requests
from requests.adapters import HTTPAdapter

from config import HTTP_TIMEOUT_SECONDS, SPORTSGAMEODDS_API_KEY

BASE_URL = "https://api.sportsgameodds.com/v2"
LEAGUE_TO_SPORT = {
    "MLB": "baseball_mlb",
    "NBA": "basketball_nba",
    "WNBA": "basketball_wnba",
    "NFL": "americanfootball_nfl",
    "NHL": "icehockey_nhl",
    "EPL": "soccer_epl",
    "MLS": "soccer_usa_mls",
}

_STAT_MARKETS = {
    "points": "player_points",
    "rebounds": "player_rebounds",
    "assists": "player_assists",
    "pointsreboundsassists": "player_points_rebounds_assists",
    "pointsrebounds": "player_points_rebounds",
    "pointsassists": "player_points_assists",
    "reboundsassists": "player_rebounds_assists",
    "blockssteals": "player_blocks_steals",
    "blocks": "player_blocks",
    "steals": "player_steals",
    "threes": "player_threes",
    "threepointersmade": "player_threes",
    "turnovers": "player_turnovers",
    "hits": "batter_hits",
    "totalbases": "batter_total_bases",
    "homeruns": "batter_home_runs",
    "rbis": "batter_rbis",
    "hitsrunsrbis": "batter_hits_runs_rbis",
    "singles": "batter_singles",
    "doubles": "batter_doubles",
    "triples": "batter_triples",
    "stolenbases": "batter_stolen_bases",
    "runs": "batter_runs_scored",
    "strikeouts": "pitcher_strikeouts",
    "pitcherstrikeouts": "pitcher_strikeouts",
    "walks": "pitcher_walks",
    "hitsallowed": "pitcher_hits_allowed",
    "earnedruns": "pitcher_earned_runs",
    "outs": "pitcher_outs",
    "passingyards": "player_pass_yds",
    "passyards": "player_pass_yds",
    "passingtouchdowns": "player_pass_tds",
    "rushingyards": "player_rush_yds",
    "receivingyards": "player_reception_yds",
    "receptions": "player_receptions",
    "passingattempts": "player_pass_attempts",
    "passingcompletions": "player_pass_completions",
    "interceptions": "player_pass_interceptions",
    "rushingattempts": "player_rush_attempts",
    "rushreceivingyards": "player_rush_reception_yds",
    "rushingreceivingyards": "player_rush_reception_yds",
    "receivingtouchdowns": "player_reception_tds",
    "rushingtouchdowns": "player_rush_tds",
    "sacks": "player_sacks",
    "solotackles": "player_solo_tackles",
    "tacklesassists": "player_tackles_assists",
    "touchdowns": "player_anytime_td",
    "shotsongoal": "player_shots_on_goal",
    "goals": "player_goals",
    "saves": "player_total_saves",
    "blockedshots": "player_blocked_shots",
    "shots": "player_shots",
    "shotsontarget": "player_shots_on_target",
}

_http_local = local()
_usage_lock = Lock()
_usage: dict[str, object] = {
    "configured": bool(SPORTSGAMEODDS_API_KEY),
    "requests": 0,
    "lastResponseAt": None,
    "lastStatus": None,
    "lastError": None,
}


def _session() -> requests.Session:
    session = getattr(_http_local, "session", None)
    if session is None:
        session = requests.Session()
        adapter = HTTPAdapter(pool_connections=4, pool_maxsize=4, max_retries=0)
        session.mount("https://", adapter)
        _http_local.session = session
    return session


def usage_snapshot() -> dict[str, object]:
    with _usage_lock:
        return dict(_usage)


def _record(status: int | None, error: str | None = None) -> None:
    with _usage_lock:
        _usage.update(
            requests=int(_usage["requests"]) + 1,
            lastResponseAt=datetime.now(timezone.utc).isoformat(),
            lastStatus=status,
            lastError=error,
        )


def _get(path: str, params: dict[str, object]) -> dict[str, Any]:
    if not SPORTSGAMEODDS_API_KEY:
        raise RuntimeError("SPORTSGAMEODDS_API_KEY is not configured")
    try:
        response = _session().get(
            f"{BASE_URL}/{path.lstrip('/')}",
            params=params,
            headers={"x-api-key": SPORTSGAMEODDS_API_KEY},
            timeout=HTTP_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict) or payload.get("success") is False:
            raise RuntimeError(str(payload.get("error") or "invalid response"))
        _record(response.status_code)
        return payload
    except Exception as exc:
        _record(None, str(exc))
        raise


def fetch_account_usage() -> dict[str, object]:
    payload = _get("account/usage", {})
    data = payload.get("data")
    return data if isinstance(data, dict) else {"data": data}


def fetch_upcoming_events(
    league_id: str,
    *,
    max_pages: int = 2,
    limit: int = 50,
) -> list[dict[str, Any]]:
    now = datetime.now(timezone.utc)
    params: dict[str, object] = {
        "leagueID": league_id,
        "oddsAvailable": "true",
        "started": "false",
        "includeOpposingOdds": "true",
        "includeAltLines": "false",
        "includeOpenCloseOdds": "true",
        "startsAfter": now.isoformat().replace("+00:00", "Z"),
        "startsBefore": (now + timedelta(days=4)).isoformat().replace("+00:00", "Z"),
        "limit": max(1, min(100, limit)),
    }
    events: list[dict[str, Any]] = []
    cursor: str | None = None
    for _ in range(max(1, max_pages)):
        page = _get("events", {**params, **({"cursor": cursor} if cursor else {})})
        data = page.get("data")
        if isinstance(data, list):
            events.extend(item for item in data if isinstance(item, dict))
        cursor = str(page.get("nextCursor") or "").strip() or None
        if not cursor:
            break
    return events


def _normalized_stat(stat_id: object) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(stat_id or "").lower())


def _market_key(
    *,
    stat_id: object,
    sport_key: str,
    bet_type: str,
    market_name: str,
) -> str | None:
    normalized = _normalized_stat(stat_id)
    text = market_name.lower()
    if normalized == "goals" and sport_key.startswith("soccer_"):
        return (
            "player_goal_scorer_anytime"
            if bet_type == "yn"
            else "player_goals"
        )
    if normalized == "strikeouts":
        return "pitcher_strikeouts" if "pitcher" in text else "batter_strikeouts"
    if normalized == "walks":
        return "pitcher_walks" if "pitcher" in text else "batter_walks"
    return _STAT_MARKETS.get(normalized)


def _number(value: object) -> float | None:
    try:
        return float(str(value).replace("+", "").strip())
    except (TypeError, ValueError):
        return None


def _team_name(event: dict[str, Any], side: str) -> str:
    teams = event.get("teams")
    candidate: object = None
    if isinstance(teams, dict):
        candidate = teams.get(side)
        if candidate is None:
            side_id = event.get(f"{side}TeamID")
            candidate = teams.get(side_id) if side_id else None
    if isinstance(candidate, dict):
        return str(
            candidate.get("name")
            or candidate.get("displayName")
            or candidate.get("shortName")
            or candidate.get("teamID")
            or ""
        )
    if candidate is not None:
        return str(candidate)
    return str(
        event.get(f"{side}TeamName")
        or event.get(f"{side}Team")
        or event.get(f"{side}TeamID")
        or ""
    )


def normalize_event(
    raw_event: dict[str, Any],
    *,
    sport_key: str,
) -> tuple[dict[str, Any], dict[str, Any]]:
    raw_id = str(raw_event.get("eventID") or raw_event.get("id") or "").strip()
    event_id = f"sgo:{raw_id}"
    status = raw_event.get("status")
    status_map = status if isinstance(status, dict) else {}
    event = {
        "id": event_id,
        "home_team": _team_name(raw_event, "home"),
        "away_team": _team_name(raw_event, "away"),
        "commence_time": (
            status_map.get("startsAt")
            or raw_event.get("startsAt")
            or raw_event.get("startTime")
            or ""
        ),
        "status": (
            "final"
            if status_map.get("finalized") or raw_event.get("finalized")
            else "live"
            if status_map.get("started") and not status_map.get("ended")
            else "scheduled"
        ),
    }
    players = raw_event.get("players")
    player_map = players if isinstance(players, dict) else {}
    odds = raw_event.get("odds")
    odds_map = odds if isinstance(odds, dict) else {}

    books: dict[str, dict[str, dict[tuple[str, float], list[dict[str, Any]]]]] = {}
    for raw_odd in odds_map.values():
        if not isinstance(raw_odd, dict):
            continue
        bet_type = str(raw_odd.get("betTypeID") or "").lower()
        side = str(raw_odd.get("sideID") or "").lower()
        period = str(raw_odd.get("periodID") or "").lower()
        entity_id = str(
            raw_odd.get("playerID") or raw_odd.get("statEntityID") or ""
        )
        if (
            bet_type not in {"ou", "yn"}
            or side not in {"over", "under", "yes", "no"}
            or period not in {"game", "reg", ""}
            or entity_id in {"", "all", "home", "away"}
        ):
            continue
        player = player_map.get(entity_id)
        player_name = (
            str(player.get("name") or "").strip()
            if isinstance(player, dict)
            else ""
        )
        if not player_name:
            market_name = str(raw_odd.get("marketName") or "")
            player_name = market_name.split(" Over/Under", 1)[0].strip()
        market_key = _market_key(
            stat_id=raw_odd.get("statID"),
            sport_key=sport_key,
            bet_type=bet_type,
            market_name=str(raw_odd.get("marketName") or ""),
        )
        if not player_name or not market_key:
            continue
        by_bookmaker = raw_odd.get("byBookmaker")
        if not isinstance(by_bookmaker, dict):
            continue
        for bookmaker_id, book_value in by_bookmaker.items():
            if not isinstance(book_value, dict) or book_value.get("available") is False:
                continue
            line = _number(
                book_value.get("overUnder")
                or raw_odd.get("bookOverUnder")
                or raw_odd.get("fairOverUnder")
            )
            price = _number(book_value.get("odds"))
            if bet_type == "yn" and line is None:
                line = 0.5
            if line is None or price is None:
                continue
            market_groups = books.setdefault(str(bookmaker_id), {}).setdefault(
                market_key, {}
            )
            market_groups.setdefault((player_name, line), []).append(
                {
                    "name": side.title(),
                    "description": player_name,
                    "point": line,
                    "price": price,
                    "player_id": entity_id,
                }
            )

    bookmakers: list[dict[str, Any]] = []
    for book_id, markets in books.items():
        normalized_markets: list[dict[str, Any]] = []
        for market_key, groups in markets.items():
            outcomes = [
                outcome
                for group in groups.values()
                for outcome in group
            ]
            normalized_markets.append({"key": market_key, "outcomes": outcomes})
        bookmakers.append(
            {"key": book_id, "title": book_id.upper(), "markets": normalized_markets}
        )
    return event, {"bookmakers": bookmakers, "source": "sportsgameodds"}
