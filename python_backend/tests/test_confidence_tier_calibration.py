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
    report, _ = _run(
        monkeypatch, [("Premium", 2419, 69.15, 1734, 2419, 0.0752, 0.70)]
    )

    assert report[0]["meetsItsClaim"] is True
    assert report[0]["actionable"] is True
    # The whole interval sits above break-even, so the edge is real rather
    # than a favourable stretch.
    assert report[0]["profitability"] == "proven_profitable"
    assert report[0]["flatStakeRoiLow"] > 0


def test_a_tier_that_promises_more_than_it_delivers_is_flagged(monkeypatch):
    """This is the check that did not exist.

    A band claiming 57.9% delivered 54.0% and lost 9.1% flat-staked while
    the card called it playable, and nothing surfaced it until the question
    was asked by hand months later.
    """

    report, _ = _run(
        monkeypatch, [("Lean", 2859, 57.9, 1544, 2859, -0.091, 0.70)]
    )

    assert report[0]["claimShortfall"] < 0
    assert report[0]["profitability"] == "proven_unprofitable"
    assert report[0]["flatStakeRoiHigh"] < 0


def test_undersized_tiers_are_withheld_rather_than_guessed_at(monkeypatch):
    report, _ = _run(monkeypatch, [("Premium", 3, 69.0, 3, 3, 0.9, 0.7)])

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


def test_a_tier_within_noise_of_break_even_is_not_condemned(monkeypatch):
    """The judgement that keeps this measurement honest in both directions.

    The tier below Premium returns -2.2% flat, which looks like the retired
    band until the interval is drawn: [-5.4%, +0.9%] straddles zero on 2,468
    priced results, while the retired band sat roughly five standard errors
    below it. Acting on the point estimate alone would have cut half the
    actionable board over a rounding error.
    """

    report, _ = _run(
        monkeypatch, [("Strong", 2469, 61.63, 1487, 2469, -0.0226, 0.80)]
    )

    assert report[0]["profitability"] == "not_distinguishable"
    assert report[0]["flatStakeRoiLow"] < 0 < report[0]["flatStakeRoiHigh"]
    # Still actionable: nothing here proves it loses money.
    assert report[0]["actionable"] is True


def test_a_claim_missed_only_within_noise_is_not_called_a_miss(monkeypatch):
    report, _ = _run(
        monkeypatch, [("Strong", 2469, 61.63, 1487, 2469, -0.0226, 0.80)]
    )

    # 60.2% observed against a 61.6% claim, with the interval reaching above
    # the claim: a point estimate a hair under its number is not a broken
    # promise, and treating it as one trains everyone to ignore the flag.
    assert report[0]["meetsItsClaim"] is True


def test_the_interval_widens_when_the_sample_is_thin(monkeypatch):
    thin, _ = _run(monkeypatch, [("Premium", 60, 69.0, 43, 60, 0.075, 0.70)])
    thick, _ = _run(monkeypatch, [("Premium", 6000, 69.0, 4300, 6000, 0.075, 0.70)])

    thin_width = thin[0]["hitRateHigh"] - thin[0]["hitRateLow"]
    thick_width = thick[0]["hitRateHigh"] - thick[0]["hitRateLow"]
    assert thin_width > thick_width * 5
    assert thin[0]["profitability"] == "not_distinguishable"
