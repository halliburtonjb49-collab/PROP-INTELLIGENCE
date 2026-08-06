"""Ice-time and situation-split projections for NHL player props.

Hockey props are an ice-time problem with a strength-state complication. A
winger's shot total depends on how many minutes he plays, but those minutes
are not interchangeable: a power-play minute produces shots at a very
different rate from a shorthanded one, and a player whose power-play role
changes can see his totals move while his overall ice time does not.

Projections therefore split opportunity by situation and sum:

    SOG = SOG(5v5) + SOG(PP) + SOG(SH)
"""

from __future__ import annotations

from dataclasses import dataclass
from math import exp

# Strength states a skater's ice time divides into. Kept explicit so a caller
# cannot silently omit one and have its shots vanish from the total.
STRENGTH_STATES = ("even", "power_play", "short_handed")


@dataclass(frozen=True)
class SituationIceTime:
    even: float = 0.0
    power_play: float = 0.0
    short_handed: float = 0.0

    @property
    def total(self) -> float:
        return self.even + self.power_play + self.short_handed


@dataclass(frozen=True)
class SituationShotRates:
    """Attempts per minute and the share reaching the net, by strength state.

    On-goal rate is separate from attempt rate because they move
    independently: a point shot from the blue line on the power play is
    blocked far more often than an even-strength chance from the slot.
    """

    even_attempts_per_minute: float = 0.0
    power_play_attempts_per_minute: float = 0.0
    short_handed_attempts_per_minute: float = 0.0
    even_on_goal_rate: float = 0.55
    power_play_on_goal_rate: float = 0.50
    short_handed_on_goal_rate: float = 0.60


@dataclass(frozen=True)
class ShotsProjection:
    shots_on_goal: float
    even: float
    power_play: float
    short_handed: float
    opponent_factor: float


def project_shots_on_goal(
    *,
    ice_time: SituationIceTime,
    rates: SituationShotRates,
    opponent_factor: float = 1.0,
) -> ShotsProjection:
    """SOG = sum over strength states of TOI * attempts/min * on-goal rate."""

    factor = max(0.75, min(1.25, float(opponent_factor)))
    even = (
        max(0.0, ice_time.even)
        * max(0.0, rates.even_attempts_per_minute)
        * max(0.0, min(1.0, rates.even_on_goal_rate))
    )
    power_play = (
        max(0.0, ice_time.power_play)
        * max(0.0, rates.power_play_attempts_per_minute)
        * max(0.0, min(1.0, rates.power_play_on_goal_rate))
    )
    short_handed = (
        max(0.0, ice_time.short_handed)
        * max(0.0, rates.short_handed_attempts_per_minute)
        * max(0.0, min(1.0, rates.short_handed_on_goal_rate))
    )
    # The opponent's suppression applies to the whole total rather than to any
    # one state, since it describes how the game is played, not the special
    # teams' structure.
    return ShotsProjection(
        shots_on_goal=round((even + power_play + short_handed) * factor, 4),
        even=round(even * factor, 4),
        power_play=round(power_play * factor, 4),
        short_handed=round(short_handed * factor, 4),
        opponent_factor=round(factor, 4),
    )


@dataclass(frozen=True)
class PointsProjection:
    goals: float
    assists: float
    points: float
    any_point_probability: float


def project_points(
    *,
    expected_shots: float,
    shooting_percentage: float,
    team_expected_goals_on_ice: float,
    assist_participation: float,
) -> PointsProjection:
    """E[points] = E[goals] + E[assists].

    Goals come from the player's own shots; assists come from the goals his
    team scores while he is on the ice and how often he is involved in them.
    The two are counted separately because a playmaker and a shooter reach the
    same point total by different routes.
    """

    goals = max(0.0, float(expected_shots)) * max(
        0.0, min(1.0, float(shooting_percentage))
    )
    # A player cannot assist his own goal, so the team's on-ice expectation is
    # reduced by his share of it before assist participation is applied.
    teammate_goals = max(0.0, float(team_expected_goals_on_ice) - goals)
    assists = teammate_goals * max(0.0, min(2.0, float(assist_participation)))
    total = goals + assists
    return PointsProjection(
        goals=round(goals, 5),
        assists=round(assists, 5),
        points=round(total, 5),
        # Points are counts, so the chance of at least one follows from the
        # Poisson rate rather than from the mean being above a line.
        any_point_probability=round(1.0 - exp(-total), 5),
    )


@dataclass(frozen=True)
class SavesProjection:
    saves: float
    shots_against: float
    save_percentage: float
    pull_adjusted: bool


def project_goalie_saves(
    *,
    opponent_shot_volume: float,
    team_suppression_factor: float = 1.0,
    expected_save_percentage: float = 0.905,
    is_back_to_back: bool = False,
    pull_probability: float = 0.0,
) -> SavesProjection:
    """Saves = expected shots against * expected save percentage.

    Shots against is the volatile term and the one worth modelling carefully:
    save percentage varies far less between goalies than shot volume varies
    between games.
    """

    shots = max(0.0, float(opponent_shot_volume)) * max(
        0.75, min(1.25, float(team_suppression_factor))
    )
    if is_back_to_back:
        # A rested opponent generates marginally more; the effect is small and
        # deliberately conservative.
        shots *= 1.02
    pull = max(0.0, min(1.0, float(pull_probability)))
    if pull > 0:
        # A pulled goalie stops facing shots. Roughly the last tenth of the
        # game is lost when it happens.
        shots *= 1.0 - (pull * 0.10)
    percentage = max(0.0, min(1.0, float(expected_save_percentage)))
    return SavesProjection(
        saves=round(shots * percentage, 4),
        shots_against=round(shots, 4),
        save_percentage=round(percentage, 5),
        pull_adjusted=pull > 0,
    )
