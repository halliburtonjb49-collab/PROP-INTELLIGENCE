import services.public_track_record_service as track_record
from services.public_track_record_service import (
    MINIMUM_PUBLISHED_SAMPLE,
    public_track_record,
)


def _install(monkeypatch, payload: dict) -> None:
    monkeypatch.setattr(track_record, "model_performance", lambda *_, **__: payload)


def _mature(**over) -> dict:
    base = {
        "modelVersion": "v9",
        "sampleSize": 640,
        "accuracy": 0.5731,
        "simulatedRoi": 0.0412,
        "brierScore": 0.2401,
        "calibrated": True,
        "clv": {
            "available": True,
            "sampleSize": 610,
            "beatClosingLineRate": 0.5820,
            "averageLineClvPoints": 0.1400,
            "averageOddsClvExpectedValuePercent": 1.9,
            "reason": None,
        },
        "segments": [
            {"confidenceTier": "HIGH", "sampleSize": 200, "hits": 130},
            {"confidenceTier": "HIGH", "sampleSize": 100, "hits": 60},
            {"confidenceTier": "MEDIUM", "sampleSize": 240, "hits": 130},
            {"confidenceTier": "BASELINE", "sampleSize": 100, "hits": 47},
        ],
    }
    base.update(over)
    return base


def test_a_mature_record_publishes_its_numbers(monkeypatch) -> None:
    _install(monkeypatch, _mature())
    record = public_track_record()

    assert record["published"] is True
    assert record["sampleSize"] == 640
    assert record["winRate"] == 0.5731
    assert record["simulatedRoi"] == 0.0412
    assert record["closingLineValue"]["beatClosingLineRate"] == 0.5820


def test_a_thin_record_publishes_no_rate_at_all(monkeypatch) -> None:
    """Nine graded picks is noise with a percent sign, not a track record.

    On a page aimed at buyers a rate is a claim, so below the minimum the
    rates are absent rather than zero -- zero is a number, absent is true.
    """

    _install(monkeypatch, _mature(sampleSize=9))
    record = public_track_record()

    assert record["published"] is False
    assert record["winRate"] is None
    assert record["simulatedRoi"] is None
    assert record["brierScore"] is None
    assert record["closingLineValue"]["beatClosingLineRate"] is None
    assert record["closingLineValue"]["available"] is False


def test_a_thin_record_says_how_far_along_it_is(monkeypatch) -> None:
    # Withholding a number without saying why reads as a broken page.
    _install(monkeypatch, _mature(sampleSize=9))
    record = public_track_record()

    assert record["sampleSize"] == 9
    assert record["minimumPublishedSample"] == MINIMUM_PUBLISHED_SAMPLE
    assert record["gradedPicksRemaining"] == MINIMUM_PUBLISHED_SAMPLE - 9


def test_the_boundary_counts_as_earned(monkeypatch) -> None:
    _install(monkeypatch, _mature(sampleSize=MINIMUM_PUBLISHED_SAMPLE))

    assert public_track_record()["published"] is True


def test_tiers_are_summed_not_recomputed(monkeypatch) -> None:
    _install(monkeypatch, _mature())
    tiers = {row["tier"]: row for row in public_track_record()["confidenceTiers"]}

    # The two HIGH segments combine into one published tier.
    assert tiers["HIGH"]["sampleSize"] == 300
    assert tiers["HIGH"]["hits"] == 190
    assert tiers["HIGH"]["winRate"] == round(190 / 300, 4)


def test_tiers_read_strongest_first(monkeypatch) -> None:
    _install(monkeypatch, _mature())
    order = [row["tier"] for row in public_track_record()["confidenceTiers"]]

    assert order == ["HIGH", "MEDIUM", "BASELINE"]


def test_a_thin_tier_withholds_its_own_rate(monkeypatch) -> None:
    # A reader comparing tiers reads the strongest number as the claim, so a
    # tier earns its rate on the same terms the overall record does.
    _install(
        monkeypatch,
        _mature(
            segments=[
                {"confidenceTier": "HIGH", "sampleSize": 4, "hits": 4},
                {"confidenceTier": "MEDIUM", "sampleSize": 300, "hits": 160},
            ]
        ),
    )
    tiers = {row["tier"]: row for row in public_track_record()["confidenceTiers"]}

    assert tiers["HIGH"]["sampleSize"] == 4
    assert tiers["HIGH"]["winRate"] is None
    assert tiers["HIGH"]["published"] is False
    assert tiers["MEDIUM"]["winRate"] == round(160 / 300, 4)


def test_an_unknown_tier_is_ignored_rather_than_shown_raw(monkeypatch) -> None:
    _install(
        monkeypatch,
        _mature(segments=[{"confidenceTier": "MYSTERY", "sampleSize": 500, "hits": 400}]),
    )

    assert public_track_record()["confidenceTiers"] == []


def test_the_record_is_timestamped(monkeypatch) -> None:
    # A record with no age cannot be judged for freshness.
    _install(monkeypatch, _mature())
    stamp = public_track_record()["generatedAt"]

    assert isinstance(stamp, str) and stamp.endswith("+00:00")


def test_an_empty_database_does_not_crash_the_page(monkeypatch) -> None:
    _install(monkeypatch, {"modelVersion": "v9", "sampleSize": 0, "segments": []})
    record = public_track_record()

    assert record["published"] is False
    assert record["winRate"] is None
    assert record["confidenceTiers"] == []
    assert record["closingLineValue"]["available"] is False


def test_malformed_upstream_values_do_not_leak_through(monkeypatch) -> None:
    # The performance view is a database read; a null or a string must not
    # reach the page as one.
    _install(
        monkeypatch,
        _mature(sampleSize="640", accuracy="not a number", simulatedRoi=None),
    )
    record = public_track_record()

    assert record["sampleSize"] == 640
    assert record["winRate"] is None
    assert record["simulatedRoi"] is None


def test_roi_keeps_the_word_simulated(monkeypatch) -> None:
    # It is modelled from entry odds, not money that was staked. Calling it
    # plain ROI on a page aimed at buyers would be a claim we cannot support.
    _install(monkeypatch, _mature())
    record = public_track_record()

    assert "simulatedRoi" in record
    assert "roi" not in record


def test_a_broken_performance_view_does_not_error_the_page(monkeypatch) -> None:
    """The buyer-facing page must never answer with a server error.

    "The record is unavailable" is a much smaller problem than a page that
    looks broken to the person deciding whether to pay.
    """

    def explode(*_args, **_kwargs):
        raise RuntimeError("relation prediction_snapshots does not exist")

    monkeypatch.setattr(track_record, "model_performance", explode)
    record = public_track_record()

    assert record["published"] is False
    assert record["winRate"] is None
    assert record["sampleSize"] == 0
    assert record["confidenceTiers"] == []


def test_the_reason_is_kept_rather_than_swallowed(monkeypatch) -> None:
    # Swallowing it silently would move the mystery rather than remove it.
    def explode(*_args, **_kwargs):
        raise RuntimeError("relation prediction_snapshots does not exist")

    monkeypatch.setattr(track_record, "model_performance", explode)
    public_track_record()

    assert "RuntimeError" in track_record.last_failure()
    assert "prediction_snapshots" in track_record.last_failure()


def test_a_recovery_clears_the_stale_reason(monkeypatch) -> None:
    def explode(*_args, **_kwargs):
        raise RuntimeError("transient")

    monkeypatch.setattr(track_record, "model_performance", explode)
    public_track_record()
    assert track_record.last_failure() != ""

    _install(monkeypatch, _mature())
    public_track_record()

    assert track_record.last_failure() == ""
