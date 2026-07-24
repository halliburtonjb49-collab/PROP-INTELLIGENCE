"""Resolves soccer player headshot URLs via the Sportmonks football API.

Unlike SportsData.io (whose headshot product is licensed separately via
IMAGN and doesn't cover soccer at all), Sportmonks exposes `image_path`
directly on the standard Player entity - no special account provisioning
needed, just a valid API token.

Chain to build the cache (see refresh_sportmonks_headshot_map):
  1. GET /leagues (include=currentSeason;country) - find our target
     leagues by name + country, read off each one's current season id.
  2. GET /teams/seasons/{season_id} - team ids competing this season.
  3. GET /squads/teams/{team_id} (include=player) - each team's roster,
     with player name + image_path nested in the response.

Same request-time-safe pattern as the other headshot services: this only
ever runs from a scheduled sync job; get_props() just reads the cache.
"""

import json
import re
import unicodedata
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path

import requests

from config import (
    HTTP_TIMEOUT_SECONDS,
    SPORTMONKS_API_KEY,
    SPORTMONKS_HEADSHOT_MAP_PATH,
)

HEADSHOT_MAP_PATH = SPORTMONKS_HEADSHOT_MAP_PATH
_BASE_URL = "https://api.sportmonks.com/v3/football"

# (league name substring, country name) matched case-insensitively against
# Sportmonks' /leagues response. Keyed to the app's own PROP_SYNC_SPORTS
# soccer coverage.
_TARGET_LEAGUES: dict[str, tuple[str, str]] = {
    "soccer_epl": ("premier league", "england"),
    "soccer_usa_mls": ("major league soccer", "united states"),
    "soccer_france_ligue_one": ("ligue 1", "france"),
    "soccer_germany_bundesliga": ("bundesliga", "germany"),
    "soccer_italy_serie_a": ("serie a", "italy"),
    "soccer_spain_la_liga": ("la liga", "spain"),
}


