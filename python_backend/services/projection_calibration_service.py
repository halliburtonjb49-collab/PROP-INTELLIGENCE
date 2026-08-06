"""Market-aware probability and context adjustments for prop projections."""

from __future__ import annotations

from dataclasses import dataclass
from math import exp
from statistics import NormalDist, fmean
from typing import Sequence


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


# Recency-weighted baseline
# -------------------------
# A last-5 or season average alone is either too jumpy or too slow. The baseline
# blends nested trailing windows so recent form leads without discarding the
# stable long-run level:
#
#     B = w5 * R5 + w10 * R10 + w20 * R20 + wSeason * RSeason
#
# The windows overlap by design, so the result is always a convex combination of
# the observed values regardless of how many games exist.

RECENCY_WINDOWS: tuple[int, int, int] = (5, 10, 20)

# Starting configuration only. Per-market weights must be learned through
# backtesting and registered in _MARKET_RECENCY_WEIGHTS as they are validated;
# a market with no learned entry keeps this default.
DEFAULT_RECENCY_WEIGHTS: tuple[float, float, float, float] = (0.40, 0.25, 0.20, 0.15)

_MARKET_RECENCY_WEIGHTS: dict[str, tuple[float, float, float, float]] = {}


def _market_signature(sport: str, market: str) -> str:
    return f"{sport} {market}".lower().replace("_", " ").strip()


def recency_weights_for(sport: str, market: str) -> tuple[float, float, float, float]:
    """Learned weights for a market, falling back to the default configuration."""

    return _MARKET_RECENCY_WEIGHTS.get(
        _market_signature(sport, market),
        DEFAULT_RECENCY_WEIGHTS,
    )


def recency_weighted_baseline(
    values: Sequence[float],
    *,
    weights: tuple[float, float, float, float] | None = None,
) -> float:
    """Blend trailing windows of a time-ordered (oldest first) game log."""

    ordered = [float(value) for value in values]
    if not ordered:
        raise ValueError("At least one value is required")
    w5, w10, w20, w_season = weights or DEFAULT_RECENCY_WEIGHTS
    short, medium, long = RECENCY_WINDOWS
    total = w5 + w10 + w20 + w_season
    if total <= 0:
        raise ValueError("Recency weights must sum to a positive number")
    blended = (
        (w5 * fmean(ordered[-short:]))
        + (w10 * fmean(ordered[-medium:]))
        + (w20 * fmean(ordered[-long:]))
        + (w_season * fmean(ordered))
    )
    return blended / total


# Small-sample shrinkage
# ----------------------
# A raw player rate over a handful of games is mostly noise. Shrink it toward a
# broader prior with weight w = N / (N + k), so two unusually strong games can no
# longer carry a projection on their own:
#
#     Adjusted Rate = w * PlayerRate + (1 - w) * Prior
#
# k is the sample size at which the player's own rate earns half the weight.

DEFAULT_SHRINKAGE_K = 8.0

# Starting configuration only; k belongs to the same backtesting sweep as the
# recency weights. High-variance, low-frequency markets need a heavier prior.
_MARKET_SHRINKAGE_K: dict[str, float] = {}


def shrinkage_k_for(sport: str, market: str) -> float:
    return _MARKET_SHRINKAGE_K.get(
        _market_signature(sport, market),
        DEFAULT_SHRINKAGE_K,
    )


def shrinkage_weight(sample_size: int, *, k: float = DEFAULT_SHRINKAGE_K) -> float:
    """w = N / (N + k): the share of the estimate the player's own rate earns."""

    games = max(0, int(sample_size))
    denominator = games + max(0.0, float(k))
    if denominator <= 0:
        return 1.0
    return games / denominator


def shrink_toward_prior(
    rate: float,
    prior: float | None,
    *,
    sample_size: int,
    k: float = DEFAULT_SHRINKAGE_K,
) -> tuple[float, float]:
    """Return the shrunk rate and the weight the player's own rate received."""

    if prior is None:
        return float(rate), 1.0
    weight = shrinkage_weight(sample_size, k=k)
    return (weight * float(rate)) + ((1 - weight) * float(prior)), weight
