from services.baseline_projection_service import (
    MODEL_VERSION,
    baseline_is_actionable,
    basketball_market_value,
    compute_baseline_projection,
    role_bucket_prior,
)
from services.prop_probability_service import evaluate_market


def test_historical_index_reuses_fresh_shared_cache(monkeypatch) -> None:
    from datetime import datetime, timezone
    from services import baseline_projection_service as service

    generated = datetime.now(timezone.utc).isoformat()
    monkeypatch.setattr(service, "database_is_configured", lambda: True)
    monkeypatch.setattr(service, "get_compressed_json", lambda _key: {
        "version": 1,
        "generatedAt": generated,
        "basketball": [["WNBA", "player", [[20, 5, 4, 1, 0, 2, 1, 32]]]],
        "mlb": [["pitcher:7", "strikeouts", [5, 6, 7]]],
        "multiSport": [["NFL", "receiver", "receiving_yards", [60, 70]]],
    })
    monkeypatch.setattr(
        service,
        "get_database_pool",
        lambda: (_ for _ in ()).throw(AssertionError("database should not load")),
    )

    index = service._HistoricalProjectionIndex()
    index.ensure_loaded()

    assert index.basketball[("WNBA", "player")][0][0] == 20
    assert index.mlb[("pitcher:7", "strikeouts")] == [5.0, 6.0, 7.0]
    assert index.multi_sport[("NFL", "receiver", "receiving_yards")] == [60.0, 70.0]


def test_historical_index_rejects_stale_shared_cache(monkeypatch) -> None:
    from datetime import datetime, timedelta, timezone
    from services import baseline_projection_service as service

    monkeypatch.setattr(service, "get_compressed_json", lambda _key: {
        "version": 1,
        "generatedAt": (datetime.now(timezone.utc) - timedelta(hours=2)).isoformat(),
        "basketball": [["WNBA", "stale", [[1, 1, 1, 1, 1, 1, 1]]]],
        "mlb": [],
        "multiSport": [],
    })
    index = service._HistoricalProjectionIndex()

    assert index._load_shared() is False
    assert index.basketball == {}


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


def test_sustained_recent_form_raises_confidence_over_season_only_rate() -> None:
    improving = compute_baseline_projection(
        ([18] * 20) + ([24] * 20), line=20.5, sport="WNBA", market="Points"
    )

    assert improving is not None
    season_only = evaluate_market(
        projection=improving.projection,
        line=20.5,
        volatility=improving.volatility,
        side="OVER",
        sample_size=improving.sample_size,
        sport="WNBA",
        market="Points",
        empirical_hit_rate=improving.historical_hit_rate / 100,
        model_calibrated=False,
        sharp_probability=None,
        decimal_odds=None,
    )
    assert improving.historical_hit_rate == 50
    assert improving.recent_hit_rate > improving.historical_hit_rate
    assert improving.hit_probability > season_only.model_probability
    assert improving.confidence <= 80




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


def test_basketball_projection_decomposes_when_minutes_are_present(monkeypatch) -> None:
    from datetime import datetime, timezone
    from services import baseline_projection_service
    from services.baseline_projection_service import _HistoricalProjectionIndex

    # Off in production: the walk-forward backtest found no accuracy gain.
    # The path is still exercised so the experiment can be rerun.
    monkeypatch.setattr(
        baseline_projection_service, "MINUTES_DECOMPOSITION_ENABLED", True
    )
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


def test_basketball_is_per_game_by_default() -> None:
    """The shipped default after the backtest: no decomposition."""

    from datetime import datetime, timezone
    from services.baseline_projection_service import _HistoricalProjectionIndex

    index = _HistoricalProjectionIndex()
    index.loaded_at = datetime.now(timezone.utc)
    index.basketball[("NBA", "anyplayer")] = (
        [_basketball_row(12, 18)] * 5 + [_basketball_row(22, 34)] * 5
    )

    result = index.project(
        sport="NBA", player="Any Player", player_id="1",
        market="player_points", line=17.5,
    )

    assert result is not None
    assert result.decomposed is False
    assert result.source == "historical-game-logs"


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


def test_nfl_and_nhl_markets_project_from_stored_logs() -> None:
    from datetime import datetime, timezone
    from services.baseline_projection_service import _HistoricalProjectionIndex

    index = _HistoricalProjectionIndex()
    index.loaded_at = datetime.now(timezone.utc)
    index.multi_sport[("NFL", "wrthree", "receiving_yards")] = [
        62, 78, 55, 91, 70, 84, 66, 73, 88, 59,
    ]
    index.multi_sport[("NHL", "winger", "shots_on_goal")] = [3, 4, 2, 5, 3, 4, 3, 2, 4, 3]

    receiving = index.project(
        sport="NFL", player="WR Three", player_id="3",
        market="player_receiving_yards", line=68.5,
    )
    shots = index.project(
        sport="NHL", player="Winger", player_id="21",
        market="player_shots_on_goal", line=2.5,
    )

    assert receiving is not None and receiving.projection > 0
    assert shots is not None and shots.projection > 2.5


def test_unmapped_gridiron_markets_stay_unprojected() -> None:
    from datetime import datetime, timezone
    from services.baseline_projection_service import _HistoricalProjectionIndex

    index = _HistoricalProjectionIndex()
    index.loaded_at = datetime.now(timezone.utc)
    index.multi_sport[("NFL", "kicker", "field_goals")] = [2] * 10

    # Matching an unrecognised market to some other stat would measure the
    # wrong thing, so it stays unprojected.
    assert index.project(
        sport="NFL", player="Kicker", player_id="7",
        market="player_field_goals_made", line=1.5,
    ) is None
