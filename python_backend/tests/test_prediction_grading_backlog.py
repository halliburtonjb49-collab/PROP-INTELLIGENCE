from datetime import datetime, timezone

from services import prediction_automation_service as automation


class _Cursor:
    def __init__(self, recorder):
        self.recorder = recorder
        self.rowcount = 0

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def execute(self, query, params=None):
        self.recorder.append((" ".join(str(query).split()), params))

    def fetchall(self):
        return []

    def fetchone(self):
        return (22337, datetime(2026, 8, 5, 17, 5, tzinfo=timezone.utc), 1018)


class _Connection:
    def __init__(self, recorder):
        self.recorder = recorder

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def cursor(self):
        return _Cursor(self.recorder)

    def commit(self):
        return None


def _run(monkeypatch):
    recorder: list[tuple[str, object]] = []
    monkeypatch.setattr(automation, "database_is_configured", lambda: True)
    monkeypatch.setattr(
        automation,
        "get_database_pool",
        lambda: type("Pool", (), {"connection": lambda _self: _Connection(recorder)})(),
    )
    return automation.grade_completed_predictions(), recorder


def test_each_cycle_serves_the_expiring_end_of_the_queue(monkeypatch):
    """Grading used to run newest-first only.

    The rows closest to falling out of the fourteen day window were therefore
    serviced last and expired ungraded even while throughput was sufficient
    to clear the backlog.
    """

    _result, recorder = _run(monkeypatch)
    batch = next(q for q, _p in recorder if "with eligible as" in q)

    assert "order by event_time asc limit" in batch
    assert "order by event_time desc limit" in batch


def test_a_stuck_cohort_cannot_consume_the_whole_batch(monkeypatch):
    """Oldest-first alone would let unresolvable rows starve the queue.

    A prediction with no game or player match never resolves, so under a
    strict oldest-first order it would sit at the head and be retried every
    cycle for a fortnight. Each half is bounded independently.
    """

    _result, recorder = _run(monkeypatch)
    params = next(p for q, p in recorder if "with eligible as" in q)

    assert params == (automation._GRADING_BATCH_HALF,) * 2


def test_backlog_depth_is_reported(monkeypatch):
    """A healthy graded count looked identical at ten rows pending or twenty
    thousand. The queue depth has to be visible in the same metrics."""

    result, _recorder = _run(monkeypatch)

    assert result["backlogTotal"] == 22337
    assert result["backlogOldestEventTime"] == "2026-08-05T17:05:00+00:00"
    assert result["backlogExpiringWithin24h"] == 1018
