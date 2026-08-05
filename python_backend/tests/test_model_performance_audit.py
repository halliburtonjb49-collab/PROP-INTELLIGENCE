from services.model_performance_service import (
    _audit_recommendation, _dominant_model_version, _rolling_row,
)


class _FakeCursor:
    def __init__(self, row):
        self._row = row

    def execute(self, _query):
        pass

    def fetchone(self):
        return self._row


def test_dominant_model_version_returns_the_top_row() -> None:
    cursor = _FakeCursor(("provider-projection-v1", 85))
    assert _dominant_model_version(cursor) == "provider-projection-v1"


def test_dominant_model_version_handles_no_graded_rows() -> None:
    cursor = _FakeCursor(None)
    assert _dominant_model_version(cursor) is None


def test_dominant_model_version_handles_null_version() -> None:
    cursor = _FakeCursor((None, 3))
    assert _dominant_model_version(cursor) is None


def test_audit_waits_for_a_safe_sample() -> None:
    result = _audit_recommendation(12, 0.75, 0.80)
    assert result["status"] == "COLLECTING"
    assert result["actionable"] is False


def test_audit_flags_underperforming_segment() -> None:
    result = _audit_recommendation(50, 0.46, 0.62)
    assert result["status"] == "RECALIBRATE"
    assert result["actionable"] is True


def test_audit_accepts_calibrated_segment() -> None:
    result = _audit_recommendation(50, 0.61, 0.63)
    assert result["status"] == "HEALTHY"
    assert result["calibrationGap"] == 0.02


def test_rolling_row_reports_accuracy_confidence_and_status() -> None:
    result = _rolling_row("sport", ("WNBA", 100, 42, 0.61))
    assert result["value"] == "WNBA"
    assert result["accuracy"] == 0.42
    assert result["averageConfidence"] == 0.61
    assert result["calibrationGap"] == 0.19
    assert result["status"] == "RECALIBRATE"
