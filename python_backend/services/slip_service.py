import json
import sqlite3
from collections.abc import Callable
from pathlib import Path
from typing import Any

from calculations.slip_grader import (
    grade_leg,
    grade_slip_status,
)
from models.slip import (
    LegResultUpdate,
    SlipCreate,
    SlipLeg,
    SlipResponse,
    create_slip_response,
)
from services.market_normalizer import normalize_market
from services.team_normalizer import normalize_team_name

BASE_DIR = Path(__file__).resolve().parent.parent
DATABASE_PATH = BASE_DIR / "prop_intelligence_cache.db"


def _connect() -> sqlite3.Connection:
    connection = sqlite3.connect(DATABASE_PATH)
    connection.row_factory = sqlite3.Row
    return connection


def initialize_slip_table() -> None:
    with _connect() as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS slips (
                id TEXT PRIMARY KEY,
                status TEXT NOT NULL,
                stake REAL NOT NULL,
                potential_payout REAL NOT NULL,
                created_at TEXT NOT NULL,
                legs_json TEXT NOT NULL
            )
            """
        )


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


def create_slip(request: SlipCreate) -> SlipResponse:
    initialize_slip_table()
    payout = _calculate_payout(request)
    slip = create_slip_response(request, payout)

    with _connect() as connection:
        connection.execute(
            """
            INSERT INTO slips (
                id,
                status,
                stake,
                potential_payout,
                created_at,
                legs_json
            )
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                slip.id,
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


def get_slips(status: str | None = None) -> list[SlipResponse]:
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

    if status:
        query += " WHERE status = ?"
        parameters = (status,)

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
) -> bool:
    if status not in {"active", "won", "lost"}:
        raise ValueError("Invalid slip status.")

    initialize_slip_table()
    with _connect() as connection:
        cursor = connection.execute(
            """
            UPDATE slips
            SET status = ?
            WHERE id = ?
            """,
            (status, slip_id),
        )
        return cursor.rowcount > 0


def update_slip_results(
    updates: list[LegResultUpdate],
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
            WHERE status = 'active'
            """
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
