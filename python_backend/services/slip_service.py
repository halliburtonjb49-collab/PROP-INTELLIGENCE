import json
import os
import sqlite3
from collections.abc import Callable
from pathlib import Path
from typing import Any
from datetime import datetime, timedelta, timezone

from calculations.slip_grader import (
    grade_leg,
    grade_slip_status,
)
from models.slip import (
    ClosingLineUpdate, LegResultUpdate,
    SlipCreate,
    SlipLeg,
    SlipResponse,
    create_slip_response,
)
from models.intelligence import ClosingLineValueRequest
from services.clv_service import closing_line_value
from services.market_normalizer import normalize_market
from services.team_normalizer import normalize_team_name

BASE_DIR = Path(__file__).resolve().parent.parent
DATABASE_PATH = Path(
    os.getenv("SLIP_DATABASE_PATH", str(BASE_DIR / "prop_intelligence_cache.db"))
).expanduser().resolve()


def _connect() -> sqlite3.Connection:
    DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(DATABASE_PATH)
    connection.row_factory = sqlite3.Row
    return connection


def slip_storage_health() -> dict[str, object]:
    """Validate that ticket storage is writable and report persistence mode."""
    configured = os.getenv("SLIP_DATABASE_PATH", "").strip()
    try:
        initialize_slip_table()
        with _connect() as connection:
            connection.execute("SELECT 1").fetchone()
        return {
            "status": "ok",
            "path": str(DATABASE_PATH),
            "persistentPathConfigured": bool(configured),
            "mode": "persistent-disk" if configured else "local-development",
        }
    except (OSError, sqlite3.Error) as error:
        return {
            "status": "error", "path": str(DATABASE_PATH),
            "persistentPathConfigured": bool(configured), "error": str(error),
        }


def initialize_slip_table() -> None:
    with _connect() as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS slips (
                id TEXT PRIMARY KEY,
                user_id TEXT,
                status TEXT NOT NULL,
                stake REAL NOT NULL,
                potential_payout REAL NOT NULL,
                created_at TEXT NOT NULL,
                legs_json TEXT NOT NULL
            )
            """
        )
        columns = {row[1] for row in connection.execute("PRAGMA table_info(slips)").fetchall()}
        if "user_id" not in columns:
            connection.execute("ALTER TABLE slips ADD COLUMN user_id TEXT")
        connection.execute("CREATE INDEX IF NOT EXISTS slips_user_status_idx ON slips(user_id, status, created_at DESC)")


def _american_decimal_multiplier(odds: float | None) -> float:
    if odds is None:
        return 1.0

    if odds > 0:
        return 1 + (odds / 100)

    if odds < 0:
        return 1 + (100 / abs(odds))

    return 1.0


def _calculate_payout(request: SlipCreate) -> float:
    if request.stake <= 0:
        return 0

    combined_multiplier = 1.0
    for leg in request.legs:
        combined_multiplier *= _american_decimal_multiplier(
            leg.odds
        )

    return round(
        request.stake * combined_multiplier,
        2,
    )


def calculate_payout_preview(
    request: SlipCreate,
) -> float:
    return _calculate_payout(request)


def create_slip(request: SlipCreate, user_id: str | None = None) -> SlipResponse:
    initialize_slip_table()
    payout = _calculate_payout(request)
    slip = create_slip_response(request, payout)

    with _connect() as connection:
        connection.execute(
            """
            INSERT INTO slips (
                id,
                user_id,
                status,
                stake,
                potential_payout,
                created_at,
                legs_json
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                slip.id,
                user_id,
                slip.status,
                slip.stake,
                slip.potential_payout,
                slip.created_at,
                json.dumps(
                    [leg.model_dump() for leg in slip.legs]
                ),
            ),
        )

    return slip


