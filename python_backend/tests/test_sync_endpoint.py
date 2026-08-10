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

    def fake_pipeline(fast_callback, coverage_callback):
        fast_callback([{"sport": "primary", "props": 10}])
        observed.update(main._sync_state_snapshot())
        coverage_results = [
            {"sport": "primary", "props": 10},
            {"sport": "coverage", "props": 0},
        ]
        coverage_callback(coverage_results)
        coverage_observed.update(main._sync_state_snapshot())
        return [
            *coverage_results,
            {"sport": "model_recalculation", "props": 10},
        ]

    monkeypatch.setattr(main, "run_global_sync_pipeline", fake_pipeline)
    monkeypatch.setattr(main, "_invalidate_prop_catalog", lambda: None)
    monkeypatch.setattr(main, "get_props", lambda: [])
    monkeypatch.setattr(main, "capture_closing_lines_from_props", lambda _props: {})
    monkeypatch.setattr(main, "quota_snapshot", lambda: {"remaining": 1000})
    main._mark_sync_running()

    main._run_sync_background(release_local_lock=False)

    assert observed["status"] == "complete"
    assert observed["coverageStatus"] == "running"
    assert observed["postProcessingStatus"] == "pending"
    assert coverage_observed["coverageStatus"] == "complete"
    assert coverage_observed["postProcessingStatus"] == "running"
    final = main._sync_state_snapshot()
    assert final["status"] == "complete"
    assert final["coverageStatus"] == "complete"
    assert final["postProcessingStatus"] == "complete"
    assert len(final["coverageResults"]) == 2
    assert len(final["results"]) == 3


def test_post_processing_failure_preserves_completed_coverage(monkeypatch) -> None:
    def fake_pipeline(fast_callback, coverage_callback):
        results = [{"sport": "primary", "props": 10}]
        fast_callback(results)
        coverage_callback(results)
        raise RuntimeError("model recalculation failed")

    monkeypatch.setattr(main, "run_global_sync_pipeline", fake_pipeline)
    monkeypatch.setattr(main, "_invalidate_prop_catalog", lambda: None)
    monkeypatch.setattr(main, "quota_snapshot", lambda: {"remaining": 1000})
    main._mark_sync_running()

    main._run_sync_background(release_local_lock=False)

    final = main._sync_state_snapshot()
    assert final["status"] == "complete"
    assert final["coverageStatus"] == "complete"
    assert final["coverageError"] is None
    assert final["postProcessingStatus"] == "failed"
    assert final["postProcessingError"] == "model recalculation failed"
