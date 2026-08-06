"""Monte Carlo over a shared game state, so correlated props move together.

The existing simulator asserts correlation: it builds a pairwise matrix from
heuristics and forces draws to obey it. That answers "how related do we think
these two props are" with a number somebody chose.

This one derives correlation instead. Each simulation draws one game -- its
pace, its margin, whether it goes to overtime, who is available -- and then
generates every prop in that game against that same draw. Two props end up
correlated because they were shaped by the same game, not because a
coefficient said so. A fast game lifts both teams' counting stats; a blowout
takes the fourth quarter away from both sides' starters; a player's own
minutes draw moves all of his own markets together.

That structure is what the Prop Builder needs: the joint probability of a
two-leg ticket is counted from simulations where both legs actually hit,
rather than multiplied as if the legs were independent.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from random import Random
from statistics import NormalDist, fmean, pstdev
from typing import Mapping, Sequence

from services.prop_probability_service import outcome_from_quantile

# The spec's floor. Below roughly this many draws the tail probabilities that
# decide a marginal pick are still moving between runs.
DEFAULT_SIMULATIONS = 10_000

# Rounding the adjusted mean before caching a discrete quantile table. Two
# decimals is far finer than any line resolution and keeps the cache small.
_QUANTILE_CACHE_PRECISION = 2

# Distributions whose variance cannot be set below their mean.
_COUNT_DISTRIBUTIONS = frozenset(
    {"poisson", "negative-binomial", "zero-inflated-poisson"}
)


@dataclass(frozen=True)
class GameState:
    """One simulated game, shared by every prop belonging to it."""

    pace_factor: float
    score_margin: float
    overtime_periods: int
    blowout: bool
    weather_factor: float

    @property
    def is_close(self) -> bool:
        return abs(self.score_margin) < 6.0


@dataclass(frozen=True)
class GameConditions:
    """What is known about the game before it is simulated."""

    expected_margin: float = 0.0
    margin_volatility: float = 12.0
    pace_volatility: float = 0.06
    overtime_probability: float = 0.06
    # Margin beyond which starters begin losing late minutes.
    blowout_margin: float = 16.0
    # 1.0 in a dome or good conditions; below that where weather suppresses.
    weather_factor: float = 1.0


@dataclass(frozen=True)
class PropSpec:
    """A prop to simulate, and how the game state moves it."""

    prop_id: str
    player: str
    team: str
    line: float
    side: str
    projection: float
    volatility: float
    distribution: str = "normal"
    # How much a faster game lifts this stat. Counting stats scale with
    # possessions; efficiency and per-attempt stats barely move.
    pace_sensitivity: float = 1.0
    # How much a blowout costs this stat, through lost late minutes. Starters
    # lose; nothing gains, so this is a reduction or nothing.
    blowout_sensitivity: float = 0.35
    # Whether the player's own minutes drive this stat, which is what ties a
    # player's markets to each other.
    minutes_driven: bool = True
    # Chance the player does not play at all.
    inactive_probability: float = 0.0
    weather_sensitivity: float = 0.0


@dataclass(frozen=True)
class PropOutcome:
    prop_id: str
    over_probability: float
    under_probability: float
    push_probability: float
    hit_probability: float
    mean_outcome: float
    outcome_volatility: float


@dataclass(frozen=True)
class SimulationResult:
    outcomes: Mapping[str, PropOutcome]
    correlations: Mapping[tuple[str, str], float]
    simulations: int
    method: str = "shared-game-state-monte-carlo"

    def joint_hit_probability(self, prop_ids: Sequence[str]) -> float | None:
        """Probability every leg hits, counted from the joint draws."""

        return self._joint.get(tuple(sorted(str(value) for value in prop_ids)))

    _joint: Mapping[tuple[str, ...], float] = field(default_factory=dict)


def draw_game_state(random: Random, conditions: GameConditions) -> GameState:
    """One game: how fast, how close, and whether it needed extra time."""

    margin = random.gauss(conditions.expected_margin, conditions.margin_volatility)
    pace = max(0.80, min(1.20, random.gauss(1.0, conditions.pace_volatility)))
    overtime = 0
    # Overtime is only reachable from a game that was close to level.
    if abs(margin) < 4.0 and random.random() < (conditions.overtime_probability / 0.25):
        overtime = 1
        # Extra periods add possessions to everyone still on the floor.
        pace *= 1.0 + (0.10 * overtime)
    return GameState(
        pace_factor=pace,
        score_margin=margin,
        overtime_periods=overtime,
        blowout=abs(margin) >= conditions.blowout_margin,
        weather_factor=conditions.weather_factor,
    )


# Fitted from stored basketball logs rather than chosen. Each was measured
# against the quantity the simulator actually needs, which is not always the
# obvious one:
#
#   minutes  residual spread around the recency-weighted minutes projection,
#            not the raw spread of minutes. Measured at 0.293 in both leagues,
#            and notably the projection does not narrow it -- minutes really
#            are that uncertain.
#   pace     spread of team possessions per game.
#   form     the part of per-minute production that a player's markets share.
#            Taken from the correlation between his own per-minute scoring,
#            rebounding and passing rates, which is low (0.048 NBA, 0.027
#            WNBA) but sits on top of a large rate spread, so the shared
#            component is rate_spread * sqrt(correlation) rather than either
#            number alone. Using the rate spread directly would treat pure
#            shooting luck as though it moved every market together.
@dataclass(frozen=True)
class CouplingVolatility:
    minutes: float
    pace: float
    form: float


FITTED_COUPLING: Mapping[str, CouplingVolatility] = {
    "NBA": CouplingVolatility(minutes=0.293, pace=0.056, form=0.118),
    "WNBA": CouplingVolatility(minutes=0.294, pace=0.072, form=0.097),
}

# Used where a sport has not been fitted. Deliberately the more conservative
# NBA figures rather than an average of everything.
DEFAULT_COUPLING = CouplingVolatility(minutes=0.293, pace=0.060, form=0.110)

DEFAULT_FORM_VOLATILITY = DEFAULT_COUPLING.form
DEFAULT_MINUTES_VOLATILITY = DEFAULT_COUPLING.minutes


def coupling_for(sport: str) -> CouplingVolatility:
    return FITTED_COUPLING.get(str(sport or "").strip().upper(), DEFAULT_COUPLING)


def residual_volatility(
    spec: PropSpec,
    *,
    minutes_volatility: float,
    pace_volatility: float,
    form_volatility: float = DEFAULT_FORM_VOLATILITY,
) -> float:
    """The prop's own randomness, with the shared game's share removed.

    A prop's historical volatility already contains the game-to-game swings in
    pace, script and minutes, because those games all happened. Drawing a game
    state and then drawing again at full volatility counts that variation
    twice: it inflates the spread and, worse, dilutes correlation, since the
    shared component becomes a small part of a total that is too large.

    Splitting total variance into the part the shared state explains and the
    part left over keeps the marginal spread honest while routing the shared
    part through the channel that actually ties props together.
    """

    residual, _ = variance_split(
        spec,
        minutes_volatility=minutes_volatility,
        pace_volatility=pace_volatility,
        form_volatility=form_volatility,
    )
    return residual


def variance_split(
    spec: PropSpec,
    *,
    minutes_volatility: float,
    pace_volatility: float,
    form_volatility: float = DEFAULT_FORM_VOLATILITY,
) -> tuple[float, float]:
    """Residual spread, and how far the shared channels must be scaled back.

    The shared channels are fitted league-wide while volatility arrives per
    prop, so nothing guarantees the first fits inside the second. A prop whose
    own spread is narrower than the league's minutes and pace swings imply
    would otherwise be simulated wider than it really is, because the residual
    cannot go below zero and the excess leaks into the total.

    Scaling the shared channels down for that prop keeps the marginal
    distribution right, which is the invariant every probability depends on.
    Correlation is what gives way instead, which is the correct thing to
    sacrifice: a prop that genuinely varies less than the league does move
    less with the game.
    """

    total_variance = max(1e-9, float(spec.volatility) ** 2)
    multiplier_variance = (spec.pace_sensitivity * pace_volatility) ** 2
    if spec.minutes_driven:
        multiplier_variance += minutes_volatility**2 + form_volatility**2
    shared_variance = (float(spec.projection) ** 2) * multiplier_variance
    if shared_variance <= 0:
        return float(spec.volatility), 1.0

    # Leave the prop some randomness of its own; a prop that is a pure
    # function of the game state is not something the data ever shows.
    usable_shared = min(shared_variance, total_variance * 0.85)

    if spec.distribution in _COUNT_DISTRIBUTIONS:
        # A Poisson or negative binomial cannot hold variance below its mean,
        # and asking for it silently falls back to a Poisson whose variance is
        # the mean -- which is larger than requested and quietly reinflates the
        # marginal. Cap the shared share so the residual stays representable.
        headroom = total_variance - float(spec.projection)
        usable_shared = min(usable_shared, max(0.0, headroom))

    scale = usable_shared / shared_variance
    residual = (max(0.0, total_variance - usable_shared)) ** 0.5
    return residual, scale


def _state_multiplier(
    state: GameState,
    spec: PropSpec,
    *,
    minutes_multiplier: float,
    form_multiplier: float = 1.0,
    shared_scale: float = 1.0,
) -> float:
    """How this game moves this prop, before its own randomness.

    shared_scale shrinks every shared swing toward one for a prop whose own
    spread cannot accommodate the league-wide channels at full strength.
    """

    damp = max(0.0, min(1.0, shared_scale)) ** 0.5
    multiplier = 1.0 + ((state.pace_factor - 1.0) * spec.pace_sensitivity * damp)
    if state.blowout and spec.blowout_sensitivity > 0:
        # A starter's late minutes are the first thing a decided game removes.
        multiplier *= 1.0 - (spec.blowout_sensitivity * 0.18)
    if spec.minutes_driven:
        multiplier *= 1.0 + ((minutes_multiplier - 1.0) * damp)
        multiplier *= 1.0 + ((form_multiplier - 1.0) * damp)
    if spec.weather_sensitivity > 0:
        multiplier *= 1.0 - (
            (1.0 - state.weather_factor) * spec.weather_sensitivity
        )
    return max(0.0, multiplier)


class _QuantileSampler:
    """Discrete quantile lookups, cached by the mean they were built for."""

    def __init__(self) -> None:
        self._cache: dict[tuple[str, float, float], float] = {}

    def outcome(
        self,
        quantile: float,
        *,
        projection: float,
        volatility: float,
        distribution: str,
    ) -> float:
        if distribution == "normal":
            # The common case has a closed form and needs no cache.
            return max(
                0.0, NormalDist(projection, max(1e-6, volatility)).inv_cdf(quantile)
            )
        key = (
            distribution,
            round(projection, _QUANTILE_CACHE_PRECISION),
            round(quantile, 3),
        )
        cached = self._cache.get(key)
        if cached is None:
            cached = outcome_from_quantile(
                quantile,
                projection=projection,
                volatility=volatility,
                distribution=distribution,
            )
            self._cache[key] = cached
        return cached


def simulate_game(
    specs: Sequence[PropSpec],
    *,
    conditions: GameConditions | None = None,
    simulations: int = DEFAULT_SIMULATIONS,
    seed: int = 7,
    sport: str = "",
    minutes_volatility: float | None = None,
    form_volatility: float | None = None,
) -> SimulationResult:
    """Simulate every prop in one game against a shared state per draw.

    Correlation is measured from the resulting outcomes rather than supplied,
    so what comes back describes the simulated games rather than restating an
    assumption.
    """

    if not specs:
        return SimulationResult(outcomes={}, correlations={}, simulations=0)

    setup = conditions or GameConditions()
    # Fitted values unless a caller overrides them, so a simulation reflects
    # the league it is simulating rather than one set of constants.
    coupling = coupling_for(sport)
    if minutes_volatility is None:
        minutes_volatility = coupling.minutes
    if form_volatility is None:
        form_volatility = coupling.form
    random = Random(seed)
    sampler = _QuantileSampler()
    draws = max(1, int(simulations))

    players = sorted({spec.player for spec in specs})
    split = {
        spec.prop_id: variance_split(
            spec,
            minutes_volatility=minutes_volatility,
            pace_volatility=setup.pace_volatility,
            form_volatility=form_volatility,
        )
        for spec in specs
    }
    residual = {key: value[0] for key, value in split.items()}
    samples: dict[str, list[float]] = {spec.prop_id: [] for spec in specs}
    hits: dict[str, list[int]] = {spec.prop_id: [] for spec in specs}
    over = {spec.prop_id: 0 for spec in specs}
    under = {spec.prop_id: 0 for spec in specs}
    push = {spec.prop_id: 0 for spec in specs}

    for _ in range(draws):
        state = draw_game_state(random, setup)
        # One minutes draw per player per game, shared by all of that player's
        # markets. This is what makes points and points-rebounds-assists move
        # together rather than independently.
        minutes_by_player = {
            player: max(0.0, random.gauss(1.0, minutes_volatility))
            for player in players
        }
        # A player's role on the night, drawn once and shared by all of his
        # markets. Minutes alone do not explain why a heavy-usage night lifts
        # points, rebounds and assists together.
        form_by_player = {
            player: max(0.0, random.gauss(1.0, form_volatility))
            for player in players
        }
        inactive = {
            player: random.random()
            for player in players
        }
        for spec in specs:
            if spec.inactive_probability > 0 and (
                inactive[spec.player] < spec.inactive_probability
            ):
                outcome = 0.0
            else:
                multiplier = _state_multiplier(
                    state,
                    spec,
                    minutes_multiplier=minutes_by_player[spec.player],
                    form_multiplier=form_by_player[spec.player],
                    shared_scale=split[spec.prop_id][1],
                )
                adjusted = max(0.0, spec.projection * multiplier)
                outcome = sampler.outcome(
                    random.random(),
                    projection=adjusted,
                    volatility=max(1e-6, residual[spec.prop_id]),
                    distribution=spec.distribution,
                )
            samples[spec.prop_id].append(outcome)
            if outcome > spec.line:
                over[spec.prop_id] += 1
            elif outcome < spec.line:
                under[spec.prop_id] += 1
            else:
                push[spec.prop_id] += 1
            wins = (
                outcome > spec.line
                if spec.side.strip().upper() == "OVER"
                else outcome < spec.line
            )
            hits[spec.prop_id].append(int(wins))

    outcomes = {
        spec.prop_id: PropOutcome(
            prop_id=spec.prop_id,
            over_probability=round(over[spec.prop_id] / draws, 5),
            under_probability=round(under[spec.prop_id] / draws, 5),
            push_probability=round(push[spec.prop_id] / draws, 5),
            hit_probability=round(sum(hits[spec.prop_id]) / draws, 5),
            mean_outcome=round(fmean(samples[spec.prop_id]), 4),
            outcome_volatility=round(pstdev(samples[spec.prop_id]), 4)
            if draws > 1
            else 0.0,
        )
        for spec in specs
    }

    correlations: dict[tuple[str, str], float] = {}
    for first in range(len(specs)):
        for second in range(first + 1, len(specs)):
            left, right = specs[first].prop_id, specs[second].prop_id
            correlations[(left, right)] = round(
                _correlation(samples[left], samples[right]), 4
            )

    joint: dict[tuple[str, ...], float] = {}
    for first in range(len(specs)):
        for second in range(first + 1, len(specs)):
            left, right = specs[first].prop_id, specs[second].prop_id
            both = sum(
                1
                for index in range(draws)
                if hits[left][index] and hits[right][index]
            )
            joint[tuple(sorted((left, right)))] = round(both / draws, 5)

    return SimulationResult(
        outcomes=outcomes,
        correlations=correlations,
        simulations=draws,
        _joint=joint,
    )


def _correlation(left: Sequence[float], right: Sequence[float]) -> float:
    if len(left) < 2:
        return 0.0
    left_mean, right_mean = fmean(left), fmean(right)
    left_spread = pstdev(left)
    right_spread = pstdev(right)
    if left_spread <= 0 or right_spread <= 0:
        return 0.0
    covariance = sum(
        (a - left_mean) * (b - right_mean) for a, b in zip(left, right)
    ) / len(left)
    return max(-1.0, min(1.0, covariance / (left_spread * right_spread)))


def ticket_probability(
    result: SimulationResult,
    prop_ids: Sequence[str],
) -> dict[str, object]:
    """Joint probability of a ticket, next to the independent assumption.

    The gap between the two is the point. Legs from one game are not
    independent, and multiplying their individual probabilities misprices a
    ticket in whichever direction their correlation runs.
    """

    ids = [str(value) for value in prop_ids]
    independent = 1.0
    for prop_id in ids:
        outcome = result.outcomes.get(prop_id)
        if outcome is None:
            return {"jointProbability": None, "reason": "unknown_prop"}
        independent *= outcome.hit_probability
    joint = result.joint_hit_probability(ids) if len(ids) == 2 else None
    return {
        "jointProbability": joint,
        "independentProbability": round(independent, 5),
        "correlationEffect": (
            round(joint - independent, 5) if joint is not None else None
        ),
        "legs": len(ids),
    }
