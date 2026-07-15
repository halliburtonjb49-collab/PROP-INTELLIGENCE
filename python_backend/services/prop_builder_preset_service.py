import json
import sqlite3
from pathlib import Path

from config import DB_PATH
from models.prop_builder_preset import (
    PropBuilderPreset,
    PropBuilderPresetCreate,
)


def _connect() -> sqlite3.Connection:
    connection = sqlite3.connect(
        Path(DB_PATH),
    )
    connection.row_factory = sqlite3.Row
    return connection


def initialize_prop_builder_presets() -> None:
    with _connect() as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS
            prop_builder_presets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                sports_json TEXT NOT NULL,
                prop_sites_json TEXT NOT NULL,
                markets_json TEXT NOT NULL DEFAULT '[]',
                leg_count INTEGER NOT NULL,
                minimum_edge INTEGER NOT NULL,
                minimum_confidence INTEGER NOT NULL,
                same_game_allowed INTEGER NOT NULL,
                build_mode TEXT NOT NULL,
                risk_mode TEXT NOT NULL DEFAULT 'BALANCED',
                side_preference TEXT NOT NULL
            )
            """
        )
    _ensure_preset_columns()


def _ensure_preset_columns() -> None:
    with _connect() as connection:
        columns = {
            str(row["name"])
            for row in connection.execute(
                """
                PRAGMA table_info(
                    prop_builder_presets
                )
                """
            ).fetchall()
        }
        if "markets_json" not in columns:
            connection.execute(
                """
                ALTER TABLE
                    prop_builder_presets
                ADD COLUMN
                    markets_json TEXT
                    NOT NULL DEFAULT '[]'
                """
            )
        if "risk_mode" not in columns:
            connection.execute(
                """
                ALTER TABLE
                    prop_builder_presets
                ADD COLUMN
                    risk_mode TEXT
                    NOT NULL DEFAULT 'BALANCED'
                """
            )


def create_prop_builder_preset(
    preset: PropBuilderPresetCreate,
) -> PropBuilderPreset:
    initialize_prop_builder_presets()
    with _connect() as connection:
        connection.execute(
            """
            INSERT INTO prop_builder_presets (
                name,
                sports_json,
                prop_sites_json,
                markets_json,
                leg_count,
                minimum_edge,
                minimum_confidence,
                same_game_allowed,
                build_mode,
                risk_mode,
                side_preference
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(name)
            DO UPDATE SET
                sports_json = excluded.sports_json,
                prop_sites_json = excluded.prop_sites_json,
                markets_json = excluded.markets_json,
                leg_count = excluded.leg_count,
                minimum_edge = excluded.minimum_edge,
                minimum_confidence = excluded.minimum_confidence,
                same_game_allowed = excluded.same_game_allowed,
                build_mode = excluded.build_mode,
                risk_mode = excluded.risk_mode,
                side_preference = excluded.side_preference
            """,
            (
                preset.name.strip(),
                json.dumps(preset.sports),
                json.dumps(preset.prop_sites),
                json.dumps(preset.markets),
                preset.leg_count,
                preset.minimum_edge,
                preset.minimum_confidence,
                int(preset.same_game_allowed),
                preset.build_mode,
                preset.risk_mode,
                preset.side_preference,
            ),
        )
        row = connection.execute(
            """
            SELECT *
            FROM prop_builder_presets
            WHERE name = ?
            """,
            (
                preset.name.strip(),
            ),
        ).fetchone()

    if row is None:
        raise RuntimeError("Unable to save preset.")

    return _row_to_preset(row)


def list_prop_builder_presets() -> list[PropBuilderPreset]:
    initialize_prop_builder_presets()
    with _connect() as connection:
        rows = connection.execute(
            """
            SELECT *
            FROM prop_builder_presets
            ORDER BY name ASC
            """
        ).fetchall()

    return [_row_to_preset(row) for row in rows]


def delete_prop_builder_preset(
    preset_id: int,
) -> bool:
    initialize_prop_builder_presets()
    with _connect() as connection:
        cursor = connection.execute(
            """
            DELETE FROM prop_builder_presets
            WHERE id = ?
            """,
            (
                preset_id,
            ),
        )

    return cursor.rowcount > 0


def seed_default_prop_builder_presets() -> None:
    initialize_prop_builder_presets()
    defaults = [
        PropBuilderPresetCreate(
            name="WNBA Safe 3",
            sports=["WNBA"],
            prop_sites=[
                "PrizePicks",
                "Underdog",
                "Sleeper",
                "FanDuel",
                "Draft Picks",
            ],
            markets=[],
            leg_count=3,
            minimum_edge=65,
            minimum_confidence=70,
            same_game_allowed=False,
            build_mode="SAME_SPORT",
            risk_mode="SAFE",
            side_preference="ANY",
        ),
        PropBuilderPresetCreate(
            name="WNBA Assists Safe 3",
            sports=["WNBA"],
            prop_sites=[
                "PrizePicks",
                "Underdog",
                "Sleeper",
                "FanDuel",
                "Draft Picks",
            ],
            markets=["assists"],
            leg_count=3,
            minimum_edge=65,
            minimum_confidence=70,
            same_game_allowed=False,
            build_mode="SAME_SPORT",
            risk_mode="SAFE",
            side_preference="ANY",
        ),
        PropBuilderPresetCreate(
            name="Mixed Sports Top 5",
            sports=["WNBA", "NBA", "MLB", "NFL", "NHL"],
            prop_sites=[
                "PrizePicks",
                "Underdog",
                "Sleeper",
                "FanDuel",
                "Draft Picks",
            ],
            markets=[],
            leg_count=5,
            minimum_edge=60,
            minimum_confidence=65,
            same_game_allowed=False,
            build_mode="MIXED_SPORTS",
            risk_mode="BALANCED",
            side_preference="ANY",
        ),
        PropBuilderPresetCreate(
            name="PrizePicks Only",
            sports=["WNBA", "NBA", "MLB", "NFL", "NHL"],
            prop_sites=["PrizePicks"],
            markets=[],
            leg_count=3,
            minimum_edge=60,
            minimum_confidence=60,
            same_game_allowed=False,
            build_mode="MIXED_SPORTS",
            risk_mode="BALANCED",
            side_preference="ANY",
        ),
    ]

    for preset in defaults:
        create_prop_builder_preset(preset)


def _row_to_preset(
    row: sqlite3.Row,
) -> PropBuilderPreset:
    return PropBuilderPreset(
        id=int(row["id"]),
        name=str(row["name"]),
        sports=json.loads(row["sports_json"]),
        prop_sites=json.loads(row["prop_sites_json"]),
        markets=json.loads(row["markets_json"]),
        leg_count=int(row["leg_count"]),
        minimum_edge=int(row["minimum_edge"]),
        minimum_confidence=int(row["minimum_confidence"]),
        same_game_allowed=bool(row["same_game_allowed"]),
        build_mode=str(row["build_mode"]),
        risk_mode=str(row["risk_mode"]),
        side_preference=str(row["side_preference"]),
    )
