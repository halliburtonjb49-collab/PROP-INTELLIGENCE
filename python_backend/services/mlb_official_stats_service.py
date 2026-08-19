"""Authoritative completed-game MLB prop results from the MLB Stats API."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
import logging
import re
import unicodedata
from typing import Any

import requests

from database.postgres import database_is_configured, get_database_pool
from services.mlb_headshot_service import mlb_player_id


LOGGER = logging.getLogger(__name__)
BASE_URL = "https://statsapi.mlb.com/api"
TIMEOUT_SECONDS = 12
_response_cache: dict[str, Any] = {}
# Grading has been failing to find an official result for 100% of checked
# MLB predictions in production. Rather than guess which of (game
# matching / player matching / market parsing) is the actual failure
# point, sample a few real failures per grading cycle and log exactly
# where the chain breaks.
_diagnostic_budget = {"remaining": 5}


@dataclass(frozen=True)
class OfficialMlbResult:
    value: float
    game_pk: str
    source: str = "mlb-stats-api"


def _normalized(value: object) -> str:
    text = unicodedata.normalize("NFKD", str(value or ""))
    ascii_text = "".join(char for char in text if not unicodedata.combining(char))
    return re.sub(r"[^a-z0-9]+", "", ascii_text.lower())


def _event_date(value: str) -> str:
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        parsed = datetime.now(timezone.utc)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(ZoneInfo("America/New_York")).date().isoformat()


def _event_datetime(value: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        parsed = datetime.now(timezone.utc)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _schedule_window(value: str) -> tuple[str, str]:
    """Cover every North-American scheduling day around an absolute start time."""
    event_day = _event_datetime(value).date()
    return (
        (event_day - timedelta(days=1)).isoformat(),
        (event_day + timedelta(days=1)).isoformat(),
    )


def _team_aliases(team: object) -> set[str]:
    if not isinstance(team, dict):
        return set()
    aliases = {
        _normalized(team.get(field, ""))
        for field in ("name", "teamName", "clubName", "shortName", "abbreviation")
    }
    return {alias for alias in aliases if alias}


def _matchup_contains_team(matchup: str, team: object) -> bool:
    wanted = _normalized(matchup)
    return any(alias in wanted for alias in _team_aliases(team))


def _get_json(path: str, params: dict[str, object] | None = None) -> Any:
    cache_key = f"{path}|{sorted((params or {}).items())}"
    if cache_key in _response_cache:
        return _response_cache[cache_key]
    response = requests.get(
        f"{BASE_URL}{path}",
        params=params,
        timeout=TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()
    _response_cache[cache_key] = payload
    return payload


def _final_game_pk(
    *,
    game_start_time: str,
    matchup: str,
    api_sports_game_id: str,
) -> str | None:
    if str(api_sports_game_id).isdigit():
        return str(api_sports_game_id)
    start_date, end_date = _schedule_window(game_start_time)
    payload = _get_json(
        "/v1/schedule",
        {
            "sportId": 1,
            "startDate": start_date,
            "endDate": end_date,
            "hydrate": "team",
        },
    )
    matches: list[tuple[str, datetime | None]] = []
    total_games = 0
    final_games = 0
    team_matched_games = 0
    sample_games: list[str] = []
    for date_row in payload.get("dates", []) if isinstance(payload, dict) else []:
        for game in date_row.get("games", []) if isinstance(date_row, dict) else []:
            total_games += 1
            teams = game.get("teams", {})
            away = (
                teams.get("away", {}).get("team", {})
                if isinstance(teams, dict)
                else {}
            )
            home = (
                teams.get("home", {}).get("team", {})
                if isinstance(teams, dict)
                else {}
            )
            status = game.get("status", {})
            final = str(status.get("abstractGameState", "")).lower() == "final"
            if final:
                final_games += 1
            if len(sample_games) < 6:
                sample_games.append(
                    f"{away.get('name')}@{home.get('name')}"
                    f"[{status.get('abstractGameState')}]"
                )
            team_matched = _matchup_contains_team(
                matchup, away
            ) and _matchup_contains_team(matchup, home)
            if final and team_matched:
                team_matched_games += 1
            if (
                final
                and team_matched
                and game.get("gamePk") is not None
            ):
                try:
                    game_time = datetime.fromisoformat(
                        str(game.get("gameDate", "")).replace("Z", "+00:00")
                    )
                except ValueError:
                    game_time = None
                matches.append((str(game["gamePk"]), game_time))
    resolved: str | None = None
    if len(matches) == 1:
        resolved = matches[0][0]
    elif len(matches) > 1:
        try:
            wanted_time = datetime.fromisoformat(
                str(game_start_time).replace("Z", "+00:00")
            )
            timed = [item for item in matches if item[1] is not None]
            if timed:
                resolved = min(
                    timed,
                    key=lambda item: abs((item[1] - wanted_time).total_seconds()),
                )[0]
        except ValueError:
            resolved = None
    if resolved is None and _diagnostic_budget["remaining"] > 0:
        _diagnostic_budget["remaining"] -= 1
        LOGGER.warning(
            "mlb grading: no game match matchup=%r window=%s-%s "
            "totalGames=%s finalGames=%s teamMatchedFinalGames=%s "
            "ambiguousMatches=%s sample=%s",
            matchup, start_date, end_date,
            total_games, final_games, team_matched_games,
            len(matches), sample_games,
        )
    return resolved


def _player_stats(boxscore: dict[str, Any], player_name: str) -> dict[str, Any] | None:
    wanted = _normalized(player_name)
    matches: list[dict[str, Any]] = []
    all_names: list[str] = []
    teams = boxscore.get("teams", {})
    for side in ("away", "home"):
        players = (
            teams.get(side, {}).get("players", {})
            if isinstance(teams, dict)
            else {}
        )
        if not isinstance(players, dict):
            continue
        for row in players.values():
            if not isinstance(row, dict):
                continue
            name = row.get("person", {}).get("fullName", "")
            all_names.append(name)
            if _normalized(name) == wanted:
                matches.append(row.get("stats", {}))
    if len(matches) != 1 and _diagnostic_budget["remaining"] > 0:
        _diagnostic_budget["remaining"] -= 1
        LOGGER.warning(
            "mlb grading: player match failed wantedPlayer=%r matchCount=%s "
            "boxscoreNames=%s",
            player_name, len(matches), all_names,
        )
    return matches[0] if len(matches) == 1 else None


_PITCHER_MARKET_TOKENS = (
    "pitcher",
    "hits allowed",
    "walks allowed",
    "earned run",
    "outs recorded",
)


def _market_text(market: str) -> str:
    return str(market).lower().replace("_", " ")


def _is_pitcher_market(text: str) -> bool:
    """Route a market to the pitching or the batting half of the box score.

    "Batter Strikeouts" and "Pitcher Strikeouts" share their only distinctive
    token, so the batter prefix has to win before the generic strikeout token
    is consulted. A bare "Strikeouts" market is the pitcher line.
    """

    if "batter" in text:
        return False
    return "strikeout" in text or any(
        token in text for token in _PITCHER_MARKET_TOKENS
    )


def _pitching_value(pitching: dict[str, Any], text: str) -> Any:
    if "strikeout" in text:
        return pitching.get("strikeOuts")
    if "out" in text:
        innings = str(pitching.get("inningsPitched", ""))
        if "." not in innings:
            return None
        whole, partial = innings.split(".", 1)
        return (int(whole) * 3) + int(partial[:1] or 0)
    if "hit" in text:
        return pitching.get("hits")
    if "walk" in text:
        return pitching.get("baseOnBalls")
    if "earned" in text:
        return pitching.get("earnedRuns")
    return None


def _batting_value(batting: dict[str, Any], text: str) -> Any:
    """Resolve a batter market against the official batting line.

    Singles, doubles, walks and batter strikeouts previously fell through
    every branch and returned None, which stranded the bulk of the MLB board
    as ungradable while the box score carried each of those stats outright.
    Order matters: the longer phrases have to be tested before the tokens
    they contain ("stolen bases" before "total bases", the combined
    hits + runs + rbis market before plain "rbi" or "hit").
    """

    def total(*keys: str) -> Any:
        parts = [batting.get(key) for key in keys]
        if any(part is None for part in parts):
            return None
        return sum(parts)

    if "stolen base" in text:
        return batting.get("stolenBases")
    if "total base" in text:
        return batting.get("totalBases")
    if "home run" in text:
        return batting.get("homeRuns")
    if "hit" in text and "run" in text and "rbi" in text:
        return total("hits", "runs", "rbi")
    if "rbi" in text:
        return batting.get("rbi")
    if "single" in text:
        # The box score reports extra base hits but never singles directly.
        extra_bases = total("doubles", "triples", "homeRuns")
        hits = batting.get("hits")
        if extra_bases is None or hits is None:
            return None
        return hits - extra_bases
    if "double" in text:
        return batting.get("doubles")
    if "triple" in text:
        return batting.get("triples")
    if "walk" in text:
        return batting.get("baseOnBalls")
    if "strikeout" in text:
        return batting.get("strikeOuts")
    if "hit" in text:
        return batting.get("hits")
    if "run" in text:
        return batting.get("runs")
    return None


def _market_value(stats: dict[str, Any], market: str) -> float | None:
    text = _market_text(market)
    pitching = stats.get("pitching", {})
    batting = stats.get("batting", {})
    if _is_pitcher_market(text):
        value = _pitching_value(pitching, text)
    else:
        value = _batting_value(batting, text)
    result: float | None
    try:
        result = float(value) if value is not None else None
    except (TypeError, ValueError):
        result = None
    if result is None and _diagnostic_budget["remaining"] > 0:
        _diagnostic_budget["remaining"] -= 1
        LOGGER.warning(
            "mlb grading: market value failed market=%r rawValue=%r "
            "pitchingKeys=%s battingKeys=%s",
            market, value, list(pitching.keys()), list(batting.keys()),
        )
    return result


_HIT_EVENTS = frozenset({"single", "double", "triple", "home_run"})
_WALK_EVENTS = frozenset({"walk", "intent_walk"})
_STRIKEOUT_EVENTS = frozenset({"strikeout", "strikeout_double_play"})


def _statcast_batter_stat(text: str) -> str | None:
    """Name the batter stat the pitch log can reconstruct, else None.

    Runs, RBIs and the combined hits + runs + rbis market are not derivable
    from a batter's own pitch log, so they stay ungraded rather than be
    graded as the hits they partially resemble.
    """

    if "hit" in text and "run" in text and "rbi" in text:
        return None
    if "total base" in text:
        return "total_bases"
    if "home run" in text:
        return "home_runs"
    if "single" in text:
        return "singles"
    if "double" in text:
        return "doubles"
    if "triple" in text:
        return "triples"
    if "walk" in text:
        return "walks"
    if "strikeout" in text:
        return "strikeouts"
    if "hit" in text:
        return "hits"
    return None


def official_mlb_result(
    *,
    player_name: str,
    market: str,
    matchup: str,
    game_start_time: str,
    api_sports_game_id: str = "",
) -> OfficialMlbResult | None:
    try:
        game_pk = _final_game_pk(
            game_start_time=game_start_time,
            matchup=matchup,
            api_sports_game_id=api_sports_game_id,
        )
        if game_pk is None:
            return None
        boxscore = _get_json(f"/v1/game/{game_pk}/boxscore")
        if not isinstance(boxscore, dict):
            return None
        stats = _player_stats(boxscore, player_name)
        if stats is None:
            return None
        value = _market_value(stats, market)
        if value is None:
            return None
        return OfficialMlbResult(value=value, game_pk=game_pk)
    except (requests.RequestException, TypeError, ValueError):
        return None


def historical_mlb_result(
    *, player_name: str, market: str, game_start_time: str,
    player_id: str = "", matchup: str = "", api_sports_game_id: str = "",
) -> OfficialMlbResult | None:
    """Resolve a completed prop from ingested Statcast when boxscore matching fails.

    A player/date may contain two games during a doubleheader. We intentionally
    refuse to combine them; the exact game must be resolved by the official API.
    """
    if not database_is_configured():
        return None
    official_id = str(player_id or "").strip()
    if not official_id.isdigit():
        resolved = mlb_player_id(player_name)
        official_id = str(resolved or "")
    if not official_id.isdigit():
        return None
    text = _market_text(market)
    is_pitcher = _is_pitcher_market(text)
    batter_stat = None if is_pitcher else _statcast_batter_stat(text)
    if is_pitcher and "strikeout" not in text:
        return None
    if not is_pitcher and batter_stat is None:
        return None
    identifier_column = "pitcher_id" if is_pitcher else "batter_id"
    exact_game_pk = _final_game_pk(
        game_start_time=game_start_time,
        matchup=matchup,
        api_sports_game_id=api_sports_game_id,
    ) if matchup or api_sports_game_id else None
    start_date, end_date = _schedule_window(game_start_time)
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        if exact_game_pk:
            cursor.execute(
                f"""select game_pk,events from historical_mlb_pitches
                    where {identifier_column}=%s and game_pk=%s
                    order by game_pk""",
                (official_id, exact_game_pk),
            )
        else:
            cursor.execute(
                f"""select game_pk,events from historical_mlb_pitches
                    where {identifier_column}=%s and game_date between %s and %s
                    order by game_pk""",
                (official_id, start_date, end_date),
            )
        rows = cursor.fetchall()
    by_game: dict[str, list[str]] = {}
    for game_pk, event in rows:
        by_game.setdefault(str(game_pk), []).append(str(event or ""))
    if len(by_game) != 1:
        return None
    game_pk, events = next(iter(by_game.items()))
    if is_pitcher:
        value = sum(event in _STRIKEOUT_EVENTS for event in events)
    elif batter_stat == "total_bases":
        weights = {"single": 1, "double": 2, "triple": 3, "home_run": 4}
        value = sum(weights.get(event, 0) for event in events)
    elif batter_stat == "walks":
        value = sum(event in _WALK_EVENTS for event in events)
    elif batter_stat == "strikeouts":
        value = sum(event in _STRIKEOUT_EVENTS for event in events)
    elif batter_stat == "hits":
        value = sum(event in _HIT_EVENTS for event in events)
    else:
        wanted = {
            "singles": "single",
            "doubles": "double",
            "triples": "triple",
            "home_runs": "home_run",
        }[batter_stat]
        value = sum(event == wanted for event in events)
    return OfficialMlbResult(
        value=float(value), game_pk=game_pk, source="statcast-history",
    )
