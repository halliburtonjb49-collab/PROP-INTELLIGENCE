"""Delivery-level cricket projections, separated by format.

Cricket's formats are different sports wearing one name. A T20 innings is
twenty overs of controlled aggression; a Test innings has no over limit and
rewards survival. Blending them produces a baseline that describes neither,
so every function requires a format and no default is supplied.

The batting model is a survival problem before it is a scoring one. A batter
does not face a fixed number of balls -- they face balls until they are
dismissed or the innings ends -- so expected runs is a sum over deliveries
weighted by the probability of still being there to face them:

    E[runs] = sum over i of P(survive to ball i) * E[runs on ball i]
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

T20 = "T20"
ODI = "ODI"
TEST = "TEST"
HUNDRED = "THE_HUNDRED"


@dataclass(frozen=True)
class FormatProfile:
    """Per-format behaviour. Never shared between formats."""

    name: str
    balls_per_innings: int
    # Chance of dismissal on any given delivery, before adjustment. Aggression
    # and survival trade off differently in each format.
    base_dismissal_hazard: float
    base_runs_per_ball: float
    boundary_rate_per_ball: float
    powerplay_balls: int


FORMAT_PROFILES: Mapping[str, FormatProfile] = {
    T20: FormatProfile(
        name="Twenty20",
        balls_per_innings=120,
        base_dismissal_hazard=0.035,
        base_runs_per_ball=1.35,
        boundary_rate_per_ball=0.14,
        powerplay_balls=36,
    ),
    ODI: FormatProfile(
        name="One Day International",
        balls_per_innings=300,
        base_dismissal_hazard=0.021,
        base_runs_per_ball=0.95,
        boundary_rate_per_ball=0.10,
        powerplay_balls=60,
    ),
    TEST: FormatProfile(
        name="Test",
        # No over limit; the figure bounds a single day's batting rather than
        # an innings, and survival dominates scoring rate entirely.
        balls_per_innings=540,
        base_dismissal_hazard=0.011,
        base_runs_per_ball=0.52,
        boundary_rate_per_ball=0.055,
        powerplay_balls=0,
    ),
    HUNDRED: FormatProfile(
        name="The Hundred",
        balls_per_innings=100,
        base_dismissal_hazard=0.038,
        base_runs_per_ball=1.40,
        boundary_rate_per_ball=0.15,
        powerplay_balls=25,
    ),
}


def format_profile(match_format: str) -> FormatProfile | None:
    """Profile for a format, or None when it is not one of the four.

    Returning None rather than defaulting is the point: projecting a Test
    innings on Twenty20 hazards would be nonsense, and silently doing so is
    the failure this prevents.
    """

    return FORMAT_PROFILES.get(str(match_format or "").strip().upper())


def survival_curve(
    dismissal_hazards: Sequence[float],
) -> list[float]:
    """P(survive through ball n) = product of (1 - hazard) up to n.

    Hazards are taken per delivery rather than as one average because a
    batter is most vulnerable early, before they have judged the pace and
    bounce, and the product of a varying hazard is not the power of its mean.
    """

    survival: list[float] = []
    alive = 1.0
    for hazard in dismissal_hazards:
        alive *= max(0.0, 1.0 - max(0.0, min(1.0, float(hazard))))
        survival.append(round(alive, 8))
    return survival


@dataclass(frozen=True)
class BattingProjection:
    expected_balls: float
    expected_runs: float
    expected_boundaries: float
    survival_to_end: float


def project_batting(
    *,
    match_format: str,
    dismissal_hazards: Sequence[float],
    runs_per_ball: Sequence[float] | float | None = None,
    boundary_rate_per_ball: float | None = None,
    matchup_factor: float = 1.0,
) -> BattingProjection | None:
    """Expected balls, runs and boundaries from a per-delivery hazard curve.

    Expected balls faced is itself an output of the survival curve, not an
    input: it is the sum of the probabilities of surviving to face each one.
    """

    profile = format_profile(match_format)
    if profile is None or not dismissal_hazards:
        return None

    survival = survival_curve(dismissal_hazards)
    # The batter faces ball i only if they survived ball i-1, so the chance of
    # facing each delivery is the survival probability before it.
    facing = [1.0] + survival[:-1]
    expected_balls = sum(facing)

    if runs_per_ball is None:
        rates = [profile.base_runs_per_ball] * len(facing)
    elif isinstance(runs_per_ball, (int, float)):
        rates = [float(runs_per_ball)] * len(facing)
    else:
        rates = [float(value) for value in runs_per_ball]
        rates += [profile.base_runs_per_ball] * (len(facing) - len(rates))

    matchup = max(0.5, min(1.5, float(matchup_factor)))
    expected_runs = sum(
        chance * rate * matchup for chance, rate in zip(facing, rates)
    )
    boundary_rate = (
        profile.boundary_rate_per_ball
        if boundary_rate_per_ball is None
        else max(0.0, min(1.0, float(boundary_rate_per_ball)))
    )
    return BattingProjection(
        expected_balls=round(expected_balls, 4),
        expected_runs=round(expected_runs, 4),
        expected_boundaries=round(expected_balls * boundary_rate * matchup, 4),
        survival_to_end=round(survival[-1], 6),
    )


def position_hazard_curve(
    *,
    match_format: str,
    balls: int,
    batting_position: int,
    settling_balls: int = 12,
    settling_multiplier: float = 1.8,
) -> list[float] | None:
    """Per-delivery dismissal hazard for a batting position.

    Two effects are modelled. A new batter is markedly more likely to be out
    in their first few deliveries than once set, and a lower-order batter both
    faces a stronger scoring imperative and has less support, so their hazard
    is higher throughout.
    """

    profile = format_profile(match_format)
    if profile is None or balls <= 0:
        return None
    position = max(1, min(11, int(batting_position)))
    # Openers and the top order carry the lowest baseline hazard; it rises
    # down the card.
    position_multiplier = 1.0 + ((position - 1) * 0.06)
    hazards: list[float] = []
    for index in range(int(balls)):
        hazard = profile.base_dismissal_hazard * position_multiplier
        if index < max(0, int(settling_balls)):
            hazard *= max(1.0, float(settling_multiplier))
        hazards.append(min(0.95, hazard))
    return hazards


@dataclass(frozen=True)
class BowlingProjection:
    expected_balls: float
    expected_wickets: float
    expected_runs_conceded: float


# Scoring against a bowler depends on when they bowl far more than on who they
# bowl to. Death overs are a different game from the powerplay.
PHASE_RUN_MULTIPLIERS: Mapping[str, float] = {
    "powerplay": 1.15,
    "middle": 0.88,
    "death": 1.45,
}
PHASE_WICKET_MULTIPLIERS: Mapping[str, float] = {
    "powerplay": 1.10,
    "middle": 0.85,
    "death": 1.30,
}


def project_bowling(
    *,
    match_format: str,
    expected_overs: float,
    wicket_probability_per_ball: float,
    runs_allowed_per_ball: float,
    phase: str = "middle",
) -> BowlingProjection | None:
    """Wickets and runs conceded from expected deliveries, split by phase.

    Runs and wickets are both scaled by phase rather than by a single overall
    factor, because the death overs raise scoring far more than they raise
    wicket chances -- a bowler there concedes more and takes only slightly
    more.
    """

    profile = format_profile(match_format)
    if profile is None:
        return None
    balls = max(0.0, float(expected_overs)) * 6.0
    run_multiplier = PHASE_RUN_MULTIPLIERS.get(str(phase).lower(), 1.0)
    wicket_multiplier = PHASE_WICKET_MULTIPLIERS.get(str(phase).lower(), 1.0)
    return BowlingProjection(
        expected_balls=round(balls, 3),
        expected_wickets=round(
            balls
            * max(0.0, min(1.0, float(wicket_probability_per_ball)))
            * wicket_multiplier,
            4,
        ),
        expected_runs_conceded=round(
            balls * max(0.0, float(runs_allowed_per_ball)) * run_multiplier, 4
        ),
    )
