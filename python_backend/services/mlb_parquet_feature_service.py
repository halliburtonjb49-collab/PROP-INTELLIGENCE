"""Leakage-safe MLB player-game features derived from Statcast Parquet files."""

from __future__ import annotations

from pathlib import Path
import json
from typing import Iterable

import polars as pl

from database.postgres import database_is_configured, get_database_pool


HIT_EVENTS = ("single", "double", "triple", "home_run")
ON_BASE_EVENTS = HIT_EVENTS + ("walk", "intent_walk", "hit_by_pitch")
FEATURE_VERSION = "mlb-statcast-rolling-v1"


def _required(frame: pl.LazyFrame, names: set[str]) -> None:
    missing = names.difference(frame.collect_schema().names())
    if missing:
        raise ValueError(f"Statcast input is missing required columns: {sorted(missing)}")


def _game_date() -> pl.Expr:
    return pl.col("game_date").cast(pl.Date, strict=False)


def batter_game_outcomes(frame: pl.LazyFrame) -> pl.LazyFrame:
    """Return one realized batting-stat row per batter and game."""
    _required(frame, {"game_date", "game_pk", "batter", "events"})
    event = pl.col("events").cast(pl.String).str.to_lowercase()
    total_bases = (
        pl.when(event == "single").then(1)
        .when(event == "double").then(2)
        .when(event == "triple").then(3)
        .when(event == "home_run").then(4)
        .otherwise(0)
    )
    return (
        frame.with_columns(game_date=_game_date(), event=event)
        .filter(pl.col("game_date").is_not_null() & pl.col("game_pk").is_not_null()
                & pl.col("batter").is_not_null())
        .group_by("game_date", "game_pk", "batter")
        .agg(
            plate_appearances=pl.col("event").is_not_null().sum(),
            hits=pl.col("event").is_in(HIT_EVENTS).sum(),
            total_bases=total_bases.sum(),
            home_runs=(pl.col("event") == "home_run").sum(),
            walks=pl.col("event").is_in(("walk", "intent_walk")).sum(),
            strikeouts=(pl.col("event") == "strikeout").sum(),
            times_on_base=pl.col("event").is_in(ON_BASE_EVENTS).sum(),
        )
        .sort("game_date", "game_pk", "batter")
    )


def pitcher_game_outcomes(frame: pl.LazyFrame) -> pl.LazyFrame:
    """Return one realized pitching-stat row per pitcher and game."""
    _required(frame, {"game_date", "game_pk", "pitcher", "events", "description"})
    event = pl.col("events").cast(pl.String).str.to_lowercase()
    description = pl.col("description").cast(pl.String).str.to_lowercase()
    return (
        frame.with_columns(game_date=_game_date(), event=event, pitch_description=description)
        .filter(pl.col("game_date").is_not_null() & pl.col("game_pk").is_not_null()
                & pl.col("pitcher").is_not_null())
        .group_by("game_date", "game_pk", "pitcher")
        .agg(
            pitches=pl.len(),
            batters_faced=pl.col("event").is_not_null().sum(),
            strikeouts=(pl.col("event") == "strikeout").sum(),
            walks=pl.col("event").is_in(("walk", "intent_walk")).sum(),
            hits_allowed=pl.col("event").is_in(HIT_EVENTS).sum(),
            whiffs=pl.col("pitch_description").is_in(
                ("swinging_strike", "swinging_strike_blocked", "missed_bunt")
            ).sum(),
            called_strikes=(pl.col("pitch_description") == "called_strike").sum(),
        )
        .sort("game_date", "game_pk", "pitcher")
    )


def add_prior_date_rolling_features(
    games: pl.LazyFrame,
    *,
    player_column: str,
    stat_columns: tuple[str, ...],
    windows: tuple[int, ...] = (5, 10, 20),
) -> pl.LazyFrame:
    """Attach rolling means using prior dates only, never current-day outcomes."""
    schema = set(games.collect_schema().names())
    required = {"game_date", player_column, *stat_columns}
    missing = required.difference(schema)
    if missing:
        raise ValueError(f"Game outcomes are missing columns: {sorted(missing)}")

    daily = games.group_by("game_date", player_column).agg(
        *[pl.col(name).sum().alias(name) for name in stat_columns],
        games_on_date=pl.len(),
    ).sort(player_column, "game_date")
    rolling = daily.with_columns(
        prior_dates=pl.col("game_date").cum_count().over(player_column) - 1,
        *[
            pl.col(stat)
            .shift(1)
            .rolling_mean(window_size=window, min_samples=1)
            .over(player_column)
            .alias(f"pregame_{stat}_avg_{window}d")
            for stat in stat_columns
            for window in windows
        ],
    ).select(
        "game_date", player_column, "prior_dates",
        *[f"pregame_{stat}_avg_{window}d" for stat in stat_columns for window in windows],
    )
    return games.join(rolling, on=["game_date", player_column], how="left")


