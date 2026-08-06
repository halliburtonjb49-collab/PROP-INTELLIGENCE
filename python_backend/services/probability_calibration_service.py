"""Isotonic recalibration of model probabilities, fitted per sport.

The reliability curve showed the model is underconfident below even money and
overconfident just above it, with the two errors cancelling in the aggregate.
That shape is a monotonic distortion: the ordering of predictions is mostly
right while the numbers attached to them are not. Isotonic regression is the
correct tool for exactly that -- it finds the non-decreasing function of
predicted probability that best fits observed outcomes, correcting the values
without reordering them.

Nothing here changes a projection. It changes only the probability derived
from one, which is what the reliability curve measured and what betting
decisions are made on.

A fitted map is only used when it beats the identity on data it was not
fitted to. In-sample improvement is guaranteed and meaningless; the guard is
what makes this safe to apply.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from math import log
from threading import Lock
from typing import Sequence

from database.postgres import database_is_configured, get_database_pool

# Below this many graded outcomes a fitted curve is mostly noise.
MINIMUM_FIT_SAMPLE = 500

# Share of the sample held back to judge whether the fit actually helps.
HOLDOUT_FRACTION = 0.30

# A fit must beat the identity by at least this much log loss on held-out data
# before it is used, so a wash never displaces the untouched probability.
MINIMUM_LOG_LOSS_GAIN = 0.002

# Calibrated probabilities stay inside this range. A prop is never a certainty
# and the downstream expected-value maths must not divide by zero.
_FLOOR = 0.02
_CEILING = 0.98

_CACHE_TTL = timedelta(hours=6)


@dataclass(frozen=True)
class CalibrationMap:
    """A fitted monotonic map from raw probability to calibrated probability."""

    sport: str
    # Ascending breakpoints and the calibrated value at or above each.
    thresholds: tuple[float, ...]
    values: tuple[float, ...]
    sample_size: int
    holdout_log_loss_gain: float
    holdout_sample_size: int

    def apply(self, probability: float) -> float:
        raw = max(0.0, min(1.0, float(probability)))
        if not self.thresholds:
            return raw
        # The calibrated value is the one attached to the last breakpoint at or
        # below the raw probability.
        calibrated = self.values[0]
        for threshold, value in zip(self.thresholds, self.values):
            if raw >= threshold:
                calibrated = value
            else:
                break
        return max(_FLOOR, min(_CEILING, calibrated))


def _log_loss(pairs: Sequence[tuple[float, bool]]) -> float:
    if not pairs:
        return 0.0
    return -sum(
        log(max(1e-12, probability)) if outcome else log(max(1e-12, 1 - probability))
        for probability, outcome in pairs
    ) / len(pairs)


def fit_isotonic(
    pairs: Sequence[tuple[float, bool]],
) -> tuple[tuple[float, ...], tuple[float, ...]]:
    """Pool adjacent violators: the best non-decreasing fit to the outcomes.

    Predictions are sorted by probability and neighbouring groups are merged
    whenever a later group has a lower observed rate than an earlier one, which
    is the only thing isotonic regression forbids. What survives is a step
    function that never decreases.
    """

    ordered = sorted(pairs, key=lambda pair: pair[0])
    if not ordered:
        return (), ()

    # Each block carries its lower edge, its summed outcomes and its weight.
    blocks: list[list[float]] = []
    for probability, outcome in ordered:
        blocks.append([probability, 1.0 if outcome else 0.0, 1.0])
        # Merge backwards while the sequence would otherwise decrease.
        while len(blocks) > 1:
            previous, current = blocks[-2], blocks[-1]
            if (previous[1] / previous[2]) <= (current[1] / current[2]):
                break
            previous[1] += current[1]
            previous[2] += current[2]
            blocks.pop()

    thresholds = tuple(block[0] for block in blocks)
    values = tuple(round(block[1] / block[2], 6) for block in blocks)
    return thresholds, values


def _split(
    pairs: Sequence[tuple[float, bool]],
    *,
    holdout_fraction: float,
) -> tuple[list[tuple[float, bool]], list[tuple[float, bool]]]:
    """Split into fit and holdout deterministically, without shuffling.

    Every third-ish prediction is held out by position rather than at random,
    so the split is reproducible and both halves span the whole probability
    range instead of one of them landing in a corner of it.
    """

    if not pairs:
        return [], []
    step = max(2, round(1 / max(0.01, holdout_fraction)))
    fit: list[tuple[float, bool]] = []
    holdout: list[tuple[float, bool]] = []
    for index, pair in enumerate(pairs):
        (holdout if index % step == 0 else fit).append(pair)
    return fit, holdout


def build_calibration_map(
    pairs: Sequence[tuple[float, bool]],
    *,
    sport: str = "",
    minimum_sample: int = MINIMUM_FIT_SAMPLE,
    holdout_fraction: float = HOLDOUT_FRACTION,
    minimum_gain: float = MINIMUM_LOG_LOSS_GAIN,
) -> CalibrationMap | None:
    """Fit a map and return it only if it beats the identity out of sample.

    Returning None means the raw probabilities stand. That is the right answer
    whenever the fit cannot be shown to help, because an unvalidated
    correction is just a different kind of error.
    """

    graded = [
        (max(0.0, min(1.0, float(probability))), bool(outcome))
        for probability, outcome in pairs
        if probability is not None and outcome is not None
    ]
    if len(graded) < minimum_sample:
        return None

    fit_pairs, holdout_pairs = _split(graded, holdout_fraction=holdout_fraction)
    if not fit_pairs or not holdout_pairs:
        return None

    thresholds, values = fit_isotonic(fit_pairs)
    if not thresholds:
        return None
    candidate = CalibrationMap(
        sport=str(sport or "").upper(),
        thresholds=thresholds,
        values=values,
        sample_size=len(graded),
        holdout_log_loss_gain=0.0,
        holdout_sample_size=len(holdout_pairs),
    )

    baseline = _log_loss(holdout_pairs)
    calibrated = _log_loss(
        [(candidate.apply(probability), outcome) for probability, outcome in holdout_pairs]
    )
    gain = baseline - calibrated
    if gain < minimum_gain:
        return None
    return CalibrationMap(
        sport=candidate.sport,
        thresholds=thresholds,
        values=values,
        sample_size=len(graded),
        holdout_log_loss_gain=round(gain, 6),
        holdout_sample_size=len(holdout_pairs),
    )


def _fetch_graded(sport: str, days: int) -> list[tuple[float, bool]]:
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select hit_probability, hit from prediction_snapshots
               where hit is not null and hit_probability is not null
                 and upper(sport) = upper(%s)
                 and created_at >= now() - (%s || ' days')::interval
               order by created_at""",
            (sport, str(max(1, int(days)))),
        )
        return [(float(row[0]), bool(row[1])) for row in cursor.fetchall()]


