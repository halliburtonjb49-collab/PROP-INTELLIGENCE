import json
import sqlite3
from pathlib import Path
from typing import Any

from services.score_service import fetch_scores
from services.slip_service import initialize_slip_table

BASE_DIR = Path(__file__).resolve().parent.parent
DATABASE_PATH = BASE_DIR / "prop_intelligence_cache.db"

# Map display labels from saved legs back to odds-api sport keys.
SPORT_TO_KEY = {
    "MLB": "baseball_mlb",
    "WNBA": "basketball_wnba",
    "NBA": "basketball_nba",
    "NFL": "americanfootball_nfl",
}


def _connect() -> sqlite3.Connection:
    connection = sqlite3.connect(DATABASE_PATH)
    connection.row_factory = sqlite3.Row
    return connection


def _sport_key_from_leg(leg_sport: str) -> str | None:
    sport = (leg_sport or "").strip()
    if not sport:
        return None

    if "_" in sport:
        return sport.lower()

    return SPORT_TO_KEY.get(sport.upper())


def _derive_game_state(score_event: dict[str, Any]) -> tuple[str, bool]:
    completed = bool(score_event.get("completed"))
    if completed:
        return "completed", True

    scores = score_event.get("scores")
    if isinstance(scores, list) and len(scores) > 0:
        return "in_progress", False

    return "scheduled", False


def refresh_saved_slip_game_statuses(days_from: int = 1) -> dict[str, int | list[str]]:
    initialize_slip_table()

    with _connect() as connection:
        rows = connection.execute(
            """
            SELECT
                id,
                legs_json
            FROM slips
            """
        ).fetchall()

    slips_scanned = len(rows)
    legs_checked = 0
    legs_updated = 0
    slips_updated = 0

    sport_keys: set[str] = set()
    for row in rows:
        raw_legs = json.loads(row["legs_json"])
        for leg in raw_legs:
            event_id = str(leg.get("event_id", "")).strip()
            if not event_id:
                continue

            sport_key = _sport_key_from_leg(str(leg.get("sport", "")))
            if sport_key:
                sport_keys.add(sport_key)

    scores_by_sport_event: dict[str, dict[str, dict[str, Any]]] = {}
    for sport_key in sorted(sport_keys):
        payload = fetch_scores(sport_key, days_from=days_from)
        scores_by_sport_event[sport_key] = {
            str(item.get("id", "")): item for item in payload
        }

    with _connect() as connection:
        for row in rows:
            raw_legs = json.loads(row["legs_json"])
            row_changed = False

            for leg in raw_legs:
                event_id = str(leg.get("event_id", "")).strip()
                if not event_id:
                    continue

                sport_key = _sport_key_from_leg(str(leg.get("sport", "")))
                if not sport_key:
                    continue

                score_event = scores_by_sport_event.get(sport_key, {}).get(event_id)
                if not score_event:
                    continue

                legs_checked += 1
                game_status, game_completed = _derive_game_state(score_event)

                old_status = str(leg.get("game_status", "scheduled"))
                old_completed = bool(leg.get("game_completed", False))

                if old_status != game_status or old_completed != game_completed:
                    leg["game_status"] = game_status
                    leg["game_completed"] = game_completed
                    legs_updated += 1
                    row_changed = True

            if not row_changed:
                continue

            connection.execute(
                """
                UPDATE slips
                SET legs_json = ?
                WHERE id = ?
                """,
                (json.dumps(raw_legs), row["id"]),
            )
            slips_updated += 1

    return {
        "slips_scanned": slips_scanned,
        "slips_updated": slips_updated,
        "legs_checked": legs_checked,
        "legs_updated": legs_updated,
        "sports_requested": sorted(sport_keys),
    }