def build_feature_parquets(source: Path, output_directory: Path) -> dict[str, object]:
    """Build batter and pitcher feature Parquets without loading all pitches into RAM."""
    output_directory.mkdir(parents=True, exist_ok=True)
    pitches = pl.scan_parquet(source)
    batter = add_prior_date_rolling_features(
        batter_game_outcomes(pitches), player_column="batter",
        stat_columns=("plate_appearances", "hits", "total_bases", "home_runs", "walks", "strikeouts"),
    )
    pitcher = add_prior_date_rolling_features(
        pitcher_game_outcomes(pitches), player_column="pitcher",
        stat_columns=("pitches", "batters_faced", "strikeouts", "walks", "hits_allowed", "whiffs"),
    )
    batter_path = output_directory / "mlb_batter_game_features.parquet"
    pitcher_path = output_directory / "mlb_pitcher_game_features.parquet"
    batter.sink_parquet(batter_path)
    pitcher.sink_parquet(pitcher_path)
    return {
        "batterPath": str(batter_path.resolve()),
        "pitcherPath": str(pitcher_path.resolve()),
        "batterRows": pl.scan_parquet(batter_path).select(pl.len()).collect().item(),
        "pitcherRows": pl.scan_parquet(pitcher_path).select(pl.len()).collect().item(),
    }


def _json_values(row: dict[str, object], names: Iterable[str]) -> dict[str, object]:
    return {name: row[name] for name in names if name in row and row[name] is not None}


def feature_records(path: Path, *, role: str) -> list[dict[str, object]]:
    """Normalize one generated feature Parquet into versioned database records."""
    normalized_role = role.strip().upper()
    if normalized_role not in {"BATTER", "PITCHER"}:
        raise ValueError("role must be BATTER or PITCHER")
    player_column = normalized_role.lower()
    outcomes = (
        ("plate_appearances", "hits", "total_bases", "home_runs", "walks", "strikeouts", "times_on_base")
        if normalized_role == "BATTER"
        else ("pitches", "batters_faced", "strikeouts", "walks", "hits_allowed", "whiffs", "called_strikes")
    )
    frame = pl.read_parquet(path)
    required = {"game_date", "game_pk", player_column, "prior_dates"}
    missing = required.difference(frame.columns)
    if missing:
        raise ValueError(f"Feature Parquet is missing columns: {sorted(missing)}")
    feature_names = tuple(name for name in frame.columns if name.startswith("pregame_"))
    records = []
    for row in frame.iter_rows(named=True):
        player_id = str(row[player_column])
        game_pk = str(row["game_pk"])
        records.append({
            "id": f"{FEATURE_VERSION}:{normalized_role}:{player_id}:{game_pk}",
            "player_role": normalized_role,
            "player_id": player_id,
            "game_pk": game_pk,
            "game_date": row["game_date"],
            "outcomes": _json_values(row, outcomes),
            "pregame_features": _json_values(row, feature_names),
            "prior_dates": max(0, int(row["prior_dates"] or 0)),
            "feature_version": FEATURE_VERSION,
        })
    return records


def persist_feature_records(rows: list[dict[str, object]], *, batch_size: int = 500) -> int:
    """Idempotently persist feature records in bounded batches."""
    if not rows or not database_is_configured():
        return 0
    total = 0
    statement = """insert into mlb_player_game_features
        (id,player_role,player_id,game_pk,game_date,outcomes,pregame_features,
         prior_dates,feature_version)
        values(%s,%s,%s,%s,%s,%s::jsonb,%s::jsonb,%s,%s)
        on conflict(id) do update set outcomes=excluded.outcomes,
          pregame_features=excluded.pregame_features,prior_dates=excluded.prior_dates,
          updated_at=now()"""
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        for offset in range(0, len(rows), max(1, batch_size)):
            batch = rows[offset:offset + max(1, batch_size)]
            cursor.executemany(statement, [(
                row["id"], row["player_role"], row["player_id"], row["game_pk"],
                row["game_date"], json.dumps(row["outcomes"]),
                json.dumps(row["pregame_features"]), row["prior_dates"],
                row["feature_version"],
            ) for row in batch])
            total += len(batch)
        connection.commit()
    return total


def persist_feature_parquets(output_directory: Path) -> dict[str, int]:
    batter = feature_records(output_directory / "mlb_batter_game_features.parquet", role="BATTER")
    pitcher = feature_records(output_directory / "mlb_pitcher_game_features.parquet", role="PITCHER")
    return {
        "batterUpserted": persist_feature_records(batter),
        "pitcherUpserted": persist_feature_records(pitcher),
    }


def latest_player_features(*, role: str, player_id: str, before_date: object) -> dict[str, object] | None:
    """Load the latest pregame feature snapshot strictly before a target date."""
    if not database_is_configured():
        return None
    normalized_role = role.strip().upper()
    if normalized_role not in {"BATTER", "PITCHER"}:
        return None
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select game_date,pregame_features,prior_dates,feature_version
               from mlb_player_game_features
               where player_role=%s and player_id=%s and game_date < %s
               order by game_date desc,game_pk desc limit 1""",
            (normalized_role, str(player_id), before_date),
        )
        row = cursor.fetchone()
    if not row:
        return None
    return {"gameDate": row[0], "features": row[1], "priorDates": row[2], "featureVersion": row[3]}
