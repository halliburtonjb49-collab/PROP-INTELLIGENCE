"""Chronological challenger evaluation and conservative promotion rules."""

from __future__ import annotations

from dataclasses import dataclass
from math import fsum
from typing import Sequence


SUPPORTED_MODEL_SEGMENTS = (
    ("WNBA", "PLAYER POINTS"),
    ("WNBA", "PLAYER REBOUNDS"),
    ("WNBA", "PLAYER ASSISTS"),
    ("WNBA", "PLAYER POINTS REBOUNDS"),
    ("WNBA", "PLAYER POINTS ASSISTS"),
    ("WNBA", "PLAYER REBOUNDS ASSISTS"),
    ("WNBA", "PLAYER POINTS REBOUNDS ASSISTS"),
    ("MLB", "PITCHER STRIKEOUTS"),
    ("MLB", "BATTER HITS"),
    ("MLB", "BATTER TOTAL BASES"),
    ("MLB", "BATTER RBIS"),
    ("MLB", "BATTER RUNS"),
    ("MLB", "BATTER WALKS"),
    ("MLB", "BATTER HOME RUNS"),
)


@dataclass(frozen=True)
class EvaluationMetrics:
    sample_size: int
    mean_absolute_error: float
    brier_score: float
    calibration_gap: float
    accuracy: float
    average_clv: float | None
    positive_clv_rate: float | None


def chronological_splits(size: int, folds: int = 3, minimum_train: int = 100) -> list[tuple[range, range]]:
    """Expanding-window splits; input rows must already be ordered by event time."""
    if size <= minimum_train or folds < 1:
        return []
    validation = max(1, (size - minimum_train) // folds)
    splits = []
    for fold in range(folds):
        train_end = minimum_train + validation * fold
        valid_end = size if fold == folds - 1 else min(size, train_end + validation)
        if valid_end > train_end:
            splits.append((range(0, train_end), range(train_end, valid_end)))
    return splits


def evaluate_predictions(
    actual: Sequence[float],
    projection: Sequence[float],
    line: Sequence[float],
    side: Sequence[str],
    probability: Sequence[float],
    clv: Sequence[float | None],
) -> EvaluationMetrics:
    size = len(actual)
    if not size or not all(
        len(values) == size
        for values in (projection, line, side, probability, clv)
    ):
        raise ValueError("All evaluation arrays must have the same non-zero length")
    hits = [a > l if s.upper() == "OVER" else a < l for a, l, s in zip(actual, line, side)]
    mae = fsum(abs(a - p) for a, p in zip(actual, projection)) / size
    brier = fsum((pr - float(hit)) ** 2 for pr, hit in zip(probability, hits)) / size
    accuracy = fsum(float(hit) for hit in hits) / size
    average_probability = fsum(probability) / size
    measured_clv = [value for value in clv if value is not None]
    return EvaluationMetrics(
        sample_size=size,
        mean_absolute_error=round(mae, 6),
        brier_score=round(brier, 6),
        calibration_gap=round(abs(average_probability - accuracy), 6),
        accuracy=round(accuracy, 6),
        average_clv=(round(fsum(measured_clv) / len(measured_clv), 6) if measured_clv else None),
        positive_clv_rate=(
            round(sum(value > 0 for value in measured_clv) / len(measured_clv), 6)
            if measured_clv
            else None
        ),
    )


def should_promote(challenger: EvaluationMetrics, baseline: EvaluationMetrics) -> bool:
    """Require the challenger to beat every declared release criterion."""
    if challenger.sample_size < 200 or challenger.sample_size != baseline.sample_size:
        return False
    clv_ok = (
        challenger.average_clv is not None
        and baseline.average_clv is not None
        and challenger.positive_clv_rate is not None
        and baseline.positive_clv_rate is not None
        and challenger.average_clv >= baseline.average_clv
        and challenger.positive_clv_rate >= baseline.positive_clv_rate
        and challenger.positive_clv_rate >= .55
    )
    return all((
        challenger.mean_absolute_error < baseline.mean_absolute_error,
        challenger.brier_score < baseline.brier_score,
        challenger.calibration_gap <= baseline.calibration_gap,
        challenger.accuracy > baseline.accuracy,
        clv_ok,
    ))
