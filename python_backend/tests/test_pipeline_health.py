from services.pipeline_run_service import summarize_pipeline_health


def test_recovered_pipeline_is_healthy_but_retains_failure_history() -> None:
    runs = [
        {"pipeline": "pregame-sync", "status": "SUCCEEDED", "id": "new"},
        {"pipeline": "pregame-sync", "status": "PARTIAL", "id": "old"},
        {"pipeline": "historical-sync", "status": "SUCCEEDED", "id": "history"},
    ]

    result = summarize_pipeline_health(runs)

    assert result["healthy"] is True
    assert result["activeFailures"] == []
    assert result["recentFailures"] == [runs[1]]


def test_latest_pipeline_failure_is_active() -> None:
    runs = [
        {"pipeline": "pregame-sync", "status": "PARTIAL", "id": "new"},
        {"pipeline": "pregame-sync", "status": "SUCCEEDED", "id": "old"},
    ]

    result = summarize_pipeline_health(runs)

    assert result["healthy"] is False
    assert result["activeFailures"] == [runs[0]]
