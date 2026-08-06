"""Distribution-aware prop probabilities, sharp blending, and push-aware EV."""

from __future__ import annotations

from dataclasses import dataclass
from math import exp, floor, isclose, lgamma, log, sqrt
from random import Random
from statistics import NormalDist
from typing import Callable


@dataclass(frozen=True)
class ProbabilityResult:
    over: float
    under: float
    push: float
    distribution: str
    variance: float

    def probability_for(self, side: str) -> float:
        return self.over if side.strip().upper() == "OVER" else self.under


@dataclass(frozen=True)
class EvResult:
    win_probability: float
    push_probability: float
    loss_probability: float
    decimal_odds: float
    expected_value: float
    fair_decimal_odds: float | None


@dataclass(frozen=True)
class MarketEvaluation:
    model_probability: float
    fair_probability: float
    market_probability: float | None
    push_probability: float
    loss_probability: float
    ev_percentage: float | None
    fair_decimal_odds: float | None
    is_positive_ev: bool
    distribution: str
    market_weight: float
    uncertainty: float
    calibration_adjustment: float
    recommended_stake_fraction: float
    over_probability: float = 0.0
    under_probability: float = 0.0
    interval_low: float = 0.0
    interval_high: float = 0.0


@dataclass(frozen=True)
class SelectionDecision:
    side: str
    confidence: int
    reason: str
    fair_probability: float | None
    uncertainty_adjusted_probability: float | None


def power_method_devig(
    over_probability: float,
    under_probability: float,
) -> tuple[float, float]:
    """Remove two-way market margin with the power method."""
    over = float(over_probability)
    under = float(under_probability)
    if not 0 < over < 1 or not 0 < under < 1:
        raise ValueError("Implied probabilities must be between zero and one")

    # Bisection avoids adding SciPy to the production runtime.
    low, high = 0.01, 20.0
    for _ in range(80):
        exponent = (low + high) / 2
        if over**exponent + under**exponent > 1:
            low = exponent
        else:
            high = exponent
    exponent = (low + high) / 2
    fair_over = over**exponent
    fair_under = under**exponent
    total = fair_over + fair_under
    return round(fair_over / total, 6), round(fair_under / total, 6)


def shin_method_devig(*implied_probabilities: float) -> tuple[float, ...]:
    """Remove market margin using Shin's informed-trader model.

    The inputs must describe every mutually exclusive outcome in one market.
    Bisection is used instead of a SciPy dependency. Markets without a
    positive overround fall back to proportional normalization because Shin's
    insider-share parameter has no admissible positive root there.
    """
    probabilities = tuple(float(value) for value in implied_probabilities)
    if len(probabilities) < 2:
        raise ValueError("Shin devigging requires at least two outcomes")
    if any(not 0 < value < 1 for value in probabilities):
        raise ValueError("Implied probabilities must be between zero and one")
    overround = sum(probabilities)
    if overround <= 1.0 + 1e-12:
        return tuple(round(value / overround, 6) for value in probabilities)

    def adjusted(z: float) -> tuple[float, ...]:
        denominator = 2 * (1 - z)
        return tuple(
            (sqrt(z * z + 4 * (1 - z) * value * value / overround) - z)
            / denominator
            for value in probabilities
        )

    low, high = 0.0, 1.0 - 1e-12
    if sum(adjusted(high)) > 1:
        return tuple(round(value / overround, 6) for value in probabilities)
    for _ in range(100):
        midpoint = (low + high) / 2
        if sum(adjusted(midpoint)) > 1:
            low = midpoint
        else:
            high = midpoint
    fair = adjusted((low + high) / 2)
    total = sum(fair)
    return tuple(round(value / total, 6) for value in fair)


