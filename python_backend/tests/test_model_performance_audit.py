from services.model_performance_service import _audit_recommendation


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
