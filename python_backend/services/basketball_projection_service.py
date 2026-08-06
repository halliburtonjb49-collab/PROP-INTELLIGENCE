"""Minutes-first basketball projections for the NBA and the WNBA.

A per-game average answers "how much does this player usually produce" and
therefore lags every change in role. Decomposing into opportunity and rate
answers "how much will they play, and how productive are they while playing",
which reacts to a rotation change immediately:

    stat = minutes * per-minute rate * context factors

The two leagues share this architecture and share no parameters. A WNBA game
is forty minutes rather than forty-eight, its rotations are shorter and
tighter, and its per-minute rates and variances are its own. Every constant
below is therefore looked up by sport, and no default silently applies NBA
behaviour to a WNBA player.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from random import Random
from statistics import fmean, pstdev
from typing import Mapping, Sequence

from services.projection_calibration_service import (
    recency_weighted_baseline,
    shrink_toward_prior,
)


@dataclass(frozen=True)
class LeagueParameters:
    """Everything that differs between the two leagues in one place."""

    regulation_minutes: int
    # A player cannot be projected past this; it is regulation length plus a
    # realistic overtime allowance, not a hard rule-book maximum.
    maximum_minutes: float
    starter_minutes: float
    rotation_minutes: float
    # Minutes moved per unit of each additive adjustment.
    blowout_minutes_penalty: float
    back_to_back_penalty: float
    return_from_injury_penalty: float
    absent_starter_bonus: float
    foul_trouble_penalty: float
    # A rotation is judged to have changed when recent minutes differ from the
    # prior stretch by more than this. WNBA rotations are shorter, so the same
    # absolute swing means more.
    rotation_change_minutes: float


LEAGUE_PARAMETERS: Mapping[str, LeagueParameters] = {
    "NBA": LeagueParameters(
        regulation_minutes=48,
        maximum_minutes=44.0,
        starter_minutes=30.0,
        rotation_minutes=20.0,
        blowout_minutes_penalty=4.5,
        back_to_back_penalty=2.0,
        return_from_injury_penalty=6.0,
        absent_starter_bonus=4.0,
        foul_trouble_penalty=3.0,
        rotation_change_minutes=4.0,
    ),
    "WNBA": LeagueParameters(
        regulation_minutes=40,
        maximum_minutes=38.0,
        starter_minutes=28.0,
        rotation_minutes=17.0,
        # Shorter games compress every rotation decision, so the same
        # situation moves fewer minutes in absolute terms.
        blowout_minutes_penalty=3.5,
        back_to_back_penalty=2.5,
        return_from_injury_penalty=5.0,
        absent_starter_bonus=3.5,
        foul_trouble_penalty=3.5,
        rotation_change_minutes=3.0,
    ),
}


def league_parameters(sport: str) -> LeagueParameters | None:
    return LEAGUE_PARAMETERS.get(str(sport or "").strip().upper())


@dataclass(frozen=True)
class MinutesContext:
    """Situational inputs for the minutes model.

    Every field is optional. A component is applied only when the input that
    drives it is actually known, and `applied` records which ones were, so a
    projection never silently implies information it did not have.
    """

    is_starter: bool | None = None
    absent_starters: int = 0
    is_back_to_back: bool | None = None
    returning_from_injury: bool | None = None
    # Absolute point spread. A wide one raises the chance starters sit late.
    game_spread: float | None = None
    fouls_per_36: float | None = None


@dataclass(frozen=True)
class MinutesProjection:
    minutes: float
    baseline: float
    adjustments: dict[str, float]
    role: str
    role_change: str
    volatility: float
    sample_size: int
    applied: tuple[str, ...] = field(default=())


# A spread beyond this is where fourth-quarter minutes start being given away.
_BLOWOUT_SPREAD = 12.0
_FOUL_TROUBLE_PER_36 = 4.5


def project_minutes(
    minutes_log: Sequence[float],
    *,
    sport: str,
    context: MinutesContext | None = None,
) -> MinutesProjection | None:
    """M = baseline + starter + injuries + rotation + spread + rest.

    The baseline is recency-weighted so a rotation change from three games ago
    already dominates; the additive terms then apply what the log cannot know.
    """

    parameters = league_parameters(sport)
    if parameters is None:
        return None
    played = [max(0.0, float(value)) for value in minutes_log if value is not None]
    if len(played) < 3:
        return None

    situation = context or MinutesContext()
    baseline = recency_weighted_baseline(played)
    adjustments: dict[str, float] = {}
    applied: list[str] = []

    recent = fmean(played[-3:])
    prior = played[-8:-3] or played[:-3] or played
    rotation_delta = recent - fmean(prior)
    if abs(rotation_delta) >= parameters.rotation_change_minutes:
        # The blend still carries older games; a confirmed rotation change
        # deserves more than its share of a trailing average.
        adjustments["rotation"] = round(rotation_delta * 0.35, 2)
        applied.append("rotation")

    if situation.is_starter is not None:
        target = (
            parameters.starter_minutes
            if situation.is_starter
            else parameters.rotation_minutes
        )
        # Only correct toward the role's minutes when the log disagrees with
        # the announced role, which is what a promotion or demotion looks like.
        gap = target - baseline
        if (situation.is_starter and gap > 0) or (
            not situation.is_starter and gap < 0
        ):
            adjustments["starter"] = round(gap * 0.45, 2)
            applied.append("starter")

    if situation.absent_starters:
        adjustments["injuries"] = round(
            min(2, int(situation.absent_starters)) * parameters.absent_starter_bonus,
            2,
        )
        applied.append("injuries")

    if situation.game_spread is not None:
        applied.append("spread")
        excess = abs(float(situation.game_spread)) - _BLOWOUT_SPREAD
        if excess > 0:
            share = min(1.0, excess / _BLOWOUT_SPREAD)
            adjustments["spread"] = round(
                -parameters.blowout_minutes_penalty * share, 2
            )

    if situation.is_back_to_back is not None:
        applied.append("rest")
        if situation.is_back_to_back:
            adjustments["rest"] = -parameters.back_to_back_penalty

    if situation.returning_from_injury is not None:
        applied.append("return")
        if situation.returning_from_injury:
            adjustments["return"] = -parameters.return_from_injury_penalty

    if situation.fouls_per_36 is not None:
        applied.append("fouls")
        if situation.fouls_per_36 > _FOUL_TROUBLE_PER_36:
            severity = min(
                1.0,
                (situation.fouls_per_36 - _FOUL_TROUBLE_PER_36) / 2.0,
            )
            adjustments["fouls"] = round(
                -parameters.foul_trouble_penalty * severity, 2
            )

    projected = baseline + sum(adjustments.values())
    projected = max(0.0, min(parameters.maximum_minutes, projected))
    volatility = pstdev(played) if len(played) > 1 else 0.0

    if projected >= parameters.starter_minutes:
        role = "HIGH_MINUTES"
    elif projected >= parameters.rotation_minutes:
        role = "ROTATION"
    else:
        role = "LIMITED"
    if rotation_delta >= parameters.rotation_change_minutes:
        role_change = "EXPANDED"
    elif rotation_delta <= -parameters.rotation_change_minutes:
        role_change = "REDUCED"
    else:
        role_change = "STABLE"

    return MinutesProjection(
        minutes=round(projected, 2),
        baseline=round(baseline, 2),
        adjustments=adjustments,
        role=role,
        role_change=role_change,
        volatility=round(volatility, 2),
        sample_size=len(played),
        applied=tuple(applied),
    )


@dataclass(frozen=True)
class PerMinuteRate:
    rate: float
    shrunk_from: float
    own_weight: float
    sample_minutes: float


# Per-minute rates from few minutes are noisy in the same way a per-game
# average from few games is, so they shrink toward the peer rate on the same
# w = N/(N+k) form, counted in minutes rather than games.
_RATE_SHRINKAGE_MINUTES = 120.0


def per_minute_rate(
    values: Sequence[float],
    minutes: Sequence[float],
    *,
    prior_rate: float | None = None,
) -> PerMinuteRate | None:
    """Production per minute, weighted by recency and shrunk on total minutes.

    Rates are computed from summed totals rather than by averaging per-game
    ratios, so a two-minute cameo cannot carry the same weight as a full game.
    """

    paired = [
        (float(value), float(played))
        for value, played in zip(values, minutes)
        if played is not None and float(played) > 0
    ]
    if not paired:
        return None
    recent_values = recency_weighted_baseline([value for value, _ in paired])
    recent_minutes = recency_weighted_baseline([played for _, played in paired])
    if recent_minutes <= 0:
        return None
    raw = recent_values / recent_minutes
    total_minutes = sum(played for _, played in paired)
    shrunk, own_weight = shrink_toward_prior(
        raw,
        prior_rate,
        sample_size=int(total_minutes),
        k=_RATE_SHRINKAGE_MINUTES,
    )
    return PerMinuteRate(
        rate=round(shrunk, 6),
        shrunk_from=round(raw, 6),
        own_weight=round(own_weight, 4),
        sample_minutes=round(total_minutes, 1),
    )


def project_stat(
    *,
    minutes: float,
    rate: float,
    pace_factor: float = 1.0,
    defense_factor: float = 1.0,
    role_factor: float = 1.0,
    efficiency_factor: float = 1.0,
) -> float:
    """stat = M * per-minute rate * pace * defense * role * efficiency.

    The factors are separate arguments rather than one combined multiplier so
    a projection can be explained by which of them moved it.
    """

    product = (
        max(0.0, float(minutes))
        * max(0.0, float(rate))
        * float(pace_factor)
        * float(defense_factor)
        * float(role_factor)
        * float(efficiency_factor)
    )
    return round(max(0.0, product), 4)


@dataclass(frozen=True)
class JointBasketballOutcome:
    points: float
    rebounds: float
    assists: float
    pra: float
    points_interval: tuple[float, float]
    rebounds_interval: tuple[float, float]
    assists_interval: tuple[float, float]
    pra_interval: tuple[float, float]
    simulations: int


def simulate_points_rebounds_assists(
    *,
    minutes: MinutesProjection,
    points_rate: float,
    rebounds_rate: float,
    assists_rate: float,
    sport: str,
    simulations: int = 4000,
    seed: int = 11,
    pace_factor: float = 1.0,
    defense_factor: float = 1.0,
) -> JointBasketballOutcome:
    """Draw the three components together rather than projecting each alone.

    Summing three separately-derived projections understates the spread of
    their total, because the largest driver of all three is the same number of
    minutes. Drawing minutes once per simulation and applying every rate to
    that draw carries the correlation through instead of assuming it away.
    """

    parameters = league_parameters(sport) or LEAGUE_PARAMETERS["NBA"]
    random = Random(seed)
    minutes_sigma = max(1.5, float(minutes.volatility))
    points: list[float] = []
    rebounds: list[float] = []
    assists: list[float] = []
    totals: list[float] = []

    context = float(pace_factor) * float(defense_factor)
    for _ in range(max(1, int(simulations))):
        played = random.gauss(minutes.minutes, minutes_sigma)
        played = max(0.0, min(parameters.maximum_minutes, played))
        # Per-minute efficiency varies game to game on top of minutes; without
        # it every simulated line would be a fixed multiple of the same draw.
        scored = max(0.0, played * points_rate * context * random.gauss(1.0, 0.18))
        boarded = max(0.0, played * rebounds_rate * context * random.gauss(1.0, 0.22))
        dished = max(0.0, played * assists_rate * context * random.gauss(1.0, 0.25))
        points.append(scored)
        rebounds.append(boarded)
        assists.append(dished)
        totals.append(scored + boarded + dished)

    def interval(samples: list[float]) -> tuple[float, float]:
        ordered = sorted(samples)
        low = ordered[int(0.10 * (len(ordered) - 1))]
        high = ordered[int(0.90 * (len(ordered) - 1))]
        return round(low, 2), round(high, 2)

    return JointBasketballOutcome(
        points=round(fmean(points), 3),
        rebounds=round(fmean(rebounds), 3),
        assists=round(fmean(assists), 3),
        pra=round(fmean(totals), 3),
        points_interval=interval(points),
        rebounds_interval=interval(rebounds),
        assists_interval=interval(assists),
        pra_interval=interval(totals),
        simulations=max(1, int(simulations)),
    )


@dataclass(frozen=True)
class ThreePointProjection:
    made: float
    attempts: float
    percentage: float
    alpha: float
    beta: float


# Prior strength for three-point percentage, in attempts. A shooter needs
# roughly this many attempts before their own rate outweighs the league's.
_THREE_POINT_PRIOR_ATTEMPTS = 60.0


def project_three_pointers(
    *,
    minutes: float,
    attempts_per_minute: float,
    made: float,
    attempted: float,
    league_percentage: float,
) -> ThreePointProjection:
    """3PM = M * 3PA/min * expected 3P%, with the percentage beta-binomial.

    A shooter who has hit 8 of 12 is not a 67% shooter. Treating the observed
    makes and attempts as evidence updating a beta prior centred on the league
    rate keeps a hot dozen attempts from projecting like a career.
    """

    prior_alpha = max(1e-6, float(league_percentage) * _THREE_POINT_PRIOR_ATTEMPTS)
    prior_beta = max(
        1e-6,
        (1.0 - float(league_percentage)) * _THREE_POINT_PRIOR_ATTEMPTS,
    )
    observed_made = max(0.0, float(made))
    observed_missed = max(0.0, float(attempted) - observed_made)
    alpha = prior_alpha + observed_made
    beta = prior_beta + observed_missed
    expected_percentage = alpha / (alpha + beta)
    projected_attempts = max(0.0, float(minutes) * float(attempts_per_minute))
    return ThreePointProjection(
        made=round(projected_attempts * expected_percentage, 4),
        attempts=round(projected_attempts, 3),
        percentage=round(expected_percentage, 5),
        alpha=round(alpha, 4),
        beta=round(beta, 4),
    )