def fractional_kelly_stake(
    *,
    win_probability: float,
    decimal_odds: float,
    fraction: float = 0.25,
) -> float:
    """Return a capped fractional-Kelly bankroll share for positive-EV plays."""
    probability = max(0.0, min(1.0, float(win_probability)))
    net_odds = float(decimal_odds) - 1.0
    if net_odds <= 0 or fraction <= 0:
        return 0.0
    full_kelly = (probability * float(decimal_odds) - 1.0) / net_odds
    return round(max(0.0, min(1.0, full_kelly * min(1.0, fraction))), 6)


# A projection is only half the story; the distribution around it decides the
# probability. Counting markets are discrete and overdispersed, yardage is
# right-skewed and non-negative, and a thin sample has fatter tails than a
# normal admits. Each shape below exists because one of those is true.

# Below this many games the tails are wider than a normal describes, so
# continuous markets use Student-t with the sample's degrees of freedom.
_THIN_CONTINUOUS_SAMPLE = 15
_MINIMUM_T_DEGREES_OF_FREEDOM = 3

# Below this mean, a market that names a countable event is a count no matter
# what other tokens its name carries.
_COUNT_MEAN_CEILING = 10.0

_COUNT_TOKENS = (
    "strikeout",
    "home run",
    "touchdown",
    "goal",
    "hit",
    "shot",
    "save",
    "steal",
    "block",
    "assist",
    "rebound",
    "reception",
    "tackle",
    "wicket",
    "walk",
    "double fault",
    "ace",
)

# Yardage accumulates over a variable number of plays and cannot go negative,
# which leaves a right tail a symmetric distribution understates.
_SKEWED_CONTINUOUS_TOKENS = ("yard", "rushing", "receiving")

_CONTINUOUS_TOKENS = _SKEWED_CONTINUOUS_TOKENS + ("passing", "points rebounds")


def distribution_for_market(
    sport: str,
    market: str,
    *,
    mean: float,
    variance: float,
    sample_size: int = 0,
    zero_rate: float | None = None,
) -> str:
    text = f"{sport} {market}".lower().replace("_", " ")
    low_count = any(token in text for token in _COUNT_TOKENS)
    continuous = any(token in text for token in _CONTINUOUS_TOKENS)
    # "Passing touchdowns" and "rushing touchdowns" match a continuous token
    # and a counting one. At these means they are counts: a normal would put
    # real mass below zero and none on the exact integers that decide the bet.
    if low_count and mean < _COUNT_MEAN_CEILING:
        continuous = False
    if continuous or ("point" in text and mean >= 10):
        if 0 < sample_size < _THIN_CONTINUOUS_SAMPLE:
            return "student-t"
        if any(token in text for token in _SKEWED_CONTINUOUS_TOKENS) and mean > 0:
            return "log-normal"
        return "normal"
    if low_count:
        # Excess zeros beyond what the mean implies mean two processes are at
        # work — whether the player gets a chance at all, and how often they
        # convert. One Poisson rate cannot describe both.
        if zero_rate is not None and mean > 0 and zero_rate > exp(-mean) + 0.10:
            return "zero-inflated-poisson"
        if variance > max(mean * 1.15, mean + 0.25):
            return "negative-binomial"
        return "poisson"
    return "normal"


def _poisson_cdf(k: int, mean: float) -> float:
    if k < 0:
        return 0.0
    if mean <= 0:
        return 1.0
    probability = exp(-mean)
    total = probability
    for value in range(1, k + 1):
        probability *= mean / value
        total += probability
    return min(1.0, total)


def _poisson_pmf(k: int, mean: float) -> float:
    if k < 0:
        return 0.0
    if mean <= 0:
        return 1.0 if k == 0 else 0.0
    return exp((k * log(mean)) - mean - lgamma(k + 1))


def _negative_binomial_cdf(k: int, mean: float, variance: float) -> float:
    if k < 0:
        return 0.0
    if mean <= 0:
        return 1.0
    safe_variance = max(variance, mean + 1e-6)
    shape = mean * mean / (safe_variance - mean)
    success = shape / (shape + mean)
    probability = success**shape
    total = probability
    for value in range(k):
        probability *= ((value + shape) / (value + 1)) * (1 - success)
        total += probability
    return min(1.0, total)


