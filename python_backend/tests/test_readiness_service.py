from services.readiness_service import MINIMUM_COUNTS, assess_readiness


def test_readiness_blocks_missing_tables() -> None:
    result = assess_readiness({"prediction_snapshots": None})
    assert result["status"] == "blocked"
    assert result["safeToMarketAsCalibrated"] is False


def test_readiness_warns_while_data_is_warming() -> None:
    counts = {table: minimum for table, minimum in MINIMUM_COUNTS.items()}
    result = assess_readiness(counts, graded_predictions=20)
    assert result["status"] == "warming"


def test_readiness_passes_at_minimum_coverage() -> None:
    counts = {table: minimum for table, minimum in MINIMUM_COUNTS.items()}
    result = assess_readiness(counts, graded_predictions=100)
    assert result["status"] == "ready"
    assert result["safeToMarketAsCalibrated"] is True
