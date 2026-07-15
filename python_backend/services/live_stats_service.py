import os
import time
from datetime import datetime
from pathlib import Path
from typing import Any

import requests
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

SPORTSDATAIO_KEY = (
    os.getenv("SPORTSDATAIO_KEY", "").strip()
    or os.getenv("SPORTSDATAIO_API_KEY", "").strip()
)

CACHE_SECONDS = 20
HTTP_TIMEOUT_SECONDS = 12
_live_cache: dict[str, dict[str, Any]] = {}

SPORT_CONFIG = {
    "NFL": {
        "base_url": "https://api.sportsdata.io/v3/nfl/stats/json",
        "live_boxscores_path": "/BoxScores/{season}",
    },
    "NBA": {
        "base_url": "https://api.sportsdata.io/v3/nba/stats/json",
        "live_boxscores_path": "/BoxScores/{season}",
    },
    "MLB": {
        "base_url": "https://api.sportsdata.io/v3/mlb/stats/json",
        "live_boxscores_path": "/BoxScores/{season}",
    },
    "WNBA": {
        "base_url": "https://api.sportsdata.io/v3/wnba/stats/json",
        "live_boxscores_path": "/BoxScores/{season}",
    },
}

STAT_MAP = {
    "pass yards": ["PassingYards", "PassingYardsDraftKings"],
    "passing yards": ["PassingYards", "PassingYardsDraftKings"],
    "rush yards": ["RushingYards", "RushingYardsDraftKings"],
    "rushing yards": ["RushingYards", "RushingYardsDraftKings"],
    "receiving yards": ["ReceivingYards", "ReceivingYardsDraftKings"],
    "receptions": ["Receptions", "ReceptionsDraftKings"],
    "pass attempts": ["PassingAttempts"],
    "pass completions": ["PassingCompletions"],
    "touchdowns": ["Touchdowns"],
    "points": ["Points"],
    "rebounds": ["Rebounds"],
    "assists": ["Assists"],
    "pra": ["Points", "Rebounds", "Assists"],
    "blocks": ["BlockedShots", "Blocks"],
    "steals": ["Steals"],
    "blocks & steals": ["BlockedShots", "Blocks", "Steals"],
    "three-pointers made": ["ThreePointersMade"],
    "3-pointers made": ["ThreePointersMade"],
    "pitcher strikeouts": ["PitchingStrikeouts", "Strikeouts"],
    "strikeouts": ["PitchingStrikeouts", "Strikeouts"],
    "pitcher outs recorded": ["PitchingOuts"],
    "pitcher outs": ["PitchingOuts"],
    "hits": ["Hits"],
    "hits allowed": ["PitchingHits"],
    "home runs": ["HomeRuns"],
    "rbis": ["RunsBattedIn"],
    "rbi": ["RunsBattedIn"],
}


def get_live_player_stat(
    *,
    player_name: str,
    team: str,
    prop_type: str,
    sport: str,
    season: str | None = None,
) -> float:
    sport_key = str(sport or "").strip().upper()
    target_season = season or str(datetime.now().year)

    if not SPORTSDATAIO_KEY:
        return 0.0

    if sport_key not in SPORT_CONFIG:
        return 0.0

    live_boxscores = get_live_boxscores(sport=sport_key, season=target_season)
    if not live_boxscores:
        return 0.0

    player_row = find_player_in_boxscores(
        boxscores=live_boxscores,
        player_name=player_name,
        team=team,
    )
    if not player_row:
        return 0.0

    return extract_prop_value(player_row, prop_type)


def get_live_boxscores(*, sport: str, season: str) -> list[dict[str, Any]]:
    cache_key = f"{sport}_{season}_boxscores"
    now = time.time()

    cached = _live_cache.get(cache_key)
    if cached and now - float(cached.get("time", 0)) < CACHE_SECONDS:
        data = cached.get("data")
        if isinstance(data, list):
            return data

    config = SPORT_CONFIG[sport]
    url = config["base_url"] + config["live_boxscores_path"].format(season=season)

    try:
        response = requests.get(
            url,
            params={"key": SPORTSDATAIO_KEY},
            timeout=HTTP_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        data = response.json()
        if not isinstance(data, list):
            return []
        _live_cache[cache_key] = {"time": now, "data": data}
        return data
    except requests.RequestException:
        return []


def find_player_in_boxscores(
    *,
    boxscores: list[dict[str, Any]],
    player_name: str,
    team: str | None = None,
) -> dict[str, Any] | None:
    wanted_name = normalize_name(player_name)
    wanted_team = normalize_team(team or "")

    for game in boxscores:
        possible_player_lists = [
            game.get("PlayerGames"),
            game.get("PlayerGameStats"),
            game.get("PlayerStats"),
            game.get("Players"),
        ]

        for player_list in possible_player_lists:
            if not isinstance(player_list, list):
                continue

            for player in player_list:
                if not isinstance(player, dict):
                    continue
                api_name = normalize_name(
                    player.get("Name")
                    or player.get("PlayerName")
                    or player.get("ShortName")
                    or ""
                )
                api_team = normalize_team(
                    player.get("Team")
                    or player.get("TeamKey")
                    or player.get("GlobalTeamID")
                    or ""
                )

                name_matches = (
                    wanted_name == api_name
                    or wanted_name in api_name
                    or api_name in wanted_name
                )
                team_matches = not wanted_team or wanted_team == api_team

                if name_matches and team_matches:
                    return player

    return None


def extract_prop_value(player_row: dict[str, Any], prop_type: str) -> float:
    stat_keys = STAT_MAP.get(normalize_prop_type(prop_type))
    if not stat_keys:
        return 0.0

    total = 0.0
    for key in stat_keys:
        value = player_row.get(key, 0)
        try:
            total += float(value or 0)
        except (TypeError, ValueError):
            total += 0.0

    return total


def normalize_name(value: object) -> str:
    return str(value).strip().lower().replace(".", "")


def normalize_team(value: object) -> str:
    return str(value).strip().upper()


def normalize_prop_type(value: object) -> str:
    return str(value).strip().lower()
