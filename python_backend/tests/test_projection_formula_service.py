import pytest

from services.projection_formula_service import (
    blend_projection_with_market,
    pace_adjusted_projection,
    process_projection,
)


def test_process_projection_models_volume_before_conversion() -> None:
    assert process_projection(
        opportunities=18,
        efficiency_per_opportunity=1.4,
        quality_multiplier=.95,
        conversion_multiplier=1.02,
    ) == 24.4188


def test_pace_adjustment_uses_both_teams_and_clamps_bad_extremes() -> None:
    assert pace_adjusted_projection(
        baseline=30,
        team_pace=100,
        opponent_pace=110,
        league_average_pace=100,
    ) == 31.5
    assert pace_adjusted_projection(
        baseline=30,
        team_pace=200,
        opponent_pace=200,
        league_average_pace=100,
    ) == 34.5


def test_market_blend_is_adaptive_and_requires_multiple_books() -> None:
    uncertain = blend_projection_with_market(
        custom_projection=30,
        market_origin_line=24,
        market_book_count=5,
        sample_size=0,
        calibrated=False,
    )
    reliable = blend_projection_with_market(
        custom_projection=30,
        market_origin_line=24,
        market_book_count=5,
        sample_size=40,
        calibrated=True,
    )
    single_book = blend_projection_with_market(
        custom_projection=30,
        market_origin_line=24,
        market_book_count=1,
        sample_size=0,
        calibrated=False,
    )

    assert uncertain.projection == 28.2
    assert uncertain.market_weight == .3
    assert reliable.projection == 29.52
    assert reliable.market_weight == .08
    assert single_book.projection == 30
    assert single_book.market_weight == 0


def test_pace_formula_rejects_missing_denominator() -> None:
    with pytest.raises(ValueError):
        pace_adjusted_projection(
            baseline=20,
            team_pace=100,
            opponent_pace=100,
            league_average_pace=0,
        )
