from services.baseline_projection_service import (
    MODEL_VERSION,
    baseline_is_actionable,
    basketball_market_value,
    compute_baseline_projection,
    role_bucket_prior,
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


def test_mlb_pitcher_strikeout_history_produces_baseline() -> None:
    from services.baseline_projection_service import _HistoricalProjectionIndex

    index = _HistoricalProjectionIndex()
    index.loaded_at = __import__("datetime").datetime.now(
        __import__("datetime").timezone.utc,
    )
    index.mlb[("pitcher:656876", "strikeouts")] = [
        4,
        6,
        5,
        7,
        6,
        8,
        5,
        7,
        6,
        7,
    ]

    result = index.project(
        sport="MLB",
        player="Drew Rasmussen",
        player_id="656876",
        market="Pitcher Strikeouts",
        line=5.0,
    )

    assert result is not None
    assert result.sample_size == 10
    assert result.projection > 5.0


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


def test_role_prior_matches_a_starter_to_starters_not_to_the_league() -> None:
    # Twelve bench players and six starters. A starter must not be shrunk
    # toward a league average that is dominated by bench minutes.
    population = [2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 22, 24, 25, 27, 28, 30]
    league_average = sum(population) / len(population)

    starter_prior = role_bucket_prior(26, population)
    bench_prior = role_bucket_prior(3, population)

    assert starter_prior is not None and bench_prior is not None
    assert starter_prior > league_average > bench_prior
    assert starter_prior >= 22


def test_role_prior_is_withheld_when_the_population_cannot_describe_roles() -> None:
    assert role_bucket_prior(20, [18, 19, 21]) is None


def test_thin_sample_projection_is_pulled_toward_the_role_prior() -> None:
    # Eight games from a player running hot against a role prior of 18.
    values = [30, 32, 29, 33, 31, 34, 30, 32]
    unshrunk = compute_baseline_projection(
        values, line=28.5, sport="NBA", market="Points",
    )
    shrunk = compute_baseline_projection(
        values, line=28.5, sport="NBA", market="Points", prior=18.0,
    )

    assert unshrunk is not None and shrunk is not None
    assert unshrunk.prior is None and unshrunk.prior_weight == 1
    assert shrunk.prior == 18
    assert shrunk.prior_weight == .5
    assert 18 < shrunk.projection < unshrunk.projection


def test_shrinkage_fades_as_the_sample_grows() -> None:
    thin = compute_baseline_projection(
        [30] * 8, line=28.5, sport="NBA", market="Points", prior=18.0,
    )
    deep = compute_baseline_projection(
        [30] * 40, line=28.5, sport="NBA", market="Points", prior=18.0,
    )

    assert thin is not None and deep is not None
    assert deep.prior_weight > thin.prior_weight
    assert deep.projection > thin.projection


def test_ufc_uses_sparse_sport_floor_without_relaxing_other_sports() -> None:
    from datetime import datetime, timezone
    from services.baseline_projection_service import _HistoricalProjectionIndex

    index = _HistoricalProjectionIndex()
    index.loaded_at = datetime.now(timezone.utc)
    index.multi_sport[("UFC", "fighter", "significant_strikes")] = [42, 55, 61]
    ufc = index.project(
        sport="UFC", player="Fighter", player_id="10",
        market="fighter significant strikes", line=50.5,
    )
    assert ufc is not None
    assert ufc.sample_size == 3

    index.multi_sport[("TENNIS", "player", "sets_won")] = [2, 0, 2]
    assert index.project(
        sport="TENNIS", player="Player", player_id="11",
        market="sets won", line=1.5,
    ) is None


def _basketball_row(points, minutes):
    # points, rebounds, assists, steals, blocks, turnovers, threes, minutes
    return (points, 4, 3, 1, 0, 2, 1, minutes)


def test_basketball_projection_decomposes_when_minutes_are_present() -> None:
    from datetime import datetime, timezone
    from services.baseline_projection_service import _HistoricalProjectionIndex

    index = _HistoricalProjectionIndex()
    index.loaded_at = datetime.now(timezone.utc)
    # A promotion: same scoring rate throughout, minutes nearly doubled.
    index.basketball[("NBA", "risingstarter")] = (
        [_basketball_row(12, 18)] * 5 + [_basketball_row(22, 34)] * 5
    )

    result = index.project(
        sport="NBA", player="Rising Starter", player_id="1",
        market="player_points", line=17.5,
    )

    assert result is not None
    assert result.decomposed is True
    assert result.projected_minutes is not None and result.projected_minutes > 30
    assert result.source == "historical-game-logs-minutes-rate"
    # A per-game blend still carries the bench games; minutes times rate does
    # not, so it projects nearer the current role.
    assert result.projection > 17.5


def test_basketball_falls_back_to_per_game_without_minutes() -> None:
    from datetime import datetime, timezone
    from services.baseline_projection_service import _HistoricalProjectionIndex

    index = _HistoricalProjectionIndex()
    index.loaded_at = datetime.now(timezone.utc)
    # Seven-column rows: no minutes recorded at all.
    index.basketball[("NBA", "nominutes")] = [(20, 4, 3, 1, 0, 2, 1)] * 10

    result = index.project(
        sport="NBA", player="No Minutes", player_id="2",
        market="player_points", line=18.5,
    )

    assert result is not None
    assert result.decomposed is False
    assert result.projected_minutes is None
    assert result.source == "historical-game-logs"
