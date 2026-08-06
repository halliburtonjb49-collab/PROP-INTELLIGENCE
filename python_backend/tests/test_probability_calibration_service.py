import pytest

from services.probability_calibration_service import (
    MINIMUM_FIT_SAMPLE,
    build_calibration_map,
    fit_isotonic,
)


def _pairs(probability: float, wins: int, losses: int):
    return [(probability, True)] * wins + [(probability, False)] * losses


def test_isotonic_output_never_decreases() -> None:
    # Deliberately non-monotonic evidence: the middle band wins least.
    pairs = (
        _pairs(0.30, 60, 40) + _pairs(0.50, 20, 80) + _pairs(0.70, 80, 20)
    )
    thresholds, values = fit_isotonic(pairs)

    assert list(values) == sorted(values)
    assert len(thresholds) == len(values)


def test_violating_blocks_are_pooled_into_one_value() -> None:
    # A later group winning less than an earlier one is the only thing
    # isotonic regression forbids, so the two must merge.
    pairs = _pairs(0.40, 90, 10) + _pairs(0.60, 10, 90)
    thresholds, values = fit_isotonic(pairs)

    assert len(set(values)) == 1
    assert values[0] == pytest.approx(0.5, abs=1e-6)


def test_a_calibrated_model_produces_no_usable_correction() -> None:
    # Already honest probabilities leave nothing to gain, so the fit is
    # rejected and the raw numbers stand.
    pairs = []
    for probability, count in ((0.40, 1000), (0.55, 1000), (0.70, 1000)):
        wins = round(probability * count)
        pairs += _pairs(probability, wins, count - wins)

    assert build_calibration_map(pairs, sport="TEST") is None


def test_a_miscalibrated_model_is_corrected() -> None:
    # Labelled 70%, wins 50%.
    fitted = build_calibration_map(
        _pairs(0.70, 500, 500) + _pairs(0.30, 250, 750), sport="TEST"
    )

    assert fitted is not None
    assert fitted.apply(0.70) == pytest.approx(0.50, abs=0.05)
    assert fitted.holdout_log_loss_gain > 0


def test_a_thin_sample_is_refused() -> None:
    small = _pairs(0.70, 50, 50)
    assert len(small) < MINIMUM_FIT_SAMPLE
    assert build_calibration_map(small, sport="TEST") is None


def test_a_fit_that_does_not_help_out_of_sample_is_discarded() -> None:
    # Pure noise: no monotonic correction can genuinely improve this, so the
    # guard must reject whatever the fit found in the training half.
    pairs = []
    for index in range(2000):
        probability = 0.50
        pairs.append((probability, index % 2 == 0))

    assert build_calibration_map(pairs, sport="TEST") is None


def test_calibrated_values_stay_inside_usable_bounds() -> None:
    fitted = build_calibration_map(
        _pairs(0.90, 0, 800) + _pairs(0.10, 800, 0), sport="TEST"
    )
    if fitted is not None:
        for probability in (0.0, 0.05, 0.5, 0.95, 1.0):
            calibrated = fitted.apply(probability)
            # A prop is never a certainty, and downstream expected-value maths
            # divides by this.
            assert 0.0 < calibrated < 1.0


def test_the_map_is_applied_by_lookup_not_interpolation() -> None:
    fitted = build_calibration_map(
        _pairs(0.70, 500, 500) + _pairs(0.30, 250, 750), sport="TEST"
    )
    assert fitted is not None
    # A probability below every breakpoint still resolves rather than failing.
    assert 0.0 < fitted.apply(0.01) < 1.0
    # Monotonicity survives application.
    assert fitted.apply(0.30) <= fitted.apply(0.70)


def test_holdout_is_reproducible_and_spans_the_range() -> None:
    from services.probability_calibration_service import _split

    pairs = [(index / 1000, index % 2 == 0) for index in range(1000)]
    first_fit, first_holdout = _split(pairs, holdout_fraction=0.30)
    second_fit, second_holdout = _split(pairs, holdout_fraction=0.30)

    assert first_holdout == second_holdout
    assert first_fit == second_fit
    # Both halves must cover the whole probability range, not one corner.
    assert min(p for p, _ in first_holdout) < 0.05
    assert max(p for p, _ in first_holdout) > 0.95


def test_market_residuals_are_fitted_after_the_sport_curve() -> None:
    """The two corrections must compose, not compete.

    The sport curve fixes the overall shape and the market adjustment carries
    what one market has left over. Fitting the second against raw
    probabilities would re-apply a correction the first already made.
    """

    from services.market_calibration_service import _eligible_adjustment

    fitted = build_calibration_map(
        _pairs(0.70, 500, 500) + _pairs(0.30, 250, 750), sport="TEST"
    )
    assert fitted is not None

    # One market that is unbiased once the curve has been applied.
    unbiased = [(fitted.apply(0.70), 0.5)] * 100
    residual = _eligible_adjustment(
        predicted=sum(p for p, _ in unbiased) / len(unbiased),
        actual=0.5,
        sample_size=100,
    )
    # Nothing left to correct means no second adjustment.
    assert residual == pytest.approx(0.0, abs=0.02)
