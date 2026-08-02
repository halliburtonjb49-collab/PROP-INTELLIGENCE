from services.opportunity_projection_service import project_basketball_minutes


def test_minutes_projection_detects_expanded_role() -> None:
    result = project_basketball_minutes([20, 21, 19, 20, 21, 29, 31, 32])
    assert result is not None
    assert result.projected_volume > 25
    assert result.role_change == "EXPANDED"
    assert result.multiplier > 1
    assert result.unit == "MINUTES"


def test_minutes_projection_requires_real_sample() -> None:
    assert project_basketball_minutes([30, 31, 29, 32]) is None


def test_minutes_projection_caps_workload_adjustment() -> None:
    result = project_basketball_minutes([10] * 15 + [35] * 5)
    assert result is not None
    assert result.multiplier == 1.12
