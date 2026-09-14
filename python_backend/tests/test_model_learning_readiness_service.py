from contextlib import contextmanager
from datetime import datetime, timezone

from services import model_learning_readiness_service as service


class _Cursor:
    def __init__(
        self,
        *,
        run_status: str = "SUCCEEDED",
        completed_run_status: str | None = None,
    ):
        completed = completed_run_status or run_status
        self.results = iter(
            [
                (True, True),
                (
                    datetime(2026, 9, 6, 18, tzinfo=timezone.utc),
                    datetime(2026, 9, 6, 17, tzinfo=timezone.utc),
                    True,
                    True,
                    True,
                ),
                (datetime(2026, 9, 6, 19, tzinfo=timezone.utc), run_status),
                (completed,),
            ]
        )

    def execute(self, _query):
        return None

    def fetchone(self):
        return next(self.results)

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


class _Connection:
    def __init__(self, cursor):
        self._cursor = cursor

    def cursor(self):
        return self._cursor


class _Pool:
    def __init__(self, cursor):
        self._cursor = cursor

    @contextmanager
    def connection(self):
        yield _Connection(self._cursor)


def test_learning_readiness_proves_capture_grade_and_successful_run(monkeypatch):
    monkeypatch.setattr(service, "database_is_configured", lambda: True)
    monkeypatch.setattr(service, "get_database_pool", lambda: _Pool(_Cursor()))

    result = service.model_learning_readiness()

    assert result["status"] == "ready"
    assert all(result["checks"].values())
    assert result["latestGradedAt"] == "2026-09-06T17:00:00+00:00"


def test_learning_readiness_reports_warming_after_failed_learning_run(monkeypatch):
    monkeypatch.setattr(service, "database_is_configured", lambda: True)
    monkeypatch.setattr(
        service,
        "get_database_pool",
        lambda: _Pool(_Cursor(run_status="PARTIAL")),
    )

    result = service.model_learning_readiness()

    assert result["status"] == "warming"
    assert result["checks"]["latestLearningRunSucceeded"] is False


def test_active_learning_run_keeps_last_completed_success_healthy(monkeypatch):
    monkeypatch.setattr(service, "database_is_configured", lambda: True)
    monkeypatch.setattr(
        service,
        "get_database_pool",
        lambda: _Pool(
            _Cursor(run_status="RUNNING", completed_run_status="SUCCEEDED")
        ),
    )

    result = service.model_learning_readiness()

    assert result["status"] == "ready"
    assert result["checks"]["latestLearningRunSucceeded"] is True
    assert result["latestLearningRunStatus"] == "RUNNING"


def test_learning_readiness_blocks_without_database(monkeypatch):
    monkeypatch.setattr(service, "database_is_configured", lambda: False)

    result = service.model_learning_readiness()

    assert result["status"] == "blocked"
    assert result["checks"] == {"database": False}