def _regularized_incomplete_beta(a: float, b: float, x: float) -> float:
    """I_x(a, b) via the Lentz continued fraction, avoiding a SciPy dependency."""

    if x <= 0:
        return 0.0
    if x >= 1:
        return 1.0
    # The fraction converges quickly only on the near side of the mode; the
    # symmetry I_x(a,b) = 1 - I_{1-x}(b,a) covers the other.
    if x > (a + 1) / (a + b + 2):
        return 1.0 - _regularized_incomplete_beta(b, a, 1 - x)

    front = exp(
        lgamma(a + b) - lgamma(a) - lgamma(b) + a * log(x) + b * log(1 - x)
    )
    tiny = 1e-30
    c = 1.0
    d = 1.0 - (a + b) * x / (a + 1)
    d = tiny if abs(d) < tiny else d
    d = 1.0 / d
    result = d
    for m in range(1, 300):
        m2 = 2 * m
        for numerator in (
            m * (b - m) * x / ((a + m2 - 1) * (a + m2)),
            -(a + m) * (a + b + m) * x / ((a + m2) * (a + m2 + 1)),
        ):
            d = 1.0 + numerator * d
            d = tiny if abs(d) < tiny else d
            c = 1.0 + numerator / c
            c = tiny if abs(c) < tiny else c
            d = 1.0 / d
            result *= c * d
        if abs(c * d - 1.0) < 1e-14:
            break
    return front * result / a


def student_t_cdf(t: float, degrees_of_freedom: float) -> float:
    """P(T <= t) for Student's t with the given degrees of freedom."""

    df = max(1.0, float(degrees_of_freedom))
    tail = 0.5 * _regularized_incomplete_beta(df / 2, 0.5, df / (df + t * t))
    return 1.0 - tail if t > 0 else tail


def _student_t_over(mean: float, sigma: float, line: float, df: float) -> float:
    if sigma <= 0:
        return 1.0 if mean > line else 0.0
    return 1.0 - student_t_cdf((line - mean) / sigma, df)


def _log_normal_parameters(mean: float, variance: float) -> tuple[float, float]:
    """Underlying normal mu and sigma that reproduce this mean and variance."""

    safe_mean = max(mean, 1e-9)
    sigma_squared = log(1.0 + (variance / (safe_mean * safe_mean)))
    return log(safe_mean) - (sigma_squared / 2), sqrt(max(sigma_squared, 1e-12))


def _log_normal_over(mean: float, variance: float, line: float) -> float:
    if line <= 0:
        return 1.0
    mu, sigma = _log_normal_parameters(mean, variance)
    return 1.0 - NormalDist(mu, sigma).cdf(log(line))


def _zero_inflated_parameters(mean: float, zero_rate: float) -> tuple[float, float]:
    """Inflation share and Poisson rate matching an observed zero frequency.

    The pair must satisfy mean = (1 - pi) * lam and zero_rate = pi + (1 - pi)
    * exp(-lam). Both are monotone in pi, so bisection is stable.
    """

    observed_zero = max(0.0, min(0.999, float(zero_rate)))
    if mean <= 0 or observed_zero <= exp(-mean):
        return 0.0, max(mean, 0.0)

    def zero_probability(inflation: float) -> float:
        rate = mean / max(1e-9, 1 - inflation)
        return inflation + (1 - inflation) * exp(-rate)

    low, high = 0.0, 0.999
    for _ in range(80):
        midpoint = (low + high) / 2
        if zero_probability(midpoint) < observed_zero:
            low = midpoint
        else:
            high = midpoint
    inflation = (low + high) / 2
    return inflation, mean / max(1e-9, 1 - inflation)


