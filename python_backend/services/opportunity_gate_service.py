"""Final opportunity-first safety gate for player-prop recommendations."""

from __future__ import annotations

from dataclasses import dataclass


MINIMUM_ACTION_PROBABILITY = 0.58
MINIMUM_NORMALIZED_EDGE = 0.40
MINIMUM_SAMPLE_SIZE = 8
MINIMUM_DATA_QUALITY = 0.60


@dataclass(frozen=True)
class OpportunityGate:
    actionable: bool
    score: float
    status: str
    normalized_edge: float | None
    reasons: tuple[str, ...]


def evaluate_opportunity_gate(
    *,
    projection: float | None,
    line: float,
    volatility: float | None,
    probability: float | None,
    sample_size: int,
    data_quality_score: float,
    injury_status: str,
    lineup_status: str,
    context_values: tuple[float | None, ...] = (),
) -> OpportunityGate:
    """Require volume certainty, context coverage, and a risk-adjusted edge."""
    reasons: list[str] = []
    injury = injury_status.strip().lower()
    lineup = lineup_status.strip().lower()
    unavailable = injury in {"out", "inactive", "injured reserve"} or lineup in {
        "out", "inactive"
    }
    if unavailable:
        reasons.append("player_unavailable")
    if lineup not in {"confirmed", "starter", "starting", "active"}:
        reasons.append("lineup_not_confirmed")
    if injury in {"unknown", "questionable", "doubtful", "day-to-day"}:
        reasons.append("injury_status_unresolved")
    if sample_size < MINIMUM_SAMPLE_SIZE:
        reasons.append("insufficient_projection_sample")
    if data_quality_score < MINIMUM_DATA_QUALITY:
        reasons.append("insufficient_data_quality")
    if probability is None or probability < MINIMUM_ACTION_PROBABILITY:
        reasons.append("probability_below_action_threshold")

    normalized_edge = None
    if projection is not None and volatility is not None and volatility > 0:
        normalized_edge = abs(float(projection) - float(line)) / float(volatility)
    if normalized_edge is None or normalized_edge < MINIMUM_NORMALIZED_EDGE:
        reasons.append("uncertainty_adjusted_edge_too_small")

    supplied_context = sum(value is not None for value in context_values)
    context_coverage = supplied_context / len(context_values) if context_values else 0.0
    if context_coverage < 0.5:
        reasons.append("opportunity_context_incomplete")

    score = (
        min(1.0, max(0.0, data_quality_score)) * 0.30
        + min(1.0, sample_size / 20) * 0.15
        + min(1.0, max(0.0, (probability or 0.5) - 0.5) / 0.20) * 0.20
        + min(1.0, (normalized_edge or 0.0) / 0.80) * 0.20
        + context_coverage * 0.15
    )
    actionable = not reasons
    return OpportunityGate(
        actionable=actionable,
        score=round(score, 3),
        status="MODEL_PICK" if actionable else "SYSTEM_LEAN",
        normalized_edge=(round(normalized_edge, 4) if normalized_edge is not None else None),
        reasons=tuple(reasons),
    )
