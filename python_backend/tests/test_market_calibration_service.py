from services.market_calibration_service import _key


def test_calibration_key_keeps_over_and_under_separate() -> None:
    over = _key("wnba", "Player Points", "Baseline-V1", "over")
    under = _key("wnba", "Player Points", "Baseline-V1", "under")

    assert over != under
    assert over == ("WNBA", "player points", "baseline-v1", "OVER")
    assert under[-1] == "UNDER"