def get_slips(status: str | None = None, user_id: str | None = None) -> list[SlipResponse]:
    initialize_slip_table()
    query = """
        SELECT
            id,
            status,
            stake,
            potential_payout,
            created_at,
            legs_json
        FROM slips
    """
    parameters: tuple[object, ...] = ()

    filters = []
    parameter_list: list[object] = []
    if user_id is not None:
        filters.append("user_id = ?")
        parameter_list.append(user_id)
    if status:
        filters.append("status = ?")
        parameter_list.append(status)
    if filters:
        query += " WHERE " + " AND ".join(filters)
    parameters = tuple(parameter_list)

    query += " ORDER BY created_at DESC"

    with _connect() as connection:
        rows = connection.execute(
            query,
            parameters,
        ).fetchall()

    slips: list[SlipResponse] = []
    for row in rows:
        raw_legs = json.loads(row["legs_json"])
        slips.append(
            SlipResponse(
                id=row["id"],
                status=row["status"],
                stake=float(row["stake"]),
                potential_payout=float(
                    row["potential_payout"]
                ),
                created_at=row["created_at"],
                legs=[
                    SlipLeg.model_validate(leg)
                    for leg in raw_legs
                ],
            )
        )

    return slips


def update_slip_status(
    slip_id: str,
    status: str,
    user_id: str | None = None,
) -> bool:
    if status not in {"active", "won", "lost"}:
        raise ValueError("Invalid slip status.")

    initialize_slip_table()
    with _connect() as connection:
        cursor = connection.execute(
            """
            UPDATE slips
            SET status = ?
            WHERE id = ? AND (? IS NULL OR user_id = ?)
            """,
            (status, slip_id, user_id, user_id),
        )
        return cursor.rowcount > 0


def delete_slip(slip_id: str, user_id: str) -> bool:
    """Unlocks (removes) a saved slip, scoped to its owner."""
    initialize_slip_table()
    with _connect() as connection:
        cursor = connection.execute(
            "DELETE FROM slips WHERE id = ? AND user_id = ?",
            (slip_id, user_id),
        )
        return cursor.rowcount > 0


def update_slip_closing_lines(
    slip_id: str,
    updates: list[ClosingLineUpdate],
    user_id: str,
) -> dict[str, object] | None:
    """Attach closing prices and calculated CLV to a user's saved slip."""
    initialize_slip_table()
    update_map = {update.prop_id: update for update in updates}
    with _connect() as connection:
        row = connection.execute(
            "SELECT legs_json FROM slips WHERE id = ? AND user_id = ?",
            (slip_id, user_id),
        ).fetchone()
        if row is None:
            return None
        legs = json.loads(row["legs_json"])
        updated = 0
        for leg in legs:
            update = update_map.get(str(leg.get("prop_id", "")))
            if update is None:
                continue
            entry_line = float(leg.get("entry_line") or leg.get("line") or 0)
            if entry_line <= 0:
                continue
            entry_odds_raw = leg.get("odds")
            entry_odds = int(entry_odds_raw) if entry_odds_raw is not None else None
            clv = closing_line_value(ClosingLineValueRequest(
                side=str(leg.get("side", "OVER")).upper(),
                entry_line=entry_line,
                closing_line=update.closing_line,
                entry_odds=entry_odds,
                closing_odds=update.closing_odds,
            ))
            leg.update({
                "entry_line": entry_line,
                "closing_line": update.closing_line,
                "closing_odds": update.closing_odds,
                "line_clv": clv["lineClv"],
                "line_clv_percent": clv["lineClvPercent"],
                "beat_closing_line": clv["beatClosingLine"],
            })
            updated += 1
        if updated:
            connection.execute(
                "UPDATE slips SET legs_json = ? WHERE id = ? AND user_id = ?",
                (json.dumps(legs), slip_id, user_id),
            )
        measured = [leg for leg in legs if leg.get("beat_closing_line") is not None]
        positive = sum(1 for leg in measured if leg.get("beat_closing_line") is True)
        return {
            "slipId": slip_id,
            "updatedLegs": updated,
            "measuredLegs": len(measured),
            "beatCloseCount": positive,
            "beatCloseRate": round(positive / len(measured) * 100, 1) if measured else 0,
        }


def _normalized_match_value(value: object) -> str:
    return "".join(character for character in str(value or "").lower() if character.isalnum())


