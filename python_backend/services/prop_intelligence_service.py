from __future__ import annotations

from math import comb
from typing import Any

from services.prop_probability_service import (
    blend_with_sharp_market,
    expected_value,
    power_method_devig,
    prop_probabilities,
)


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, float(value)))


def _is_mlb_strikeout_market(sport: str, market: str) -> bool:
    market_text = str(market or "").lower().replace("_", " ")
    sport_text = str(sport or "").strip().upper()
    return sport_text == "MLB" and "strikeout" in market_text


def _log5_rate(pitcher_rate: float, lineup_rate: float, league_rate: float) -> float:
    pitcher = _clamp(pitcher_rate, 0.01, 0.95)
    lineup = _clamp(lineup_rate, 0.01, 0.95)
    league = _clamp(league_rate, 0.01, 0.95)
    numerator = (pitcher * lineup) / league
    denominator = numerator + (((1 - pitcher) * (1 - lineup)) / (1 - league))
    if denominator <= 0:
        return pitcher
    return _clamp(numerator / denominator, 0.01, 0.95)


def _project_batters_faced(
    pitches_per_start: float | None,
    pitches_per_batter: float | None,
    fallback: int = 24,
) -> int:
    if pitches_per_start is None or pitches_per_batter is None:
        return fallback
    if pitches_per_start <= 0 or pitches_per_batter <= 0:
        return fallback
    return max(12, min(36, int(pitches_per_start / pitches_per_batter)))


def _binomial_over_probability(
    *,
    trials: int,
    success_probability: float,
    line: float,
) -> float:
    # Sportsbook strikeout lines are usually x.5, so pushing is rare.
    threshold = int(line)
    probability = 0.0
    p = _clamp(success_probability, 0.0001, 0.9999)
    for value in range(threshold + 1, trials + 1):
        probability += comb(trials, value) * (p ** value) * ((1 - p) ** (trials - value))
    return _clamp(probability, 0.0, 1.0)


def _analyze_mlb_strikeout_prop(
    *,
    player: str,
    sport: str,
    market: str,
    line: float,
    projected_mean: float,
    sharp_over_odds: float | None,
    sharp_under_odds: float | None,
    retail_over_odds: float | None,
    retail_under_odds: float | None,
    bankroll: float,
    kelly_fraction: float,
    pitcher_k_pct: float | None,
    lineup_k_pct: float | None,
    pitches_per_start: float | None,
    pitches_per_batter: float | None,
    pitcher_csw: float | None,
    lineup_csw_against: float | None,
    temp_f: float,
    umpire_k_boost: float,
    park_k_factor: float,
    league_avg_k_rate: float,
    league_avg_csw: float,
) -> dict[str, Any]:
    projected_tbf = _project_batters_faced(
        pitches_per_start,
        pitches_per_batter,
        fallback=24,
    )
    fallback_pitcher_rate = _clamp(projected_mean / max(1, projected_tbf), 0.05, 0.6)

    if pitcher_csw is not None and lineup_csw_against is not None:
        base_rate = _log5_rate(pitcher_csw, lineup_csw_against, league_avg_csw)
        skill_source = "csw_log5"
    else:
        base_rate = _log5_rate(
            pitcher_k_pct if pitcher_k_pct is not None else fallback_pitcher_rate,
            lineup_k_pct if lineup_k_pct is not None else league_avg_k_rate,
            league_avg_k_rate,
        )
        skill_source = "k_rate_log5"

    weather_modifier = ((70.0 - float(temp_f)) / 10.0) * 0.005
    adjusted_rate = (base_rate + weather_modifier + float(umpire_k_boost)) * float(park_k_factor)
    true_k_probability = _clamp(adjusted_rate, 0.01, 0.8)

    over_probability = _binomial_over_probability(
        trials=projected_tbf,
        success_probability=true_k_probability,
        line=line,
    )
    under_probability = 1.0 - over_probability

    blended_over_probability, market_weight = blend_with_sharp_market(
        over_probability,
        None,
        sample_size=max(1, projected_tbf),
        model_calibrated=True,
    )
    blended_under_probability = _clamp(1.0 - blended_over_probability, 0.0, 1.0)

    over_ev = expected_value(
        win_probability=blended_over_probability,
        push_probability=0.0,
        decimal_odds=sharp_over_odds or retail_over_odds or 1.91,
    )
    under_ev = expected_value(
        win_probability=blended_under_probability,
        push_probability=0.0,
        decimal_odds=sharp_under_odds or retail_under_odds or 1.91,
    )
    over_edge = over_ev.expected_value * 100.0
    under_edge = under_ev.expected_value * 100.0

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
            float(bankroll) * _clamp(kelly_fraction, 0.0, 1.0) * max(0.0, chosen_ev.expected_value),
        )

    return {
        "player": player,
        "sport": sport,
        "market": market,
        "recommendation": recommendation,
        "method": "mlb_strikeout_log5_binomial",
        "skillSource": skill_source,
        "matchupKRate": round(base_rate, 6),
        "trueKRate": round(true_k_probability, 6),
        "projectedBattersFaced": projected_tbf,
        "projectedMedianStrikeouts": round(true_k_probability * projected_tbf, 2),
        "modelOverProbability": round(over_probability, 6),
        "marketOverProbability": round(blended_over_probability, 6),
        "expectedValuePercent": round(max(over_edge, under_edge), 2),
        "suggestedWagerUsd": round(suggested_wager, 2),
        "edgePercent": round(max(over_edge, under_edge), 2),
        "confidence": confidence,
        "marketWeight": round(market_weight, 4),
        "distribution": "binomial",
        "line": round(line, 2),
        "projection": round(projected_mean, 2),
    }


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
    pitcher_k_pct: float | None = None,
    lineup_k_pct: float | None = None,
    pitches_per_start: float | None = None,
    pitches_per_batter: float | None = None,
    pitcher_csw: float | None = None,
    lineup_csw_against: float | None = None,
    temp_f: float = 70.0,
    umpire_k_boost: float = 0.0,
    park_k_factor: float = 1.0,
    league_avg_k_rate: float = 0.224,
    league_avg_csw: float = 0.275,
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

    if _is_mlb_strikeout_market(sport, market):
        return _analyze_mlb_strikeout_prop(
            player=player,
            sport=sport,
            market=market,
            line=line_value,
            projected_mean=projection_value,
            sharp_over_odds=sharp_over_odds,
            sharp_under_odds=sharp_under_odds,
            retail_over_odds=retail_over_odds,
            retail_under_odds=retail_under_odds,
            bankroll=bankroll,
            kelly_fraction=kelly_fraction,
            pitcher_k_pct=pitcher_k_pct,
            lineup_k_pct=lineup_k_pct,
            pitches_per_start=pitches_per_start,
            pitches_per_batter=pitches_per_batter,
            pitcher_csw=pitcher_csw,
            lineup_csw_against=lineup_csw_against,
            temp_f=temp_f,
            umpire_k_boost=umpire_k_boost,
            park_k_factor=park_k_factor,
            league_avg_k_rate=league_avg_k_rate,
            league_avg_csw=league_avg_csw,
        )

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
        "method": "market_blended_distribution",
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
