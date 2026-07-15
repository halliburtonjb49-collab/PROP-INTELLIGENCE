import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from config import DB_PATH
from models.prop_builder_history import (
    PropBuilderHistory,
    PropBuilderHistoryCreate,
)


def _connect() -> sqlite3.Connection:
    connection = sqlite3.connect(
        Path(DB_PATH),
    )
    connection.row_factory = sqlite3.Row
    return connection


def initialize_prop_builder_history() -> None:
    with _connect() as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS
            prop_builder_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at TEXT NOT NULL,
                build_mode TEXT NOT NULL,
                risk_mode TEXT NOT NULL DEFAULT 'BALANCED',
                sports_json TEXT NOT NULL,
                prop_sites_json TEXT NOT NULL,
                markets_json TEXT NOT NULL DEFAULT '[]',
                requested_legs INTEGER NOT NULL,
                generated_legs INTEGER NOT NULL,
                average_edge REAL NOT NULL,
                average_confidence REAL NOT NULL,
                legs_json TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending',
                legs_won INTEGER NOT NULL DEFAULT 0,
                legs_lost INTEGER NOT NULL DEFAULT 0,
                legs_pushed INTEGER NOT NULL DEFAULT 0,
                legs_pending INTEGER NOT NULL DEFAULT 0,
                hit_rate REAL NOT NULL DEFAULT 0
            )
            """
        )
    _ensure_history_columns()


def _ensure_history_columns() -> None:
    required_columns = {
        "risk_mode": "TEXT NOT NULL DEFAULT 'BALANCED'",
        "markets_json": "TEXT NOT NULL DEFAULT '[]'",
        "status": "TEXT NOT NULL DEFAULT 'pending'",
        "legs_won": "INTEGER NOT NULL DEFAULT 0",
        "legs_lost": "INTEGER NOT NULL DEFAULT 0",
        "legs_pushed": "INTEGER NOT NULL DEFAULT 0",
        "legs_pending": "INTEGER NOT NULL DEFAULT 0",
        "hit_rate": "REAL NOT NULL DEFAULT 0",
    }
    with _connect() as connection:
        existing_columns = {
            str(row["name"])
            for row in connection.execute(
                """
                PRAGMA table_info(
                    prop_builder_history
                )
                """
            ).fetchall()
        }
        for name, definition in required_columns.items():
            if name in existing_columns:
                continue
            connection.execute(
                f"""
                ALTER TABLE
                    prop_builder_history
                ADD COLUMN
                    {name} {definition}
                """
            )


def create_prop_builder_history(
    build: PropBuilderHistoryCreate,
) -> PropBuilderHistory:
    initialize_prop_builder_history()
    created_at = datetime.now(
        timezone.utc,
    ).isoformat()

    with _connect() as connection:
        cursor = connection.execute(
            """
            INSERT INTO prop_builder_history (
                created_at,
                build_mode,
                risk_mode,
                sports_json,
                prop_sites_json,
                markets_json,
                requested_legs,
                generated_legs,
                average_edge,
                average_confidence,
                legs_json,
                status,
                legs_won,
                legs_lost,
                legs_pushed,
                legs_pending,
                hit_rate
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                created_at,
                build.build_mode,
                build.risk_mode,
                json.dumps(build.sports),
                json.dumps(build.prop_sites),
                json.dumps(build.markets),
                build.requested_legs,
                build.generated_legs,
                build.average_edge,
                build.average_confidence,
                json.dumps(build.legs),
                build.status,
                build.legs_won,
                build.legs_lost,
                build.legs_pushed,
                build.legs_pending,
                build.hit_rate,
            ),
        )
        history_id = cursor.lastrowid
        row = connection.execute(
            """
            SELECT *
            FROM prop_builder_history
            WHERE id = ?
            """,
            (history_id,),
        ).fetchone()

    if row is None:
        raise RuntimeError(
            "Unable to save builder history.",
        )

    return _row_to_history(row)


def list_prop_builder_history(
    *,
    limit: int = 30,
) -> list[PropBuilderHistory]:
    initialize_prop_builder_history()
    safe_limit = max(
        1,
        min(limit, 100),
    )
    with _connect() as connection:
        rows = connection.execute(
            """
            SELECT *
            FROM prop_builder_history
            ORDER BY created_at DESC
            LIMIT ?
            """,
            (safe_limit,),
        ).fetchall()

    return [
        _row_to_history(row)
        for row in rows
    ]


def get_prop_builder_history(
    history_id: int,
) -> PropBuilderHistory | None:
    initialize_prop_builder_history()
    with _connect() as connection:
        row = connection.execute(
            """
            SELECT *
            FROM prop_builder_history
            WHERE id = ?
            """,
            (history_id,),
        ).fetchone()

    if row is None:
        return None

    return _row_to_history(row)


def delete_prop_builder_history(
    history_id: int,
) -> bool:
    initialize_prop_builder_history()
    with _connect() as connection:
        cursor = connection.execute(
            """
            DELETE FROM prop_builder_history
            WHERE id = ?
            """,
            (history_id,),
        )

    return cursor.rowcount > 0


def clear_prop_builder_history() -> int:
    initialize_prop_builder_history()
    with _connect() as connection:
        cursor = connection.execute(
            """
            DELETE FROM prop_builder_history
            """
        )

    return cursor.rowcount


def _row_to_history(
    row: sqlite3.Row,
) -> PropBuilderHistory:
    return PropBuilderHistory(
        id=int(row["id"]),
        created_at=datetime.fromisoformat(
            str(row["created_at"]),
        ),
        build_mode=str(
            row["build_mode"],
        ),
        risk_mode=str(
            row["risk_mode"],
        ),
        sports=json.loads(
            row["sports_json"],
        ),
        prop_sites=json.loads(
            row["prop_sites_json"],
        ),
        markets=json.loads(
            row["markets_json"],
        ),
        requested_legs=int(
            row["requested_legs"],
        ),
        generated_legs=int(
            row["generated_legs"],
        ),
        average_edge=float(
            row["average_edge"],
        ),
        average_confidence=float(
            row["average_confidence"],
        ),
        legs=json.loads(
            row["legs_json"],
        ),
        status=str(
            row["status"],
        ),
        legs_won=int(
            row["legs_won"],
        ),
        legs_lost=int(
            row["legs_lost"],
        ),
        legs_pushed=int(
            row["legs_pushed"],
        ),
        legs_pending=int(
            row["legs_pending"],
        ),
        hit_rate=float(
            row["hit_rate"],
        ),
    )
