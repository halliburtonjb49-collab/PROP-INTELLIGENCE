"""Resolves athlete headshot URLs via ESPN's public site APIs.

Covers roster-based football, basketball, and hockey leagues plus athlete-
detail fallbacks for leagues whose roster responses omit embedded headshots.

ESPN's own stats sites for some leagues block traffic from cloud/datacenter
IPs (e.g. stats.nba.com resets connections outright), which is why this
goes through ESPN's site API instead - it's been reliable from a hosted
Render environment.

Same request-time-safe pattern as mlb_headshot_service.py: a scheduled sync
job populates a local cache; get_props() and friends only ever read it.
"""

import json
import time
import re
import unicodedata
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests

from config import ESPN_HEADSHOT_MAP_PATH, HTTP_TIMEOUT_SECONDS
from services.distributed_cache_service import (
    get_json as get_distributed_json,
    set_json as set_distributed_json,
)

HEADSHOT_MAP_PATH = ESPN_HEADSHOT_MAP_PATH
_BUNDLED_MAP_PATH = Path(__file__).resolve().parents[1] / "data" / "espn_headshot_map.json"
_DISTRIBUTED_CACHE_KEY = "headshots:espn:v1"
_DISTRIBUTED_CACHE_TTL_SECONDS = 8 * 24 * 60 * 60
_HEADSHOT_STALE_HOURS = 26
_last_map_refresh_check = 0.0
_MAP_REFRESH_CHECK_SECONDS = 300

# App sport label (services.formatters.format_sport_label output) ->
# (ESPN sport slug, ESPN league slug).
LEAGUES: dict[str, tuple[str, str]] = {
    "NFL": ("football", "nfl"),
    "NCAAF": ("football", "college-football"),
    "NBA": ("basketball", "nba"),
    "WNBA": ("basketball", "wnba"),
    "NCAAB": ("basketball", "mens-college-basketball"),
    "NHL": ("hockey", "nhl"),
}

# Individual sports expose athletes through current-event scoreboards rather
# than team rosters.
EVENT_LEAGUES: dict[str, tuple[str, str]] = {}

# Team rosters expose athlete ids but require one core-athlete request to
# retrieve each available headshot.
DETAIL_ROSTER_LEAGUES: dict[str, tuple[str, str]] = {
    "SOCCER": ("soccer", "usa.1"),
    "CFL": ("football", "cfl"),
}


