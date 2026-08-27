import os
import re
import time
import unicodedata
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import requests
from dotenv import load_dotenv
from providers.espn_basketball_statistics import EspnBasketballStatisticsProvider
from services.mlb_official_stats_service import (
    market_is_known as mlb_market_is_known,
    resolve_market_value as resolve_mlb_market_value,
)

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

SPORTSDATAIO_KEY = (
    os.getenv("SPORTSDATAIO_KEY", "").strip()
    or os.getenv("SPORTSDATAIO_API_KEY", "").strip()
)

CACHE_SECONDS = 20
HTTP_TIMEOUT_SECONDS = 12
_live_cache: dict[str, dict[str, Any]] = {}
_espn_logs_cache: dict[str, dict[str, Any]] = {}
_mlb_statsapi_cache: dict[str, dict[str, Any]] = {}

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
    "NFL": {
        "base_url": "https://api.sportsdata.io/v3/nfl/stats/json",
        "live_boxscores_path": "/BoxScores/{date}",
    },
    "NHL": {
        "base_url": "https://api.sportsdata.io/v3/nhl/stats/json",
        "live_boxscores_path": "/BoxScores/{date}",
    },
}

STAT_MAP = {
    "pass yards": ["PassingYards", "PassingYardsDraftKings"],
    "pass yds": ["PassingYards", "PassingYardsDraftKings"],
    "passing yards": ["PassingYards", "PassingYardsDraftKings"],
    "passing touchdowns": ["PassingTouchdowns"],
    "pass touchdowns": ["PassingTouchdowns"],
    "pass tds": ["PassingTouchdowns"],
    "passing interceptions": ["PassingInterceptions", "Interceptions"],
    "pass interceptions": ["PassingInterceptions", "Interceptions"],
    "rush yards": ["RushingYards", "RushingYardsDraftKings"],
    "rush yds": ["RushingYards", "RushingYardsDraftKings"],
    "rushing yards": ["RushingYards", "RushingYardsDraftKings"],
    "receiving yards": ["ReceivingYards", "ReceivingYardsDraftKings"],
    "reception yards": ["ReceivingYards", "ReceivingYardsDraftKings"],
    "reception yds": ["ReceivingYards", "ReceivingYardsDraftKings"],
    "rush reception yards": ["RushingYards", "ReceivingYards"],
    "rush receiving yards": ["RushingYards", "ReceivingYards"],
    "receptions": ["Receptions", "ReceptionsDraftKings"],
    "pass attempts": ["PassingAttempts"],
    "pass completions": ["PassingCompletions"],
    "rush attempts": ["RushingAttempts"],
    "rushing attempts": ["RushingAttempts"],
    "receiving touchdowns": ["ReceivingTouchdowns"],
    "reception touchdowns": ["ReceivingTouchdowns"],
    "reception tds": ["ReceivingTouchdowns"],
    "rushing touchdowns": ["RushingTouchdowns"],
    "rush touchdowns": ["RushingTouchdowns"],
    "rush tds": ["RushingTouchdowns"],
    "anytime td": ["Touchdowns"],
    "anytime touchdown": ["Touchdowns"],
    "touchdowns": ["Touchdowns"],
    "sacks": ["Sacks"],
    "solo tackles": ["SoloTackles"],
    "tackles assists": ["AssistedTackles", "TackleAssists"],
    "points": ["Points"],
    "rebounds": ["Rebounds"],
    "assists": ["Assists"],
    "points rebounds": ["Points", "Rebounds"],
    "points assists": ["Points", "Assists"],
    "rebounds assists": ["Rebounds", "Assists"],
    "points rebounds assists": ["Points", "Rebounds", "Assists"],
    "pra": ["Points", "Rebounds", "Assists"],
    "blocks": ["BlockedShots", "Blocks"],
    "steals": ["Steals"],
    "blocks & steals": ["BlockedShots", "Blocks", "Steals"],
    "blocks steals": ["BlockedShots", "Blocks", "Steals"],
    "turnovers": ["Turnovers"],
    "field goals": ["FieldGoalsMade"],
    "fantasy points": ["FantasyPoints", "FantasyPointsDraftKings"],
    "three-pointers made": ["ThreePointersMade"],
    "three pointers made": ["ThreePointersMade"],
    "3-pointers made": ["ThreePointersMade"],
    "3 pointers made": ["ThreePointersMade"],
    "threes": ["ThreePointersMade"],
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
    "blocked shots": ["BlockedShots"],
    "power play points": ["PowerPlayPoints"],
    "goalie saves": ["GoaltendingSaves", "Saves"],
    "total saves": ["GoaltendingSaves", "Saves"],
    "saves": ["GoaltendingSaves", "Saves"],
    "birdies": ["Birdies"],
    "birdies or better": ["Birdies"],
    "bogeys": ["Bogeys"],
    "pars": ["Pars"],
    "fairways": ["FairwaysHit"],
    "fairways hit": ["FairwaysHit"],
    "greens": ["GreensInRegulation"],
    "greens in regulation": ["GreensInRegulation"],
    "strokes": ["Score"],
    "round score": ["Score"],
}


