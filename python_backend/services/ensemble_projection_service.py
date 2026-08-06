"""Combine independent projections and measure how much they disagree.

No single model should decide a projection. Each has a characteristic failure:
a recency baseline lags role change, a simulation inherits whatever
distribution it was handed, and a market-derived number is confidently wrong
exactly when the market is slow. Averaging them does not remove those
failures, but it stops any one of them from owning the answer.

The spread between members is as useful as the average. When models built on
different evidence agree, the projection is supported from several directions;
when they diverge, something is wrong that none of them can see alone. That
disagreement feeds the confidence system rather than being averaged away.

Weights are per sport and market, learned by backtesting. The defaults here
are a starting configuration, not a claim.
"""

from __future__ import annotations

from dataclasses import dataclass
from statistics import fmean, pstdev
from typing import Mapping, Sequence

from services.projection_calibration_service import parameter_keys

# Model identities. A member absent for a given prop is dropped and the
# remaining weights renormalise, so a missing model never silently counts as
# a projection of zero.
HISTORICAL = "historical"
GRADIENT_BOOSTING = "gradient_boosting"
BAYESIAN = "bayesian"
SIMULATION = "simulation"
MARKET = "market"

MEMBERS = (HISTORICAL, GRADIENT_BOOSTING, BAYESIAN, SIMULATION, MARKET)

# Starting configuration. Weight belongs with the models that are actually
# built and validated; a member that does not yet exist carries none, so
# adding one is a deliberate act rather than an accident of defaults.
DEFAULT_WEIGHTS: Mapping[str, float] = {
    HISTORICAL: 0.45,
    GRADIENT_BOOSTING: 0.0,
    BAYESIAN: 0.0,
    SIMULATION: 0.35,
    MARKET: 0.20,
}

_MARKET_WEIGHTS: dict[str, Mapping[str, float]] = {}


def weights_for(
    sport: str,
    market: str,
    competition: str = "",
) -> Mapping[str, float]:
    """Learned ensemble weights, most specific first."""

    for key in parameter_keys(sport, market, competition):
        weights = _MARKET_WEIGHTS.get(key)
        if weights is not None:
            return weights
    return DEFAULT_WEIGHTS


def register_weights(
    sport: str,
    market: str,
    weights: Mapping[str, float],
    *,
    competition: str = "",
) -> None:
    """Install backtested weights for one sport and market."""

    unknown = set(weights) - set(MEMBERS)
    if unknown:
        raise ValueError(f"Unknown ensemble members: {sorted(unknown)}")
    total = sum(max(0.0, float(value)) for value in weights.values())
    if total <= 0:
        raise ValueError("Ensemble weights must sum to a positive number")
    key = parameter_keys(sport, market, competition)[0]
    _MARKET_WEIGHTS[key] = {
        member: max(0.0, float(weights.get(member, 0.0))) / total
        for member in MEMBERS
    }


@dataclass(frozen=True)
class EnsembleProjection:
    projection: float
    members: Mapping[str, float]
    applied_weights: Mapping[str, float]
    # Standard deviation across contributing members, in stat units.
    disagreement: float
    # Disagreement relative to the projection, which is comparable across
    # markets in a way the raw spread is not.
    relative_disagreement: float
    contributing: tuple[str, ...]


def combine(
    projections: Mapping[str, float | None],
    *,
    sport: str = "",
    market: str = "",
    competition: str = "",
) -> EnsembleProjection | None:
    """Weighted combination of whichever members produced a projection.

    Returns None when no member did, so the caller falls back rather than
    receiving an average of nothing.
    """

    available = {
        member: float(value)
        for member, value in projections.items()
        if member in MEMBERS and value is not None
    }
    if not available:
        return None

    configured = weights_for(sport, market, competition)
    weights = {
        member: max(0.0, float(configured.get(member, 0.0)))
        for member in available
    }
    total = sum(weights.values())
    if total <= 0:
        # Every contributing member carries zero configured weight. Falling
        # back to an equal split is better than returning nothing, since the
        # members did produce projections.
        weights = {member: 1.0 for member in available}
        total = float(len(available))
    applied = {member: value / total for member, value in weights.items()}
    projection = sum(available[member] * applied[member] for member in available)

    values = list(available.values())
    spread = pstdev(values) if len(values) > 1 else 0.0
    centre = abs(fmean(values)) if values else 0.0
    return EnsembleProjection(
        projection=round(projection, 4),
        members={member: round(value, 4) for member, value in available.items()},
        applied_weights={
            member: round(value, 4) for member, value in applied.items()
        },
        disagreement=round(spread, 4),
        relative_disagreement=round(spread / centre, 4) if centre > 0 else 0.0,
        contributing=tuple(sorted(available)),
    )


# Above this relative spread the members are telling materially different
# stories and the projection should not be trusted at face value.
STRONG_DISAGREEMENT = 0.20


def models_disagree(ensemble: EnsembleProjection | None) -> bool:
    """Whether the spread is wide enough to warrant a confidence deduction.

    A single contributing member cannot disagree with anything, so it is not
    treated as agreement either -- that case is handled as a sample-and-
    coverage problem by the confidence system, not as consensus.
    """

    if ensemble is None or len(ensemble.contributing) < 2:
        return False
    return ensemble.relative_disagreement >= STRONG_DISAGREEMENT
