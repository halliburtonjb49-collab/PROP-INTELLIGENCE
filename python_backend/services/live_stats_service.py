import os
import re
import time
import unicodedata
from dataclasses import dataclass
from datetime import datetime, timezone
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
    "NBA": {
        "base_url": "https://api.sportsdata.io/v3/nba/stats/json",
        "live_boxscores_path": "/BoxScores/{date}",
    },
    "MLB": {
        "base_url": "https://api.sportsdata.io/v3/mlb/stats/json",
        "live_boxscores_path": "/BoxScores/{date}",
    },
    "WNBA": {
        "base_url": "https://api.sportsdata.io/v3/wnba/stats/json",
        "live_boxscores_path": "/BoxScores/{date}",
    },
    "NHL": {
        "base_url": "https://api.sportsdata.io/v3/nhl/stats/json",
        "live_boxscores_path": "/BoxScores/{date}",
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
    "goals": ["Goals"],
    "shots on goal": ["ShotsOnGoal"],
    "player shots on goal": ["ShotsOnGoal"],
    "goalie saves": ["GoaltendingSaves", "Saves"],
    "saves": ["GoaltendingSaves", "Saves"],
    "birdies": ["Birdies"],
    "birdies or better": ["Birdies"],
    "bogeys": ["Bogeys"],
    "pars": ["Pars"],
    "fairways": ["FairwaysHit"],
    "greens": ["GreensInRegulation"],
    "strokes": ["Score"],
    "round score": ["Score"],
}


@dataclass(frozen=True)
class LiveStatSnapshot:
    value: float | None
    completed: bool
    status: str = ""


def get_live_player_stat(
    *,
    player_name: str,
    team: str,
    prop_type: str,
    sport: str,
    season: str | None = None,
    event_id: str = "",
    matchup: str = "",
    game_start_time: str = "",
) -> float | None:
    """Returns the player's current live value for prop_type, or None if
    it can't be determined (missing key, unsupported sport, no boxscore
    data yet, player not found). None is distinct from a real 0 value
    (e.g. a batter with 0 hits so far in a live game)."""
    sport_key = str(sport or "").strip().upper()
    return get_live_player_stat_snapshot(
        player_name=player_name,
        team=team,
        prop_type=prop_type,
        sport=sport,
        season=season,
        event_id=event_id,
        matchup=matchup,
        game_start_time=game_start_time,
    ).value


def get_live_player_stat_snapshot(
    *,
    player_name: str,
    team: str,
    prop_type: str,
    sport: str,
    season: str | None = None,
    event_id: str = "",
    matchup: str = "",
    game_start_time: str = "",
) -> LiveStatSnapshot:
    sport_key = str(sport or "").strip().upper()
    target_season = season or str(datetime.now().year)

    if not SPORTSDATAIO_KEY:
        return LiveStatSnapshot(None, False, "provider_unavailable")

    if sport_key in {"PGA", "GOLF"}:
        return _get_golf_snapshot(
            player_name=player_name,
            prop_type=prop_type,
            season=target_season,
            matchup=matchup,
            game_start_time=game_start_time,
        )
    if sport_key not in SPORT_CONFIG:
        return LiveStatSnapshot(None, False, "unsupported_sport")

    event_date = _sportsdata_date(game_start_time)
    live_boxscores = get_live_boxscores(
        sport=sport_key,
        season=target_season,
        event_date=event_date,
    )
    if not live_boxscores:
        return LiveStatSnapshot(None, False, "no_boxscore")

    match = find_player_match_in_boxscores(
        boxscores=live_boxscores,
        player_name=player_name,
        team=team,
        matchup=matchup,
        event_id=event_id,
    )
    if not match:
        return LiveStatSnapshot(None, False, "player_not_found")
    player_row, game = match

    return LiveStatSnapshot(
        extract_prop_value(player_row, prop_type),
        _game_completed(game),
        _game_status(game),
    )