@dataclass(frozen=True)
class LiveStatSnapshot:
    value: float | None
    completed: bool
    status: str = ""
    source: str = ""
    game_detail: str = ""


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

    if SPORTSDATAIO_KEY:
        event_date = _sportsdata_date(game_start_time)
        live_boxscores = get_live_boxscores(
            sport=sport_key, season=target_season, event_date=event_date,
        )
        match = find_player_match_in_boxscores(
            boxscores=live_boxscores,
            player_name=player_name,
            team=team,
            matchup=matchup,
            event_id=event_id,
        ) if live_boxscores else None
        if match:
            player_row, game = match
            value = extract_prop_value(player_row, prop_type)
            if value is not None:
                return LiveStatSnapshot(
                    value,
                    _game_completed(game),
                    _game_status(game),
                    "sportsdata.io",
                    _game_detail(game, sport_key),
                )

    if sport_key in {"NBA", "WNBA"}:
        fallback = _espn_completed_basketball_snapshot(
            sport=sport_key,
            player_name=player_name,
            prop_type=prop_type,
            event_id=event_id,
            matchup=matchup,
            game_start_time=game_start_time,
        )
        if fallback.value is not None:
            return fallback

    if sport_key == "MLB":
        fallback = _mlb_statsapi_snapshot(
            player_name=player_name,
            prop_type=prop_type,
            event_id=event_id,
            matchup=matchup,
            game_start_time=game_start_time,
        )
        if fallback.value is not None:
            return fallback

    return LiveStatSnapshot(None, False, "no_authoritative_boxscore")


