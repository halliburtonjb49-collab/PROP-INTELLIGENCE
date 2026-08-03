from services.model_challenger_service import (
    EvaluationMetrics,
    chronological_splits,
    should_promote,
)


def _metrics(**changes) -> EvaluationMetrics:
    values = dict(sample_size=250, mean_absolute_error=3, brier_score=.24,
                  calibration_gap=.04, accuracy=.56, average_clv=2.0,
                  positive_clv_rate=.56)
    values.update(changes)
    return EvaluationMetrics(**values)


def test_chronological_splits_never_train_on_future_rows() -> None:
    splits = chronological_splits(400, folds=3, minimum_train=100)
    assert len(splits) == 3
    assert all(max(train) < min(validation) for train, validation in splits)
    assert list(splits[-1][1])[-1] == 399


def test_challenger_must_beat_every_metric() -> None:
    baseline = _metrics()
    challenger = _metrics(mean_absolute_error=2.8, brier_score=.22,
                          calibration_gap=.03, accuracy=.58, average_clv=2.5)
    assert should_promote(challenger, baseline) is True
    assert should_promote(_metrics(mean_absolute_error=3.1), baseline) is False


def test_challenger_cannot_promote_before_200_results() -> None:
    assert should_promote(_metrics(sample_size=199), _metrics(sample_size=199)) is False
