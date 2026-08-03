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

    def fake_pipeline(callback):
        callback([{"sport": "primary", "props": 10}])
        observed.update(main._sync_state_snapshot())
        return [
            {"sport": "primary", "props": 10},
            {"sport": "coverage", "props": 0},
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
    final = main._sync_state_snapshot()
    assert final["status"] == "complete"
    assert final["coverageStatus"] == "complete"
    assert len(final["results"]) == 2
