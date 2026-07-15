import json
from functools import lru_cache
from pathlib import Path
from typing import Any

BASE_DIR = Path(__file__).resolve().parent.parent
PLAYER_STATUS_PATH = BASE_DIR / "data" / "player_status_overrides.json"


@lru_cache(maxsize=1)
def _load_status_map() -> dict[str, Any]:
    if not PLAYER_STATUS_PATH.exists():
        return {"players": {}}
    try:
        payload = json.loads(PLAYER_STATUS_PATH.read_text(encoding="utf-8"))
        if isinstance(payload, dict):
            return payload
    except Exception:
        pass
    return {"players": {}}


def load_status_map() -> dict[str, Any]:
    payload = _load_status_map()
    players = payload.get("players")
    if not isinstance(players, dict):
        payload["players"] = {}
    return payload


def save_status_map(payload: dict[str, Any]) -> None:
    PLAYER_STATUS_PATH.parent.mkdir(parents=True, exist_ok=True)
    PLAYER_STATUS_PATH.write_text(
        json.dumps(payload, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    _load_status_map.cache_clear()


def upsert_player_availability(
    *,
    canonical_player_id: str,
    injury_status: str,
    lineup_status: str,
    notes: str = "",
) -> dict[str, str]:
    canonical = canonical_player_id.strip()
    if not canonical:
        raise ValueError("canonical_player_id is required")

    payload = load_status_map()
    players = payload.setdefault("players", {})
    entry = {
        "injury_status": injury_status.strip().lower() or "unknown",
        "lineup_status": lineup_status.strip().lower() or "unknown",
        "notes": notes.strip(),
    }
    players[canonical] = entry
    save_status_map(payload)
    return entry


def get_player_availability(*, canonical_player_id: str) -> tuple[str, str]:
    payload = _load_status_map()
    players = payload.get("players", {})
    entry = players.get(canonical_player_id, {}) if isinstance(players, dict) else {}
    injury_status = str(entry.get("injury_status") or "unknown").strip().lower()
    lineup_status = str(entry.get("lineup_status") or "unknown").strip().lower()
    return injury_status, lineup_status


def adjust_confidence_for_availability(
    *,
    base_confidence: int,
    injury_status: str,
    lineup_status: str,
) -> int:
    injury_penalties = {
        "out": 40,
        "inactive": 35,
        "doubtful": 24,
        "questionable": 14,
        "day_to_day": 8,
        "suspended": 40,
        "active": 0,
        "unknown": 0,
    }
    lineup_penalties = {
        "bench": 8,
        "minutes_restriction": 10,
        "call_up": 7,
        "two_way": 5,
        "starter": 0,
        "confirmed_starter": 0,
        "unknown": 0,
    }

    penalty = injury_penalties.get(injury_status, 0) + lineup_penalties.get(lineup_status, 0)
    adjusted = max(0, min(99, int(base_confidence) - penalty))
    return adjusted
