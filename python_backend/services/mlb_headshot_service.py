"""Resolves official MLB headshot URLs from the free, public MLB Stats API.

The name -> person-id mapping is refreshed by scripts/sync_mlb_headshots.py
(a scheduled job) and cached to disk. Request-time lookups only ever read
that local cache - never call the MLB API inline, since get_props() runs
synchronously per request.
"""

import json
import re
import unicodedata
from datetime import datetime, timezone
from functools import lru_cache

import requests

from config import BASE_DIR, HTTP_TIMEOUT_SECONDS

HEADSHOT_MAP_PATH = BASE_DIR / "data" / "mlb_headshot_map.json"

_ROSTER_URL = "https://statsapi.mlb.com/api/v1/sports/1/players"
_HEADSHOT_URL_TEMPLATE = (
    "https://img.mlbstatic.com/mlb-photos/image/upload/"
    "w_240,d_people:generic:headshot:67:current.png,q_auto:best/"
    "v1/people/{mlb_id}/headshot/67/current"
)


def _normalize_name(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_only = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    cleaned = re.sub(r"[^a-z0-9]+", " ", ascii_only.lower()).strip()
    return " ".join(cleaned.split())


@lru_cache(maxsize=1)
def _load_map() -> dict[str, int]:
    if not HEADSHOT_MAP_PATH.exists():
        return {}
    try:
        payload = json.loads(HEADSHOT_MAP_PATH.read_text(encoding="utf-8"))
        players = payload.get("players") if isinstance(payload, dict) else None
        if isinstance(players, dict):
            return {str(name): int(mlb_id) for name, mlb_id in players.items()}
    except Exception:
        pass
    return {}


def mlb_headshot_url(player_name: str) -> str | None:
    mlb_id = _load_map().get(_normalize_name(player_name))
    if mlb_id is None:
        return None
    return _HEADSHOT_URL_TEMPLATE.format(mlb_id=mlb_id)


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

    HEADSHOT_MAP_PATH.parent.mkdir(parents=True, exist_ok=True)
    HEADSHOT_MAP_PATH.write_text(
        json.dumps(
            {
                "season": year,
                "updatedAtUtc": datetime.now(timezone.utc).isoformat(),
                "players": players,
            },
            indent=2,
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    _load_map.cache_clear()
    return len(players)
