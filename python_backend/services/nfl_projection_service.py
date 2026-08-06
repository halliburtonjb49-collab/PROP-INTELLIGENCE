"""Opportunity-and-script projections for NFL player props.

Football props are decided by volume before efficiency. A receiver's yardage
follows from how many plays his offence runs, how many of them are passes, how
often he is on the field for them, and how often the ball comes his way --
efficiency only scales what opportunity has already decided. Every function
here therefore projects a count first and applies a rate second:

    plays -> attempts -> routes -> targets -> receptions -> yards

Nothing here invents an input. Each function takes the quantities it needs and
returns None when they are absent, so a caller falls back rather than
projecting on an assumed workload.
"""

from __future__ import annotations

from dataclasses import dataclass
from math import exp

# A neutral NFL offence runs roughly this many plays per game. Used only to
# express pace as a multiplier when a caller supplies rates rather than counts.
LEAGUE_NEUTRAL_PLAYS = 63.0

# Leading teams run to bleed clock and trailing teams throw to save it, so the
# spread moves pass rate in opposite directions for the two sides.
_SCRIPT_PASS_RATE_PER_POINT = 0.006
_MAX_SCRIPT_PASS_SHIFT = 0.09

# Bounds on every situational multiplier. Football samples are small enough
# that an unclamped ratio will occasionally produce an absurd projection.
_MIN_FACTOR = 0.80
_MAX_FACTOR = 1.20


def _clamp_factor(value: float) -> float:
    return max(_MIN_FACTOR, min(_MAX_FACTOR, float(value)))


@dataclass(frozen=True)
class TeamVolume:
    plays: float
    pass_attempts: float
    rush_attempts: float
    pass_rate: float


def project_team_plays(
    *,
    neutral_pace: float,
    opponent_pace: float,
    game_script_factor: float = 1.0,
    possession_adjustment: float = 1.0,
) -> float:
    """Plays = neutral pace * script * opponent pace * possession adjustment.

    Pace is averaged between the two teams rather than multiplied: both
    offences share one game clock, so a fast team facing a slow one lands
    between them rather than compounding.
    """

    shared_pace = (max(0.0, float(neutral_pace)) + max(0.0, float(opponent_pace))) / 2
    return round(
        max(0.0, shared_pace)
        * _clamp_factor(game_script_factor)
        * _clamp_factor(possession_adjustment),
        3,
    )


def script_pass_rate_shift(*, spread: float, is_favourite: bool) -> float:
    """How far the game script moves a team's pass rate, in rate points.

    A favourite protects a lead by running; an underdog throws to catch up.
    The shift is capped because even a four-score underdog still has to run
    occasionally, and no team abandons the pass entirely.
    """

    magnitude = min(
        _MAX_SCRIPT_PASS_SHIFT,
        abs(float(spread)) * _SCRIPT_PASS_RATE_PER_POINT,
    )
    return round(-magnitude if is_favourite else magnitude, 5)


def project_pass_attempts(
    *,
    plays: float,
    neutral_pass_rate: float,
    pass_rate_over_expectation: float = 0.0,
    spread: float | None = None,
    is_favourite: bool | None = None,
) -> TeamVolume:
    """Att = plays * (neutral pass rate + PROE + script shift).

    PROE is a team's standing tendency to pass more than its situations call
    for; the script shift is what this particular game does on top of it.
    """

    rate = float(neutral_pass_rate) + float(pass_rate_over_expectation)
    if spread is not None and is_favourite is not None:
        rate += script_pass_rate_shift(spread=spread, is_favourite=is_favourite)
    rate = max(0.20, min(0.80, rate))
    total_plays = max(0.0, float(plays))
    attempts = total_plays * rate
    return TeamVolume(
        plays=round(total_plays, 3),
        pass_attempts=round(attempts, 3),
        rush_attempts=round(total_plays - attempts, 3),
        pass_rate=round(rate, 5),
    )


def project_passing_yards(
    *,
    attempts: float,
    completion_probability: float,
    yards_per_completion: float,
) -> float:
    """PassYds = attempts * completion probability * yards per completion."""

    return round(
        max(0.0, float(attempts))
        * max(0.0, min(1.0, float(completion_probability)))
        * max(0.0, float(yards_per_completion)),
        3,
    )


def project_routes(*, dropbacks: float, route_participation: float) -> float:
    """Routes = dropbacks * route participation.

    Route participation is the input target share cannot replace: a receiver
    on the field for half his team's dropbacks has half the chance to be
    targeted, whatever his share of the targets that do come.
    """

    return round(
        max(0.0, float(dropbacks))
        * max(0.0, min(1.0, float(route_participation))),
        3,
    )


