"""Distribution-aware prop probabilities, sharp blending, and push-aware EV."""

from __future__ import annotations

from dataclasses import dataclass
from math import exp, floor, isclose, lgamma, log, sqrt
from random import Random
from statistics import NormalDist


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


def distribution_for_market(
    sport: str,
    market: str,
    *,
    mean: float,
    variance: float,
) -> str:
    text = f"{sport} {market}".lower().replace("_", " ")
    low_count = any(
        token in text
        for token in (
            "strikeout",
            "home run",
            "touchdown",
            "goal",
            "hit",
            "shot",
            "steal",
            "block",
            "assist",
            "rebound",
        )
    )
    continuous_or_compound = any(
        token in text
        for token in ("yard", "passing", "rushing", "receiving", "points rebounds")
    )
    if continuous_or_compound or ("point" in text and mean >= 10):
        return "normal"
    if low_count:
        return "negative-binomial" if variance > max(mean * 1.15, mean + 0.25) else "poisson"
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
) -> ProbabilityResult:
    mean = max(0.0, float(projection))
    variance = max(1e-6, float(volatility) ** 2)
    distribution = distribution_for_market(
        sport, market, mean=mean, variance=variance
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
) -> MarketEvaluation:
    probabilities = prop_probabilities(
        projection=projection,
        line=line,
        volatility=volatility,
        sport=sport,
        market=market,
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
    )


def choose_over_under(
    over: MarketEvaluation,
    under: MarketEvaluation,
    *,
    minimum_probability: float = 0.55,
    minimum_separation: float = 0.03,
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
    elif adjusted <= 0.50:
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
            confidence=round(winner.fair_probability * 100),
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
) -> float:
    target = max(1e-9, min(1 - 1e-9, quantile))
    mean = max(0.0, projection)
    variance = max(1e-6, volatility * volatility)
    if distribution == "normal":
        return max(0.0, NormalDist(mean, sqrt(variance)).inv_cdf(target))
    cumulative = 0.0
    value = 0
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
