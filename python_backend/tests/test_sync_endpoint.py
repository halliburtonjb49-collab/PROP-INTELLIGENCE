import main


class CapturedTasks:
    def __init__(self) -> None:
        self.tasks: list[tuple[object, tuple[object, ...], dict[str, object]]] = []

    def add_task(self, function, *args, **kwargs) -> None:
        self.tasks.append((function, args, kwargs))


def test_manual_sync_runs_where_status_is_observable(monkeypatch) -> None:
    tasks = CapturedTasks()
    monkeypatch.setattr(main, "_sync_is_fresh", lambda: False)
    if main._sync_run_lock.locked():
        main._sync_run_lock.release()

    try:
        payload = main.sync_props(tasks)

        assert payload["status"] == "running"
        assert "observable status" in payload["message"]
        assert len(tasks.tasks) == 1
        assert tasks.tasks[0][0] is main._run_sync_background
    finally:
        if main._sync_run_lock.locked():
            main._sync_run_lock.release()


def test_primary_lane_completes_before_background_coverage(monkeypatch) -> None:
    observed = {}
    coverage_observed = {}
    provider_observed = {}

    def fake_pipeline(
        fast_callback,
        coverage_callback,
        progress_callback,
        sportsgameodds_started,
        sportsgameodds_complete,
        post_processing_progress,
    ):
        fast_callback([{"sport": "primary", "props": 10}])
        observed.update(main._sync_state_snapshot())
        progress_callback({"currentSport": "coverage", "completedSports": 1, "totalSports": 1})
        coverage_results = [
            {"sport": "primary", "props": 10},
            {"sport": "coverage", "props": 0},
        ]
        coverage_callback(coverage_results)
        coverage_observed.update(main._sync_state_snapshot())
        sportsgameodds_started()
        sportsgameodds_complete({"sport": "sportsgameodds", "events": 1, "props": 4})
        provider_observed.update(main._sync_state_snapshot())
        post_processing_progress("model_recalculation")
        return [
            *coverage_results,
            {"sport": "model_recalculation", "props": 10},
        ]

    monkeypatch.setattr(main, "run_global_sync_pipeline", fake_pipeline)
    refreshes = []
    monkeypatch.setattr(
        main,
        "_refresh_prop_catalog_now",
        lambda **kwargs: refreshes.append(kwargs),
    )
    monkeypatch.setattr(main, "get_props", lambda: [])
    monkeypatch.setattr(main, "capture_closing_lines_from_props", lambda _props: {})
    monkeypatch.setattr(main, "quota_snapshot", lambda: {"remaining": 1000})
    main._mark_sync_running()

    main._run_sync_background(release_local_lock=False)

    assert observed["status"] == "complete"
    assert observed["coverageStatus"] == "running"
    assert observed["postProcessingStatus"] == "pending"
    assert coverage_observed["coverageStatus"] == "complete"
    assert coverage_observed["postProcessingStatus"] == "pending"
    assert coverage_observed["sportsGameOddsStatus"] == "pending"
    assert provider_observed["sportsGameOddsStatus"] == "complete"
    assert provider_observed["postProcessingStatus"] == "running"
    assert provider_observed["postProcessingStep"] == "catalog_refresh"
    final = main._sync_state_snapshot()
    assert final["status"] == "complete"
    assert final["coverageStatus"] == "complete"
    assert final["sportsGameOddsStatus"] == "complete"
    assert final["postProcessingStatus"] == "complete"
    assert len(final["coverageResults"]) == 2
    assert len(final["results"]) == 3
    assert refreshes == [
        {"persist_snapshot": False},
        {"persist_snapshot": True},
    ]


def test_post_processing_failure_preserves_completed_coverage(monkeypatch) -> None:
    def fake_pipeline(
        fast_callback,
        coverage_callback,
        _progress_callback,
        sportsgameodds_started,
        sportsgameodds_complete,
        post_processing_progress,
    ):
        results = [{"sport": "primary", "props": 10}]
        fast_callback(results)
        coverage_callback(results)
        sportsgameodds_started()
        sportsgameodds_complete({"sport": "sportsgameodds", "events": 1, "props": 4})
        post_processing_progress("model_recalculation")
        raise RuntimeError("model recalculation failed")

    monkeypatch.setattr(main, "run_global_sync_pipeline", fake_pipeline)
    monkeypatch.setattr(main, "_invalidate_prop_catalog", lambda: None)
    monkeypatch.setattr(main, "_refresh_prop_catalog_now", lambda **_kwargs: [])
    monkeypatch.setattr(main, "quota_snapshot", lambda: {"remaining": 1000})
    main._mark_sync_running()

    main._run_sync_background(release_local_lock=False)

    final = main._sync_state_snapshot()
    assert final["status"] == "complete"
    assert final["coverageStatus"] == "complete"
    assert final["sportsGameOddsStatus"] == "complete"
    assert final["coverageError"] is None
    assert final["postProcessingStatus"] == "failed"
    assert final["postProcessingStep"] == "failed"
    assert final["postProcessingError"] == "model recalculation failed"
