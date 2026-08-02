from services import launch_control_service, scoreboard_metrics_service


def test_launch_control_panel_consolidates_secret_safe_signals(monkeypatch) -> None:
    monkeypatch.setattr(
        launch_control_service,
        "production_acceptance_snapshot",
        lambda: {
            "providerQuota": {"remaining": 420, "lowQuota": False},
            "propFeed": {
                "total": 75,
                "ageMinutes": 3,
                "healthy": True,
            },
        },
    )
    monkeypatch.setattr(
        launch_control_service,
        "cache_health",
        lambda: {"available": True, "mode": "redis"},
    )
    monkeypatch.setattr(
        launch_control_service,
        "queue_health",
        lambda: {
            "available": True,
            "mode": "rq",
            "workers": 2,
            "queued": 1,
            "failed": 0,
        },
    )
    monkeypatch.setattr(
        launch_control_service,
        "game_market_health",
        lambda: {"status": "ok", "errors": 1},
    )
    monkeypatch.setattr(
        launch_control_service,
        "recent_pipeline_runs",
        lambda _limit: [
            {
                "pipeline": "pregame-sync",
                "status": "SUCCEEDED",
                "errors": [],
            }
        ],
    )
    monkeypatch.setattr(
        launch_control_service,
        "_database_counts",
        lambda: {
            "activeUsers": {"count": 4, "instrumented": True},
            "failedLogins": {"count": None, "instrumented": False},
            "failedPayments": {"count": 0},
            "unsettledSlips": {"count": 6},
        },
    )
    monkeypatch.setattr(
        launch_control_service,
        "model_performance",
        lambda: {"sampleSize": 120, "accuracy": 0.6, "segments": []},
    )
    monkeypatch.setattr(
        launch_control_service,
        "operations_summary",
        lambda: {"databaseConfigured": True, "snapshotsToday": 24},
    )

    result = launch_control_service.launch_control_snapshot()

    assert result["api"]["status"] == "ok"
    assert result["redis"]["available"] is True
    assert result["workers"]["workers"] == 2
    assert result["providers"]["remainingQuota"] == 420
    assert result["providers"]["errors"] == 1
    assert result["propFreshness"]["ageMinutes"] == 3
    assert result["activeUsers"]["count"] == 4
    assert result["failedLogins"]["count"] is None
    assert result["failedPayments"]["count"] == 0
    assert result["unsettledSlips"]["count"] == 6
    assert result["pipelines"]["healthy"] is True
    assert result["modelPerformance"]["sampleSize"] == 120
    assert result["predictionOperations"]["snapshotsToday"] == 24


def test_scoreboard_latency_snapshot_records_request() -> None:
    before = scoreboard_metrics_service.scoreboard_latency_snapshot()["sampleCount"]
    scoreboard_metrics_service.record_scoreboard_request(125.4, succeeded=True)
    result = scoreboard_metrics_service.scoreboard_latency_snapshot()

    assert result["sampleCount"] == before + 1
    assert result["lastMs"] is not None
    assert result["status"] == "ok"