def _zero_inflated_poisson_cdf(k: int, mean: float, zero_rate: float) -> float:
    if k < 0:
        return 0.0
    inflation, rate = _zero_inflated_parameters(mean, zero_rate)
    return min(1.0, inflation + (1 - inflation) * _poisson_cdf(k, rate))


def _zero_inflated_poisson_pmf(k: int, mean: float, zero_rate: float) -> float:
    if k < 0:
        return 0.0
    inflation, rate = _zero_inflated_parameters(mean, zero_rate)
    poisson = _poisson_pmf(k, rate)
    return (inflation + (1 - inflation) * poisson) if k == 0 else (1 - inflation) * poisson


def _negative_binomial_pmf(k: int, mean: float, variance: float) -> float:
    if k < 0:
        return 0.0
    if mean <= 0:
        return 1.0 if k == 0 else 0.0
    safe_variance = max(variance, mean + 1e-6)
    shape = mean * mean / (safe_variance - mean)
    success = shape / (shape + mean)
    return exp(
        lgamma(k + shape)
        - lgamma(shape)
        - lgamma(k + 1)
        + shape * log(success)
        + k * log(1 - success)
    )


def prop_probabilities(
    *,
    projection: float,
    line: float,
    volatility: float,
    sport: str,
    market: str,
    sample_size: int = 0,
    zero_rate: float | None = None,
) -> ProbabilityResult:
    mean = max(0.0, float(projection))
    variance = max(1e-6, float(volatility) ** 2)
    distribution = distribution_for_market(
        sport,
        market,
        mean=mean,
        variance=variance,
        sample_size=sample_size,
        zero_rate=zero_rate,
    )
    integer_line = isclose(line, round(line), abs_tol=1e-9)
    boundary = floor(line)

    if distribution == "poisson":
        below_or_equal = _poisson_cdf(boundary, mean)
        push = _poisson_pmf(boundary, mean) if integer_line else 0.0
        under = below_or_equal - push if integer_line else below_or_equal
        over = 1.0 - below_or_equal
    elif distribution == "negative-binomial":
        below_or_equal = _negative_binomial_cdf(boundary, mean, variance)
        push = (
            _negative_binomial_pmf(boundary, mean, variance)
            if integer_line
            else 0.0
        )
        under = below_or_equal - push if integer_line else below_or_equal
        over = 1.0 - below_or_equal
    elif distribution == "zero-inflated-poisson":
        observed_zero = float(zero_rate or 0.0)
        below_or_equal = _zero_inflated_poisson_cdf(boundary, mean, observed_zero)
        push = (
            _zero_inflated_poisson_pmf(boundary, mean, observed_zero)
            if integer_line
            else 0.0
        )
        under = below_or_equal - push if integer_line else below_or_equal
        over = 1.0 - below_or_equal
    elif distribution == "log-normal":
        over = _log_normal_over(mean, variance, line)
        under = 1.0 - over
        push = 0.0
    elif distribution == "student-t":
        sigma = sqrt(variance)
        degrees_of_freedom = max(
            _MINIMUM_T_DEGREES_OF_FREEDOM, float(sample_size) - 1
        )
        correction = 0.5 if integer_line else 0.0
        over = _student_t_over(mean, sigma, line + correction, degrees_of_freedom)
        under = student_t_cdf(
            (line - correction - mean) / sigma, degrees_of_freedom
        )
        push = max(0.0, 1.0 - over - under) if integer_line else 0.0
    else:
        sigma = sqrt(variance)
        # A continuity correction better approximates integer counting outcomes.
        over = 1.0 - NormalDist(mean, sigma).cdf(line + (0.5 if integer_line else 0))
        under = NormalDist(mean, sigma).cdf(line - (0.5 if integer_line else 0))
        push = max(0.0, 1.0 - over - under) if integer_line else 0.0

    total = max(1e-12, over + under + push)
    return ProbabilityResult(
        over=round(max(0.0, over / total), 6),
        under=round(max(0.0, under / total), 6),
        push=round(max(0.0, push / total), 6),
        distribution=distribution,
        variance=round(variance, 6),
    )


