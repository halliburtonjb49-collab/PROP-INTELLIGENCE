"""Basic PGA player roster groundwork via SportsData.io's Golf API.

Deliberately headshot-less for now: SportsData.io's licensed headshot data
(via IMAGN) requires their Client Management team to enable it on the
account first - it's not something a standard API key gets automatically
(their own Golf Data Workflow Guide directs you to contact them for that
introduction). This module just builds the name -> PlayerID map, so once
headshot access is confirmed, adding photos is a small follow-up (a URL
template keyed on the cached PlayerID) rather than starting from scratch.

Same request-time-safe pattern as the other headshot services: this only
ever runs from a scheduled sync job; nothing here executes per-request.
"""

import json
import re
import unicodedata
from datetime import datetime, timezone
from functools import lru_cache

import requests

from config import BASE_DIR, HTTP_TIMEOUT_SECONDS, SPORTSDATAIO_API_KEY

ROSTER_MAP_PATH = BASE_DIR / "data" / "sportsdataio_golf_roster.json"
_PLAYERS_URL = "https://api.sportsdata.io/golf/v2/json/Players"


def _normalize_name(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_only = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    cleaned = re.sub(r"[^a-z0-9]+", " ", ascii_only.lower()).strip()
    return " ".join(cleaned.split())


@lru_cache(maxsize=1)
def _load_map() -> dict[str, int]:
    if not ROSTER_MAP_PATH.exists():
        return {}
    try:
        payload = json.loads(ROSTER_MAP_PATH.read_text(encoding="utf-8"))
        players = payload.get("players") if isinstance(payload, dict) else None
        if isinstance(players, dict):
            return {str(name): int(pid) for name, pid in players.items()}
    except Exception:
        pass
    return {}


def golf_player_id(player_name: str) -> int | None:
    return _load_map().get(_normalize_name(player_name))


def refresh_golf_roster_map() -> int:
    """Fetches the active PGA player list and rewrites the local cache.

    Intended to run from a scheduled sync script only.
    """
    if not SPORTSDATAIO_API_KEY:
        raise RuntimeError("SPORTSDATAIO_API_KEY is not configured")

    response = requests.get(
        _PLAYERS_URL,
        headers={"Ocp-Apim-Subscription-Key": SPORTSDATAIO_API_KEY},
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    people = response.json()

    players: dict[str, int] = {}
    for person in people:
        full_name = person.get("Name")
        player_id = person.get("PlayerID")
        if not full_name or not isinstance(player_id, int):
            continue
        players[_normalize_name(str(full_name))] = player_id

    ROSTER_MAP_PATH.parent.mkdir(parents=True, exist_ok=True)
    ROSTER_MAP_PATH.write_text(
        json.dumps(
            {
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