def capture_closing_lines_from_props(
    props: list[object], *, now: datetime | None = None,
    minutes_before: int = 15, minutes_after: int = 5,
) -> dict[str, int]:
    """Capture exact-match closing prices for active legs near event start."""
    initialize_slip_table()
    current = now or datetime.now(timezone.utc)
    if current.tzinfo is None:
        current = current.replace(tzinfo=timezone.utc)
    candidates: dict[tuple[str, str, str, str], object] = {}
    for prop in props:
        start_raw = getattr(prop, "startTimeUtc", "") or getattr(prop, "gameStartTime", "")
        try:
            starts_at = datetime.fromisoformat(str(start_raw).replace("Z", "+00:00"))
        except ValueError:
            continue
        if starts_at.tzinfo is None:
            starts_at = starts_at.replace(tzinfo=timezone.utc)
        window_start = current - timedelta(minutes=minutes_after)
        window_end = current + timedelta(minutes=minutes_before)
        if not window_start <= starts_at <= window_end:
            continue
        key = (
            _normalized_match_value(getattr(prop, "eventId", "")),
            _normalized_match_value(getattr(prop, "player", "")),
            _normalized_match_value(getattr(prop, "marketKey", "") or getattr(prop, "market", "")),
            _normalized_match_value(getattr(prop, "sportsbook", "")),
        )
        if all(key):
            candidates[key] = prop

    scanned = matched = updated_slips = 0
    with _connect() as connection:
        rows = connection.execute(
            "SELECT id, legs_json FROM slips WHERE status = 'active'"
        ).fetchall()
        for row in rows:
            legs = json.loads(row["legs_json"])
            changed = False
            for leg in legs:
                scanned += 1
                if leg.get("closing_line") is not None:
                    continue
                key = (
                    _normalized_match_value(leg.get("event_id")),
                    _normalized_match_value(leg.get("player")),
                    _normalized_match_value(leg.get("market")),
                    _normalized_match_value(leg.get("sportsbook")),
                )
                prop = candidates.get(key)
                if prop is None:
                    continue
                entry_line = float(leg.get("entry_line") or leg.get("line") or 0)
                close_line = float(getattr(prop, "currentLine", None) or getattr(prop, "line", 0))
                if entry_line <= 0 or close_line <= 0:
                    continue
                side = str(leg.get("side", "OVER")).upper()
                close_odds_raw = getattr(prop, "underOdds" if side == "UNDER" else "overOdds", None)
                close_odds = int(close_odds_raw) if close_odds_raw is not None else None
                entry_odds_raw = leg.get("odds")
                entry_odds = int(entry_odds_raw) if entry_odds_raw is not None else None
                clv = closing_line_value(ClosingLineValueRequest(
                    side=side, entry_line=entry_line, closing_line=close_line,
                    entry_odds=entry_odds, closing_odds=close_odds,
                ))
                leg.update({
                    "entry_line": entry_line, "closing_line": close_line,
                    "closing_odds": close_odds, "line_clv": clv["lineClv"],
                    "line_clv_percent": clv["lineClvPercent"],
                    "beat_closing_line": clv["beatClosingLine"],
                    "closing_captured_at": current.isoformat(),
                })
                matched += 1
                changed = True
            if changed:
                connection.execute(
                    "UPDATE slips SET legs_json = ? WHERE id = ?",
                    (json.dumps(legs), row["id"]),
                )
                updated_slips += 1
    return {"scannedLegs": scanned, "matchedLegs": matched, "updatedSlips": updated_slips}


