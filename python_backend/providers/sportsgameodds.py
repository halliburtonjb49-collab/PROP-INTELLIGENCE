"""SportsGameOdds v2 supplemental player-prop provider."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
import logging
import re
from threading import Lock, local
from typing import Any

import requests
from requests.adapters import HTTPAdapter

from config import HTTP_TIMEOUT_SECONDS, SPORTSGAMEODDS_API_KEY

LOGGER = logging.getLogger(__name__)
BASE_URL = "https://api.sportsgameodds.com/v2"
LEAGUE_TO_SPORT = {
    "ATP": "tennis_atp",
    "WTA": "tennis_wta",
    "PGA_MEN": "golf_pga",
    "UFC": "mma_mixed_martial_arts",
    "MLB": "baseball_mlb",
    "NBA": "basketball_nba",
    "WNBA": "basketball_wnba",
    "NFL": "americanfootball_nfl",
    "NHL": "icehockey_nhl",
    "EPL": "soccer_epl",
    "MLS": "soccer_usa_mls",
}

from services.market_config import SPORT_MARKETS

# Stats whose meaning depends on the sport. `shots` is a shot on target in
# soccer and a shot on goal in hockey, and the shared table below can only
# hold one of them, so the sport decides first.
_SPORT_STAT_MARKETS = {
    # A goalkeeper save and a goaltender save are the same act under
    # different market names, and soccer publishes tackles and goals of its
    # own that the shared table maps elsewhere.
    "_soccer": {
        "saves": "player_goalkeeper_saves",
        "goalkeepersaves": "player_goalkeeper_saves",
        "shots": "player_shots",
        "shotsontarget": "player_shots_on_target",
        "tackles": "player_tackles",
        "assists": "player_assists",
    },
    "aussierules_afl": {
        "goals": "player_goals_scored_over",
        "disposals": "player_disposals_over",
        "marks": "player_marks_over",
        "tackles": "player_tackles_over",
        "kicks": "player_kicks_over",
        "handballs": "player_handballs_over",
        "clearances": "player_clearances_over",
    },
    "icehockey_nhl": {
        "shots": "player_shots_on_goal",
        "shotsongoal": "player_shots_on_goal",
        "points": "player_points",
        "assists": "player_assists",
        "goals": "player_goals",
        "saves": "player_total_saves",
        "blockedshots": "player_blocked_shots",
        "powerplaypoints": "player_power_play_points",
    },
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
    "birdies": "player_birdies",
    "bogeys": "player_bogeys",
    "pars": "player_pars",
    "fairwayshit": "player_fairways_hit",
    "greensinregulation": "player_greens_in_regulation",
    "strokes": "player_strokes",
    "significantstrikes": "fighter_significant_strikes",
    "takedowns": "fighter_takedowns",
    "knockdowns": "fighter_knockdowns",
    "submissionattempts": "fighter_submission_attempts",
    "fighttime": "fighter_fight_time",
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
    "rateLimitedResponses": 0,
    "consecutiveRateLimits": 0,
    "cooldownUntil": None,
}


class ProviderCooldownError(RuntimeError):
    """Raised without making a request while the provider cooldown is active."""


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
        snapshot = dict(_usage)
    cooldown_until = snapshot.get("cooldownUntil")
    retry_after = 0
    if isinstance(cooldown_until, str):
        try:
            parsed = datetime.fromisoformat(cooldown_until.replace("Z", "+00:00"))
            retry_after = max(
                0,
                int((parsed - datetime.now(timezone.utc)).total_seconds()),
            )
        except ValueError:
            retry_after = 0
    snapshot["coolingDown"] = retry_after > 0
    snapshot["retryAfterSeconds"] = retry_after
    return snapshot


def _record(
    status: int | None,
    error: str | None = None,
    *,
    rate_limited: bool = False,
    cooldown_until: datetime | None = None,
) -> None:
    with _usage_lock:
        consecutive = int(_usage["consecutiveRateLimits"])
        if rate_limited:
            consecutive += 1
        elif status is not None and status < 400:
            consecutive = 0
        _usage.update(
            requests=int(_usage["requests"]) + 1,
            lastResponseAt=datetime.now(timezone.utc).isoformat(),
            lastStatus=status,
            lastError=error,
            rateLimitedResponses=(
                int(_usage["rateLimitedResponses"]) + (1 if rate_limited else 0)
            ),
            consecutiveRateLimits=consecutive,
            cooldownUntil=(
                cooldown_until.isoformat()
                if cooldown_until is not None
                else None
                if status is not None and status < 400
                else _usage.get("cooldownUntil")
            ),
        )


def _retry_after_seconds(response: requests.Response) -> int:
    raw = response.headers.get("Retry-After", "").strip()
    if raw.isdigit():
        return max(1, int(raw))
    if raw:
        try:
            retry_at = parsedate_to_datetime(raw)
            if retry_at.tzinfo is None:
                retry_at = retry_at.replace(tzinfo=timezone.utc)
            return max(
                1,
                int((retry_at - datetime.now(timezone.utc)).total_seconds()),
            )
        except (TypeError, ValueError):
            pass
    with _usage_lock:
        consecutive = int(_usage["consecutiveRateLimits"]) + 1
    return min(900, 60 * (2 ** min(4, consecutive - 1)))


def _enforce_cooldown() -> None:
    snapshot = usage_snapshot()
    if snapshot["coolingDown"] is True:
        raise ProviderCooldownError(
            "SportsGameOdds cooldown active; "
            f"retry in {snapshot['retryAfterSeconds']} seconds"
        )


def _get(path: str, params: dict[str, object]) -> dict[str, Any]:
    if not SPORTSGAMEODDS_API_KEY:
        raise RuntimeError("SPORTSGAMEODDS_API_KEY is not configured")
    _enforce_cooldown()
    try:
        response = _session().get(
            f"{BASE_URL}/{path.lstrip('/')}",
            params=params,
            headers={"x-api-key": SPORTSGAMEODDS_API_KEY},
            timeout=HTTP_TIMEOUT_SECONDS,
        )
        if response.status_code == 429:
            delay = _retry_after_seconds(response)
            cooldown_until = datetime.now(timezone.utc) + timedelta(seconds=delay)
            error = f"HTTP 429 rate limited; retry after {delay} seconds"
            _record(
                429,
                error,
                rate_limited=True,
                cooldown_until=cooldown_until,
            )
            raise ProviderCooldownError(error)
        if response.status_code >= 400:
            body = response.text.strip()[:500]
            raise requests.HTTPError(
                f"{response.status_code} error for url: {response.url} body: {body or '<empty>'}",
                response=response,
            )
        payload = response.json()
        if not isinstance(payload, dict) or payload.get("success") is False:
            raise RuntimeError(str(payload.get("error") or "invalid response"))
        _record(response.status_code)
        return payload
    except ProviderCooldownError:
        raise
    except requests.HTTPError as exc:
        _record(exc.response.status_code if exc.response is not None else None, str(exc))
        raise
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
    max_pages: int = 1,
    limit: int = 25,
) -> list[dict[str, Any]]:
    now = datetime.now(timezone.utc)
    specialty_horizon_days = 10 if league_id in {"PGA_MEN", "UFC"} else 4
    params: dict[str, object] = {
        "leagueID": league_id,
        "oddsAvailable": "true",
        "started": "false",
        "includeOpposingOdds": "true",
        "includeAltLines": "false",
        "includeOpenCloseOdds": "true",
        "startsAfter": now.isoformat().replace("+00:00", "Z"),
        "startsBefore": (now + timedelta(days=specialty_horizon_days)).isoformat().replace("+00:00", "Z"),
        "limit": max(1, min(100, limit)),
    }
    events: list[dict[str, Any]] = []
    cursor: str | None = None
    for _ in range(max(1, max_pages)):
        request_params = {**params, **({"cursor": cursor} if cursor else {})}
        try:
            page = _get("events", request_params)
        except requests.HTTPError as exc:
            # Some specialty leagues reject optional expansion flags even
            # though the common events endpoint accepts them elsewhere.
            # Retry once with the documented minimum query before declaring
            # the league unavailable.
            if exc.response is None or exc.response.status_code != 400:
                raise
            minimal_params = {
                key: value
                for key, value in request_params.items()
                if key in {"leagueID", "oddsAvailable", "started", "limit", "cursor"}
            }
            page = _get("events", minimal_params)
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
    """Resolve a stat to a market this sport actually has.

    The resolver below has many early returns for sport-specific shapes, and
    a guard placed inside any one of them would leave the others open --
    which is how `strikeouts` on a basketball event still resolved to a
    batter market. Validating once, here, covers every path.
    """

    mapped = _resolve_market_key(
        stat_id=stat_id,
        sport_key=sport_key,
        bet_type=bet_type,
        market_name=market_name,
    )
    if mapped is None:
        return None
    known = SPORT_MARKETS.get(sport_key)
    if known and mapped not in known:
        return None
    return mapped


def _resolve_market_key(
    *,
    stat_id: object,
    sport_key: str,
    bet_type: str,
    market_name: str,
) -> str | None:
    normalized = _normalized_stat(stat_id)
    text = market_name.lower()
    if sport_key.startswith("tennis_"):
        mapped = {
            "points": "player_sets_won",
            "truepoints": "player_tennis_points_won",
            "breakpoints": "player_break_points_won",
            "breakpointswon": "player_break_points_won",
            "games": "player_games_won",
            "gameswon": "player_games_won",
            "servingaces": "player_aces",
            "aces": "player_aces",
            "doublefaults": "player_double_faults",
            "fantasyscore": "player_fantasy_points",
        }.get(normalized)
        if mapped is not None:
            return mapped
        if "double fault" in text:
            return "player_double_faults"
        if "break point" in text:
            return "player_break_points_won"
        if "ace" in text:
            return "player_aces"
        if "games won" in text:
            return "player_games_won"
        if "sets won" in text:
            return "player_sets_won"
        return None
    if sport_key.startswith("golf_"):
        mapped = {
            "birdies": "player_birdies",
            "bogeys": "player_bogeys",
            "pars": "player_pars",
            "fairwayshit": "player_fairways_hit",
            "greensinregulation": "player_greens_in_regulation",
            "strokes": "player_strokes",
            "roundscore": "player_strokes",
            "fantasyscore": "player_fantasy_points",
        }.get(normalized)
        if mapped is not None:
            return mapped
        for token, key in {
            "birdie": "player_birdies",
            "bogey": "player_bogeys",
            "par": "player_pars",
            "fairway": "player_fairways_hit",
            "green in regulation": "player_greens_in_regulation",
            "round score": "player_strokes",
            "stroke": "player_strokes",
        }.items():
            if token in text:
                return key
        return None
    if sport_key == "mma_mixed_martial_arts":
        mapped = {
            "significantstrikes": "fighter_significant_strikes",
            "takedowns": "fighter_takedowns",
            "knockdowns": "fighter_knockdowns",
            "submissionattempts": "fighter_submission_attempts",
            "fighttime": "fighter_fight_time",
            "fantasyscore": "player_fantasy_points",
        }.get(normalized)
        if mapped is not None:
            return mapped
        for token, key in {
            "significant strike": "fighter_significant_strikes",
            "takedown": "fighter_takedowns",
            "knockdown": "fighter_knockdowns",
            "submission attempt": "fighter_submission_attempts",
            "fight time": "fighter_fight_time",
        }.items():
            if token in text:
                return key
        return None
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
    sport_specific = _SPORT_STAT_MARKETS.get(sport_key)
    if sport_specific is None and sport_key.startswith("soccer_"):
        sport_specific = _SPORT_STAT_MARKETS["_soccer"]
    sport_specific = sport_specific or {}
    mapped = sport_specific.get(normalized) or _STAT_MARKETS.get(normalized)
    return mapped


def _number(value: object) -> float | None:
    try:
        return float(str(value).replace("+", "").strip())
    except (TypeError, ValueError):
        return None


def _period_supported(sport_key: str, period: str) -> bool:
    if period in {"game", "reg", ""}:
        return True
    if sport_key.startswith("tennis_"):
        return period in {"match", "set"}
    if sport_key.startswith("golf_"):
        return period in {"round", "tournament"}
    if sport_key == "mma_mixed_martial_arts":
        return period in {"fight", "bout"}
    return False


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
    # Temporary: ATP/WTA/UFC fetch events successfully but yield zero props in
    # production, meaning every odd is being dropped by one of the filters
    # below. Sample the first few drops per event so the next sync's logs
    # reveal the real periodID/statID/betTypeID values instead of guessing.
    is_specialty_diagnostic = (
        sport_key.startswith("tennis_")
        or sport_key == "mma_mixed_martial_arts"
    )
    if is_specialty_diagnostic and not odds_map:
        LOGGER.warning(
            "sportsgameodds event has no odds payload sport=%s eventID=%r "
            "rawOddsType=%s rawKeys=%s",
            sport_key,
            raw_event.get("eventID") or raw_event.get("id"),
            type(odds).__name__,
            sorted(raw_event.keys()),
        )
    _logged_skips: set[tuple[object, ...]] = set()
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
            or not _period_supported(sport_key, period)
            or entity_id in {"", "all", "home", "away"}
        ):
            if is_specialty_diagnostic and len(_logged_skips) < 5:
                key = (bet_type, side, period, entity_id)
                if key not in _logged_skips:
                    _logged_skips.add(key)
                    LOGGER.warning(
                        "sportsgameodds dropped odd (filter) sport=%s betTypeID=%r "
                        "sideID=%r periodID=%r entityID=%r statID=%r marketName=%r",
                        sport_key,
                        raw_odd.get("betTypeID"),
                        raw_odd.get("sideID"),
                        raw_odd.get("periodID"),
                        entity_id,
                        raw_odd.get("statID"),
                        raw_odd.get("marketName"),
                    )
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
            if is_specialty_diagnostic and len(_logged_skips) < 5:
                key = ("market", raw_odd.get("statID"), raw_odd.get("marketName"))
                if key not in _logged_skips:
                    _logged_skips.add(key)
                    LOGGER.warning(
                        "sportsgameodds dropped odd (no market_key) sport=%s "
                        "statID=%r marketName=%r playerName=%r",
                        sport_key,
                        raw_odd.get("statID"),
                        raw_odd.get("marketName"),
                        player_name,
                    )
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
