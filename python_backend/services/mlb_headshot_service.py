"""Resolves official MLB headshot URLs from the free, public MLB Stats API.

The name -> person-id mapping is refreshed by scripts/sync_mlb_headshots.py
(a scheduled job) and cached to disk. A bounded, process-cached official
search repairs individual misses so a stale map cannot leave cards blank.
"""

import json
import re
import time
import unicodedata
from datetime import datetime, timezone
from functools import lru_cache

import requests

from config import BASE_DIR, HTTP_TIMEOUT_SECONDS
from services.distributed_cache_service import (
    get_json as get_distributed_json,
    set_json as set_distributed_json,
)

HEADSHOT_MAP_PATH = BASE_DIR / "data" / "mlb_headshot_map.json"

_ROSTER_URL = "https://statsapi.mlb.com/api/v1/sports/1/players"
_PLAYER_SEARCH_URL = "https://statsapi.mlb.com/api/v1/people/search"
_HEADSHOT_URL_TEMPLATE = (
    "https://img.mlbstatic.com/mlb-photos/image/upload/"
    "w_240,d_people:generic:headshot:67:current.png,q_auto:best/"
    "v1/people/{mlb_id}/headshot/67/current"
)

_DISTRIBUTED_CACHE_KEY = "headshots:mlb:v1"
_DISTRIBUTED_CACHE_TTL_SECONDS = 8 * 24 * 60 * 60
_last_map_refresh_check = 0.0
_MAP_REFRESH_CHECK_SECONDS = 300
_LOOKUP_TIMEOUT_SECONDS = min(float(HTTP_TIMEOUT_SECONDS), 2.5)
_runtime_player_ids: dict[str, int] = {}

def _normalize_name(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_only = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    cleaned = re.sub(r"[^a-z0-9]+", " ", ascii_only.lower()).strip()
    return " ".join(cleaned.split())


@lru_cache(maxsize=1)
def _load_map() -> dict[str, int]:
    shared = get_distributed_json(_DISTRIBUTED_CACHE_KEY)
    players = shared.get("players") if isinstance(shared, dict) else None
    if isinstance(players, dict):
        return {str(name): int(mlb_id) for name, mlb_id in players.items()}

    if HEADSHOT_MAP_PATH.exists():
        try:
            payload = json.loads(HEADSHOT_MAP_PATH.read_text(encoding="utf-8"))
            players = payload.get("players") if isinstance(payload, dict) else None
            if isinstance(players, dict):
                return {str(name): int(mlb_id) for name, mlb_id in players.items()}
        except Exception:
            pass
    return {}


def _ensure_map_fresh() -> None:
    global _last_map_refresh_check
    now = time.monotonic()
    if now - _last_map_refresh_check >= _MAP_REFRESH_CHECK_SECONDS:
        _load_map.cache_clear()
        _last_map_refresh_check = now


def mlb_headshot_url(player_name: str) -> str | None:
    mlb_id = mlb_player_id(player_name)
    if mlb_id is None:
        return None
    return _HEADSHOT_URL_TEMPLATE.format(mlb_id=mlb_id)


def mlb_player_id(player_name: str) -> int | None:
    _ensure_map_fresh()
    normalized = _normalize_name(player_name)
    if not normalized:
        return None
    cached = _load_map().get(normalized) or _runtime_player_ids.get(normalized)
    if cached is not None:
        return cached
    resolved = _search_official_player_id(player_name, normalized)
    if resolved is not None:
        _runtime_player_ids[normalized] = resolved
    return resolved


@lru_cache(maxsize=512)
def _search_official_player_id(player_name: str, normalized: str) -> int | None:
    """Resolve a cache miss against MLB, once per player and process."""
    try:
        response = requests.get(
            _PLAYER_SEARCH_URL,
            params={"names": player_name, "sportIds": 1},
            timeout=_LOOKUP_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        people = response.json().get("people", [])
    except (requests.RequestException, ValueError, TypeError):
        return None

    exact_matches = [
        person
        for person in people
        if _normalize_name(str(person.get("fullName") or "")) == normalized
    ]
    candidates = exact_matches or people
    for person in candidates:
        person_id = person.get("id")
        if isinstance(person_id, int):
            return person_id
    return None


def refresh_mlb_headshot_map(season: int | None = None) -> int:
    """Fetches the full active MLB roster and rewrites the local cache.

    Intended to run from a scheduled sync script only - this makes a real
    network call and should never execute on the request path.
    """
    year = season or datetime.now(timezone.utc).year
    response = requests.get(
        _ROSTER_URL,
        params={"season": year},
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    people = response.json().get("people", [])

    players: dict[str, int] = {}
    for person in people:
        full_name = person.get("fullName")
        person_id = person.get("id")
        if not full_name or not isinstance(person_id, int):
            continue
        players[_normalize_name(str(full_name))] = person_id

    payload = {
        "season": year,
        "updatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "players": players,
    }
    set_distributed_json(
        _DISTRIBUTED_CACHE_KEY,
        payload,
        ttl_seconds=_DISTRIBUTED_CACHE_TTL_SECONDS,
    )
    HEADSHOT_MAP_PATH.parent.mkdir(parents=True, exist_ok=True)
    HEADSHOT_MAP_PATH.write_text(
        json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8"
    )
    _load_map.cache_clear()
    return len(players)
