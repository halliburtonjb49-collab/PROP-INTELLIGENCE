import pytest

from services.score_probability_service import (
    dixon_coles_matrix,
    dixon_coles_tau,
    dixon_coles_totals,
)


def test_dixon_coles_tau_adjusts_only_low_scores() -> None:
    assert dixon_coles_tau(0, 0, 1.5, 1.1, -0.08) > 1
    assert dixon_coles_tau(1, 1, 1.5, 1.1, -0.08) > 1
    assert dixon_coles_tau(2, 1, 1.5, 1.1, -0.08) == 1


def test_dixon_coles_matrix_is_normalized_and_totals_partition_mass() -> None:
    matrix = dixon_coles_matrix(1.55, 1.05, -0.07)
    assert sum(sum(row) for row in matrix) == pytest.approx(1)
    result = dixon_coles_totals(1.55, 1.05, -0.07, 2.5)
    assert result["pushProbability"] == 0
    assert result["overProbability"] + result["underProbability"] == pytest.approx(1)
    assert result["method"] == "dixon-coles"


def test_dixon_coles_rejects_rho_that_creates_negative_probability() -> None:
    with pytest.raises(ValueError):
        dixon_coles_matrix(3.0, 3.0, 0.2)
