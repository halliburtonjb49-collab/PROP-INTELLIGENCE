from services.baseline_projection_service import (
    MODEL_VERSION,
    baseline_is_actionable,
    basketball_market_value,
    compute_baseline_projection,
)


def test_baseline_requires_a_real_minimum_sample() -> None:
    assert compute_baseline_projection([20, 21, 19, 22, 20, 18, 21], line=20.5) is None


def test_baseline_is_time_ordered_and_transparently_capped() -> None:
    values = [10, 10, 10, 10, 10, 20, 20, 20, 20, 20]
    result = compute_baseline_projection(values, line=14.5)

    assert result is not None
    assert result.model_version == MODEL_VERSION
    assert result.sample_size == 10
    assert result.projection > sum(values) / len(values)
    assert 50 <= result.confidence <= 72
    assert result.calibrated is False
    assert result.historical_hit_rate == 50
    assert baseline_is_actionable(result, recommendation_tier="Strong") is False


def test_basketball_combination_markets_use_actual_components() -> None:
    # points, rebounds, assists, steals, blocks, turnovers, threes
    row = (24, 10, 8, 2, 1, 3, 4)
    assert basketball_market_value("player_points", row) == 24
    assert basketball_market_value("player_rebounds_assists", row) == 18
    assert basketball_market_value("player_points_rebounds_assists", row) == 42
    assert basketball_market_value("player_threes", row) == 4
    assert basketball_market_value("player_first_basket", row) is None


def test_mlb_combination_market_is_not_treated_as_hits(monkeypatch) -> None:
    from services.baseline_projection_service import _HistoricalProjectionIndex

    index = _HistoricalProjectionIndex()
    index.loaded_at = __import__("datetime").datetime.now(
        __import__("datetime").timezone.utc,
    )
    index.mlb[("batter:7", "hits")] = [1] * 10

    assert index.project(
        sport="MLB",
        player="Player",
        player_id="7",
        market="batter_hits_runs_rbis",
        line=1.5,
    ) is None
    assert index.project(
        sport="MLB",
        player="Player",
        player_id="7",
        market="batter_hits",
        line=0.5,
    ) is not None


def test_soccer_uses_only_exact_supported_markets() -> None:
    from services.baseline_projection_service import _HistoricalProjectionIndex

    index = _HistoricalProjectionIndex()
    index.loaded_at = __import__("datetime").datetime.now(
        __import__("datetime").timezone.utc,
    )
    index.multi_sport[("SOCCER", "teststriker", "shots_on_target")] = [2] * 10

    supported = index.project(
        sport="SOCCER",
        player="Test Striker",
        player_id="7",
        market="player_shots_on_target",
        line=1.5,
    )
    assert supported is not None
    assert supported.projection == 2
    assert index.project(
        sport="SOCCER",
        player="Test Striker",
        player_id="7",
        market="player_first_goal_scorer",
        line=0.5,
    ) is None


def test_baseline_requires_both_model_strength_and_historical_support() -> None:
    result = compute_baseline_projection(
        [23, 21, 24, 22, 25, 23, 24, 22, 25, 24],
        line=20.5,
    )
    assert result is not None
    assert result.historical_hit_rate >= 55
    assert baseline_is_actionable(result, recommendation_tier="Strong") is True
    assert baseline_is_actionable(result, recommendation_tier="Pass") is False