def get_live_boxscores(
    *, sport: str, season: str, event_date: str | None = None
) -> list[dict[str, Any]]:
    date_value = event_date or _sportsdata_date("")
    cache_key = f"{sport}_{date_value}_boxscores"
    now = time.time()

    cached = _live_cache.get(cache_key)
    if cached and now - float(cached.get("time", 0)) < CACHE_SECONDS:
        data = cached.get("data")
        if isinstance(data, list):
            return data

    config = SPORT_CONFIG[sport]
    path = config["live_boxscores_path"].format(
        season=season,
        date=date_value,
    )
    url = config["base_url"] + path

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
    match = find_player_match_in_boxscores(
        boxscores=boxscores,
        player_name=player_name,
        team=team,
    )
    return match[0] if match else None


def find_player_match_in_boxscores(
    *,
    boxscores: list[dict[str, Any]],
    player_name: str,
    team: str | None = None,
    matchup: str = "",
    event_id: str = "",
) -> tuple[dict[str, Any], dict[str, Any]] | None:
    wanted_name = normalize_name(player_name)
    wanted_team = normalize_team(team or "")
    matches: list[tuple[dict[str, Any], dict[str, Any]]] = []

    for game in boxscores:
        if not isinstance(game, dict):
            continue
        if event_id and str(
            game.get("GameID")
            or game.get("GameKey")
            or game.get("GlobalGameID")
            or ""
        ) == event_id:
            game_matches = True
        else:
            game_matches = _matchup_matches(game, matchup)
        if matchup and not game_matches:
            continue
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
                    matches.append((player, game))

    # Ambiguous name matches must remain unresolved instead of borrowing a
    # stat from the wrong game.
    return matches[0] if len(matches) == 1 else None


def extract_prop_value(player_row: dict[str, Any], prop_type: str) -> float | None:
    stat_keys = STAT_MAP.get(normalize_prop_type(prop_type))
    if not stat_keys:
        return None

    total = 0.0
    for key in stat_keys:
        value = player_row.get(key, 0)
        try:
            total += float(value or 0)
        except (TypeError, ValueError):
            total += 0.0

    return total


def normalize_name(value: object) -> str:
    normalized = unicodedata.normalize("NFKD", str(value))
    ascii_value = "".join(
        char for char in normalized if not unicodedata.combining(char)
    )
    return " ".join(re.sub(r"[^a-z0-9]+", " ", ascii_value.lower()).split())


def normalize_team(value: object) -> str:
    return str(value).strip().upper()


def normalize_prop_type(value: object) -> str:
    return " ".join(
        str(value).strip().lower().replace("_", " ").replace("-", " ").split()
    )


def _sportsdata_date(value: str) -> str:
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        parsed = datetime.now(timezone.utc)
    return parsed.strftime("%Y-%b-%d").upper()


def _game_object(game: dict[str, Any]) -> dict[str, Any]:
    nested = game.get("Game") or game.get("Score")
    return nested if isinstance(nested, dict) else game


def _game_status(game: dict[str, Any]) -> str:
    source = _game_object(game)
    return str(
        source.get("Status")
        or source.get("GameStatus")
        or source.get("StatusName")
        or ""
    )


def _game_completed(game: dict[str, Any]) -> bool:
    source = _game_object(game)
    if source.get("IsOver") is True or source.get("IsClosed") is True:
        return True
    return _game_status(game).strip().lower() in {
        "final", "finished", "completed", "f", "closed",
    }


def _matchup_matches(game: dict[str, Any], matchup: str) -> bool:
    if not matchup:
        return True
    source = _game_object(game)
    wanted = normalize_name(matchup)
    away = normalize_name(
        source.get("AwayTeam") or source.get("AwayTeamName") or ""
    )
    home = normalize_name(
        source.get("HomeTeam") or source.get("HomeTeamName") or ""
    )
    return bool(away and home and away in wanted and home in wanted)


