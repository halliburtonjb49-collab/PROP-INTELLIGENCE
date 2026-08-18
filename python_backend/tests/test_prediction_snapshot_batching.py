from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from services import prediction_automation_service as service


class _Cursor:
    def __init__(self) -> None:
        self.statements: list[str] = []

    def execute(self, statement: str, params: object = None) -> None:
        self.statements.append(" ".join(statement.split()).lower())

    def fetchall(self) -> list[tuple[str, str]]:
        return [("prop-1", "model-a")]


class _Connection:
    def __init__(self, cursor: _Cursor) -> None:
        self._cursor = cursor
        self.commits = 0

    @contextmanager
    def cursor(self):
        yield self._cursor

    def commit(self) -> None:
        self.commits += 1


class _Pool:
    def __init__(self, connection: _Connection) -> None:
        self._connection = connection

    @contextmanager
    def connection(self):
        yield self._connection


def test_snapshot_prefetches_existing_keys_in_one_query(monkeypatch) -> None:
    cursor = _Cursor()
    connection = _Connection(cursor)
    future = (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat()
    prop = SimpleNamespace(
        id="prop-1",
        dataStale=False,
        projectionModelVersion="model-a",
        recommendedSide="OVER",
        projection=6.0,
        line=5.5,
        sport="MLB",
        startTimeUtc=future,
        edgeSigned=0.5,
        recommendationEdge=0.5,
        fairProbability=0.62,
        confidence=62,
    )

    monkeypatch.setattr(service, "database_is_configured", lambda: True)
    monkeypatch.setattr(service, "get_database_pool", lambda: _Pool(connection))
    monkeypatch.setattr(service, "get_props", lambda: [prop, prop])
    monkeypatch.setattr(service, "_publish_probability_sources", lambda: None)

    result = service.snapshot_live_predictions()

    assert result["created"] == 0
    assert connection.commits == 1
    assert len(cursor.statements) == 1
    assert cursor.statements[0].startswith(
        "select prop_id,model_version from prediction_snapshots"
    )
    assert "where prop_id=" not in cursor.statements[0]
