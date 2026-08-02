import pytest

from models.intelligence import ClosingLineValueRequest
from services.clv_service import (
    american_implied_probability,
    closing_line_value,
    odds_clv_expected_value,
    vig_free_probability,
)


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


def test_vig_free_clv_matches_documented_example() -> None:
    assert vig_free_probability(-145, 125) == pytest.approx(.5711, abs=.0001)
    assert odds_clv_expected_value(-110, -145, 125) == pytest.approx(.0903, abs=.0002)


def test_clv_response_exposes_expected_value_when_both_close_sides_exist() -> None:
    result = closing_line_value(ClosingLineValueRequest(
        side="OVER", entry_line=20.5, closing_line=20.5,
        entry_odds=-110, closing_odds=-145, closing_opposite_odds=125,
    ))
    assert result["closingNoVigProbability"] == pytest.approx(.5711, abs=.0001)
    assert result["oddsClvExpectedValuePercent"] == pytest.approx(9.03, abs=.02)
