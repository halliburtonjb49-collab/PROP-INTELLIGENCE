"""NFL player game logs from the nflverse weekly release.

The ESPN scoreboard is queried one date at a time, so seeding a season costs
roughly 240 requests and produces exactly the counting stats a box score
carries. nflverse publishes the same season as a single weekly parquet, which
DuckDB can read straight from the URL -- one request for the whole year, and
no new dependency, since DuckDB and pandas are already here.

It also carries what the box score cannot: air yards, yards after catch,
target share and EPA. Nothing projects from those yet, and this deliberately
does not pretend otherwise -- they are stored so the work that needs them has
something to start from, not so a card can claim it used them.

The stat names match the ones the projection already asks for. A source that
stored "pass_yds" while the projection looked up "passing_yards" would be the
same defect this codebase spent a day removing, in a new place.
"""

from __future__ import annotations

import hashlib
import logging
from typing import Any, Iterable, Mapping

logger = logging.getLogger(__name__)

WEEKLY_URL = (
    "https://github.com/nflverse/nflverse-data/releases/download/"
    "stats_player/stats_player_week_{season}.parquet"
)

# nflverse column to the stat name the projection looks up. Only stats a
# market actually resolves to are mapped; the rest are carried in raw.
_STAT_COLUMNS: Mapping[str, str] = {
    "passing_yards": "passing_yards",
    "passing_tds": "passing_touchdowns",
    "passing_interceptions": "interceptions_thrown",
    "completions": "completions",
    "attempts": "pass_attempts",
    "carries": "carries",
    "rushing_yards": "rushing_yards",
    "rushing_tds": "rushing_touchdowns",
    "receptions": "receptions",
    "receiving_yards": "receiving_yards",
    "receiving_tds": "receiving_touchdowns",
    "targets": "targets",
}

# Kept for later work rather than projected from. Storing them costs nothing
# and not storing them means re-fetching a season to get them.
_CONTEXT_COLUMNS: tuple[str, ...] = (
    "passing_air_yards",
    "passing_yards_after_catch",
    "passing_epa",
    "receiving_air_yards",
    "receiving_yards_after_catch",
    "receiving_epa",
    "rushing_epa",
    "target_share",
    "air_yards_share",
)

_SELECTED = (
    "player_id", "player_display_name", "position", "season", "week",
    "season_type", "game_id", "team", "opponent_team",
) + tuple(_STAT_COLUMNS) + _CONTEXT_COLUMNS


def _number(value: object) -> float | None:
    try:
        if value is None:
            return None
        number = float(value)
    except (TypeError, ValueError):
        return None
    return None if number != number else number  # drop NaN


def log_id(season: object, week: object, player_id: object) -> str:
    """Stable per player-week, so a re-fetch updates rather than duplicates."""

    raw = f"nflverse:{season}:{week}:{player_id}"
    return hashlib.sha1(
        raw.encode("utf-8"), usedforsecurity=False
    ).hexdigest()


def normalize_weekly_rows(rows: Iterable[Mapping[str, Any]]) -> list[dict[str, object]]:
    """Weekly rows to the game-log shape the repository stores.

    A row with no mapped stat at all is dropped rather than stored empty: an
    inactive player's blank week would otherwise teach the model a zero he
    never actually posted.
    """

    logs: list[dict[str, object]] = []
    for row in rows:
        player_id = str(row.get("player_id") or "").strip()
        if not player_id:
            continue
        stats: dict[str, float] = {}
        for column, stat in _STAT_COLUMNS.items():
            value = _number(row.get(column))
            if value is not None:
                stats[stat] = value
        if not stats:
            continue
        context = {
            column: value
            for column in _CONTEXT_COLUMNS
            if (value := _number(row.get(column))) is not None
        }
        season = row.get("season")
        week = row.get("week")
        logs.append({
            "id": log_id(season, week, player_id),
            "sport": "NFL",
            "league": "NFL",
            "event_id": str(row.get("game_id") or ""),
            "player_id": player_id,
            "player_name": str(row.get("player_display_name") or ""),
            "team_id": str(row.get("team") or ""),
            # nflverse is weekly rather than dated; the game id carries the
            # date and the ordering only needs to be stable and correct.
            "game_date": f"{season}-W{str(week).zfill(2)}",
            "stats": stats,
            "source": "nflverse",
            "raw": {
                "position": row.get("position"),
                "opponent": row.get("opponent_team"),
                "seasonType": row.get("season_type"),
                "context": context,
            },
        })
    return logs


class NflverseStatisticsProvider:
    """Reads a season of weekly player stats in one request."""

    def weekly_logs(self, season: int) -> list[dict[str, object]]:
        import duckdb

        columns = ", ".join(_SELECTED)
        url = WEEKLY_URL.format(season=season)
        connection = duckdb.connect()
        try:
            try:
                connection.execute("install httpfs; load httpfs;")
            except Exception:
                # Already present in most builds; the read below is the test
                # that matters and it reports its own failure.
                pass
            rows = connection.execute(
                f"select {columns} from read_parquet('{url}')"
            ).fetchall()
            names = [description[0] for description in connection.description]
        finally:
            connection.close()
        return normalize_weekly_rows(dict(zip(names, row)) for row in rows)