def projection_interval(
    *,
    projection: float,
    volatility: float,
    distribution: str,
    coverage: float = 0.80,
    sample_size: int = 0,
    zero_rate: float | None = None,
) -> tuple[float, float]:
    """Central interval from the same distribution that produced the odds.

    A projection without a range invites false precision: 25.4 against a line
    of 23.5 reads very differently when the interval is 24-27 than when it is
    12-39.
    """

    share = max(0.0, min(0.99, float(coverage)))
    tail = (1.0 - share) / 2
    low = outcome_from_quantile(
        tail,
        projection=projection,
        volatility=volatility,
        distribution=distribution,
        sample_size=sample_size,
        zero_rate=zero_rate,
    )
    high = outcome_from_quantile(
        1 - tail,
        projection=projection,
        volatility=volatility,
        distribution=distribution,
        sample_size=sample_size,
        zero_rate=zero_rate,
    )
    return round(min(low, high), 2), round(max(low, high), 2)


def blend_with_sharp_market(
    model_probability: float,
    sharp_probability: float | None,
    *,
    sample_size: int,
    model_calibrated: bool,
) -> tuple[float, float]:
    if sharp_probability is None:
        return round(model_probability, 6), 0.0
    reliability = max(0.0, min(1.0, sample_size / 40.0))
    market_weight = 0.45 - (0.25 * reliability)
    if not model_calibrated:
        market_weight = max(market_weight, 0.35)
    blended = (
        model_probability * (1 - market_weight)
        + float(sharp_probability) * market_weight
    )
    return round(max(0.01, min(0.99, blended)), 6), round(market_weight, 4)


def expected_value(
    *,
    win_probability: float,
    push_probability: float,
    decimal_odds: float,
) -> EvResult:
    win = max(0.0, min(1.0, float(win_probability)))
    push = max(0.0, min(1.0 - win, float(push_probability)))
    loss = max(0.0, 1.0 - win - push)
    decimal = float(decimal_odds)
    ev = (win * decimal) + push - 1.0
    fair = (1.0 - push) / win if win > 0 else None
    return EvResult(
        win_probability=round(win, 6),
        push_probability=round(push, 6),
        loss_probability=round(loss, 6),
        decimal_odds=round(decimal, 4),
        expected_value=round(ev, 6),
        fair_decimal_odds=round(fair, 4) if fair is not None else None,
    )


