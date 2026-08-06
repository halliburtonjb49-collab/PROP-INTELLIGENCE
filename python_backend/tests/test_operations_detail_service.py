import pytest

from services import operations_detail_service as detail
from services.operations_detail_service import (
    DETAILS,
    MAXIMUM_LIMIT,
    available_details,
    mask_email,
    operations_detail,
)


class _Cursor:
    """Records the SQL it was given and replays a fixed result."""

    def __init__(self, rows):
        self._rows = rows
        self.sql = ""
        self.params = None

    def execute(self, sql, params=None):
        self.sql = sql
        self.params = params

    def fetchall(self):
        return self._rows

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


class _Connection:
    def __init__(self, cursor):
        self._cursor = cursor

    def cursor(self):
        return self._cursor

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


def _patch_db(monkeypatch, cursor):
    monkeypatch.setattr(detail, "database_is_configured", lambda: True)
    monkeypatch.setattr(
        detail, "get_database_pool", lambda: _Pool(_Connection(cursor))
    )


class _Pool:
    def __init__(self, connection):
        self._connection = connection

    def connection(self):
        return self._connection


def test_an_address_is_recognisable_without_being_reusable() -> None:
    assert mask_email("jordan.smith@example.com") == "jo**********@example.com"
    assert mask_email("al@example.com") == "a*@example.com"
    assert mask_email("") == "--"
    assert mask_email(None) == "--"
    # The domain survives, so the owner can tell a real signup from a bot.
    assert mask_email("someone@gmail.com").endswith("@gmail.com")


def test_every_tile_with_a_detail_declares_its_columns() -> None:
    for key, query in DETAILS.items():
        assert query.columns, key
        assert query.title and query.description, key
    assert "newSignups" in available_details()


def test_a_metric_with_no_detail_says_so_rather_than_failing() -> None:
    result = operations_detail("somethingElse")

    assert result["supported"] is False
    assert result["reason"] == "no_detail_for_metric"
    assert result["rows"] == []
    # The caller is told what it could have asked for.
    assert "newSignups" in result["available"]


def test_signups_return_masked_accounts(monkeypatch) -> None:
    import datetime

    when = datetime.datetime(2026, 8, 6, 12, 0, tzinfo=datetime.timezone.utc)
    cursor = _Cursor([("jordan.smith@example.com", "Jordan", when)])
    _patch_db(monkeypatch, cursor)

    result = operations_detail("newSignups")

    assert result["supported"] is True
    assert result["rows"][0]["account"] == "jo**********@example.com"
    assert result["rows"][0]["name"] == "Jordan"
    assert result["rows"][0]["signedUpAt"].startswith("2026-08-06")


def test_detail_uses_the_same_window_as_the_tile(monkeypatch) -> None:
    cursor = _Cursor([])
    _patch_db(monkeypatch, cursor)
    operations_detail("newSignups")

    # A detail on a different window than the count would contradict it.
    assert "24 hours" in cursor.sql
    assert "user_profiles" in cursor.sql


def test_the_row_limit_is_bounded(monkeypatch) -> None:
    cursor = _Cursor([])
    _patch_db(monkeypatch, cursor)

    operations_detail("newSignups", limit=10_000)
    assert cursor.params[-1] == MAXIMUM_LIMIT

    operations_detail("newSignups", limit=0)
    assert cursor.params[-1] == 1


def test_a_full_page_is_reported_as_truncated(monkeypatch) -> None:
    import datetime

    when = datetime.datetime(2026, 8, 6, tzinfo=datetime.timezone.utc)
    cursor = _Cursor([("a@b.com", "A", when)] * 3)
    _patch_db(monkeypatch, cursor)

    result = operations_detail("newSignups", limit=3)
    # A screen of rows must not read as the whole story.
    assert result["truncated"] is True

    cursor = _Cursor([("a@b.com", "A", when)])
    _patch_db(monkeypatch, cursor)
    assert operations_detail("newSignups", limit=3)["truncated"] is False


def test_a_database_failure_leaves_the_tile_working(monkeypatch) -> None:
    class _Broken(_Cursor):
        def execute(self, sql, params=None):
            raise RuntimeError("connection reset")

    _patch_db(monkeypatch, _Broken([]))
    result = operations_detail("newSignups")

    # Detail is an enrichment; losing it must not look like a crash.
    assert result["supported"] is True
    assert result["rows"] == []
    assert result["reason"] == "RuntimeError"


def test_no_database_returns_an_explicit_reason(monkeypatch) -> None:
    monkeypatch.setattr(detail, "database_is_configured", lambda: False)
    result = operations_detail("newSignups")

    assert result["reason"] == "database_not_configured"
    assert result["rows"] == []
