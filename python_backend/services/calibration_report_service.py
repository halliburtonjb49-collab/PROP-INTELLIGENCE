"""Reliability curves: of everything called 60%, how much of it won.

Brier score and log loss already answer "how good are these probabilities" with
one number. Neither says *where* they are wrong, and the two failures that
matter look identical in a summary statistic: a model that is confidently
wrong at the top of its range and one that is timid in the middle can post the
same Brier score while needing opposite fixes.

Binning by predicted probability separates them. A model is calibrated when
the observed rate inside each bin matches the probability the bin was labelled
with, so the gap per bin is the diagnosis and the sample size per bin is how
much to trust it.
"""

from __future__ import annotations

from dataclasses import dataclass
from math import sqrt
from typing import Sequence

from database.postgres import database_is_configured, get_database_pool

DEFAULT_BUCKET_WIDTH = 0.05

# A bin below this is reported but not judged. Ten graded picks can sit twenty
# points off their label through luck alone.
MINIMUM_BUCKET_SAMPLE = 30

# Standard errors beyond which a gap is unlikely to be noise.
_MISCALIBRATION_SIGMA = 2.0


@dataclass(frozen=True)
class CalibrationBucket:
    lower: float
    upper: float
    sample_size: int
    predicted: float
    observed: float
    gap: float
    standard_error: float
    judged: bool

    @property
    def is_miscalibrated(self) -> bool:
        """Whether the gap is larger than sampling noise explains."""

        if not self.judged or self.standard_error <= 0:
            return False
        return abs(self.gap) > (_MISCALIBRATION_SIGMA * self.standard_error)


@dataclass(frozen=True)
class CalibrationReport:
    buckets: tuple[CalibrationBucket, ...]
    sample_size: int
    expected_calibration_error: float | None
    maximum_calibration_error: float | None
    brier_score: float | None
    log_loss: float | None
    overall_predicted: float | None
    overall_observed: float | None
    judged_sample_size: int

    @property
    def direction(self) -> str:
        """Whether the model runs hot, cold, or neither, over judged bins."""

        if self.overall_predicted is None or self.overall_observed is None:
            return "unknown"
        gap = self.overall_predicted - self.overall_observed
        if abs(gap) < 0.01:
            return "calibrated"
        return "overconfident" if gap > 0 else "underconfident"


def build_calibration_report(
    predictions: Sequence[tuple[float, bool]],
    *,
    bucket_width: float = DEFAULT_BUCKET_WIDTH,
    minimum_bucket_sample: int = MINIMUM_BUCKET_SAMPLE,
) -> CalibrationReport:
    """Bin (predicted probability, outcome) pairs into a reliability curve.

    Expected calibration error weights each bin by how many predictions landed
    in it, so a badly calibrated bin holding six picks cannot outweigh a good
    one holding six hundred.
    """

    graded = [
        (max(0.0, min(1.0, float(probability))), bool(outcome))
        for probability, outcome in predictions
        if probability is not None and outcome is not None
    ]
    if not graded:
        return CalibrationReport(
            buckets=(),
            sample_size=0,
            expected_calibration_error=None,
            maximum_calibration_error=None,
            brier_score=None,
            log_loss=None,
            overall_predicted=None,
            overall_observed=None,
            judged_sample_size=0,
        )

    width = max(0.01, min(0.5, float(bucket_width)))
    # Binary representation makes 0.60 / 0.05 land just under twelve, which
    # would file a prediction of exactly 0.60 in the bin below its own label.
    # The same rounding is needed on the bin count, or the top bin is clamped
    # one place too low and the highest predictions are misreported.
    epsilon = 1e-9
    last_index = max(0, round(1 / width) - 1)
    bins: dict[int, list[tuple[float, bool]]] = {}
    for probability, outcome in graded:
        # The top edge belongs to the last bin rather than opening a new one.
        index = min(int((probability / width) + epsilon), last_index)
        bins.setdefault(index, []).append((probability, outcome))

    buckets: list[CalibrationBucket] = []
    for index in sorted(bins):
        entries = bins[index]
        count = len(entries)
        predicted = sum(probability for probability, _ in entries) / count
        observed = sum(1 for _, outcome in entries if outcome) / count
        # Binomial standard error of the observed rate.
        error = sqrt(max(0.0, observed * (1 - observed)) / count) if count else 0.0
        buckets.append(
            CalibrationBucket(
                lower=round(index * width, 4),
                upper=round((index + 1) * width, 4),
                sample_size=count,
                predicted=round(predicted, 5),
                observed=round(observed, 5),
                gap=round(predicted - observed, 5),
                standard_error=round(error, 5),
                judged=count >= minimum_bucket_sample,
            )
        )

    judged = [bucket for bucket in buckets if bucket.judged]
    judged_total = sum(bucket.sample_size for bucket in judged)
    expected_error = (
        sum(abs(bucket.gap) * bucket.sample_size for bucket in judged) / judged_total
        if judged_total
        else None
    )
    maximum_error = max((abs(bucket.gap) for bucket in judged), default=None)

    brier = sum(
        (probability - (1.0 if outcome else 0.0)) ** 2 for probability, outcome in graded
    ) / len(graded)
    # Clamped so a probability of exactly zero or one cannot make the loss
    # infinite and destroy the average.
    from math import log

    log_loss = -sum(
        log(max(1e-12, probability)) if outcome else log(max(1e-12, 1 - probability))
        for probability, outcome in graded
    ) / len(graded)

    return CalibrationReport(
        buckets=tuple(buckets),
        sample_size=len(graded),
        expected_calibration_error=(
            round(expected_error, 5) if expected_error is not None else None
        ),
        maximum_calibration_error=(
            round(maximum_error, 5) if maximum_error is not None else None
        ),
        brier_score=round(brier, 6),
        log_loss=round(log_loss, 6),
        overall_predicted=(
            round(
                sum(bucket.predicted * bucket.sample_size for bucket in judged)
                / judged_total,
                5,
            )
            if judged_total
            else None
        ),
        overall_observed=(
            round(
                sum(bucket.observed * bucket.sample_size for bucket in judged)
                / judged_total,
                5,
            )
            if judged_total
            else None
        ),
        judged_sample_size=judged_total,
    )