def evaluate_market(
    *,
    projection: float,
    line: float,
    volatility: float,
    sport: str,
    market: str,
    side: str,
    sample_size: int,
    model_calibrated: bool,
    empirical_hit_rate: float | None,
    sharp_probability: float | None,
    decimal_odds: float | None,
    calibration_adjustment: float = 0.0,
    zero_rate: float | None = None,
    probability_calibrator: Callable[[float], float] | None = None,
) -> MarketEvaluation:
    probabilities = prop_probabilities(
        projection=projection,
        line=line,
        volatility=volatility,
        sport=sport,
        market=market,
        sample_size=sample_size,
        zero_rate=zero_rate,
    )
    raw = probabilities.probability_for(side)
    reliability = max(0.0, min(1.0, sample_size / (sample_size + 20.0)))
    model_probability = 0.5 + (raw - 0.5) * reliability
    if empirical_hit_rate is not None:
        empirical = max(0.0, min(1.0, empirical_hit_rate))
        empirical_weight = min(0.35, sample_size / 100.0)
        model_probability = (
            model_probability * (1 - empirical_weight)
            + empirical * empirical_weight
        )
    model_probability = max(0.01, min(0.99, model_probability))
    # Order matters. The fitted curve corrects the sport's overall shape, and
    # the additive adjustment is fitted against already-calibrated
    # probabilities, so it carries only the residual bias of one market. The
    # curve must therefore run first, or the additive term would be applied to
    # a probability it was never fitted against.
    if probability_calibrator is not None:
        model_probability = max(
            0.01, min(0.99, float(probability_calibrator(model_probability)))
        )
    applied_adjustment = max(-0.08, min(0.08, calibration_adjustment))
    model_probability = max(
        0.01, min(0.99, model_probability + applied_adjustment)
    )
    fair, market_weight = blend_with_sharp_market(
        model_probability,
        sharp_probability,
        sample_size=sample_size,
        model_calibrated=model_calibrated,
    )
    fair = round(min(fair, 1.0 - probabilities.push), 6)
    ev_result = (
        expected_value(
            win_probability=fair,
            push_probability=probabilities.push,
            decimal_odds=decimal_odds,
        )
        if decimal_odds is not None
        else None
    )
    loss = max(0.0, 1.0 - fair - probabilities.push)
    uncertainty = sqrt(max(0.0, fair * (1 - fair)) / max(1, sample_size))
    interval_low, interval_high = projection_interval(
        projection=projection,
        volatility=volatility,
        distribution=probabilities.distribution,
        sample_size=sample_size,
        zero_rate=zero_rate,
    )
    return MarketEvaluation(
        model_probability=round(model_probability, 6),
        fair_probability=fair,
        market_probability=sharp_probability,
        push_probability=probabilities.push,
        loss_probability=round(loss, 6),
        ev_percentage=(
            round(ev_result.expected_value * 100, 2) if ev_result is not None else None
        ),
        fair_decimal_odds=(
            ev_result.fair_decimal_odds if ev_result is not None else None
        ),
        is_positive_ev=(
            ev_result is not None and ev_result.expected_value > 0
        ),
        distribution=probabilities.distribution,
        market_weight=market_weight,
        uncertainty=round(uncertainty, 6),
        calibration_adjustment=round(applied_adjustment, 6),
        recommended_stake_fraction=(
            fractional_kelly_stake(
                win_probability=fair,
                decimal_odds=decimal_odds,
            )
            if decimal_odds is not None
            else 0.0
        ),
        over_probability=probabilities.over,
        under_probability=probabilities.under,
        interval_low=interval_low,
        interval_high=interval_high,
    )


def choose_over_under(
    over: MarketEvaluation,
    under: MarketEvaluation,
    *,
    minimum_probability: float = 0.58,
    minimum_uncertainty_adjusted_probability: float = 0.58,
    minimum_separation: float = 0.04,
    minimum_expected_value_percent: float = 1.0,
) -> SelectionDecision:
    """Select the stronger side only when its uncertainty-adjusted edge clears gates."""
    winner, runner_up, side = (
        (over, under, "OVER")
        if over.fair_probability >= under.fair_probability
        else (under, over, "UNDER")
    )
    adjusted = winner.fair_probability - winner.uncertainty
    separation = winner.fair_probability - runner_up.fair_probability
    if winner.fair_probability < minimum_probability:
        reason = "probability_below_threshold"
    elif adjusted < minimum_uncertainty_adjusted_probability:
        reason = "uncertainty_overlaps_even_probability"
    elif separation < minimum_separation:
        reason = "sides_too_close"
    elif (
        winner.ev_percentage is not None
        and winner.ev_percentage < minimum_expected_value_percent
    ):
        reason = "expected_value_below_threshold"
    else:
        return SelectionDecision(
            side=side,
            confidence=round(adjusted * 100),
            reason="ensemble_probability_and_value_clear_thresholds",
            fair_probability=winner.fair_probability,
            uncertainty_adjusted_probability=round(adjusted, 6),
        )
    return SelectionDecision(
        side="N/A",
        confidence=0,
        reason=reason,
        fair_probability=winner.fair_probability,
        uncertainty_adjusted_probability=round(adjusted, 6),
    )


