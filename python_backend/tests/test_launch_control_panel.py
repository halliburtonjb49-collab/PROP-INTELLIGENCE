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
            "newSignups": {
                "count": 2,
                "windowHours": 24,
                "last7Days": 9,
                "total": 120,
                "instrumented": True,
            },
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
    monkeypatch.setattr(
        launch_control_service,
        "_current_strikeout_input_coverage",
        lambda: {
            "available": True,
            "total": 12,
            "fullModelCoverage": 0.75,
            "fallbackRate": 0.25,
            "pitcherCswCoverage": 0.5,
            "lineupKCoverage": 0.66,
            "environmentCoverage": 0.58,
        },
    )
    monkeypatch.setattr(
        launch_control_service,
        "_graded_strikeout_method_report",
        lambda: {
            "available": True,
            "methods": [
                {
                    "method": "mlb_strikeout_log5_binomial",
                    "sampleSize": 18,
                    "accuracy": 0.61,
                    "fallbackPitcherRate": 0.10,
                    "fallbackLineupRate": 0.20,
                    "fallbackTbfRate": 0.15,
                    "marketBlendRate": 1.0,
                }
            ],
        },
    )
    monkeypatch.setattr(
        launch_control_service,
        "get_strikeout_release_controls",
        lambda: {
            "configured": True,
            "source": "database",
            "controls": {
                "enabled": True,
                "maxLineupAgeMinutes": 240,
            },
        },
    )
    monkeypatch.setattr(
        launch_control_service,
        "strikeout_calibration_report",
        lambda _controls=None: {
            "available": True,
            "healthy": True,
            "sampleSize": 120,
            "overallGap": 0.01,
            "adjustments": [],
        },
    )
    monkeypatch.setattr(
        launch_control_service,
        "strikeout_backtest_monitoring",
        lambda _controls=None: {
            "available": True,
            "healthy": True,
            "slices": [],
            "alerts": [],
        },
    )
    monkeypatch.setattr(
        launch_control_service,
        "strikeout_method_ab_report",
        lambda: {
            "available": True,
            "variants": [{"variant": "enriched_variant", "sampleSize": 40}],
        },
    )
    monkeypatch.setattr(
        launch_control_service,
        "strikeout_explainability_snippets",
        lambda: {
            "available": True,
            "items": [{"player": "Pitcher", "summary": "model | p 61%"}],
        },
    )
    monkeypatch.setattr(
        launch_control_service,
        "strikeout_weekly_trust_report",
        lambda _controls=None: {
            "available": True,
            "weekly": [{"sportsbook": "book-a", "sampleSize": 25}],
            "alerts": [],
            "crossBookValidation": {"reliabilityReady": True},
        },
    )
    monkeypatch.setattr(
        launch_control_service,
        "list_feedback",
        lambda limit=20: {
            "available": True,
            "summary": {"last24Hours": 2, "last7Days": 5, "new": 1, "total": 12},
            "items": [{"category": "issue", "message": "line stale", "page": "board"}],
        },
    )

    monkeypatch.setattr(
        launch_control_service,
        "product_observability",
        lambda hours=168: {
            "available": True,
            "windowHours": hours,
            "events": {"APP_OPEN": 12},
            "uniqueUsers": {"APP_OPEN": 8},
            "errors": {},
            "funnels": {"research": [], "subscription": []},
            "reliability": {"errorFreeUserRate": 1.0},
        },
    )

    monkeypatch.setattr(
        launch_control_service,
        "production_data_certification",
        lambda *_args, **_kwargs: {
            "status": "PASS", "score": 100, "checks": [],
        },
    )

    result = launch_control_service.launch_control_snapshot()

    assert result["api"]["status"] == "ok"
    assert result["redis"]["available"] is True
    assert result["workers"]["workers"] == 2
    assert result["providers"]["remainingQuota"] == 420
    assert result["providers"]["errors"] == 1
    assert result["propFreshness"]["ageMinutes"] == 3
    assert result["dataCertification"]["score"] == 100
    assert result["activeUsers"]["count"] == 4
    assert result["failedLogins"]["count"] is None
    assert result["failedPayments"]["count"] == 0
    assert result["unsettledSlips"]["count"] == 6
    assert result["newSignups"]["count"] == 2
    assert result["pipelines"]["healthy"] is True
    assert result["modelPerformance"]["sampleSize"] == 120
    assert result["predictionOperations"]["snapshotsToday"] == 24
    assert result["ownerOnlyInsights"]["strikeoutInputCoverage"]["total"] == 12
    assert result["ownerOnlyInsights"]["strikeoutMethodAudit"]["methods"][0]["method"] == "mlb_strikeout_log5_binomial"
    assert result["ownerOnlyInsights"]["strikeoutReleaseControls"]["controls"]["enabled"] is True
    assert result["ownerOnlyInsights"]["strikeoutCalibration"]["sampleSize"] == 120
    assert result["ownerOnlyInsights"]["strikeoutBacktest"]["healthy"] is True
    assert result["ownerOnlyInsights"]["strikeoutMethodComparison"]["variants"][0]["variant"] == "enriched_variant"
    assert result["ownerOnlyInsights"]["strikeoutExplainability"]["items"][0]["player"] == "Pitcher"
    assert result["ownerOnlyInsights"]["strikeoutTrustWeekly"]["available"] is True
    assert result["ownerOnlyInsights"]["feedbackInbox"]["available"] is True
    assert result["ownerOnlyInsights"]["productObservability"]["available"] is True


def test_scoreboard_latency_snapshot_records_request() -> None:
    before = scoreboard_metrics_service.scoreboard_latency_snapshot()["sampleCount"]
    scoreboard_metrics_service.record_scoreboard_request(125.4, succeeded=True)
    result = scoreboard_metrics_service.scoreboard_latency_snapshot()

    assert result["sampleCount"] == before + 1
    assert result["lastMs"] is not None
    assert result["status"] == "ok"
