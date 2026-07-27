from types import SimpleNamespace

from services.projection_calibration_service import (
    ProjectionContext,
    calibrated_hit_probability,
    contextual_projection,
    exponentially_weighted_mean,
)
from services.prop_context_service import apply_projection_context


def test_probability_uses_market_volatility_and_sample_shrinkage() -> None:
    small = calibrated_hit_probability(
        projection=6,
        line=4,
        volatility=.4,
        side="OVER",
        sample_size=8,
        sport="MLB",
        market="Pitcher Strikeouts",
    )
    mature = calibrated_hit_probability(
        projection=6,
        line=4,
        volatility=.4,
        side="OVER",
        sample_size=40,
        sport="MLB",
        market="Pitcher Strikeouts",
    )
    assert .5 < small < mature <= .8


def test_exponential_average_responds_to_recent_form_without_discarding_history() -> None:
    values = [2, 2, 2, 2, 2, 8, 8, 8]
    weighted = exponentially_weighted_mean(values)
    assert sum(values) / len(values) < weighted < 8


def test_context_multiplier_is_bounded() -> None:
    assert contextual_projection(
        10,
        ProjectionContext(workload_multiplier=.5, opponent_multiplier=.5),
    ) == 6.5
    assert contextual_projection(
        10,
        ProjectionContext(workload_multiplier=2, opponent_multiplier=2),
    ) == 13.5


def test_prop_context_recalculates_projection_probability_and_side() -> None:
    prop = SimpleNamespace(
        projection=5.5,
        line=5,
        injuryStatus="questionable",
        lineupStatus="confirmed",
        fatigueMultiplier=.95,
        matchupMultiplier=1.1,
        projectionVolatility=1.5,
        projectionSampleSize=20,
        historicalHitRate=60,
        sport="MLB",
        market="Pitcher Strikeouts",
        recommendationAvailable=True,
    )
    apply_projection_context(prop)
    assert prop.projection != 5.5
    assert .5 <= prop.fairProbability <= .8
    assert prop.recommendedSide in {"Over", "Under"}