def report_as_dict(report: CalibrationReport) -> dict[str, object]:
    return {
        "sampleSize": report.sample_size,
        "judgedSampleSize": report.judged_sample_size,
        "expectedCalibrationError": report.expected_calibration_error,
        "maximumCalibrationError": report.maximum_calibration_error,
        "brierScore": report.brier_score,
        "logLoss": report.log_loss,
        "overallPredicted": report.overall_predicted,
        "overallObserved": report.overall_observed,
        "direction": report.direction,
        "buckets": [
            {
                "range": f"{bucket.lower:.2f}-{bucket.upper:.2f}",
                "sampleSize": bucket.sample_size,
                "predicted": bucket.predicted,
                "observed": bucket.observed,
                "gap": bucket.gap,
                "standardError": bucket.standard_error,
                "judged": bucket.judged,
                "miscalibrated": bucket.is_miscalibrated,
            }
            for bucket in report.buckets
        ],
    }


def _fetch_graded(
    *,
    model_version: str | None,
    sport: str | None,
    market: str | None,
    days: int,
) -> list[tuple[float, bool]]:
    clauses = ["hit is not null", "hit_probability is not null"]
    parameters: list[object] = []
    if model_version:
        clauses.append("model_version = %s")
        parameters.append(model_version)
    if sport:
        clauses.append("upper(sport) = upper(%s)")
        parameters.append(sport)
    if market:
        clauses.append("lower(market) = lower(%s)")
        parameters.append(market)
    clauses.append("created_at >= now() - (%s || ' days')::interval")
    parameters.append(str(max(1, int(days))))

    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            f"""select hit_probability, hit from prediction_snapshots
                where {' and '.join(clauses)}""",
            tuple(parameters),
        )
        return [(float(row[0]), bool(row[1])) for row in cursor.fetchall()]


def calibration_report(
    *,
    model_version: str | None = None,
    sport: str | None = None,
    market: str | None = None,
    days: int = 180,
    bucket_width: float = DEFAULT_BUCKET_WIDTH,
) -> dict[str, object]:
    """Reliability curve over graded predictions, optionally per segment."""

    if not database_is_configured():
        return {"configured": False, "sampleSize": 0, "buckets": []}
    graded = _fetch_graded(
        model_version=model_version, sport=sport, market=market, days=days
    )
    report = build_calibration_report(graded, bucket_width=bucket_width)
    return {
        "configured": True,
        "modelVersion": model_version,
        "sport": sport,
        "market": market,
        "days": days,
        **report_as_dict(report),
    }


def calibration_by_sport(
    *,
    days: int = 180,
    bucket_width: float = DEFAULT_BUCKET_WIDTH,
) -> list[dict[str, object]]:
    """One reliability curve per sport.

    A model can be well calibrated overall while being badly wrong in one
    sport, because the aggregate hides offsetting errors.
    """

    if not database_is_configured():
        return []
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select distinct sport from prediction_snapshots
               where hit is not null and sport is not null
                 and created_at >= now() - (%s || ' days')::interval""",
            (str(max(1, int(days))),),
        )
        sports = [str(row[0]) for row in cursor.fetchall() if row[0]]
    return [
        calibration_report(sport=sport, days=days, bucket_width=bucket_width)
        for sport in sorted(sports)
    ]


# Both sides priced at -110 need this to break even.
STANDARD_BREAK_EVEN = 0.5238


def served_pick_performance(
    predictions: Sequence[tuple[float, bool]],
    *,
    release_threshold: float,
    break_even: float = STANDARD_BREAK_EVEN,
) -> dict[str, object]:
    """How the picks that clear the release gate actually did.

    The reliability curve covers every evaluated prop, most of which are never
    shown to anyone. Judging the product by that curve mistakes the model's
    scratch paper for its output: the only rows that matter commercially are
    the ones that cleared the gate and were served.
    """

    graded = [
        (float(probability), bool(outcome))
        for probability, outcome in predictions
        if probability is not None and outcome is not None
    ]
    if not graded:
        return {"evaluated": 0, "served": 0, "observedWinRate": None}

    served = [pair for pair in graded if pair[0] >= float(release_threshold)]
    if not served:
        return {
            "evaluated": len(graded),
            "served": 0,
            "servedShare": 0.0,
            "observedWinRate": None,
            "breakEven": break_even,
            "profitable": None,
        }
    wins = sum(1 for _, outcome in served if outcome)
    rate = wins / len(served)
    return {
        "evaluated": len(graded),
        "served": len(served),
        "servedShare": round(len(served) / len(graded), 5),
        "predicted": round(
            sum(probability for probability, _ in served) / len(served), 5
        ),
        "observedWinRate": round(rate, 5),
        "breakEven": break_even,
        "profitable": rate > break_even,
        "marginOverBreakEven": round(rate - break_even, 5),
    }
