import pytest

from services.confidence_service import (
    MAXIMUM_CONFIDENCE,
    MINIMUM_CONFIDENCE,
    assess_confidence,
    describe,
    uncertainty_multiplier,
)
from services.ensemble_projection_service import (
    HISTORICAL,
    MARKET,
    SIMULATION,
    combine,
    models_disagree,
    register_weights,
    weights_for,
)


def test_a_known_situation_keeps_its_confidence() -> None:
    assessment = assess_confidence(
        base_confidence=72,
        injury_status="healthy",
        lineup_status="confirmed_starter",
        sample_size=30,
        minutes_known=True,
        context_completeness=.9,
    )

    assert assessment.confidence == 72
    assert assessment.deductions == {}
    assert "Full confidence" in describe(assessment)


def test_seven_of_ten_games_does_not_survive_as_high_confidence() -> None:
    # The case the system exists to prevent: a strong-looking record on a
    # thin sample, an unconfirmed lineup and unknown minutes.
    assessment = assess_confidence(
        base_confidence=72,
        injury_status="unknown",
        lineup_status="unknown",
        sample_size=10,
        minutes_known=False,
    )

    assert assessment.confidence == 72 - 10 - 15 - 10
    assert set(assessment.deductions) == {
        "unconfirmed_lineup", "uncertain_minutes", "small_sample",
    }
    assert "lineup is not confirmed" in describe(assessment)


def test_doubtful_is_penalised_far_harder_than_questionable() -> None:
    questionable = assess_confidence(
        base_confidence=75, injury_status="questionable",
        lineup_status="confirmed", sample_size=30,
    )
    doubtful = assess_confidence(
        base_confidence=75, injury_status="doubtful",
        lineup_status="confirmed", sample_size=30,
    )

    assert questionable.confidence == 65
    assert doubtful.confidence == 50
    assert doubtful.confidence < questionable.confidence


def test_disagreeing_models_cost_confidence() -> None:
    agreeing = assess_confidence(
        base_confidence=70, lineup_status="confirmed", sample_size=30,
        models_disagree=False,
    )
    disagreeing = assess_confidence(
        base_confidence=70, lineup_status="confirmed", sample_size=30,
        models_disagree=True,
    )

    assert agreeing.confidence - disagreeing.confidence == 15


def test_stale_odds_suppress_rather_than_deduct() -> None:
    assessment = assess_confidence(
        base_confidence=80, lineup_status="confirmed", sample_size=40,
        odds_are_stale=True,
    )

    # A price that no longer exists cannot be acted on at any confidence.
    assert assessment.suppressed is True
    assert assessment.confidence == 0
    assert assessment.suppression_reason == "stale_odds"
    assert "stale" in describe(assessment)


def test_confidence_stays_within_its_bounds() -> None:
    floored = assess_confidence(
        base_confidence=40, injury_status="doubtful", lineup_status="unknown",
        sample_size=2, minutes_known=False, models_disagree=True,
        role_change="expanded", context_completeness=.2,
    )
    capped = assess_confidence(
        base_confidence=99, lineup_status="confirmed", sample_size=80,
    )

    assert floored.confidence == MINIMUM_CONFIDENCE
    assert capped.confidence == MAXIMUM_CONFIDENCE


def test_a_role_change_widens_uncertainty_rather_than_only_deducting() -> None:
    steady = assess_confidence(
        base_confidence=70, lineup_status="confirmed", sample_size=30,
    )
    changed = assess_confidence(
        base_confidence=70, lineup_status="confirmed", sample_size=30,
        role_change="expanded", minutes_known=False,
    )

    assert uncertainty_multiplier(steady) == 1.0
    assert uncertainty_multiplier(changed) > 1.3


def test_ensemble_weights_the_members_that_contributed() -> None:
    ensemble = combine(
        {HISTORICAL: 24.0, SIMULATION: 26.0, MARKET: 25.0},
        sport="NBA", market="Points",
    )

    assert ensemble is not None
    assert 24.0 < ensemble.projection < 26.0
    assert set(ensemble.contributing) == {HISTORICAL, SIMULATION, MARKET}
    assert sum(ensemble.applied_weights.values()) == pytest.approx(1.0, abs=1e-3)


def test_a_missing_member_is_dropped_not_counted_as_zero() -> None:
    ensemble = combine(
        {HISTORICAL: 25.0, SIMULATION: None, MARKET: 25.0},
        sport="NBA", market="Points",
    )

    assert ensemble is not None
    # Treating the absent member as a projection of zero would halve this.
    assert ensemble.projection == pytest.approx(25.0, abs=1e-3)
    assert SIMULATION not in ensemble.contributing


def test_no_members_yields_nothing_rather_than_an_average_of_nothing() -> None:
    assert combine({HISTORICAL: None, MARKET: None}) is None


def test_members_carrying_no_configured_weight_still_produce_a_projection() -> None:
    from services.ensemble_projection_service import BAYESIAN, GRADIENT_BOOSTING

    # Both default to zero weight; an equal split beats returning nothing.
    ensemble = combine({GRADIENT_BOOSTING: 20.0, BAYESIAN: 30.0})

    assert ensemble is not None
    assert ensemble.projection == pytest.approx(25.0, abs=1e-3)


def test_disagreement_is_relative_so_it_compares_across_markets() -> None:
    # Two points apart on a 25-point line is agreement; the same two points
    # on a 2.5-strikeout line is not.
    points = combine({HISTORICAL: 24.0, SIMULATION: 26.0})
    strikeouts = combine({HISTORICAL: 1.5, SIMULATION: 3.5})

    assert points is not None and strikeouts is not None
    assert points.disagreement == strikeouts.disagreement
    assert strikeouts.relative_disagreement > points.relative_disagreement
    assert models_disagree(points) is False
    assert models_disagree(strikeouts) is True


def test_a_lone_model_is_not_treated_as_consensus() -> None:
    solo = combine({HISTORICAL: 25.0})
    assert solo is not None
    # It cannot disagree, but that is not evidence of agreement either.
    assert models_disagree(solo) is False
    assert solo.contributing == (HISTORICAL,)


def test_registered_weights_beat_the_default_for_that_market_only() -> None:
    register_weights(
        "NBA", "Player Threes",
        {HISTORICAL: 0.2, SIMULATION: 0.3, MARKET: 0.5},
    )

    threes = weights_for("NBA", "Player Threes")
    points = weights_for("NBA", "Player Points")

    assert threes[MARKET] == pytest.approx(0.5, abs=1e-3)
    assert points[MARKET] != pytest.approx(0.5, abs=1e-3)


def test_unknown_ensemble_members_are_rejected() -> None:
    with pytest.raises(ValueError):
        register_weights("NBA", "Points", {"psychic": 1.0})
