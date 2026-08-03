from services.basketball_matchup_ingestion_service import _market_value, _scheme_label


def test_market_value_keeps_combination_markets_separate() -> None:
    row = {"points": 20, "rebounds": 8, "assists": 6}
    assert _market_value("PLAYER POINTS", row) == 20
    assert _market_value("PLAYER POINTS REBOUNDS", row) == 28
    assert _market_value("PLAYER POINTS REBOUNDS ASSISTS", row) == 34


def test_scheme_label_does_not_claim_observed_tracking_data() -> None:
    assert _scheme_label(.70, .10) == "HIGH PICK-AND-ROLL PRESSURE PROXY"
    assert _scheme_label(.20, .40) == "SWITCH-HEAVY PROXY"
    assert _scheme_label(None, None) == ""