def update_slip_results(
    updates: list[LegResultUpdate],
    user_id: str | None = None,
) -> int:
    initialize_slip_table()
    result_map = {
        update.prop_id: update.result_value
        for update in updates
    }
    changed_slips = 0

    with _connect() as connection:
        rows = connection.execute(
            """
            SELECT
                id,
                legs_json
            FROM slips
            WHERE status = 'active' AND (? IS NULL OR user_id = ?)
            """,
            (user_id, user_id),
        ).fetchall()

        for row in rows:
            raw_legs = json.loads(row["legs_json"])
            changed = False
            leg_statuses: list[str] = []

            for leg in raw_legs:
                prop_id = str(leg.get("prop_id", ""))
                if prop_id in result_map:
                    result_value = result_map[prop_id]
                    leg["result_value"] = result_value
                    leg["game_completed"] = True
                    leg["game_status"] = "completed"
                    leg["result_status"] = grade_leg(
                        side=str(leg.get("side", "")),
                        line=float(leg.get("line", 0)),
                        result_value=result_value,
                    )
                    changed = True

                leg_statuses.append(
                    str(
                        leg.get(
                            "result_status",
                            "pending",
                        )
                    )
                )

            if not changed:
                continue

            slip_status = grade_slip_status(
                leg_statuses
            )
            connection.execute(
                """
                UPDATE slips
                SET
                    status = ?,
                    legs_json = ?
                WHERE id = ?
                """,
                (
                    slip_status,
                    json.dumps(raw_legs),
                    row["id"],
                ),
            )
            changed_slips += 1

    return changed_slips


def update_slip_game_statuses(
    scores: list[dict[str, object]],
) -> int:
    initialize_slip_table()
    score_map = {
        str(score.get("id", "")): score
        for score in scores
        if score.get("id")
    }
    updated_slips = 0

    with _connect() as connection:
        rows = connection.execute(
            """
            SELECT id, legs_json
            FROM slips
            WHERE status = 'active'
            """
        ).fetchall()

        for row in rows:
            raw_legs = json.loads(row["legs_json"])
            changed = False

            for leg in raw_legs:
                event_id = str(
                    leg.get("event_id", "")
                )
                score = score_map.get(event_id)
                if not score:
                    continue

                completed = bool(
                    score.get("completed", False)
                )
                if completed:
                    game_status = "completed"
                elif score.get("scores"):
                    game_status = "live"
                else:
                    game_status = "scheduled"

                if (
                    leg.get("game_status")
                    != game_status
                    or leg.get("game_completed")
                    != completed
                ):
                    leg["game_status"] = game_status
                    leg["game_completed"] = completed
                    changed = True

            if changed:
                connection.execute(
                    """
                    UPDATE slips
                    SET legs_json = ?
                    WHERE id = ?
                    """,
                    (
                        json.dumps(raw_legs),
                        row["id"],
                    ),
                )
                updated_slips += 1

    return updated_slips


def update_slip_with_stat_results(
    *,
    event_id: str,
    stat_results: dict[str, dict[tuple[str, str], Any]],
    grade_leg_fn: Callable[..., str],
    grade_slip_fn: Callable[[list[str]], str],
) -> int:
    initialize_slip_table()
    updated_slips = 0
    results_by_id = stat_results.get("by_id", {})
    results_by_name = stat_results.get("by_name", {})

    with _connect() as connection:
        rows = connection.execute(
            """
            SELECT id, legs_json
            FROM slips
            WHERE status = 'active'
            """
        ).fetchall()

        for row in rows:
            legs = json.loads(row["legs_json"])
            changed = False

            for leg in legs:
                if str(leg.get("event_id", "")) != event_id:
                    continue

                result = None
                player_id = str(leg.get("player_id", ""))
                market = normalize_market(
                    str(leg.get("market", ""))
                )

                if player_id:
                    result = results_by_id.get(
                        (player_id, market)
                    )

                if result is None:
                    result = results_by_name.get(
                        (
                            normalize_team_name(
                                str(leg.get("player", ""))
                            ),
                            market,
                        )
                    )

                if result is None:
                    continue

                leg["result_value"] = result.value
                leg["game_completed"] = result.game_completed
                leg["game_status"] = (
                    "completed"
                    if result.game_completed
                    else "live"
                )
                leg["result_status"] = grade_leg_fn(
                    side=str(leg.get("side", "")),
                    line=float(leg.get("line", 0)),
                    result_value=float(result.value),
                )
                changed = True

            if not changed:
                continue

            statuses = [
                str(leg.get("result_status", "pending"))
                for leg in legs
            ]
            slip_status = grade_slip_fn(statuses)
            connection.execute(
                """
                UPDATE slips
                SET status = ?, legs_json = ?
                WHERE id = ?
                """,
                (
                    slip_status,
                    json.dumps(legs),
                    row["id"],
                ),
            )
            updated_slips += 1

    return updated_slips
