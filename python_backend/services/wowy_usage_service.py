"""Auditable basketball with/without-you (WOWY) usage calculations.

The NBA Stats lineup endpoint contains team totals for five-player groups. It
does not contain an individual target player's attempts in those minutes, so
those rows alone must never be presented as player usage. This service accepts
player and team totals produced by a substitution-aware play-by-play pass (or
another verified stint provider) and applies the standard usage formula.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class UsageTotals:
    player_fga: float
    player_fta: float
    player_tov: float
    player_minutes: float
    team_fga: float
    team_fta: float
    team_tov: float
    team_minutes: float


def usage_rate(totals: UsageTotals) -> float | None:
    """Return USG% or ``None`` when the denominator is not supportable."""
    player_possessions = (
        totals.player_fga + 0.44 * totals.player_fta + totals.player_tov
    )
    team_possessions = totals.team_fga + 0.44 * totals.team_fta + totals.team_tov
    denominator = team_possessions * 5 * totals.player_minutes
    if (
        denominator <= 0
        or totals.team_minutes <= 0
        or min(
            totals.player_fga,
            totals.player_fta,
            totals.player_tov,
            totals.player_minutes,
            totals.team_fga,
            totals.team_fta,
            totals.team_tov,
            totals.team_minutes,
        )
        < 0
    ):
        return None
    return 100 * player_possessions * totals.team_minutes / denominator


def analyze_wowy_usage(
    on: UsageTotals,
    off: UsageTotals,
    *,
    minimum_split_minutes: float = 100,
    full_weight_minutes: float = 300,
) -> dict[str, object]:
    """Compare target-player usage with a teammate on and off the court.

    The raw delta is exposed for research. The actionable delta is reliability
    shrunk toward zero until both samples reach ``full_weight_minutes``.
    """
    on_rate = usage_rate(on)
    off_rate = usage_rate(off)
    minimum_minutes = min(on.player_minutes, off.player_minutes)
    if on_rate is None or off_rate is None:
        return {
            "available": False,
            "actionable": False,
            "reason": "Usage could not be calculated from the supplied totals.",
        }

    raw_delta = off_rate - on_rate
    reliability = max(0.0, min(1.0, minimum_minutes / full_weight_minutes))
    actionable = minimum_minutes >= minimum_split_minutes
    adjusted_delta = raw_delta * reliability if actionable else 0.0
    # Usage is context, not a one-for-one projection adjustment. Limit its
    # influence to 8% even with an extreme split.
    projection_multiplier = max(0.92, min(1.08, 1 + adjusted_delta / 100))
    direction = (
        "OVER_CONTEXT"
        if adjusted_delta >= 2
        else "UNDER_CONTEXT"
        if adjusted_delta <= -2
        else "NEUTRAL"
    )
    return {
        "available": True,
        "actionable": actionable,
        "onUsagePercentage": round(on_rate, 2),
        "offUsagePercentage": round(off_rate, 2),
        "rawDeltaPercentagePoints": round(raw_delta, 2),
        "adjustedDeltaPercentagePoints": round(adjusted_delta, 2),
        "onMinutes": round(on.player_minutes, 1),
        "offMinutes": round(off.player_minutes, 1),
        "reliability": round(reliability, 4),
        "projectionMultiplier": round(projection_multiplier, 4),
        "direction": direction if actionable else "INSUFFICIENT_SAMPLE",
        "reason": (
            "Verified WOWY usage context; combine with price, matchup, and the calibrated model."
            if actionable
            else f"Each split needs at least {minimum_split_minutes:g} player minutes."
        ),
        "leagueId": "10",
        "sourceRequirement": "Substitution-aware WNBA play-by-play or verified stint totals",
    }