class _CalibrationRegistry:
    """Per-sport maps, refitted on a schedule rather than per request."""

    def __init__(self) -> None:
        self._maps: dict[str, CalibrationMap | None] = {}
        self._loaded_at: dict[str, datetime] = {}
        self._lock = Lock()

    def _fresh(self, sport: str) -> bool:
        loaded = self._loaded_at.get(sport)
        return loaded is not None and datetime.now(timezone.utc) - loaded < _CACHE_TTL

    def map_for(self, sport: str, *, days: int = 365) -> CalibrationMap | None:
        key = str(sport or "").upper()
        if not key or not database_is_configured():
            return None
        if self._fresh(key):
            return self._maps.get(key)
        with self._lock:
            if self._fresh(key):
                return self._maps.get(key)
            try:
                fitted = build_calibration_map(
                    _fetch_graded(key, days), sport=key
                )
            except Exception:
                # Calibration is an improvement, not a dependency. A database
                # problem must leave the raw probabilities serving.
                fitted = None
            self._maps[key] = fitted
            self._loaded_at[key] = datetime.now(timezone.utc)
            return fitted

    def reset(self) -> None:
        with self._lock:
            self._maps.clear()
            self._loaded_at.clear()


_REGISTRY = _CalibrationRegistry()


def calibrated_probability(probability: float, *, sport: str) -> float:
    """Apply the sport's fitted map, or return the probability untouched."""

    fitted = _REGISTRY.map_for(sport)
    if fitted is None:
        return float(probability)
    return fitted.apply(probability)


def calibration_status(sport: str) -> dict[str, object]:
    fitted = _REGISTRY.map_for(sport)
    if fitted is None:
        return {"sport": str(sport).upper(), "fitted": False, "reason": "no_validated_fit"}
    return {
        "sport": fitted.sport,
        "fitted": True,
        "sampleSize": fitted.sample_size,
        "holdoutSampleSize": fitted.holdout_sample_size,
        "holdoutLogLossGain": fitted.holdout_log_loss_gain,
        "breakpoints": len(fitted.thresholds),
    }


def reset_calibration_cache() -> None:
    _REGISTRY.reset()


def calibration_map_for(sport: str) -> CalibrationMap | None:
    """The fitted map for a sport, or None when none passed validation."""

    return _REGISTRY.map_for(sport)
