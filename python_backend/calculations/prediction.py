from services.prop_probability_service import power_method_devig


def american_to_implied_probability(odds: float) -> float:
    if odds > 0:
        return 100 / (odds + 100)
    return abs(odds) / (abs(odds) + 100)


def calculate_prediction(
    over_odds: float | None,
    under_odds: float | None,
) -> tuple[str, float]:
    safe_over = over_odds if isinstance(over_odds, (int, float)) else -110
    safe_under = (
        under_odds
        if isinstance(under_odds, (int, float))
        else -110
    )

    over_probability = american_to_implied_probability(
        float(safe_over)
    )
    under_probability = american_to_implied_probability(
        float(safe_under)
    )
    normalized_over, normalized_under = power_method_devig(
        over_probability,
        under_probability,
    )

    if normalized_over >= normalized_under:
        return "OVER", round(normalized_over * 100, 1)
    return "UNDER", round(normalized_under * 100, 1)
