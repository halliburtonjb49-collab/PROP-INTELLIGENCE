"""Resolves athlete headshot URLs via ESPN's public site APIs.

Covers roster-based NBA, WNBA, and NHL plus event-based PGA and UFC.
Soccer returns no headshot data through these endpoints and is deliberately
handled by the Sportmonks integration instead.

ESPN's own stats sites for some leagues block traffic from cloud/datacenter
IPs (e.g. stats.nba.com resets connections outright), which is why this
goes through ESPN's site API instead - it's been reliable from a hosted
Render environment.

Same request-time-safe pattern as mlb_headshot_service.py: a scheduled sync
job populates a local cache; get_props() and friends only ever read it.
"""

import json
import re
import unicodedata
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests

from config import ESPN_HEADSHOT_MAP_PATH, HTTP_TIMEOUT_SECONDS

HEADSHOT_MAP_PATH = ESPN_HEADSHOT_MAP_PATH

# App sport label (services.formatters.format_sport_label output) ->
# (ESPN sport slug, ESPN league slug).
LEAGUES: dict[str, tuple[str, str]] = {
    "NBA": ("basketball", "nba"),
    "WNBA": ("basketball", "wnba"),
    "NHL": ("hockey", "nhl"),
}

# Individual sports expose athletes through current-event scoreboards rather
# than team rosters.
EVENT_LEAGUES: dict[str, tuple[str, str]] = {
    "PGA": ("golf", "pga"),
    "UFC": ("mma", "ufc"),
}