@dataclass(frozen=True)
class ReceivingProjection:
    routes: float
    targets: float
    receptions: float
    yards: float
    targets_per_route: float
    catch_rate: float


def project_receiving(
    *,
    routes: float,
    targets_per_route: float,
    catch_probability: float,
    yards_per_reception: float,
) -> ReceivingProjection:
    """RecYds = routes * TPRR * catch probability * yards per reception.

    Targets per route run is the honest denominator. Target share divides by
    the team's targets, which rewards a receiver whose offence throws often
    even when his own involvement has not changed.
    """

    run = max(0.0, float(routes))
    tprr = max(0.0, min(1.0, float(targets_per_route)))
    catch = max(0.0, min(1.0, float(catch_probability)))
    targets = run * tprr
    receptions = targets * catch
    return ReceivingProjection(
        routes=round(run, 3),
        targets=round(targets, 3),
        receptions=round(receptions, 3),
        yards=round(receptions * max(0.0, float(yards_per_reception)), 3),
        targets_per_route=round(tprr, 5),
        catch_rate=round(catch, 5),
    )


# Prior strength for catch rate, in targets. A receiver needs roughly this
# many before his own rate outweighs his role's.
_CATCH_RATE_PRIOR_TARGETS = 30.0


def expected_catch_rate(
    *,
    receptions: float,
    targets: float,
    role_catch_rate: float,
) -> float:
    """Catch rate as a beta posterior rather than a raw ratio.

    Four catches on five targets is not an 80% receiver. The role's rate acts
    as the prior, so a small sample stays near it and a large one leaves it.
    """

    prior_alpha = max(1e-6, float(role_catch_rate) * _CATCH_RATE_PRIOR_TARGETS)
    prior_beta = max(
        1e-6, (1.0 - float(role_catch_rate)) * _CATCH_RATE_PRIOR_TARGETS
    )
    caught = max(0.0, float(receptions))
    dropped = max(0.0, float(targets) - caught)
    return round((prior_alpha + caught) / (prior_alpha + prior_beta + caught + dropped), 5)


def project_rushing_yards(
    *,
    team_rush_attempts: float,
    carry_share: float,
    yards_per_carry: float,
    scramble_carries: float = 0.0,
) -> float:
    """RushYds = team attempts * carry share * yards per carry.

    Quarterback scrambles are added separately because they are not part of
    the designed-run pool a back's carry share divides.
    """

    designed = (
        max(0.0, float(team_rush_attempts))
        * max(0.0, min(1.0, float(carry_share)))
    )
    carries = designed + max(0.0, float(scramble_carries))
    return round(carries * max(0.0, float(yards_per_carry)), 3)


@dataclass(frozen=True)
class TouchdownProjection:
    expected_touchdowns: float
    any_touchdown_probability: float


def project_touchdowns(
    *,
    red_zone_opportunities: float,
    conversion_rate: float,
    goal_line_carries: float = 0.0,
    goal_line_conversion_rate: float = 0.0,
    end_zone_targets: float = 0.0,
    end_zone_conversion_rate: float = 0.0,
) -> TouchdownProjection:
    """P(any TD) = 1 - exp(-lambda), with lambda built from opportunity.

    Scoring chances arrive through separate channels that convert at very
    different rates -- a goal-line carry is not a red-zone target -- so lambda
    sums them rather than applying one rate to a merged count.
    """

    expected = (
        max(0.0, float(red_zone_opportunities)) * max(0.0, float(conversion_rate))
        + max(0.0, float(goal_line_carries))
        * max(0.0, float(goal_line_conversion_rate))
        + max(0.0, float(end_zone_targets))
        * max(0.0, float(end_zone_conversion_rate))
    )
    return TouchdownProjection(
        expected_touchdowns=round(expected, 5),
        any_touchdown_probability=round(1.0 - exp(-expected), 5),
    )


# Touchdown markets settle on a single binary event with a low rate, so an
# ordinary edge is inside the noise. Confidence must clear a higher bar.
TOUCHDOWN_MINIMUM_PROBABILITY = 0.62
TOUCHDOWN_MINIMUM_EDGE = 0.06


def touchdown_market_is_actionable(
    *,
    model_probability: float,
    market_probability: float | None,
) -> bool:
    """Stricter gate for touchdown props, which are high variance by nature."""

    if model_probability < TOUCHDOWN_MINIMUM_PROBABILITY:
        return False
    if market_probability is None:
        return False
    return (model_probability - float(market_probability)) >= TOUCHDOWN_MINIMUM_EDGE
