from services.prediction_automation_service import prediction_clv


def test_prediction_clv_rewards_better_over_and_under_lines() -> None:
    assert prediction_clv("OVER", 22.5, 23.5) == {
        "closingLine": 23.5,
        "lineClvPoints": 1.0,
        "beatClosingLine": True,
    }
    assert prediction_clv("UNDER", 8.5, 7.5)["beatClosingLine"] is True


def test_prediction_clv_marks_worse_line_negative() -> None:
    result = prediction_clv("OVER", 22.5, 21.5)
    assert result["lineClvPoints"] == -1.0
    assert result["beatClosingLine"] is False