def _cached_json(
    *, cache: dict[str, dict[str, Any]], key: str, url: str,
    params: dict[str, object] | None = None, ttl_seconds: int = CACHE_SECONDS,
) -> dict[str, Any]:
    now = time.time()
    cached = cache.get(key)
    if cached and now - float(cached.get("time", 0)) < ttl_seconds:
        data = cached.get("data")
        if isinstance(data, dict):
            return data
    try:
        response = requests.get(
            url,
            params=params,
            headers={
                "Accept": "application/json",
                "User-Agent": (
                    "Mozilla/5.0 (compatible; PropsIntell/1.0; "
                    "+https://propsintell.com)"
                ),
            },
            timeout=HTTP_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        data = response.json()
    except (requests.RequestException, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    cache[key] = {"time": now, "data": data}
    return data


def _mlb_statsapi_snapshot(
    *, player_name: str, prop_type: str, event_id: str = "",
    matchup: str = "", game_start_time: str = "",
) -> LiveStatSnapshot:
    """Read an MLB in-progress box score from MLB's official Stats API.

    Odds-provider event ids are not necessarily MLB game ids, so a normalized
    matchup is the primary identity fallback. Only the matched game's feed is
    fetched, and both schedule/feed responses are cached for a short interval.
    """
    try:
        target_start = datetime.fromisoformat(
            str(game_start_time).replace("Z", "+00:00")
        )
    except (TypeError, ValueError):
        return LiveStatSnapshot(None, False, "invalid_game_date")
    game_date = target_start.date()

    start_date = (game_date - timedelta(days=1)).strftime("%Y-%m-%d")
    end_date = (game_date + timedelta(days=1)).strftime("%Y-%m-%d")
    schedule = _cached_json(
        cache=_mlb_statsapi_cache,
        key=f"schedule:{start_date}:{end_date}",
        url="https://statsapi.mlb.com/api/v1/schedule",
        # Provider start times are UTC. A late local game can fall on the next
        # UTC date, so search the adjacent dates and select only the exact
        # matchup instead of silently missing West Coast evening games.
        params={"sportId": 1, "startDate": start_date, "endDate": end_date},
    )
    exact_id_candidates: list[dict[str, Any]] = []
    matchup_candidates: list[dict[str, Any]] = []
    for date_row in schedule.get("dates", []):
        if not isinstance(date_row, dict):
            continue
        for game in date_row.get("games", []):
            if not isinstance(game, dict):
                continue
            game_pk = str(game.get("gamePk") or "")
            teams = game.get("teams")
            away = teams.get("away", {}) if isinstance(teams, dict) else {}
            home = teams.get("home", {}) if isinstance(teams, dict) else {}
            away_team = away.get("team", {}) if isinstance(away, dict) else {}
            home_team = home.get("team", {}) if isinstance(home, dict) else {}
            official_matchup = " @ ".join((
                str(away_team.get("name") or ""),
                str(home_team.get("name") or ""),
            ))
            if event_id and game_pk == str(event_id):
                exact_id_candidates.append(game)
            elif matchup and _normalize_matchup_identity(official_matchup) == (
                _normalize_matchup_identity(matchup)
            ):
                matchup_candidates.append(game)
    candidates = exact_id_candidates or matchup_candidates
    if not candidates:
        return LiveStatSnapshot(None, False, "mlb_game_not_found")

    # A three-day schedule can contain the same matchup multiple times. Use
    # the official start closest to the locked prop's start time instead of
    # treating a normal series as ambiguous.
    def _distance_from_target(game: dict[str, Any]) -> float:
        try:
            official_start = datetime.fromisoformat(
                str(game.get("gameDate") or "").replace("Z", "+00:00")
            )
            comparable_target = target_start
            if comparable_target.tzinfo is None:
                comparable_target = comparable_target.replace(tzinfo=timezone.utc)
            if official_start.tzinfo is None:
                official_start = official_start.replace(tzinfo=timezone.utc)
            return abs((official_start - comparable_target).total_seconds())
        except (TypeError, ValueError):
            return float("inf")

    candidates.sort(key=_distance_from_target)

    game_pk = str(candidates[0].get("gamePk") or "")
    if not game_pk:
        return LiveStatSnapshot(None, False, "mlb_game_not_found")
    feed = _cached_json(
        cache=_mlb_statsapi_cache,
        key=f"feed:{game_pk}",
        url=f"https://statsapi.mlb.com/api/v1.1/game/{game_pk}/feed/live",
    )
    return _mlb_snapshot_from_feed(
        feed=feed,
        player_name=player_name,
        prop_type=prop_type,
    )


def _mlb_snapshot_from_feed(
    *, feed: dict[str, Any], player_name: str, prop_type: str,
) -> LiveStatSnapshot:
    game_data = feed.get("gameData")
    live_data = feed.get("liveData")
    if not isinstance(game_data, dict) or not isinstance(live_data, dict):
        return LiveStatSnapshot(None, False, "mlb_boxscore_unavailable")
    status_row = game_data.get("status")
    abstract = (
        str(status_row.get("abstractGameState") or "")
        if isinstance(status_row, dict) else ""
    )
    detailed = (
        str(status_row.get("detailedState") or abstract)
        if isinstance(status_row, dict) else abstract
    )
    completed = abstract.strip().lower() == "final"
    status = "Final" if completed else "Live" if abstract == "Live" else detailed

    linescore = live_data.get("linescore")
    game_detail = ""
    if isinstance(linescore, dict) and not completed:
        ordinal = str(linescore.get("currentInningOrdinal") or "").strip()
        half = str(linescore.get("inningHalf") or "").strip().upper()
        game_detail = " ".join(part for part in (half, ordinal) if part)

    boxscore = live_data.get("boxscore")
    teams = boxscore.get("teams") if isinstance(boxscore, dict) else None
    matches: list[dict[str, Any]] = []
    for side in ("away", "home"):
        team_box = teams.get(side) if isinstance(teams, dict) else None
        players = team_box.get("players") if isinstance(team_box, dict) else None
        for player in players.values() if isinstance(players, dict) else []:
            if not isinstance(player, dict):
                continue
            person = player.get("person")
            name = person.get("fullName") if isinstance(person, dict) else ""
            if normalize_name(name) == normalize_name(player_name):
                matches.append(player)
    if len(matches) != 1:
        return LiveStatSnapshot(None, completed, "mlb_player_not_found")

    stats = matches[0].get("stats")
    pitching = stats.get("pitching") if isinstance(stats, dict) else None
    hitting = stats.get("batting") if isinstance(stats, dict) else None
    market = _normalize_live_stat_market(prop_type)
    # Share the grading resolver rather than keep a second, shorter table.
    # The local copy knew nothing of singles, doubles, walks or batter
    # strikeouts, so markets that graded correctly after the game still read
    # as unsupported while it was being played.
    box_score_line = {
        "pitching": pitching if isinstance(pitching, dict) else {},
        "batting": hitting if isinstance(hitting, dict) else {},
    }
    value = resolve_mlb_market_value(box_score_line, market)
    if value is None:
        return LiveStatSnapshot(
            None,
            completed,
            "missing_live_stat"
            if mlb_market_is_known(market)
            else "unsupported_market",
        )
    return LiveStatSnapshot(value, completed, status, "mlb-statsapi", game_detail)


def _espn_completed_basketball_snapshot(
    *, sport: str, player_name: str, prop_type: str, event_id: str,
    matchup: str, game_start_time: str,
) -> LiveStatSnapshot:
    try:
        target_date = datetime.fromisoformat(
            str(game_start_time).replace("Z", "+00:00")
        ).date()
    except (TypeError, ValueError):
        return LiveStatSnapshot(None, False, "invalid_game_date")

    # Saved start times are UTC while ESPN scoreboards are keyed by the
    # venue's calendar date. A 9 PM Pacific game is therefore commonly saved
    # as the following UTC day. Search the adjacent dates so a completed late
    # game does not remain FINAL/PENDING forever in Slip Watcher.
    logs: list[dict[str, object]] = []
    provider = EspnBasketballStatisticsProvider()
    for game_date in (
        target_date - timedelta(days=1),
        target_date,
        target_date + timedelta(days=1),
    ):
        cache_key = f"{sport}:{game_date.isoformat()}"
        cached = _espn_logs_cache.get(cache_key)
        now = time.time()
        if cached and now - float(cached.get("time", 0)) < 60:
            cached_logs = cached.get("data", [])
            if isinstance(cached_logs, list):
                logs.extend(cached_logs)
            continue
        try:
            daily_logs = provider.daily_game_logs(
                sport=sport,
                target_date=game_date,
                include_in_progress=True,
            )
        except (requests.RequestException, KeyError, ValueError):
            continue
        _espn_logs_cache[cache_key] = {"time": now, "data": daily_logs}
        logs.extend(daily_logs)

    if not logs:
        return LiveStatSnapshot(None, False, "espn_boxscore_unavailable")

    return _espn_snapshot_from_logs(
        logs=logs,
        player_name=player_name,
        prop_type=prop_type,
        event_id=event_id,
        matchup=matchup,
    )


def _espn_snapshot_from_logs(
    *, logs: list[dict[str, object]], player_name: str, prop_type: str,
    event_id: str = "", matchup: str = "",
) -> LiveStatSnapshot:
    wanted_player = normalize_name(player_name)
    wanted_matchup = _normalize_matchup_identity(matchup)
    player_rows = [
        row for row in logs
        if normalize_name(row.get("PLAYER_NAME", "")) == wanted_player
    ]
    candidates = [
        row for row in player_rows
        if (
            (event_id and str(row.get("GAME_ID", "")) == event_id)
            or (
                wanted_matchup
                and _normalize_matchup_identity(row.get("MATCHUP", ""))
                == wanted_matchup
            )
        )
    ]
    # Prop sites and ESPN do not share event IDs, and expansion-team or site
    # matchup labels can differ even for the same game. The surrounding fetch
    # is already restricted to the saved game's adjacent calendar dates. If
    # that window contains exactly one row for this player, it is a safe,
    # authoritative match and should power live progress instead of leaving
    # the leg at SCHEDULED/0. Multiple rows remain unresolved by design.
    if len(candidates) != 1 and len(player_rows) == 1:
        candidates = player_rows
    if len(candidates) != 1:
        return LiveStatSnapshot(None, False, "espn_player_not_found")

    row = candidates[0]
    completed = bool(row.get("GAME_COMPLETED", True))
    status = str(row.get("GAME_STATUS") or ("Final" if completed else "Live"))
    game_detail = str(row.get("GAME_DETAIL") or "")
    market = normalize_prop_type(prop_type)
    if market.startswith("player "):
        market = market.removeprefix("player ").strip()
    keys = {
        "points": ("PTS",),
        "rebounds": ("REB",),
        "assists": ("AST",),
        "points rebounds": ("PTS", "REB"),
        "points assists": ("PTS", "AST"),
        "rebounds assists": ("REB", "AST"),
        "pra": ("PTS", "REB", "AST"),
        "points rebounds assists": ("PTS", "REB", "AST"),
        "steals": ("STL",),
        "blocks": ("BLK",),
        "blocks steals": ("BLK", "STL"),
        "three pointers made": ("FG3M",),
        "3 pointers made": ("FG3M",),
        "threes": ("FG3M",),
    }.get(market)
    if market == "double double":
        counting_stats = []
        for key in ("PTS", "REB", "AST", "STL", "BLK"):
            try:
                counting_stats.append(float(row.get(key) or 0))
            except (TypeError, ValueError):
                return LiveStatSnapshot(None, False, "missing_final_stat")
        return LiveStatSnapshot(
            1.0 if sum(value >= 10 for value in counting_stats) >= 2 else 0.0,
            completed,
            status,
            "espn",
            game_detail,
        )
    if keys is None:
        return LiveStatSnapshot(None, False, "unsupported_market")
    values: list[float] = []
    for key in keys:
        try:
            values.append(float(row[key]))
        except (KeyError, TypeError, ValueError):
            return LiveStatSnapshot(None, False, "missing_final_stat")
    return LiveStatSnapshot(sum(values), completed, status, "espn", game_detail)


def _normalize_matchup_identity(value: object) -> str:
    words = normalize_name(value).split()
    return " ".join(word for word in words if word not in {"at", "vs", "v"})


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
    stat_keys = STAT_MAP.get(_normalize_live_stat_market(prop_type))
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


def _normalize_live_stat_market(value: object) -> str:
    market = normalize_prop_type(value)
    if market.startswith("player "):
        market = market.removeprefix("player ").strip()
    market = market.replace("+", " ").replace("&", " ")
    aliases = {"pts": "points", "rebs": "rebounds", "asts": "assists"}
    return " ".join(aliases.get(token, token) for token in market.split())


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


def _game_detail(game: dict[str, Any], sport: str) -> str:
    source = _game_object(game)
    if _game_completed(game):
        return ""
    clock = str(
        source.get("Clock")
        or source.get("TimeRemaining")
        or source.get("PeriodTimeRemaining")
        or ""
    ).strip()
    if not clock:
        try:
            minutes = int(source.get("TimeRemainingMinutes"))
            seconds = int(source.get("TimeRemainingSeconds") or 0)
            clock = f"{minutes}:{seconds:02d}"
        except (TypeError, ValueError):
            pass
    try:
        period = int(
            source.get("Quarter")
            or source.get("Period")
            or source.get("Inning")
            or 0
        )
    except (TypeError, ValueError):
        period = 0
    sport_key = str(sport).strip().upper()
    if sport_key in {"NBA", "WNBA", "NFL"}:
        label = (
            "OT"
            if period == 5
            else f"{period - 4}OT"
            if period > 5
            else f"Q{period}"
            if period > 0
            else ""
        )
    elif sport_key == "NHL":
        label = f"P{period}" if period > 0 else ""
    elif sport_key == "MLB":
        half = str(
            source.get("InningHalf") or source.get("HalfInning") or ""
        ).strip().upper()
        if half.startswith("T"):
            label = f"TOP {period}" if period > 0 else "TOP"
        elif half.startswith("B"):
            label = f"BOT {period}" if period > 0 else "BOT"
        else:
            label = f"INNING {period}" if period > 0 else ""
    else:
        label = f"P{period}" if period > 0 else ""
    return " • ".join(part for part in (label, clock) if part)


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
