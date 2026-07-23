"""Resolves official headshot URLs via ESPN's free, public site API.

Covers leagues that (a) are organized around team rosters and (b) actually
expose a headshot field in that roster response - confirmed for NBA, WNBA
and NHL. Soccer (EPL, MLS, and others tested) returns no headshot data at
all through this endpoint, so it's deliberately excluded here; it needs a
different source.

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

import requests

from config import BASE_DIR, HTTP_TIMEOUT_SECONDS

HEADSHOT_MAP_PATH = BASE_DIR / "data" / "espn_headshot_map.json"

# App sport label (services.formatters.format_sport_label output) ->
# (ESPN sport slug, ESPN league slug).
LEAGUES: dict[str, tuple[str, str]] = {
    "NBA": ("basketball", "nba"),
    "WNBA": ("basketball", "wnba"),
    "NHL": ("hockey", "nhl"),
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