def sample_prop_outcome(
    random: Random,
    *,
    projection: float,
    volatility: float,
    distribution: str,
) -> float:
    mean = max(0.0, projection)
    variance = max(1e-6, volatility * volatility)
    if distribution == "normal":
        return max(0.0, random.gauss(mean, sqrt(variance)))
    if distribution == "log-normal":
        mu, sigma = _log_normal_parameters(mean, variance)
        return max(0.0, exp(random.gauss(mu, sigma)))
    if distribution == "student-t":
        # A t draw is a normal scaled by an independent chi-square, which
        # random.gammavariate supplies without a SciPy dependency.
        df = max(_MINIMUM_T_DEGREES_OF_FREEDOM, 8.0)
        chi_square = 2.0 * random.gammavariate(df / 2, 1.0)
        scaled = random.gauss(0.0, 1.0) / sqrt(chi_square / df)
        return max(0.0, mean + sqrt(variance) * scaled)
    poisson_mean = mean
    if distribution == "negative-binomial" and variance > mean:
        shape = mean * mean / (variance - mean)
        poisson_mean = random.gammavariate(shape, mean / shape)
    # Exact inversion is stable for ordinary player-prop means.
    threshold = random.random()
    probability = exp(-poisson_mean)
    cumulative = probability
    value = 0
    while threshold > cumulative and value < 500:
        value += 1
        probability *= poisson_mean / value
        cumulative += probability
    return float(value)


def outcome_from_quantile(
    quantile: float,
    *,
    projection: float,
    volatility: float,
    distribution: str,
    sample_size: int = 0,
    zero_rate: float | None = None,
) -> float:
    target = max(1e-9, min(1 - 1e-9, quantile))
    mean = max(0.0, projection)
    variance = max(1e-6, volatility * volatility)
    if mean <= 0 and distribution not in {"normal", "student-t"}:
        # A count distribution with no mean produces nothing. Reached when a
        # simulated game state scales a projection to zero, and previously a
        # division by zero in the negative-binomial shape.
        return 0.0
    if distribution == "normal":
        return max(0.0, NormalDist(mean, sqrt(variance)).inv_cdf(target))
    if distribution == "log-normal":
        mu, sigma = _log_normal_parameters(mean, variance)
        return max(0.0, exp(mu + sigma * NormalDist().inv_cdf(target)))
    if distribution == "student-t":
        degrees_of_freedom = max(
            _MINIMUM_T_DEGREES_OF_FREEDOM, float(sample_size) - 1
        )
        low, high = -60.0, 60.0
        for _ in range(200):
            midpoint = (low + high) / 2
            if student_t_cdf(midpoint, degrees_of_freedom) < target:
                low = midpoint
            else:
                high = midpoint
        return max(0.0, mean + sqrt(variance) * ((low + high) / 2))
    cumulative = 0.0
    value = 0
    if distribution == "zero-inflated-poisson":
        inflation, rate = _zero_inflated_parameters(mean, float(zero_rate or 0.0))
        probability = inflation + (1 - inflation) * exp(-rate)
        poisson = exp(-rate)
        while value < 500:
            cumulative += probability
            if cumulative >= target:
                return float(value)
            value += 1
            poisson *= rate / value
            probability = (1 - inflation) * poisson
        return float(value)
    if distribution == "negative-binomial" and variance > mean:
        safe_variance = max(variance, mean + 1e-6)
        shape = mean * mean / (safe_variance - mean)
        success = shape / (shape + mean)
        probability = success**shape
        while value < 500:
            cumulative += probability
            if cumulative >= target:
                return float(value)
            probability *= ((value + shape) / (value + 1)) * (1 - success)
            value += 1
    else:
        probability = exp(-mean)
        while value < 500:
            cumulative += probability
            if cumulative >= target:
                return float(value)
            value += 1
            probability *= mean / value
    return float(value)
