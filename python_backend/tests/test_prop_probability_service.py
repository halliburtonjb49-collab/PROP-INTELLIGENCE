from random import Random

import pytest

from services.prop_probability_service import (
    blend_with_sharp_market,
    distribution_for_market,
    evaluate_market,
    expected_value,
    fractional_kelly_stake,
    outcome_from_quantile,
    power_method_devig,
    prop_probabilities,
    shin_method_devig,
)


def test_poisson_half_line_probabilities_have_no_push() -> None:
    result = prop_probabilities(
        projection=5.2,
        line=4.5,
        volatility=2.0,
        sport="MLB",
        market="Pitcher Strikeouts",
    )
    assert result.distribution == "poisson"
    assert result.push == 0
    assert result.over + result.under == pytest.approx(1, abs=1e-5)
    assert result.over > .5


def test_integer_line_has_explicit_push_mass() -> None:
    result = prop_probabilities(
        projection=4,
        line=4,
        volatility=2,
        sport="MLB",
        market="Pitcher Strikeouts",
    )
    assert result.push > 0
    assert result.over + result.under + result.push == pytest.approx(1, abs=1e-5)


def test_overdispersion_routes_count_market_to_negative_binomial() -> None:
    assert (
        distribution_for_market(
            "NBA", "Player Rebounds", mean=8, variance=20
        )
        == "negative-binomial"
    )


def test_high_scoring_points_use_normal_distribution() -> None:
    assert (
        distribution_for_market("NBA", "Player Points", mean=24, variance=30)
        == "normal"
    )


def test_push_aware_expected_value() -> None:
    result = expected_value(
        win_probability=.52,
        push_probability=.08,
        decimal_odds=1.91,
    )
    assert result.loss_probability == .40
    assert result.expected_value == pytest.approx(.0732)
    assert result.fair_decimal_odds == pytest.approx(1.7692)


def test_market_blend_trusts_market_more_for_small_uncalibrated_sample() -> None:
    _, small_weight = blend_with_sharp_market(
        .65, .52, sample_size=5, model_calibrated=False
    )
    _, mature_weight = blend_with_sharp_market(
        .65, .52, sample_size=100, model_calibrated=True
    )
    assert small_weight > mature_weight


def test_full_market_evaluation_populates_ev_and_audit_fields() -> None:
    result = evaluate_market(
        projection=6.2,
        line=4.5,
        volatility=2,
        sport="MLB",
        market="Pitcher Strikeouts",
        side="OVER",
        sample_size=20,
        model_calibrated=True,
        empirical_hit_rate=.60,
        sharp_probability=.53,
        decimal_odds=1.91,
    )
    assert result.distribution == "poisson"
    assert 0 < result.fair_probability < 1
    assert result.ev_percentage is not None
    assert result.fair_decimal_odds is not None
    assert 0 <= result.market_weight <= 1


def test_quantile_sampling_preserves_discrete_outputs() -> None:
    values = [
        outcome_from_quantile(
            Random(7).random(),
            projection=5,
            volatility=2,
            distribution="poisson",
        )
        for _ in range(5)
    ]
    assert all(value.is_integer() for value in values)


def test_power_method_devig_removes_market_margin() -> None:
    over, under = power_method_devig(115 / 215, 115 / 215)
    assert over + under == pytest.approx(1)
    assert over == pytest.approx(.5)


def test_power_method_devig_handles_asymmetric_prices() -> None:
    over, under = power_method_devig(120 / 220, 100 / 210)
    assert over + under == pytest.approx(1)
    assert over > under


def test_shin_method_devig_removes_margin_and_favorite_longshot_bias() -> None:
    fair = shin_method_devig(0.60, 0.30, 0.15)
    assert len(fair) == 3
    assert sum(fair) == pytest.approx(1)
    assert fair[0] > fair[1] > fair[2]
    assert fair[2] < 0.15 / 1.05


def test_shin_method_normalizes_market_without_positive_overround() -> None:
    fair = shin_method_devig(0.48, 0.47)
    assert sum(fair) == pytest.approx(1)


def test_fractional_kelly_only_sizes_positive_expected_value() -> None:
    assert fractional_kelly_stake(
        win_probability=.60,
        decimal_odds=1.91,
    ) == pytest.approx(.04011, abs=1e-5)
    assert fractional_kelly_stake(
        win_probability=.50,
        decimal_odds=1.91,
    ) == 0
