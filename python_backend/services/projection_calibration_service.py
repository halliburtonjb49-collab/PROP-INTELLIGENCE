"""Market-aware probability and context adjustments for prop projections."""

from __future__ import annotations

from dataclasses import dataclass
from math import exp
from statistics import NormalDist


@dataclass(frozen=True)
class ProjectionContext:
    workload_multiplier: float = 1.0
    opponent_multiplier: float = 1.0
    availability_multiplier: float = 1.0
    venue_multiplier: float = 1.0

    @property
    def combined_multiplier(self) -> float:
        value = (
            self.workload_multiplier
            * self.opponent_multiplier
            * self.availability_multiplier
            * self.venue_multiplier
        )
        return max(0.65, min(1.35, value))


def market_volatility_floor(sport: str, market: str) -> float:
    text = f"{sport} {market}".lower().replace("_", " ")
    if "strikeout" in text:
        return 1.45
    if "home run" in text:
        return 0.35
    if "hit" in text or "total base" in text:
        return 0.75
    if "rebound" in text or "assist" in text:
        return 2.0
    if "point" in text:
        return 4.5
    if "shot" in text:
        return 1.0
    return 1.0


def contextual_projection(projection: float, context: ProjectionContext) -> float:
    return round(max(0.0, projection * context.combined_multiplier), 4)


def calibrated_hit_probability(
    *,
    projection: float,
    line: float,
    volatility: float,
    side: str,
    sample_size: int,
    sport: str = "",
    market: str = "",
    empirical_hit_rate: float | None = None,
) -> float:
    sigma = max(float(volatility), market_volatility_floor(sport, market))
    z = (float(line) - float(projection)) / sigma
    over_probability = 1.0 - NormalDist().cdf(z)
    raw = over_probability if side.strip().upper() == "OVER" else 1 - over_probability

    reliability = max(0.0, min(1.0, sample_size / (sample_size + 20.0)))
    probability = 0.5 + (raw - 0.5) * reliability
    if empirical_hit_rate is not None:
        observed = max(0.0, min(1.0, empirical_hit_rate))
        empirical_weight = min(0.35, sample_size / 100.0)
        probability = (probability * (1 - empirical_weight)) + (
            observed * empirical_weight
        )
    return round(max(0.50, min(0.80, probability)), 4)


def confidence_from_probability(probability: float) -> int:
    return max(50, min(80, round(float(probability) * 100)))


def exponentially_weighted_mean(
    values: list[float],
    *,
    half_life_games: float = 6.0,
) -> float:
    if not values:
        raise ValueError("At least one value is required")
    decay = exp(-0.69314718056 / max(1.0, half_life_games))
    weights = [decay ** (len(values) - index - 1) for index in range(len(values))]
    return sum(value * weight for value, weight in zip(values, weights)) / sum(weights)
