import sqlite3
from pathlib import Path
from typing import Any


class PropCache:
    def __init__(self, database_path: Path) -> None:
        self.database_path = database_path
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self.initialize()
        self.ensure_game_columns()

    def connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database_path)
        connection.row_factory = sqlite3.Row
        return connection

    def initialize(self) -> None:
        with self.connect() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS games (
                    id TEXT PRIMARY KEY,
                    sport TEXT NOT NULL,
                    home_team TEXT,
                    away_team TEXT,
                    commence_time TEXT,
                    api_sports_game_id TEXT,
                    game_status TEXT
                )
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS props (
                    game_id TEXT NOT NULL,
                    player_name TEXT NOT NULL,
                    prop_type TEXT NOT NULL,
                    line REAL NOT NULL,
                    opening_line REAL,
                    current_line REAL,
                    line_updated_at TEXT,
                    over_odds REAL,
                    under_odds REAL,
                    bookmaker TEXT,
                    prediction TEXT,
                    confidence REAL,
                    source_player_id TEXT,
                    updated_at TEXT,
                    FOREIGN KEY (game_id) REFERENCES games(id)
                )
                """
            )

    def ensure_game_columns(self) -> None:
        with self.connect() as connection:
            columns = {
                row["name"]
                for row in connection.execute(
                    "PRAGMA table_info(games)"
                ).fetchall()
            }
            if "api_sports_game_id" not in columns:
                connection.execute(
                    """
                    ALTER TABLE games
                    ADD COLUMN api_sports_game_id TEXT
                    """
                )
            if "game_status" not in columns:
                connection.execute(
                    """
                    ALTER TABLE games
                    ADD COLUMN game_status TEXT
                    """
                )

            prop_columns = {
                row["name"]
                for row in connection.execute(
                    "PRAGMA table_info(props)"
                ).fetchall()
            }
            if "source_player_id" not in prop_columns:
                connection.execute(
                    """
                    ALTER TABLE props
                    ADD COLUMN source_player_id TEXT
                    """
                )
            if "updated_at" not in prop_columns:
                connection.execute(
                    """
                    ALTER TABLE props
                    ADD COLUMN updated_at TEXT
                    """
                )
            if "opening_line" not in prop_columns:
                connection.execute(
                    """
                    ALTER TABLE props
                    ADD COLUMN opening_line REAL
                    """
                )
            if "current_line" not in prop_columns:
                connection.execute(
                    """
                    ALTER TABLE props
                    ADD COLUMN current_line REAL
                    """
                )
            if "line_updated_at" not in prop_columns:
                connection.execute(
                    """
                    ALTER TABLE props
                    ADD COLUMN line_updated_at TEXT
                    """
                )

    def replace_games(
        self,
        sport: str,
        games: list[dict[str, Any]],
    ) -> None:
        with self.connect() as connection:
            for game in games:
                connection.execute(
                    """
                    INSERT OR REPLACE INTO games (
                        id,
                        sport,
                        home_team,
                        away_team,
                        commence_time,
                        api_sports_game_id,
                        game_status
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        game["id"],
                        sport,
                        game.get("home_team", ""),
                        game.get("away_team", ""),
                        game.get("commence_time", ""),
                        game.get("api_sports_game_id", ""),
                        game.get("game_status", ""),
                    ),
                )

    def set_api_sports_game_id(
        self,
        *,
        odds_event_id: str,
        api_sports_game_id: str,
    ) -> None:
        with self.connect() as connection:
            connection.execute(
                """
                UPDATE games
                SET api_sports_game_id = ?
                WHERE id = ?
                """,
                (
                    api_sports_game_id,
                    odds_event_id,
                ),
            )

    def clear_game_props(self, game_id: str) -> None:
        with self.connect() as connection:
            connection.execute(
                "DELETE FROM props WHERE game_id = ?",
                (game_id,),
            )

    def get_existing_prop_snapshots(
        self,
        *,
        game_id: str,
    ) -> dict[tuple[str, str, str], dict[str, object]]:
        with self.connect() as connection:
            rows = connection.execute(
                """
                SELECT
                    player_name,
                    prop_type,
                    bookmaker,
                    line,
                    opening_line,
                    current_line,
                    line_updated_at
                FROM props
                WHERE game_id = ?
                """,
                (game_id,),
            ).fetchall()

        snapshots: dict[tuple[str, str, str], dict[str, object]] = {}
        for row in rows:
            key = (
                str(row["bookmaker"] or "").strip().lower(),
                str(row["prop_type"] or "").strip().lower(),
                str(row["player_name"] or "").strip().lower(),
            )
            snapshots[key] = {
                "line": row["line"],
                "opening_line": row["opening_line"],
                "current_line": row["current_line"],
                "line_updated_at": row["line_updated_at"],
            }
        return snapshots

    def prune_sport_to_event_ids(
        self,
        *,
        sport: str,
        active_event_ids: list[str],
    ) -> None:
        with self.connect() as connection:
            if not active_event_ids:
                connection.execute(
                    "DELETE FROM props WHERE game_id IN (SELECT id FROM games WHERE sport = ?)",
                    (sport,),
                )
                connection.execute(
                    "DELETE FROM games WHERE sport = ?",
                    (sport,),
                )
                return

            placeholders = ",".join(["?"] * len(active_event_ids))
            params: list[object] = [sport, *active_event_ids]
            connection.execute(
                f"""
                DELETE FROM props
                WHERE game_id IN (
                    SELECT id FROM games
                    WHERE sport = ?
                    AND id NOT IN ({placeholders})
                )
                """,
                tuple(params),
            )
            connection.execute(
                f"""
                DELETE FROM games
                WHERE sport = ?
                AND id NOT IN ({placeholders})
                """,
                tuple(params),
            )

    def insert_prop(
        self,
        *,
        game_id: str,
        player_name: str,
        prop_type: str,
        line: float,
        opening_line: float,
        current_line: float,
        line_updated_at: str,
        over_odds: float,
        under_odds: float,
        bookmaker: str,
        prediction: str,
        confidence: float,
        source_player_id: str,
        updated_at: str,
    ) -> None:
        with self.connect() as connection:
            connection.execute(
                """
                INSERT INTO props (
                    game_id,
                    player_name,
                    prop_type,
                    line,
                    opening_line,
                    current_line,
                    line_updated_at,
                    over_odds,
                    under_odds,
                    bookmaker,
                    prediction,
                    confidence,
                    source_player_id,
                    updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    game_id,
                    player_name,
                    prop_type,
                    line,
                    opening_line,
                    current_line,
                    line_updated_at,
                    over_odds,
                    under_odds,
                    bookmaker,
                    prediction,
                    confidence,
                    source_player_id,
                    updated_at,
                ),
            )

    def replace_event_props(
        self,
        *,
        sport: str,
        game: dict[str, Any],
        props: list[tuple[object, ...]],
    ) -> None:
        """Replace one event and all of its props in a single transaction."""
        with self.connect() as connection:
            connection.execute(
                """
                INSERT OR REPLACE INTO games (
                    id, sport, home_team, away_team, commence_time,
                    api_sports_game_id, game_status
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    game["id"],
                    sport,
                    game.get("home_team", ""),
                    game.get("away_team", ""),
                    game.get("commence_time", ""),
                    game.get("api_sports_game_id", ""),
                    game.get("game_status", ""),
                ),
            )
            connection.execute(
                "DELETE FROM props WHERE game_id = ?",
                (game["id"],),
            )
            connection.executemany(
                """
                INSERT INTO props (
                    game_id, player_name, prop_type, line, opening_line,
                    current_line, line_updated_at, over_odds, under_odds,
                    bookmaker, prediction, confidence, source_player_id, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                props,
            )

    def load_props(self) -> list[sqlite3.Row]:
        with self.connect() as connection:
            return connection.execute(
                """
                SELECT
                    p.game_id,
                    p.player_name,
                    p.prop_type,
                    p.line,
                    p.opening_line,
                    p.current_line,
                    p.line_updated_at,
                    p.prediction,
                    p.confidence,
                    g.home_team,
                    g.away_team,
                    g.sport,
                    g.commence_time,
                    g.api_sports_game_id,
                    g.game_status,
                    p.bookmaker,
                    p.over_odds,
                    p.under_odds,
                    p.source_player_id,
                    p.updated_at
                FROM props p
                JOIN games g ON p.game_id = g.id
                ORDER BY p.confidence DESC
                """
            ).fetchall()