def _normalize_name(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_only = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    cleaned = re.sub(r"[^a-z0-9]+", " ", ascii_only.lower()).strip()
    return " ".join(cleaned.split())


@lru_cache(maxsize=1)
def _load_map() -> dict[str, str]:
    if not HEADSHOT_MAP_PATH.exists():
        return {}
    try:
        payload = json.loads(HEADSHOT_MAP_PATH.read_text(encoding="utf-8"))
        players = payload.get("players") if isinstance(payload, dict) else None
        if isinstance(players, dict):
            return {str(name): str(url) for name, url in players.items()}
    except Exception:
        pass
    return {}


def sportmonks_headshot_url(player_name: str) -> str | None:
    return _load_map().get(_normalize_name(player_name))


def sportmonks_headshot_cache_health() -> dict[str, object]:
    """Reports whether the request-time soccer headshot cache is usable."""
    persistent = HEADSHOT_MAP_PATH.parent == Path("/var/data")
    result: dict[str, object] = {
        "status": "missing",
        "mode": "persistent-disk" if persistent else "local-development",
        "playerCount": 0,
        "updatedAtUtc": None,
    }
    if not HEADSHOT_MAP_PATH.exists():
        return result
    try:
        payload = json.loads(HEADSHOT_MAP_PATH.read_text(encoding="utf-8"))
        players = payload.get("players") if isinstance(payload, dict) else None
        if not isinstance(players, dict):
            result["status"] = "invalid"
            return result
        result.update(
            {
                "status": "ok" if players else "empty",
                "playerCount": len(players),
                "updatedAtUtc": payload.get("updatedAtUtc"),
            }
        )
    except (OSError, ValueError):
        result["status"] = "invalid"
    return result


def _get(path: str, **params: object) -> dict:
    # Sportmonks expects the raw API token as the Authorization header value
    # (not the OAuth-style "Bearer <token>" form). Keep it out of the query
    # string so it cannot end up in request URLs or access logs.
    response = requests.get(
        f"{_BASE_URL}{path}",
        params=params,
        headers={"Authorization": SPORTMONKS_API_KEY},
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    if not response.ok:
        # Sportmonks returns a JSON body explaining *why* (e.g. "plan does
        # not include this endpoint" vs "invalid token") - surface that
        # instead of just the generic HTTP status line, since that's the
        # only thing that'll actually tell us what's wrong. The token
        # itself never appears in the URL or body, so this is safe to log.
        try:
            detail = response.json().get("message")
        except ValueError:
            detail = response.text[:300]
        raise RuntimeError(
            f"Sportmonks API error {response.status_code} on {path}: {detail}"
        )
    return response.json()


def _get_all(path: str, **params: object) -> list[dict]:
    """Collect every page from a Sportmonks collection endpoint."""
    page = 1
    rows: list[dict] = []
    while True:
        payload = _get(path, **params, page=page, per_page=50)
        rows.extend(
            entry for entry in payload.get("data", []) if isinstance(entry, dict)
        )
        pagination = payload.get("pagination") or {}
        if not pagination.get("has_more"):
            return rows
        page += 1


def _find_target_season_ids() -> dict[str, int]:
    season_ids: dict[str, int] = {}
    for league in _get_all("/leagues", include="currentSeason;country"):
        name = str(league.get("name") or "").lower()
        country = str((league.get("country") or {}).get("name") or "").lower()
        # Sportmonks names the include `currentSeason` in request parameters
        # but serializes the relation as lowercase `currentseason`.
        season = (
            league.get("currentseason")
            or league.get("currentSeason")
            or {}
        )
        season_id = season.get("id")
        if not isinstance(season_id, int):
            continue
        for league_key, (name_substr, country_name) in _TARGET_LEAGUES.items():
            if name_substr in name and country_name in country:
                season_ids[league_key] = season_id
    return season_ids


def _fetch_team_ids(season_id: int) -> list[int]:
    return [
        team["id"]
        for team in _get_all(f"/teams/seasons/{season_id}")
        if isinstance(team.get("id"), int)
    ]


def _fetch_team_squad_photos(team_id: int) -> dict[str, str]:
    players: dict[str, str] = {}
    for entry in _get_all(f"/squads/teams/{team_id}", include="player"):
        player = entry.get("player") or {}
        full_name = player.get("name") or player.get("display_name")
        image_path = player.get("image_path")
        if not full_name or not image_path:
            continue
        players[_normalize_name(str(full_name))] = str(image_path)
    return players


def refresh_sportmonks_headshot_map() -> dict[str, int]:
    """Fetches rosters for every configured soccer league and rewrites the
    local cache. Intended to run from a scheduled sync script only - this
    makes many real network calls and should never execute on the request
    path.
    """
    if not SPORTMONKS_API_KEY:
        raise RuntimeError("SPORTMONKS_API_KEY is not configured")

    season_ids = _find_target_season_ids()
    if not season_ids:
        raise RuntimeError(
            "Sportmonks returned no configured leagues. Confirm the token's "
            "subscription includes at least one supported league."
        )
    all_players: dict[str, str] = {}
    counts: dict[str, int] = {}
    for league_key, season_id in season_ids.items():
        league_players: dict[str, str] = {}
        for team_id in _fetch_team_ids(season_id):
            try:
                league_players.update(_fetch_team_squad_photos(team_id))
            except requests.RequestException:
                continue
        all_players.update(league_players)
        counts[league_key] = len(league_players)

    for league_key in _TARGET_LEAGUES:
        counts.setdefault(league_key, 0)

    if not all_players:
        raise RuntimeError(
            "Sportmonks found configured leagues but returned no player "
            "headshots; the existing cache was not overwritten."
        )

    HEADSHOT_MAP_PATH.parent.mkdir(parents=True, exist_ok=True)
    HEADSHOT_MAP_PATH.write_text(
        json.dumps(
            {
                "updatedAtUtc": datetime.now(timezone.utc).isoformat(),
                "leagueCounts": counts,
                "players": all_players,
            },
            indent=2,
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    _load_map.cache_clear()
    return counts