def _normalize_name(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_only = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    cleaned = re.sub(r"[^a-z0-9]+", " ", ascii_only.lower()).strip()
    return " ".join(cleaned.split())


@lru_cache(maxsize=1)
def _load_map() -> dict[str, dict[str, str]]:
    if not HEADSHOT_MAP_PATH.exists():
        return {}
    try:
        payload = json.loads(HEADSHOT_MAP_PATH.read_text(encoding="utf-8"))
        leagues = payload.get("leagues") if isinstance(payload, dict) else None
        if isinstance(leagues, dict):
            return {
                str(sport): {str(name): str(url) for name, url in players.items()}
                for sport, players in leagues.items()
            }
    except Exception:
        pass
    return {}


def espn_headshot_url(player_name: str, sport: str) -> str | None:
    players = _load_map().get(sport)
    if not players:
        return None
    return players.get(_normalize_name(player_name))


def espn_headshot_cache_health() -> dict[str, object]:
    result: dict[str, object] = {
        "status": "missing",
        "mode": (
            "persistent-disk"
            if HEADSHOT_MAP_PATH.parent == Path("/var/data")
            else "local-development"
        ),
        "leagueCounts": {},
        "playerCount": 0,
        "updatedAtUtc": None,
    }
    if not HEADSHOT_MAP_PATH.exists():
        return result
    try:
        payload = json.loads(HEADSHOT_MAP_PATH.read_text(encoding="utf-8"))
        leagues = payload.get("leagues") if isinstance(payload, dict) else None
        if not isinstance(leagues, dict):
            result["status"] = "invalid"
            return result
        counts = {
            str(sport): len(players)
            for sport, players in leagues.items()
            if isinstance(players, dict)
        }
        result.update(
            {
                "status": "ok" if sum(counts.values()) else "empty",
                "leagueCounts": counts,
                "playerCount": sum(counts.values()),
                "updatedAtUtc": payload.get("updatedAtUtc"),
            }
        )
    except (OSError, ValueError):
        result["status"] = "invalid"
    return result


def _fetch_team_ids(espn_sport: str, espn_league: str) -> list[str]:
    response = requests.get(
        f"https://site.api.espn.com/apis/site/v2/sports/{espn_sport}/{espn_league}/teams",
        params={"limit": 200},
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    leagues = response.json()["sports"][0]["leagues"]
    if not leagues:
        return []
    return [str(entry["team"]["id"]) for entry in leagues[0]["teams"]]


def _fetch_team_roster(espn_sport: str, espn_league: str, team_id: str) -> dict[str, str]:
    response = requests.get(
        f"https://site.api.espn.com/apis/site/v2/sports/{espn_sport}/{espn_league}"
        f"/teams/{team_id}/roster",
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    raw_athletes = response.json().get("athletes", [])

    entries: list[dict] = []
    for item in raw_athletes:
        if not isinstance(item, dict):
            continue
        if "items" in item:
            # Some leagues (e.g. NHL) group athletes by position.
            entries.extend(item["items"])
        else:
            entries.append(item)

    players: dict[str, str] = {}
    for athlete in entries:
        full_name = athlete.get("fullName")
        headshot = athlete.get("headshot")
        href = headshot.get("href") if isinstance(headshot, dict) else None
        if not full_name or not href:
            continue
        players[_normalize_name(str(full_name))] = href
    return players


def _fetch_athlete_headshot(
    espn_sport: str,
    espn_league: str,
    athlete_id: str,
) -> tuple[str, str] | None:
    response = requests.get(
        f"https://sports.core.api.espn.com/v2/sports/{espn_sport}"
        f"/leagues/{espn_league}/athletes/{athlete_id}",
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    athlete = response.json()
    full_name = athlete.get("fullName") or athlete.get("displayName")
    headshot = athlete.get("headshot")
    href = headshot.get("href") if isinstance(headshot, dict) else None
    if not full_name or not href:
        return None
    return _normalize_name(str(full_name)), str(href)


def _fetch_event_athletes(espn_sport: str, espn_league: str) -> dict[str, str]:
    response = requests.get(
        f"https://site.api.espn.com/apis/site/v2/sports/"
        f"{espn_sport}/{espn_league}/scoreboard",
        params={"limit": 100},
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    athlete_ids = {
        str(competitor["id"])
        for event in response.json().get("events", [])
        for competition in event.get("competitions", [])
        for competitor in competition.get("competitors", [])
        if competitor.get("id")
    }

    players: dict[str, str] = {}
    with ThreadPoolExecutor(max_workers=8) as executor:
        futures = {
            executor.submit(
                _fetch_athlete_headshot,
                espn_sport,
                espn_league,
                athlete_id,
            )
            for athlete_id in athlete_ids
        }
        for future in as_completed(futures):
            try:
                player = future.result()
            except requests.RequestException:
                continue
            if player:
                players[player[0]] = player[1]
    return players


def refresh_espn_headshot_map() -> dict[str, int]:
    """Fetches rosters for every configured league and rewrites the local
    cache. Intended to run from a scheduled sync script only - this makes
    many real network calls (teams + one roster call per team, per league)
    and should never execute on the request path.
    """
    leagues: dict[str, dict[str, str]] = {}
    counts: dict[str, int] = {}
    for sport_label, (espn_sport, espn_league) in LEAGUES.items():
        players: dict[str, str] = {}
        for team_id in _fetch_team_ids(espn_sport, espn_league):
            try:
                players.update(_fetch_team_roster(espn_sport, espn_league, team_id))
            except requests.RequestException:
                continue
        leagues[sport_label] = players
        counts[sport_label] = len(players)

    for sport_label, (espn_sport, espn_league) in EVENT_LEAGUES.items():
        try:
            players = _fetch_event_athletes(espn_sport, espn_league)
        except requests.RequestException:
            players = {}
        leagues[sport_label] = players
        counts[sport_label] = len(players)

    HEADSHOT_MAP_PATH.parent.mkdir(parents=True, exist_ok=True)
    HEADSHOT_MAP_PATH.write_text(
        json.dumps(
            {
                "updatedAtUtc": datetime.now(timezone.utc).isoformat(),
                "leagues": leagues,
            },
            indent=2,
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    _load_map.cache_clear()
    return counts