def _golf_get(path: str) -> Any:
    cache_key = f"golf:{path}"
    now = time.time()
    cached = _live_cache.get(cache_key)
    if cached and now - float(cached.get("time", 0)) < CACHE_SECONDS:
        return cached.get("data")
    try:
        response = requests.get(
            f"https://api.sportsdata.io/golf/v2/json/{path}",
            headers={"Ocp-Apim-Subscription-Key": SPORTSDATAIO_KEY},
            timeout=HTTP_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        data = response.json()
        _live_cache[cache_key] = {"time": now, "data": data}
        return data
    except (requests.RequestException, ValueError):
        return None


def _get_golf_snapshot(
    *,
    player_name: str,
    prop_type: str,
    season: str,
    matchup: str,
    game_start_time: str,
) -> LiveStatSnapshot:
    tournaments = _golf_get(f"Tournaments/{season}")
    if not isinstance(tournaments, list):
        return LiveStatSnapshot(None, False, "no_tournament_schedule")
    wanted = normalize_name(matchup)
    candidates = [
        item for item in tournaments
        if isinstance(item, dict)
        and wanted
        and (
            normalize_name(item.get("Name", "")) in wanted
            or wanted in normalize_name(item.get("Name", ""))
        )
    ]
    if len(candidates) != 1:
        return LiveStatSnapshot(None, False, "tournament_not_found")
    tournament = candidates[0]
    tournament_id = tournament.get("TournamentID")
    if tournament_id is None:
        return LiveStatSnapshot(None, False, "tournament_not_found")
    leaderboard = _golf_get(f"Leaderboard/{tournament_id}")
    if not isinstance(leaderboard, dict):
        return LiveStatSnapshot(None, False, "no_leaderboard")
    players = leaderboard.get("Players")
    if not isinstance(players, list):
        return LiveStatSnapshot(None, False, "no_leaderboard")
    player_matches = [
        player for player in players
        if isinstance(player, dict)
        and normalize_name(player.get("Name", "")) == normalize_name(player_name)
    ]
    if len(player_matches) != 1:
        return LiveStatSnapshot(None, False, "player_not_found")
    player = player_matches[0]
    rounds = player.get("Rounds") or player.get("PlayerRounds") or []
    if not isinstance(rounds, list) or not rounds:
        return LiveStatSnapshot(None, False, "round_not_started")
    target_day = _iso_date(game_start_time)
    day_rounds = [
        row for row in rounds
        if isinstance(row, dict) and target_day and _iso_date(str(row.get("Day", ""))) == target_day
    ]
    round_row = day_rounds[-1] if day_rounds else rounds[-1]
    if not isinstance(round_row, dict):
        return LiveStatSnapshot(None, False, "round_not_started")
    value = _golf_round_value(round_row, prop_type)
    completed = bool(round_row.get("IsRoundOver"))
    if not completed:
        holes = round_row.get("Holes")
        completed = isinstance(holes, list) and len(holes) >= 18
    return LiveStatSnapshot(value, completed, "final" if completed else "live")


def _iso_date(value: str) -> str:
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).date().isoformat()
    except (TypeError, ValueError):
        return ""


def _golf_round_value(round_row: dict[str, Any], prop_type: str) -> float | None:
    market = normalize_prop_type(prop_type)
    direct_keys = {
        "birdies": ("Birdies", "BirdiesOrBetter"),
        "birdies or better": ("BirdiesOrBetter", "Birdies"),
        "bogeys": ("Bogeys",),
        "pars": ("Pars",),
        "fairways": ("FairwaysHit",),
        "greens": ("GreensInRegulation",),
        "strokes": ("Score", "Strokes"),
        "round score": ("Score", "Strokes"),
    }
    for key in direct_keys.get(market, ()):
        value = round_row.get(key)
        if isinstance(value, (int, float)):
            return float(value)
    holes = round_row.get("Holes")
    if not isinstance(holes, list):
        return None
    scored = [
        hole for hole in holes
        if isinstance(hole, dict)
        and isinstance(hole.get("Score"), (int, float))
        and isinstance(hole.get("Par"), (int, float))
    ]
    if market in {"strokes", "round score"}:
        return float(sum(float(hole["Score"]) for hole in scored))
    if market in {"birdies", "birdies or better"}:
        return float(sum(1 for hole in scored if hole["Score"] < hole["Par"]))
    if market == "bogeys":
        return float(sum(1 for hole in scored if hole["Score"] > hole["Par"]))
    if market == "pars":
        return float(sum(1 for hole in scored if hole["Score"] == hole["Par"]))
    return None