def _normalize_name(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_only = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    cleaned = re.sub(r"[^a-z0-9]+", " ", ascii_only.lower()).strip()
    return " ".join(cleaned.split())


@lru_cache(maxsize=1)
def _load_map() -> dict[str, dict[str, str]]:
    # Merge every available layer instead of letting an older Redis payload
    # hide leagues newly added to the bundled cache (NFL was the first case).
    # Later layers win per player: bundled -> local/persistent -> Redis.
    merged: dict[str, dict[str, str]] = {}
    payloads: list[object] = []
    for path in dict.fromkeys((_BUNDLED_MAP_PATH, HEADSHOT_MAP_PATH)):
        if not path.exists():
            continue
        try:
            payloads.append(json.loads(path.read_text(encoding="utf-8")))
        except (OSError, ValueError):
            continue
    payloads.append(get_distributed_json(_DISTRIBUTED_CACHE_KEY))
    for payload in payloads:
        leagues = payload.get("leagues") if isinstance(payload, dict) else None
        if not isinstance(leagues, dict):
            continue
        for sport, players in leagues.items():
            if not isinstance(players, dict):
                continue
            target = merged.setdefault(str(sport), {})
            target.update({str(name): str(url) for name, url in players.items()})
    return merged


def _load_payload() -> tuple[dict[str, object] | None, str]:
    shared = get_distributed_json(_DISTRIBUTED_CACHE_KEY)
    if isinstance(shared, dict):
        return shared, "redis"
    if HEADSHOT_MAP_PATH.exists():
        try:
            payload = json.loads(HEADSHOT_MAP_PATH.read_text(encoding="utf-8"))
            if isinstance(payload, dict):
                return payload, (
                    "persistent-disk"
                    if HEADSHOT_MAP_PATH.parent == Path("/var/data")
                    else "local-file"
                )
        except (OSError, ValueError):
            return None, "invalid"
    if _BUNDLED_MAP_PATH != HEADSHOT_MAP_PATH and _BUNDLED_MAP_PATH.exists():
        try:
            payload = json.loads(_BUNDLED_MAP_PATH.read_text(encoding="utf-8"))
            if isinstance(payload, dict):
                return payload, "bundled-file"
        except (OSError, ValueError):
            return None, "invalid"
    return None, (
        "persistent-disk"
        if HEADSHOT_MAP_PATH.parent == Path("/var/data")
        else "local-file"
    )


def _ensure_map_fresh() -> None:
    global _last_map_refresh_check
    now = time.monotonic()
    if now - _last_map_refresh_check >= _MAP_REFRESH_CHECK_SECONDS:
        _load_map.cache_clear()
        _last_map_refresh_check = now


def espn_headshot_url(player_name: str, sport: str) -> str | None:
    _ensure_map_fresh()
    players = _load_map().get(sport)
    if not players:
        return None
    return players.get(_normalize_name(player_name))


def espn_player_id(player_name: str, sport: str) -> str | None:
    url = espn_headshot_url(player_name, sport)
    if not url:
        return None
    match = re.search(r"/(?:full|athletes)/(\d+)(?:\.png)?", url)
    return match.group(1) if match else None


def espn_headshot_cache_health(
    now: datetime | None = None,
) -> dict[str, object]:
    payload, source = _load_payload()
    result: dict[str, object] = {
        "status": "missing",
        "mode": source,
        "leagueCounts": {},
        "playerCount": 0,
        "updatedAtUtc": None,
        "ageHours": None,
        "stale": True,
        "staleAfterHours": _HEADSHOT_STALE_HOURS,
    }
    if payload is None:
        return result
    try:
        leagues = payload.get("leagues") if isinstance(payload, dict) else None
        if not isinstance(leagues, dict):
            result["status"] = "invalid"
            return result
        counts = {
            str(sport): len(players)
            for sport, players in leagues.items()
            if isinstance(players, dict)
        }
        updated_at = payload.get("updatedAtUtc")
        age_hours: float | None = None
        if updated_at:
            try:
                parsed = datetime.fromisoformat(
                    str(updated_at).replace("Z", "+00:00")
                )
                if parsed.tzinfo is None:
                    parsed = parsed.replace(tzinfo=timezone.utc)
                current = now or datetime.now(timezone.utc)
                if current.tzinfo is None:
                    current = current.replace(tzinfo=timezone.utc)
                age_hours = max(
                    0.0,
                    (current.astimezone(timezone.utc) - parsed).total_seconds()
                    / 3600,
                )
            except ValueError:
                age_hours = None
        result.update(
            {
                "status": "ok" if sum(counts.values()) else "empty",
                "leagueCounts": counts,
                "playerCount": sum(counts.values()),
                "updatedAtUtc": updated_at,
                "ageHours": round(age_hours, 1) if age_hours is not None else None,
                "stale": age_hours is None or age_hours > _HEADSHOT_STALE_HOURS,
            }
        )
    except (OSError, ValueError):
        result["status"] = "invalid"
    return result


def _fetch_team_ids(espn_sport: str, espn_league: str) -> list[str]:
    response = requests.get(
        f"https://site.api.espn.com/apis/site/v2/sports/{espn_sport}/{espn_league}/teams",
        params={"limit": 500},
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


def _fetch_league_roster_headshots(
    espn_sport: str,
    espn_league: str,
) -> dict[str, str]:
    """Fetch a league's team rosters concurrently without failing the refresh."""
    players: dict[str, str] = {}
    team_ids = _fetch_team_ids(espn_sport, espn_league)
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = {
            executor.submit(
                _fetch_team_roster,
                espn_sport,
                espn_league,
                team_id,
            )
            for team_id in team_ids
        }
        for future in as_completed(futures):
            try:
                players.update(future.result())
            except requests.RequestException:
                continue
    return players


def _fetch_roster_athlete_ids(
    espn_sport: str,
    espn_league: str,
    team_id: str,
) -> set[str]:
    response = requests.get(
        f"https://site.api.espn.com/apis/site/v2/sports/{espn_sport}/{espn_league}"
        f"/teams/{team_id}/roster",
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    athlete_ids: set[str] = set()
    for item in response.json().get("athletes", []):
        if not isinstance(item, dict):
            continue
        entries = item.get("items", []) if "items" in item else [item]
        for athlete in entries:
            if isinstance(athlete, dict) and athlete.get("id"):
                athlete_ids.add(str(athlete["id"]))
    return athlete_ids


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


def _hydrate_athlete_headshots(
    espn_sport: str,
    espn_league: str,
    athlete_ids: set[str],
) -> dict[str, str]:
    players: dict[str, str] = {}
    with ThreadPoolExecutor(max_workers=10) as executor:
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


def _fetch_detail_roster_athletes(
    espn_sport: str,
    espn_league: str,
) -> dict[str, str]:
    athlete_ids: set[str] = set()
    for team_id in _fetch_team_ids(espn_sport, espn_league):
        try:
            athlete_ids.update(
                _fetch_roster_athlete_ids(espn_sport, espn_league, team_id)
            )
        except requests.RequestException:
            continue
    return _hydrate_athlete_headshots(espn_sport, espn_league, athlete_ids)


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

    return _hydrate_athlete_headshots(espn_sport, espn_league, athlete_ids)


def refresh_espn_headshot_map() -> dict[str, int]:
    """Fetches rosters for every configured league and rewrites the local
    cache. Intended to run from a scheduled sync script only - this makes
    many real network calls (teams + one roster call per team, per league)
    and should never execute on the request path.
    """
    # Retain the last known-good league when one upstream roster call fails.
    # A partial ESPN outage must not erase photos for an entire sport.
    leagues: dict[str, dict[str, str]] = {
        sport: dict(players) for sport, players in _load_map().items()
    }
    counts: dict[str, int] = {}
    for sport_label, (espn_sport, espn_league) in LEAGUES.items():
        players = _fetch_league_roster_headshots(
            espn_sport, espn_league
        )
        if players:
            # A partial roster refresh must not erase previously working
            # portraits from teams whose ESPN request failed.
            merged_players = dict(leagues.get(sport_label, {}))
            merged_players.update(players)
            leagues[sport_label] = merged_players
        counts[sport_label] = len(leagues.get(sport_label, {}))

    for sport_label, (espn_sport, espn_league) in EVENT_LEAGUES.items():
        try:
            players = _fetch_event_athletes(espn_sport, espn_league)
        except requests.RequestException:
            players = {}
        if players:
            merged_players = dict(leagues.get(sport_label, {}))
            merged_players.update(players)
            leagues[sport_label] = merged_players
        counts[sport_label] = len(leagues.get(sport_label, {}))

    for sport_label, (espn_sport, espn_league) in DETAIL_ROSTER_LEAGUES.items():
        try:
            players = _fetch_detail_roster_athletes(espn_sport, espn_league)
        except requests.RequestException:
            players = {}
        if players:
            merged_players = dict(leagues.get(sport_label, {}))
            merged_players.update(players)
            leagues[sport_label] = merged_players
        counts[sport_label] = len(leagues.get(sport_label, {}))

    payload = {
        "updatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "leagues": leagues,
    }
    set_distributed_json(
        _DISTRIBUTED_CACHE_KEY,
        payload,
        ttl_seconds=_DISTRIBUTED_CACHE_TTL_SECONDS,
    )
    HEADSHOT_MAP_PATH.parent.mkdir(parents=True, exist_ok=True)
    HEADSHOT_MAP_PATH.write_text(
        json.dumps(payload, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    _load_map.cache_clear()
    return counts
