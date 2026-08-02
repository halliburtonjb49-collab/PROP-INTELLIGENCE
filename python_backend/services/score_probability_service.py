"""Dixon-Coles low-score correction for soccer and hockey score markets."""

from __future__ import annotations

from math import exp, factorial


def _poisson(value: int, expected: float) -> float:
    return exp(-expected) * expected**value / factorial(value)


def dixon_coles_tau(
    home_goals: int,
    away_goals: int,
    home_expected_goals: float,
    away_expected_goals: float,
    rho: float,
) -> float:
    if home_goals == 0 and away_goals == 0:
        return 1 - home_expected_goals * away_expected_goals * rho
    if home_goals == 0 and away_goals == 1:
        return 1 + home_expected_goals * rho
    if home_goals == 1 and away_goals == 0:
        return 1 + away_expected_goals * rho
    if home_goals == 1 and away_goals == 1:
        return 1 - rho
    return 1.0


def dixon_coles_matrix(
    home_expected_goals: float,
    away_expected_goals: float,
    rho: float,
    *,
    max_goals: int = 8,
) -> list[list[float]]:
    home_xg = float(home_expected_goals)
    away_xg = float(away_expected_goals)
    if home_xg <= 0 or away_xg <= 0:
        raise ValueError("Expected goals must be positive")
    if max_goals < 2 or max_goals > 15:
        raise ValueError("max_goals must be between 2 and 15")
    low_score_taus = (
        1 - home_xg * away_xg * rho,
        1 + home_xg * rho,
        1 + away_xg * rho,
        1 - rho,
    )
    if any(value <= 0 for value in low_score_taus):
        raise ValueError("rho is outside the valid range for these expected goals")

    matrix = [
        [
            dixon_coles_tau(home, away, home_xg, away_xg, rho)
            * _poisson(home, home_xg)
            * _poisson(away, away_xg)
            for away in range(max_goals + 1)
        ]
        for home in range(max_goals + 1)
    ]
    retained_mass = sum(sum(row) for row in matrix)
    if retained_mass <= 0:
        raise ValueError("Dixon-Coles matrix has no probability mass")
    return [[value / retained_mass for value in row] for row in matrix]


def dixon_coles_totals(
    home_expected_goals: float,
    away_expected_goals: float,
    rho: float,
    line: float,
    *,
    max_goals: int = 8,
) -> dict[str, object]:
    if line < 0:
        raise ValueError("Total line cannot be negative")
    matrix = dixon_coles_matrix(
        home_expected_goals, away_expected_goals, rho, max_goals=max_goals
    )
    over = under = push = 0.0
    scorelines: list[dict[str, object]] = []
    for home, row in enumerate(matrix):
        for away, probability in enumerate(row):
            total = home + away
            if total > line:
                over += probability
            elif total < line:
                under += probability
            else:
                push += probability
            scorelines.append({
                "home": home,
                "away": away,
                "probability": round(probability, 8),
            })
    scorelines.sort(key=lambda item: float(item["probability"]), reverse=True)
    return {
        "homeExpectedGoals": round(float(home_expected_goals), 4),
        "awayExpectedGoals": round(float(away_expected_goals), 4),
        "rho": round(float(rho), 6),
        "line": float(line),
        "overProbability": round(over, 6),
        "underProbability": round(under, 6),
        "pushProbability": round(push, 6),
        "mostLikelyScores": scorelines[:5],
        "method": "dixon-coles",
        "maxGoals": max_goals,
    }
