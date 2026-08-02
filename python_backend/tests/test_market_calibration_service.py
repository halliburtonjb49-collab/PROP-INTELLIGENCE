from services.market_calibration_service import _eligible_adjustment, _key


def test_calibration_key_keeps_over_and_under_separate() -> None:
    over = _key("wnba", "Player Points", "Baseline-V1", "over")
    under = _key("wnba", "Player Points", "Baseline-V1", "under")

    assert over != under
    assert over == ("WNBA", "player points", "baseline-v1", "OVER")
    assert under[-1] == "UNDER"


def test_healthy_segment_is_not_recalibrated() -> None:
    assert _eligible_adjustment(
        predicted=0.53,
        actual=0.52,
        sample_size=500,
    ) == 0.0


def test_recalibrate_segment_receives_guarded_correction() -> None:
    assert _eligible_adjustment(
        predicted=0.533,
        actual=0.387,
        sample_size=4173,
    ) == -0.08


def test_collecting_segment_is_not_recalibrated() -> None:
    assert _eligible_adjustment(
        predicted=0.73,
        actual=0.89,
        sample_size=27,
    ) == 0.0
