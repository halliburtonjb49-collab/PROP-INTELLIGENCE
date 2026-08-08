from providers.nflverse_statistics import (
    log_id,
    normalize_weekly_rows,
)


def _row(**over):
    base = {
        "player_id": "00-0023459",
        "player_display_name": "Aaron Rodgers",
        "position": "QB",
        "season": 2025,
        "week": 1,
        "season_type": "REG",
        "game_id": "2025_01_NYJ_PIT",
        "team": "PIT",
        "opponent_team": "NYJ",
        "passing_yards": 244.0,
        "passing_tds": 4.0,
        "passing_interceptions": 0.0,
        "completions": 22.0,
        "attempts": 30.0,
        "carries": 1.0,
        "rushing_yards": -1.0,
        "rushing_tds": 0.0,
        "receptions": 0.0,
        "receiving_yards": 0.0,
        "receiving_tds": 0.0,
        "targets": 0.0,
        "passing_air_yards": 139.0,
    }
    base.update(over)
    return base


def test_stat_names_match_what_the_projection_asks_for() -> None:
    """A source storing pass_yds while the projection looks up
    passing_yards would be the defect this codebase spent a day removing,
    in a new place."""

    stats = normalize_weekly_rows([_row()])[0]["stats"]

    assert stats["passing_yards"] == 244.0
    assert stats["passing_touchdowns"] == 4.0
    assert stats["interceptions_thrown"] == 0.0
    assert stats["pass_attempts"] == 30.0
    assert stats["carries"] == 1.0
    assert stats["rushing_touchdowns"] == 0.0
    assert stats["receiving_touchdowns"] == 0.0


def test_every_projectable_market_has_its_stat() -> None:
    # The twelve NFL markets that resolve to a stat must all be feedable.
    stats = normalize_weekly_rows([_row()])[0]["stats"]
    for stat in (
        "passing_yards", "passing_touchdowns", "interceptions_thrown",
        "completions", "pass_attempts", "carries", "rushing_yards",
        "rushing_touchdowns", "receptions", "receiving_yards",
        "receiving_touchdowns", "targets",
    ):
        assert stat in stats, stat


def test_a_row_with_no_stats_is_dropped_not_stored_empty() -> None:
    # An inactive player's blank week would otherwise teach the model a zero
    # he never actually posted.
    blank = {key: None for key in _row()}
    blank.update({"player_id": "x", "season": 2025, "week": 1})

    assert normalize_weekly_rows([blank]) == []


def test_a_row_without_a_player_is_skipped() -> None:
    assert normalize_weekly_rows([_row(player_id="")]) == []


def test_the_id_is_stable_so_a_refetch_updates() -> None:
    first = normalize_weekly_rows([_row()])[0]["id"]
    second = normalize_weekly_rows([_row(passing_yards=999.0)])[0]["id"]

    assert first == second
    assert log_id(2025, 1, "a") != log_id(2025, 2, "a")


def test_context_stats_are_kept_but_not_promoted() -> None:
    # Air yards and EPA are stored for work that needs them later. Nothing
    # projects from them, and they must not look like it does.
    log = normalize_weekly_rows([_row()])[0]

    assert log["raw"]["context"]["passing_air_yards"] == 139.0
    assert "passing_air_yards" not in log["stats"]


def test_a_missing_stat_is_absent_rather_than_zero() -> None:
    log = normalize_weekly_rows([_row(receiving_yards=None)])[0]

    assert "receiving_yards" not in log["stats"]
    assert log["stats"]["passing_yards"] == 244.0


def test_weeks_order_correctly_as_text() -> None:
    # Stored as a sortable string because nflverse is weekly, not dated.
    assert normalize_weekly_rows([_row(week=2)])[0]["game_date"] == "2025-W02"
    assert normalize_weekly_rows([_row(week=12)])[0]["game_date"] == "2025-W12"
