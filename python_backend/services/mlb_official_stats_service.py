"""Authoritative completed-game MLB prop results from the MLB Stats API."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import re
import unicodedata
from typing import Any

import requests


BASE_URL = "https://statsapi.mlb.com/api"
TIMEOUT_SECONDS = 12
_response_cache: dict[str, Any] = {}


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
    return parsed.date().isoformat()


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
    payload = _get_json(
        "/v1/schedule",
        {
            "sportId": 1,
            "date": _event_date(game_start_time),
            "hydrate": "team",
        },
    )
    wanted = _normalized(matchup)
    matches: list[tuple[str, datetime | None]] = []
    for date_row in payload.get("dates", []) if isinstance(payload, dict) else []:
        for game in date_row.get("games", []) if isinstance(date_row, dict) else []:
            teams = game.get("teams", {})
            away = (
                teams.get("away", {}).get("team", {}).get("name", "")
                if isinstance(teams, dict)
                else ""
            )
            home = (
                teams.get("home", {}).get("team", {}).get("name", "")
                if isinstance(teams, dict)
                else ""
            )
            status = game.get("status", {})
            final = str(status.get("abstractGameState", "")).lower() == "final"
            if (
                final
                and _normalized(away) in wanted
                and _normalized(home) in wanted
                and game.get("gamePk") is not None
            ):
                try:
                    game_time = datetime.fromisoformat(
                        str(game.get("gameDate", "")).replace("Z", "+00:00")
                    )
                except ValueError:
                    game_time = None
                matches.append((str(game["gamePk"]), game_time))
    if len(matches) == 1:
        return matches[0][0]
    if len(matches) > 1:
        try:
            wanted_time = datetime.fromisoformat(
                str(game_start_time).replace("Z", "+00:00")
            )
            timed = [item for item in matches if item[1] is not None]
            if timed:
                return min(
                    timed,
                    key=lambda item: abs((item[1] - wanted_time).total_seconds()),
                )[0]
        except ValueError:
            return None
    return None


def _player_stats(boxscore: dict[str, Any], player_name: str) -> dict[str, Any] | None:
    wanted = _normalized(player_name)
    matches: list[dict[str, Any]] = []
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
            if _normalized(name) == wanted:
                matches.append(row.get("stats", {}))
    return matches[0] if len(matches) == 1 else None


def _market_value(stats: dict[str, Any], market: str) -> float | None:
    text = str(market).lower().replace("_", " ")
    pitching = stats.get("pitching", {})
    batting = stats.get("batting", {})
    if "pitcher" in text or "strikeout" in text or "outs recorded" in text:
        if "strikeout" in text:
            value = pitching.get("strikeOuts")
        elif "out" in text:
            innings = str(pitching.get("inningsPitched", ""))
            if "." not in innings:
                return None
            whole, partial = innings.split(".", 1)
            value = (int(whole) * 3) + int(partial[:1] or 0)
        elif "hit" in text:
            value = pitching.get("hits")
        elif "walk" in text:
            value = pitching.get("baseOnBalls")
        elif "earned" in text:
            value = pitching.get("earnedRuns")
        else:
            return None
    elif "total base" in text:
        value = batting.get("totalBases")
    elif "home run" in text:
        value = batting.get("homeRuns")
    elif "rbi" in text:
        value = batting.get("rbi")
    elif "hit" in text:
        value = batting.get("hits")
    elif "run" in text:
        value = batting.get("runs")
    else:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
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
