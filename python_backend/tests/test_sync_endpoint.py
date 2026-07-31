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
