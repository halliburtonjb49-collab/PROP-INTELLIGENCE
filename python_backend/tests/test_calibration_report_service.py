import pytest

from services.calibration_report_service import (
    MINIMUM_BUCKET_SAMPLE,
    build_calibration_report,
    report_as_dict,
)


def _perfect(probability: float, count: int) -> list[tuple[float, bool]]:
    """A bin whose observed rate matches its label exactly."""

    wins = round(probability * count)
    return [(probability, True)] * wins + [(probability, False)] * (count - wins)


def test_a_perfectly_calibrated_model_has_no_error() -> None:
    predictions = (
        _perfect(0.52, 200) + _perfect(0.62, 200) + _perfect(0.72, 200)
    )
    report = build_calibration_report(predictions)

    assert report.expected_calibration_error == pytest.approx(0, abs=0.005)
    assert report.direction == "calibrated"


def test_an_overconfident_model_is_named_as_one() -> None:
    # Labelled 70%, wins 50%.
    predictions = [(0.70, True)] * 100 + [(0.70, False)] * 100
    report = build_calibration_report(predictions)

    assert report.direction == "overconfident"
    assert report.expected_calibration_error == pytest.approx(0.20, abs=0.01)
    assert report.buckets[0].gap > 0


def test_an_underconfident_model_is_named_as_one() -> None:
    predictions = [(0.35, True)] * 120 + [(0.35, False)] * 80
    report = build_calibration_report(predictions)

    assert report.direction == "underconfident"
    assert report.buckets[0].gap < 0


def test_offsetting_errors_do_not_cancel_in_the_error_measure() -> None:
    # One bin runs hot and another runs cold by the same amount. The averages
    # agree while both bins are wrong, which is the failure a single overall
    # number hides.
    predictions = (
        [(0.70, True)] * 50 + [(0.70, False)] * 50
        + [(0.30, True)] * 50 + [(0.30, False)] * 50
    )
    report = build_calibration_report(predictions)

    assert report.overall_predicted == pytest.approx(
        report.overall_observed, abs=0.01
    )
    assert report.direction == "calibrated"
    # Absolute gaps are summed, so the error survives.
    assert report.expected_calibration_error == pytest.approx(0.20, abs=0.01)


def test_error_is_weighted_by_how_many_predictions_a_bin_holds() -> None:
    # A badly wrong bin holding few picks cannot outweigh a good one holding
    # many.
    predictions = _perfect(0.55, 1000) + (
        [(0.85, False)] * 40
    )
    report = build_calibration_report(predictions)

    assert report.maximum_calibration_error > 0.8
    assert report.expected_calibration_error < 0.05


def test_thin_bins_are_reported_but_not_judged() -> None:
    predictions = _perfect(0.55, 500) + [(0.95, False)] * 5
    report = build_calibration_report(predictions)

    thin = [bucket for bucket in report.buckets if not bucket.judged]
    assert thin and thin[0].sample_size < MINIMUM_BUCKET_SAMPLE
    # A five-pick bin must not drive the headline error.
    assert report.expected_calibration_error < 0.02
    assert report.judged_sample_size == 500


def test_a_gap_inside_sampling_noise_is_not_called_miscalibration() -> None:
    # Thirty picks at 50% can land several points off by luck alone.
    predictions = [(0.50, True)] * 17 + [(0.50, False)] * 16
    report = build_calibration_report(predictions)

    bucket = report.buckets[0]
    assert bucket.judged is True
    assert bucket.is_miscalibrated is False


def test_a_gap_beyond_sampling_noise_is_flagged() -> None:
    predictions = [(0.50, True)] * 100 + [(0.50, False)] * 900
    report = build_calibration_report(predictions)

    assert report.buckets[0].is_miscalibrated is True


def test_bucket_width_controls_resolution() -> None:
    predictions = _perfect(0.52, 100) + _perfect(0.58, 100)
    coarse = build_calibration_report(predictions, bucket_width=0.10)
    fine = build_calibration_report(predictions, bucket_width=0.05)

    assert len(fine.buckets) > len(coarse.buckets)


def test_the_top_of_the_range_stays_in_the_last_bin() -> None:
    report = build_calibration_report([(1.0, True)] * 50, bucket_width=0.10)
    assert len(report.buckets) == 1
    assert report.buckets[0].upper == pytest.approx(1.0)


def test_scores_are_computed_alongside_the_curve() -> None:
    report = build_calibration_report(_perfect(0.50, 400))

    # A coin flip called at even money.
    assert report.brier_score == pytest.approx(0.25, abs=0.01)
    assert report.log_loss == pytest.approx(0.693, abs=0.01)


def test_certainty_that_is_wrong_does_not_produce_infinite_loss() -> None:
    report = build_calibration_report([(1.0, False), (0.0, True)])
    assert report.log_loss is not None
    assert report.log_loss < 1e6


def test_no_graded_predictions_yields_an_empty_report() -> None:
    report = build_calibration_report([])

    assert report.sample_size == 0
    assert report.expected_calibration_error is None
    assert report.direction == "unknown"
    assert report_as_dict(report)["buckets"] == []


def test_report_serialises_for_the_operations_endpoint() -> None:
    payload = report_as_dict(build_calibration_report(_perfect(0.60, 200)))

    assert payload["sampleSize"] == 200
    assert payload["buckets"][0]["range"] == "0.60-0.65"
    assert set(payload["buckets"][0]) >= {
        "range", "sampleSize", "predicted", "observed", "gap", "judged",
    }


def test_a_prediction_lands_in_the_bin_its_label_names() -> None:
    # 0.60 / 0.05 is just under twelve in binary, which would file a prediction
    # of exactly 0.60 one bin below its own label.
    for probability in (0.55, 0.60, 0.65, 0.70, 0.75, 0.80):
        report = build_calibration_report([(probability, True)] * 40)
        bucket = report.buckets[0]
        assert bucket.lower <= probability < bucket.upper or bucket.upper == 1.0
        assert bucket.lower == pytest.approx(probability, abs=1e-6)


def test_the_highest_bin_is_not_clamped_away() -> None:
    report = build_calibration_report([(0.97, True)] * 40, bucket_width=0.05)
    bucket = report.buckets[0]
    assert bucket.lower == pytest.approx(0.95)
    assert bucket.upper == pytest.approx(1.0)


def test_served_picks_are_judged_separately_from_every_evaluated_prop() -> None:
    from services.calibration_report_service import served_pick_performance

    # Most evaluated props never clear the gate. Judging the product by all of
    # them mistakes the model's scratch paper for its output.
    predictions = (
        [(0.51, False)] * 800 + [(0.51, True)] * 700
        + [(0.62, True)] * 62 + [(0.62, False)] * 38
    )
    result = served_pick_performance(predictions, release_threshold=0.58)

    assert result["evaluated"] == 1600
    assert result["served"] == 100
    assert result["observedWinRate"] == pytest.approx(0.62)
    assert result["profitable"] is True


def test_a_gate_nothing_clears_reports_no_served_picks() -> None:
    from services.calibration_report_service import served_pick_performance

    result = served_pick_performance([(0.50, True)] * 100, release_threshold=0.58)
    assert result["served"] == 0
    assert result["observedWinRate"] is None


def test_served_picks_below_break_even_are_flagged_unprofitable() -> None:
    from services.calibration_report_service import served_pick_performance

    result = served_pick_performance(
        [(0.60, True)] * 50 + [(0.60, False)] * 50, release_threshold=0.58
    )
    assert result["observedWinRate"] == pytest.approx(0.50)
    assert result["profitable"] is False
    assert result["marginOverBreakEven"] < 0
