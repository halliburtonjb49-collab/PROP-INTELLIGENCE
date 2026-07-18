from models.intelligence import ClosingLineValueRequest
from services.clv_service import american_implied_probability, closing_line_value


def test_over_beats_higher_closing_line() -> None:
    result = closing_line_value(ClosingLineValueRequest(
        side="OVER", entry_line=24.5, closing_line=26.5,
        entry_odds=100, closing_odds=-110,
    ))
    assert result["lineClv"] == 2
    assert result["beatClosingLine"] is True
    assert result["oddsClvProbabilityPoints"] > 0


def test_under_beats_lower_closing_line() -> None:
    result = closing_line_value(ClosingLineValueRequest(
        side="UNDER", entry_line=8.5, closing_line=7.5,
    ))
    assert result["lineClv"] == 1
    assert result["classification"] == "POSITIVE"


def test_zero_american_odds_is_invalid() -> None:
    try:
        american_implied_probability(0)
    except ValueError as error:
        assert "cannot be zero" in str(error)
    else:
        raise AssertionError("expected ValueError")
