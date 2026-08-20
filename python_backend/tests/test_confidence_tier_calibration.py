from datetime import datetime, timezone

import pytest

from services import prediction_automation_service as automation
from services.prop_recommendation_service import (
    ACTIONABLE_CONFIDENCE_FLOOR,
    PREMIUM_CONFIDENCE_FLOOR,
)


class _Cursor:
    def __init__(self, rows, recorder):
        self.rows = rows
        self.recorder = recorder

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def execute(self, query, params=None):
        self.recorder.append((" ".join(str(query).split()), params))

    def fetchall(self):
        return self.rows


class _Connection:
    def __init__(self, rows, recorder):
        self.rows = rows
        self.recorder = recorder

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def cursor(self):
        return _Cursor(self.rows, self.recorder)


def _run(monkeypatch, rows):
    recorder: list[tuple[str, object]] = []
    monkeypatch.setattr(automation, "database_is_configured", lambda: True)
    monkeypatch.setattr(
        automation,
        "get_database_pool",
        lambda: type(
            "Pool", (), {"connection": lambda _self: _Connection(rows, recorder)}
        )(),
    )
    return automation.confidence_tier_calibration(minimum_sample=10), recorder


def test_a_tier_that_undersells_itself_is_not_flagged(monkeypatch):
    # Premium claimed 69.1% and delivered 71.6% at +7.5% flat ROI. Beating
    # your own number is not a calibration failure.
    report, _ = _run(monkeypatch, [("Premium", 2419, 69.15, 0.7168, 0.0752)])

    assert report[0]["meetsItsClaim"] is True
    assert report[0]["claimShortfall"] == pytest.approx(0.0253, abs=1e-4)
    assert report[0]["actionable"] is True


def test_a_tier_that_promises_more_than_it_delivers_is_flagged(monkeypatch):
    """This is the check that did not exist.

    A band claiming 57.9% delivered 54.0% and lost 9.1% flat-staked while
    the card called it playable, and nothing surfaced it until the question
    was asked by hand months later.
    """

    report, _ = _run(monkeypatch, [("Strong", 2465, 61.63, 0.6024, -0.0221)])

    assert report[0]["meetsItsClaim"] is False
    assert report[0]["claimShortfall"] < 0
    assert report[0]["flatStakeRoi"] == pytest.approx(-0.0221)


def test_undersized_tiers_are_withheld_rather_than_guessed_at(monkeypatch):
    report, _ = _run(monkeypatch, [("Premium", 3, 69.0, 1.0, 0.9)])

    assert report == []


def test_confidences_that_never_reached_a_card_are_excluded(monkeypatch):
    """Confidence is floored at 50 wherever it is displayed.

    Snapshots carrying 0 never made a claim to anyone, and averaging them in
    dragged the stated hit rate of the Pass tier to 14.8% against a 51.3%
    outcome -- a number that reads like spectacular underconfidence and is
    simply meaningless.
    """

    _report, recorder = _run(monkeypatch, [])
    query = recorder[0][0]

    assert "(inputs->>'confidence')::int >= 50" in query


def test_the_measurement_grades_the_boundaries_the_board_actually_uses(
    monkeypatch,
):
    _report, recorder = _run(monkeypatch, [])

    assert recorder[0][1] == (
        PREMIUM_CONFIDENCE_FLOOR,
        ACTIONABLE_CONFIDENCE_FLOOR,
    )


def test_the_daily_window_fires_once_per_day(monkeypatch):
    import scripts.sync_pregame as pregame

    class _Clock(datetime):
        @classmethod
        def now(cls, tz=None):
            return cls(2026, 8, 20, 10, 0, tzinfo=tz or timezone.utc)

    monkeypatch.setattr(pregame, "datetime", _Clock)
    assert pregame._is_daily_measurement_window() is True

    class _Later(datetime):
        @classmethod
        def now(cls, tz=None):
            return cls(2026, 8, 20, 10, 10, tzinfo=tz or timezone.utc)

    monkeypatch.setattr(pregame, "datetime", _Later)
    assert pregame._is_daily_measurement_window() is False
