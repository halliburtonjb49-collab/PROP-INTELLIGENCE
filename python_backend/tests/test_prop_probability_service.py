from math import exp
from random import Random

import pytest

from services.prop_probability_service import (
    _zero_inflated_parameters,
    blend_with_sharp_market,
    distribution_for_market,
    evaluate_market,
    expected_value,
    fractional_kelly_stake,
    choose_over_under,
    outcome_from_quantile,
    power_method_devig,
    projection_interval,
    prop_probabilities,
    shin_method_devig,
    student_t_cdf,
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


def _evaluation(probability: float, *, uncertainty: float = .02, ev: float | None = 3):
    from services.prop_probability_service import MarketEvaluation

    return MarketEvaluation(
        model_probability=probability,
        fair_probability=probability,
        market_probability=.5,
        push_probability=0,
        loss_probability=1 - probability,
        ev_percentage=ev,
        fair_decimal_odds=1 / probability,
        is_positive_ev=ev is not None and ev > 0,
        distribution="normal",
        market_weight=.25,
        uncertainty=uncertainty,
        calibration_adjustment=0,
        recommended_stake_fraction=0,
    )


def test_selector_compares_both_sides_and_can_choose_under() -> None:
    decision = choose_over_under(
        _evaluation(.40, uncertainty=.01),
        _evaluation(.60, uncertainty=.01),
    )
    assert decision.side == "UNDER"
    assert decision.confidence == 59


def test_selector_displays_uncertainty_adjusted_not_raw_confidence() -> None:
    decision = choose_over_under(
        _evaluation(.38, uncertainty=.02),
        _evaluation(.62, uncertainty=.03),
    )
    assert decision.side == "UNDER"
    assert decision.fair_probability == .62
    assert decision.uncertainty_adjusted_probability == .59
    assert decision.confidence == 59


def test_selector_abstains_when_signal_is_too_close_or_uncertain() -> None:
    assert choose_over_under(_evaluation(.51), _evaluation(.49)).side == "N/A"
    decision = choose_over_under(
        _evaluation(.60, uncertainty=.08), _evaluation(.40)
    )
    assert decision.side == "N/A"
    assert decision.reason == "uncertainty_overlaps_even_probability"


def test_selector_requires_positive_actionable_value_when_odds_exist() -> None:
    decision = choose_over_under(
        _evaluation(.62, uncertainty=.02, ev=.4),
        _evaluation(.38, uncertainty=.02, ev=-.4),
    )
    assert decision.side == "N/A"
    assert decision.reason == "expected_value_below_threshold"


def test_worked_example_matches_the_normal_reference_probability() -> None:
    # Projection 25.4, line 23.5, sigma 6.2 -> z = -0.306 -> P(Over) ~ 62%.
    result = prop_probabilities(
        projection=25.4,
        line=23.5,
        volatility=6.2,
        sport="NBA",
        market="Player Points",
        sample_size=30,
    )
    assert result.distribution == "normal"
    assert result.over == pytest.approx(.62, abs=.01)
    assert result.under == pytest.approx(.38, abs=.01)


def test_thin_sample_continuous_market_uses_fat_tailed_student_t() -> None:
    assert (
        distribution_for_market(
            "NBA", "Player Points", mean=25, variance=38, sample_size=9
        )
        == "student-t"
    )
    thin = prop_probabilities(
        projection=25.4, line=23.5, volatility=6.2,
        sport="NBA", market="Player Points", sample_size=9,
    )
    deep = prop_probabilities(
        projection=25.4, line=23.5, volatility=6.2,
        sport="NBA", market="Player Points", sample_size=30,
    )
    # Fatter tails move probability away from the favoured side, not toward it.
    assert .5 < thin.over < deep.over


def test_student_t_cdf_matches_known_reference_points() -> None:
    assert student_t_cdf(0, 10) == pytest.approx(.5, abs=1e-9)
    assert student_t_cdf(1.812, 10) == pytest.approx(.95, abs=1e-3)
    assert student_t_cdf(-1.812, 10) == pytest.approx(.05, abs=1e-3)
    assert student_t_cdf(2.228, 10) == pytest.approx(.975, abs=1e-3)


def test_yardage_uses_log_normal_and_keeps_the_right_tail() -> None:
    assert (
        distribution_for_market(
            "NFL", "Player Receiving Yards", mean=62, variance=900, sample_size=25
        )
        == "log-normal"
    )
    result = prop_probabilities(
        projection=62, line=62, volatility=30,
        sport="NFL", market="Player Receiving Yards", sample_size=25,
    )
    # Right skew puts the median below the mean, so a line at the mean is an
    # under, unlike the symmetric case where it would be exactly even.
    assert result.over < .5
    assert result.over + result.under == pytest.approx(1, abs=1e-5)


def test_excess_zeros_route_to_zero_inflated_poisson() -> None:
    assert (
        distribution_for_market(
            "NFL", "Player Touchdowns", mean=.6, variance=.9, zero_rate=.75
        )
        == "zero-inflated-poisson"
    )
    # A plain Poisson at this mean implies far fewer blanks than observed.
    assert (
        distribution_for_market(
            "NFL", "Player Touchdowns", mean=.6, variance=.9, zero_rate=.55
        )
        != "zero-inflated-poisson"
    )


def test_zero_inflation_lowers_the_over_relative_to_plain_poisson() -> None:
    inflated = prop_probabilities(
        projection=.6, line=.5, volatility=.95,
        sport="NFL", market="Player Touchdowns", zero_rate=.75,
    )
    plain = prop_probabilities(
        projection=.6, line=.5, volatility=.7,
        sport="NFL", market="Player Touchdowns",
    )
    assert inflated.distribution == "zero-inflated-poisson"
    assert inflated.over < plain.over
    assert inflated.over + inflated.under == pytest.approx(1, abs=1e-5)


def test_zero_inflated_parameters_reproduce_the_observed_zero_rate() -> None:
    inflation, rate = _zero_inflated_parameters(.6, .75)
    assert 0 < inflation < 1
    assert (1 - inflation) * rate == pytest.approx(.6, abs=1e-6)
    assert inflation + (1 - inflation) * exp(-rate) == pytest.approx(.75, abs=1e-6)


def test_projection_interval_brackets_the_projection() -> None:
    low, high = projection_interval(
        projection=25.4, volatility=6.2, distribution="normal",
    )
    assert low < 25.4 < high
    tighter, _ = projection_interval(
        projection=25.4, volatility=2.0, distribution="normal",
    )
    assert tighter > low


def test_interval_covers_every_supported_distribution() -> None:
    for distribution in (
        "normal",
        "student-t",
        "log-normal",
        "poisson",
        "negative-binomial",
        "zero-inflated-poisson",
    ):
        low, high = projection_interval(
            projection=6.0,
            volatility=2.5,
            distribution=distribution,
            sample_size=10,
            zero_rate=.2,
        )
        assert 0 <= low <= high, distribution


def test_evaluation_reports_both_sides_and_the_interval() -> None:
    evaluation = evaluate_market(
        projection=25.4,
        line=23.5,
        volatility=6.2,
        sport="NBA",
        market="Player Points",
        side="OVER",
        sample_size=30,
        model_calibrated=False,
        empirical_hit_rate=None,
        sharp_probability=None,
        decimal_odds=None,
    )
    assert evaluation.over_probability == pytest.approx(.62, abs=.01)
    assert evaluation.under_probability == pytest.approx(.38, abs=.01)
    assert evaluation.interval_low < 25.4 < evaluation.interval_high


def test_scoring_markets_stay_counts_despite_a_continuous_token() -> None:
    # "Passing touchdowns" names both a continuous and a counting concept. At
    # a mean under one it is a count, and a normal would misprice the 0.5 line.
    assert (
        distribution_for_market(
            "NFL", "Passing Touchdowns", mean=1.8, variance=1.9, sample_size=25
        )
        == "poisson"
    )
    assert (
        distribution_for_market(
            "NFL", "Rushing Touchdowns", mean=.6, variance=.7, sample_size=25
        )
        == "poisson"
    )
    # Yardage under the same tokens remains continuous.
    assert (
        distribution_for_market(
            "NFL", "Passing Yards", mean=268, variance=1225, sample_size=25
        )
        == "log-normal"
    )


def test_combination_markets_are_not_demoted_to_counts_by_a_token_match() -> None:
    assert (
        distribution_for_market(
            "NBA", "Points Rebounds Assists", mean=41, variance=64, sample_size=30
        )
        == "normal"
    )


def test_american_odds_convert_to_implied_probability() -> None:
    from calculations.prediction import american_to_implied_probability
    from services.prop_service import _american_to_implied_probability

    # -115 -> 115/215 = 53.49%; +110 -> 100/210 = 47.62%.
    assert american_to_implied_probability(-115) == pytest.approx(.5349, abs=1e-4)
    assert american_to_implied_probability(110) == pytest.approx(.4762, abs=1e-4)
    assert _american_to_implied_probability(-115) == pytest.approx(.5349, abs=1e-4)
    assert _american_to_implied_probability(110) == pytest.approx(.4762, abs=1e-4)


def test_raw_implied_probabilities_carry_the_margin_devig_removes() -> None:
    from calculations.prediction import american_to_implied_probability

    over = american_to_implied_probability(-115)
    under = american_to_implied_probability(-115)
    # Both sides at -115 sum past one; that excess is the book's margin.
    assert over + under == pytest.approx(1.0698, abs=1e-4)

    fair_over, fair_under = power_method_devig(over, under)
    assert fair_over + fair_under == pytest.approx(1)
    assert fair_over == pytest.approx(.5)
    assert fair_over < over


def test_expected_value_uses_profit_and_stake() -> None:
    # EV = P(win) * profit - P(loss) * stake, at 0.60/1.91 with no push:
    # .60 * .91 - .40 * 1 = .146
    result = expected_value(
        win_probability=.60,
        push_probability=0,
        decimal_odds=1.91,
    )
    assert result.expected_value == pytest.approx(.146, abs=1e-6)
    assert result.loss_probability == pytest.approx(.40)
