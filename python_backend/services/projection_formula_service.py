"""Auditable projection formulas that fail closed when inputs are unavailable."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ProjectionBlend:
    projection: float
    market_weight: float


def process_projection(
    *,
    opportunities: float,
    efficiency_per_opportunity: float,
    quality_multiplier: float = 1.0,
    conversion_multiplier: float = 1.0,
) -> float:
    """Project an outcome from opportunity volume and situational efficiency."""
    values = (
        opportunities,
        efficiency_per_opportunity,
        quality_multiplier,
        conversion_multiplier,
    )
    if any(float(value) < 0 for value in values):
        raise ValueError("Projection formula inputs cannot be negative")
    return round(
        float(opportunities)
        * float(efficiency_per_opportunity)
        * float(quality_multiplier)
        * float(conversion_multiplier),
        4,
    )


def pace_adjusted_projection(
    *,
    baseline: float,
    team_pace: float,
    opponent_pace: float,
    league_average_pace: float,
) -> float:
    """Apply the average team/opponent pace relative to the league baseline."""
    if league_average_pace <= 0 or team_pace <= 0 or opponent_pace <= 0:
        raise ValueError("Pace inputs must be positive")
    factor = (float(team_pace) + float(opponent_pace)) / (
        2 * float(league_average_pace)
    )
    # A bad or mismatched pace feed should never create an extreme projection.
    factor = max(0.85, min(1.15, factor))
    return round(max(0.0, float(baseline) * factor), 4)


def blend_projection_with_market(
    *,
    custom_projection: float,
    market_origin_line: float | None,
    market_book_count: int,
    sample_size: int,
    calibrated: bool,
) -> ProjectionBlend:
    """Shrink uncertain projections toward a multi-book market benchmark.

    The market receives less weight as the model builds a larger verified
    sample. A single-book line is not treated as a market benchmark.
    """
    if (
        market_origin_line is None
        or market_book_count < 2
        or custom_projection < 0
        or market_origin_line < 0
    ):
        return ProjectionBlend(round(max(0.0, custom_projection), 4), 0.0)
    reliability = max(0.0, min(1.0, float(sample_size) / 40.0))
    maximum_weight = 0.20 if calibrated else 0.30
    minimum_weight = 0.08 if calibrated else 0.12
    market_weight = maximum_weight - (
        (maximum_weight - minimum_weight) * reliability
    )
    blended = (
        float(custom_projection) * (1 - market_weight)
        + float(market_origin_line) * market_weight
    )
    return ProjectionBlend(round(blended, 4), round(market_weight, 4))
