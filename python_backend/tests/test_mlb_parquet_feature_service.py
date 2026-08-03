from datetime import date

import polars as pl

from services.mlb_parquet_feature_service import (
    FEATURE_VERSION,
    add_prior_date_rolling_features,
    batter_game_outcomes,
    feature_records,
    pitcher_game_outcomes,
)


def _pitches() -> pl.LazyFrame:
    return pl.DataFrame({
        "game_date": [date(2026, 6, 1), date(2026, 6, 1), date(2026, 6, 2), date(2026, 6, 2)],
        "game_pk": [1, 1, 2, 2],
        "batter": [10, 10, 10, 11],
        "pitcher": [20, 20, 20, 20],
        "events": [None, "single", "strikeout", "home_run"],
        "description": ["called_strike", "hit_into_play", "swinging_strike", "hit_into_play"],
    }).lazy()


def test_statcast_outcomes_aggregate_by_player_and_game() -> None:
    batters = batter_game_outcomes(_pitches()).collect()
    first = batters.filter((pl.col("game_pk") == 1) & (pl.col("batter") == 10)).row(0, named=True)
    assert first["plate_appearances"] == 1
    assert first["hits"] == 1
    assert first["total_bases"] == 1

    pitchers = pitcher_game_outcomes(_pitches()).collect()
    second = pitchers.filter(pl.col("game_pk") == 2).row(0, named=True)
    assert second["strikeouts"] == 1
    assert second["hits_allowed"] == 1
    assert second["whiffs"] == 1


def test_rolling_features_never_include_current_date() -> None:
    games = batter_game_outcomes(_pitches())
    featured = add_prior_date_rolling_features(
        games, player_column="batter", stat_columns=("hits",), windows=(5,),
    ).collect()
    day_one = featured.filter((pl.col("batter") == 10) & (pl.col("game_date") == date(2026, 6, 1))).row(0, named=True)
    day_two = featured.filter((pl.col("batter") == 10) & (pl.col("game_date") == date(2026, 6, 2))).row(0, named=True)
    assert day_one["pregame_hits_avg_5d"] is None
    assert day_two["pregame_hits_avg_5d"] == 1.0


def test_same_date_doubleheader_uses_identical_pregame_history() -> None:
    games = pl.DataFrame({
        "game_date": [date(2026, 6, 1), date(2026, 6, 2), date(2026, 6, 2)],
        "game_pk": [1, 2, 3], "batter": [10, 10, 10], "hits": [1, 0, 4],
    }).lazy()
    featured = add_prior_date_rolling_features(
        games, player_column="batter", stat_columns=("hits",), windows=(5,),
    ).collect().filter(pl.col("game_date") == date(2026, 6, 2))
    assert featured["pregame_hits_avg_5d"].to_list() == [1.0, 1.0]


def test_feature_records_are_versioned_and_separate_outcomes(tmp_path) -> None:
    path = tmp_path / "batter.parquet"
    pl.DataFrame({
        "game_date": [date(2026, 6, 2)], "game_pk": [2], "batter": [10],
        "hits": [2], "prior_dates": [8], "pregame_hits_avg_5d": [1.2],
    }).write_parquet(path)
    row = feature_records(path, role="BATTER")[0]
    assert row["id"] == f"{FEATURE_VERSION}:BATTER:10:2"
    assert row["outcomes"] == {"hits": 2}
    assert row["pregame_features"] == {"pregame_hits_avg_5d": 1.2}
    assert row["prior_dates"] == 8


def test_feature_records_reject_unknown_roles(tmp_path) -> None:
    path = tmp_path / "empty.parquet"
    pl.DataFrame({"value": [1]}).write_parquet(path)
    try:
        feature_records(path, role="CATCHER")
    except ValueError as exc:
        assert "BATTER or PITCHER" in str(exc)
    else:
        raise AssertionError("Unknown MLB feature role was accepted")
