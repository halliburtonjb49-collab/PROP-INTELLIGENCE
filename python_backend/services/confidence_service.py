"""Confidence as evidence quality, not as a restatement of the edge.

A player hitting the over in seven of ten games is not seventy percent
confidence. That number describes ten observations; it says nothing about
whether the lineup is confirmed, whether the minutes are known, or whether
the models built on different evidence agree.

Confidence here is what is known about the situation, held separately from
how large the edge is:

    confidence = calibration * completeness * role * lineup * agreement

A pick can carry a large projected edge and low confidence. Those are
different statements and the system keeps them apart deliberately.

Each factor is expressed as a deduction from full confidence so the reasons
survive into the response. A user who is told a pick is 58 rather than 72
should be able to see that it is because the lineup is unconfirmed and the
minutes are uncertain.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

# Deductions in confidence points. Ordered by how much they should move a
# projection that is otherwise sound.
DEDUCTIONS: Mapping[str, int] = {
    "unconfirmed_lineup": 10,
    "questionable_injury": 10,
    # A doubtful tag is a different statement from questionable and is
    # penalised toward the top of the range.
    "doubtful_injury": 25,
    "uncertain_minutes": 15,
    "small_sample": 10,
    "models_disagree": 15,
    "missing_venue_context": 5,
    "major_role_change": 10,
}

# Below this many observations the estimate is a small sample whatever the
# model says about it.
SMALL_SAMPLE_SIZE = 12

# Confidence is a bounded statement about evidence. Even a perfectly known
# situation is not a certainty, and even a poorly known one is not zero once
# a pick is being shown at all.
MINIMUM_CONFIDENCE = 25
MAXIMUM_CONFIDENCE = 85


@dataclass(frozen=True)
class ConfidenceAssessment:
    confidence: int
    base_confidence: int
    deductions: Mapping[str, int]
    reasons: tuple[str, ...]
    suppressed: bool
    suppression_reason: str = ""

    @property
    def total_deducted(self) -> int:
        return sum(self.deductions.values())


def _text(value: object) -> str:
    return str(value if value is not None else "").strip().lower()


def assess_confidence(
    *,
    base_confidence: int,
    injury_status: object = "",
    lineup_status: object = "",
    sample_size: int = 0,
    models_disagree: bool = False,
    minutes_known: bool = True,
    role_change: object = "",
    context_completeness: float | None = None,
    odds_are_stale: bool = False,
) -> ConfidenceAssessment:
    """Confidence after every evidence deduction that applies.

    Stale odds suppress rather than deduct. A price that no longer exists
    cannot be acted on at any confidence, so reducing the number would still
    show a pick that cannot be taken.
    """

    deductions: dict[str, int] = {}
    reasons: list[str] = []

    injury = _text(injury_status)
    if injury in {"doubtful", "out", "inactive", "suspended"}:
        deductions["doubtful_injury"] = DEDUCTIONS["doubtful_injury"]
        reasons.append(f"injury status is {injury}")
    elif injury in {"questionable", "day_to_day", "game_time_decision"}:
        deductions["questionable_injury"] = DEDUCTIONS["questionable_injury"]
        reasons.append(f"injury status is {injury}")

    lineup = _text(lineup_status)
    if lineup in {"", "unknown", "unconfirmed", "projected"}:
        deductions["unconfirmed_lineup"] = DEDUCTIONS["unconfirmed_lineup"]
        reasons.append("lineup is not confirmed")

    if not minutes_known:
        deductions["uncertain_minutes"] = DEDUCTIONS["uncertain_minutes"]
        reasons.append("playing time is uncertain")

    if int(sample_size or 0) < SMALL_SAMPLE_SIZE:
        deductions["small_sample"] = DEDUCTIONS["small_sample"]
        reasons.append(f"only {int(sample_size or 0)} games of history")

    if models_disagree:
        deductions["models_disagree"] = DEDUCTIONS["models_disagree"]
        reasons.append("models disagree on the projection")

    if _text(role_change) in {"expanded", "reduced"}:
        # A role change does not make the projection wrong, but it makes the
        # history behind it describe a role the player no longer has.
        deductions["major_role_change"] = DEDUCTIONS["major_role_change"]
        reasons.append(f"role recently {_text(role_change)}")

    if context_completeness is not None and float(context_completeness) < 0.70:
        deductions["missing_venue_context"] = DEDUCTIONS["missing_venue_context"]
        reasons.append("venue or situational context is incomplete")

    confidence = int(base_confidence) - sum(deductions.values())
    confidence = max(MINIMUM_CONFIDENCE, min(MAXIMUM_CONFIDENCE, confidence))

    if odds_are_stale:
        return ConfidenceAssessment(
            confidence=0,
            base_confidence=int(base_confidence),
            deductions=deductions,
            reasons=tuple(reasons + ["odds are stale"]),
            suppressed=True,
            suppression_reason="stale_odds",
        )

    return ConfidenceAssessment(
        confidence=confidence,
        base_confidence=int(base_confidence),
        deductions=deductions,
        reasons=tuple(reasons),
        suppressed=False,
    )


def uncertainty_multiplier(assessment: ConfidenceAssessment) -> float:
    """How far to widen a distribution given what is unknown.

    A role change and unknown minutes do not shift the projection so much as
    make it less certain, which belongs in the spread rather than the mean.
    """

    widened = 1.0
    if "major_role_change" in assessment.deductions:
        widened *= 1.15
    if "uncertain_minutes" in assessment.deductions:
        widened *= 1.20
    if "small_sample" in assessment.deductions:
        widened *= 1.10
    return round(widened, 4)


def describe(assessment: ConfidenceAssessment) -> str:
    """One sentence a user can act on, not a list of internal tokens."""

    if assessment.suppressed:
        return "No pick: the price is stale and may no longer be available."
    if not assessment.reasons:
        return "Full confidence: lineup, availability and history are all known."
    return "Confidence reduced because " + "; ".join(assessment.reasons) + "."
