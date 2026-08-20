from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from services import line_movement_recorder as recorder


def _prop(**overrides):
    base = {
        "eventId": "evt-1",
        "player": "Napheesa Collier",
        "marketKey": "player_points",
        "market": "Points",
        "sportsbook": "DRAFTKINGS",
        "sport": "WNBA",
        "sourceProvider": "odds-api",
        "line": 21.5,
        "overOdds": -115,
        "underOdds": -105,
        "startTimeUtc": (
            datetime.now(timezone.utc) + timedelta(hours=3)
        ).isoformat(),
    }
    base.update(overrides)
    return SimpleNamespace(**base)


def _capture(monkeypatch):
    written: list = []

    class _Cursor:
        rowcount = 0

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def executemany(self, _query, rows):
            written.extend(rows)
            _Cursor.rowcount = len(rows)

    class _Connection:
        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def cursor(self):
            return _Cursor()

        def commit(self):
            return None

    monkeypatch.setattr(recorder, "database_is_configured", lambda: True)
    monkeypatch.setattr(
        recorder,
        "get_database_pool",
        lambda: type("Pool", (), {"connection": lambda _self: _Connection()})(),
    )
    return written


def test_a_pregame_price_is_recorded(monkeypatch):
    """Closing line value could not be computed at all.

    The table it reads was empty, because the only pipeline that filled it
    is triggered from a test and from nowhere in production.
    """

    written = _capture(monkeypatch)

    result = recorder.record_line_movements([_prop()])

    assert result["considered"] == 1
    assert written and written[0][3] == "evt-1"
    assert written[0][7] == 21.5


def test_a_started_game_is_not_a_pregame_line(monkeypatch):
    # Closing value measured against a price recorded after tip-off means
    # nothing.
    written = _capture(monkeypatch)

    started = _prop(
        startTimeUtc=(
            datetime.now(timezone.utc) - timedelta(minutes=1)
        ).isoformat()
    )
    result = recorder.record_line_movements([started])

    assert result["considered"] == 0
    assert written == []


def test_an_unchanged_price_reuses_its_fingerprint(monkeypatch):
    """A row per refresh would be two million a day for no benefit.

    The fingerprint excludes the timestamp on purpose, so the table records
    movement rather than polling and the insert conflicts away.
    """

    written = _capture(monkeypatch)
    recorder.record_line_movements([_prop()])
    recorder.record_line_movements([_prop()])

    assert written[0][10] == written[1][10]


def test_a_moved_line_is_a_new_row(monkeypatch):
    written = _capture(monkeypatch)
    recorder.record_line_movements([_prop()])
    recorder.record_line_movements([_prop(line=22.5)])

    assert written[0][10] != written[1][10]


def test_a_moved_price_at_the_same_line_is_also_movement(monkeypatch):
    written = _capture(monkeypatch)
    recorder.record_line_movements([_prop()])
    recorder.record_line_movements([_prop(overOdds=-130)])

    assert written[0][10] != written[1][10]


def test_a_database_failure_never_takes_the_catalog_down(monkeypatch):
    monkeypatch.setattr(recorder, "database_is_configured", lambda: True)

    def _boom():
        raise RuntimeError("pool exhausted")

    monkeypatch.setattr(recorder, "get_database_pool", lambda: _boom())

    assert recorder.record_line_movements([_prop()])["recorded"] == 0


def test_an_incomplete_prop_is_skipped(monkeypatch):
    written = _capture(monkeypatch)

    result = recorder.record_line_movements([_prop(eventId="")])

    assert result["considered"] == 0
    assert written == []
