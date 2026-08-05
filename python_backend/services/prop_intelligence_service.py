from __future__ import annotations

from typing import Any

from services.prop_probability_service import (
    blend_with_sharp_market,
    expected_value,
    power_method_devig,
    prop_probabilities,
)


def _decimal_to_implied_probability(odds: float | None) -> float | None:
    if odds is None:
        return None
    try:
        value = float(odds)
    except (TypeError, ValueError):
        return None
    if value <= 0:
        return None
    return 1.0 / value


def analyze_prop(
    *,
    player: str,
    sport: str,
    market: str,
    line: float,
    projected_mean: float,
    projected_std_dev: float,
    sharp_over_odds: float | None = None,
    sharp_under_odds: float | None = None,
    retail_over_odds: float | None = None,
    retail_under_odds: float | None = None,
    bankroll: float = 1000.0,
    kelly_fraction: float = 0.25,
    simulations: int = 2000,
    seed: int = 42,
) -> dict[str, Any]:
    """Generate a simple EV-based recommendation for a single prop.

    The implementation uses a lightweight distribution model plus market devigging
    so it can produce a conservative recommendation without dependencies outside
    the existing backend runtime.
    """

    try:
        line_value = float(line)
        projection_value = float(projected_mean)
        volatility_value = max(0.0, float(projected_std_dev))
    except (TypeError, ValueError):
        return {
            "player": player,
            "sport": sport,
            "market": market,
            "recommendation": "PASS",
            "modelOverProbability": 0.0,
            "marketOverProbability": 0.0,
            "expectedValuePercent": 0.0,
            "suggestedWagerUsd": 0.0,
            "edgePercent": 0.0,
            "confidence": 0,
            "marketWeight": 0.0,
            "distribution": "normal",
        }

    if line_value <= 0:
        return {
            "player": player,
            "sport": sport,
            "market": market,
            "recommendation": "PASS",
            "modelOverProbability": 0.0,
            "marketOverProbability": 0.0,
            "expectedValuePercent": 0.0,
            "suggestedWagerUsd": 0.0,
            "edgePercent": 0.0,
            "confidence": 0,
            "marketWeight": 0.0,
            "distribution": "normal",
        }

    probabilities = prop_probabilities(
        projection=projection_value,
        line=line_value,
        volatility=volatility_value,
        sport=sport,
        market=market,
    )
    model_over_probability = probabilities.over
    model_under_probability = probabilities.under

    sharp_over_implied = _decimal_to_implied_probability(sharp_over_odds)
    sharp_under_implied = _decimal_to_implied_probability(sharp_under_odds)
    retail_over_implied = _decimal_to_implied_probability(retail_over_odds)
    retail_under_implied = _decimal_to_implied_probability(retail_under_odds)

    if sharp_over_implied is not None and sharp_under_implied is not None:
        sharp_over_devig, sharp_under_devig = power_method_devig(
            sharp_over_implied,
            sharp_under_implied,
        )
    else:
        sharp_over_devig, sharp_under_devig = model_over_probability, model_under_probability

    if retail_over_implied is not None and retail_under_implied is not None:
        retail_over_devig, retail_under_devig = power_method_devig(
            retail_over_implied,
            retail_under_implied,
        )
    else:
        retail_over_devig, retail_under_devig = sharp_over_devig, sharp_under_devig

    blended_over_probability, market_weight = blend_with_sharp_market(
        model_over_probability,
        (sharp_over_devig * 0.7) + (retail_over_devig * 0.3),
        sample_size=max(1, int(simulations)),
        model_calibrated=True,
    )
    blended_under_probability, _ = blend_with_sharp_market(
        model_under_probability,
        (sharp_under_devig * 0.7) + (retail_under_devig * 0.3),
        sample_size=max(1, int(simulations)),
        model_calibrated=True,
    )

    over_ev = expected_value(
        win_probability=blended_over_probability,
        push_probability=probabilities.push,
        decimal_odds=sharp_over_odds or 1.91,
    )
    under_ev = expected_value(
        win_probability=blended_under_probability,
        push_probability=probabilities.push,
        decimal_odds=sharp_under_odds or 1.91,
    )

    over_edge = (over_ev.expected_value * 100.0)
    under_edge = (under_ev.expected_value * 100.0)

    if over_edge > under_edge and over_edge > 1.0:
        recommendation = "OVER"
        chosen_probability = blended_over_probability
        chosen_ev = over_ev
    elif under_edge > over_edge and under_edge > 1.0:
        recommendation = "UNDER"
        chosen_probability = blended_under_probability
        chosen_ev = under_ev
    else:
        recommendation = "PASS"
        chosen_probability = max(blended_over_probability, blended_under_probability)
        chosen_ev = over_ev if over_edge >= under_edge else under_ev

    confidence = max(0, min(99, int(round(chosen_probability * 100))))
    suggested_wager = 0.0
    if recommendation != "PASS" and chosen_probability > 0.5:
        suggested_wager = max(
            0.0,
            float(bankroll) * max(0.0, min(1.0, float(kelly_fraction))) * max(0.0, chosen_ev.expected_value),
        )

    return {
        "player": player,
        "sport": sport,
        "market": market,
        "recommendation": recommendation,
        "modelOverProbability": round(model_over_probability, 6),
        "marketOverProbability": round(blended_over_probability, 6),
        "expectedValuePercent": round(max(over_edge, under_edge), 2),
        "suggestedWagerUsd": round(suggested_wager, 2),
        "edgePercent": round(max(over_edge, under_edge), 2),
        "confidence": confidence,
        "marketWeight": round(market_weight, 4),
        "distribution": probabilities.distribution,
        "seed": seed,
        "line": round(line_value, 2),
        "projection": round(projection_value, 2),
        "volatility": round(volatility_value, 2),
    }
