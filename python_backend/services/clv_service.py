"""Deterministic closing-line-value calculations for player props."""

from models.intelligence import ClosingLineValueRequest


def american_implied_probability(odds: int) -> float:
    if odds == 0:
        raise ValueError("American odds cannot be zero")
    if odds > 0:
        return 100 / (odds + 100)
    return abs(odds) / (abs(odds) + 100)


def vig_free_probability(side_odds: int, opposite_odds: int) -> float:
    """Return the proportional no-vig probability for a two-way market."""
    side = american_implied_probability(side_odds)
    opposite = american_implied_probability(opposite_odds)
    total = side + opposite
    if total <= 0:
        raise ValueError("Closing market probability must be positive")
    return side / total


def odds_clv_expected_value(
    entry_odds: int,
    closing_side_odds: int,
    closing_opposite_odds: int,
) -> float:
    entry_break_even = american_implied_probability(entry_odds)
    true_close = vig_free_probability(closing_side_odds, closing_opposite_odds)
    return true_close / entry_break_even - 1


def closing_line_value(request: ClosingLineValueRequest) -> dict[str, object]:
    line_delta = (
        request.closing_line - request.entry_line
        if request.side == "OVER"
        else request.entry_line - request.closing_line
    )
    line_percent = line_delta / abs(request.entry_line) * 100
    result: dict[str, object] = {
        "side": request.side,
        "entryLine": request.entry_line,
        "closingLine": request.closing_line,
        "lineClv": round(line_delta, 4),
        "lineClvPercent": round(line_percent, 4),
        "beatClosingLine": line_delta > 0,
        "classification": "POSITIVE" if line_delta > 0 else "NEGATIVE" if line_delta < 0 else "PUSH",
        "oddsClvProbabilityPoints": None,
        "disclosure": "CLV measures entry price versus the closing market; it does not determine whether a wager won.",
    }
    if request.entry_odds is not None and request.closing_odds is not None:
        entry_probability = american_implied_probability(request.entry_odds)
        close_probability = american_implied_probability(request.closing_odds)
        probability_points = (close_probability - entry_probability) * 100
        result.update({
            "entryImpliedProbability": round(entry_probability, 6),
            "closingImpliedProbability": round(close_probability, 6),
            "oddsClvProbabilityPoints": round(probability_points, 4),
        })
        if request.closing_opposite_odds is not None:
            true_close = vig_free_probability(
                request.closing_odds,
                request.closing_opposite_odds,
            )
            clv_ev = odds_clv_expected_value(
                request.entry_odds,
                request.closing_odds,
                request.closing_opposite_odds,
            )
            result.update({
                "closingNoVigProbability": round(true_close, 6),
                "oddsClvExpectedValue": round(clv_ev, 6),
                "oddsClvExpectedValuePercent": round(clv_ev * 100, 4),
                "oddsClvMethod": "proportional-no-vig",
            })
    return result
