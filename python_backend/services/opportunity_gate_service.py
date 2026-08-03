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
    adjusted_probability: float | None
    grade: str
    explanation: str
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
    blockers: list[str] = []
    injury = injury_status.strip().lower()
    lineup = lineup_status.strip().lower()
    unavailable = injury in {"out", "inactive", "injured reserve"} or lineup in {
        "out", "inactive"
    }
    if unavailable:
        blockers.append("player_unavailable")
    probability_penalty = 0.0
    if lineup not in {"confirmed", "starter", "starting", "active"}:
        reasons.append("lineup_not_confirmed")
        probability_penalty += 0.03
    if injury in {"unknown", "questionable", "doubtful", "day-to-day", "injury reported"}:
        reasons.append("injury_status_unresolved")
        probability_penalty += 0.02
    if sample_size < MINIMUM_SAMPLE_SIZE:
        blockers.append("insufficient_projection_sample")
    if data_quality_score < MINIMUM_DATA_QUALITY:
        blockers.append("insufficient_data_quality")

    normalized_edge = None
    if projection is not None and volatility is not None and volatility > 0:
        normalized_edge = abs(float(projection) - float(line)) / float(volatility)
    if normalized_edge is None or normalized_edge < MINIMUM_NORMALIZED_EDGE:
        blockers.append("uncertainty_adjusted_edge_too_small")

    supplied_context = sum(value is not None for value in context_values)
    context_coverage = supplied_context / len(context_values) if context_values else 0.0
    if context_coverage < 0.5:
        reasons.append("opportunity_context_incomplete")
        probability_penalty += (1 - context_coverage) * 0.04
    adjusted_probability = (
        max(0.0, float(probability) - probability_penalty)
        if probability is not None else None
    )
    if adjusted_probability is None or adjusted_probability < MINIMUM_ACTION_PROBABILITY:
        blockers.append("probability_below_action_threshold")

    score = (
        min(1.0, max(0.0, data_quality_score)) * 0.30
        + min(1.0, sample_size / 20) * 0.15
        + min(1.0, max(0.0, (probability or 0.5) - 0.5) / 0.20) * 0.20
        + min(1.0, (normalized_edge or 0.0) / 0.80) * 0.20
        + context_coverage * 0.15
    )
    all_reasons = tuple(blockers + reasons)
    actionable = not blockers
    if actionable:
        grade = (
            "A" if (adjusted_probability or 0) >= .65 and score >= .75
            else "B" if (adjusted_probability or 0) >= .60
            else "C"
        )
    else:
        grade = "C" if score >= .65 else "D"
    labels = {
        "player_unavailable": "player is unavailable",
        "lineup_not_confirmed": "lineup is not confirmed",
        "injury_status_unresolved": "injury status is unresolved",
        "insufficient_projection_sample": "projection sample is too small",
        "insufficient_data_quality": "supporting data quality is incomplete",
        "probability_below_action_threshold": "adjusted probability is below 58%",
        "uncertainty_adjusted_edge_too_small": "edge is small relative to volatility",
        "opportunity_context_incomplete": "matchup and opportunity context is incomplete",
    }
    explanation = (
        "Qualified model pick with complete opportunity and uncertainty checks."
        if not all_reasons
        else "Pick remains visible; grade reduced because "
        + ", ".join(labels.get(reason, reason.replace("_", " ")) for reason in all_reasons[:3])
        + "."
    )
    return OpportunityGate(
        actionable=actionable,
        score=round(score, 3),
        status="MODEL_PICK" if actionable else "SYSTEM_LEAN",
        normalized_edge=(round(normalized_edge, 4) if normalized_edge is not None else None),
        adjusted_probability=(
            round(adjusted_probability, 6)
            if adjusted_probability is not None else None
        ),
        grade=grade,
        explanation=explanation,
        reasons=all_reasons,
    )
