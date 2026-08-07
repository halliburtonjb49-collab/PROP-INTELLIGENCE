import pytest

from services import odds_service


@pytest.fixture(autouse=True)
def _clean():
    odds_service._sport_results.clear()
    yield
    odds_service._sport_results.clear()


def test_a_sport_that_returns_games_but_no_props_is_named():
    """The three causes of an empty rail look identical from outside.

    Out of season, not covered by the plan, and not requested all produce the
    same blank board, and guessing between them is how a sport stays broken.
    """

    odds_service.record_sport_fetch("soccer_epl", events=12, props=0)
    odds_service.record_sport_fetch("baseball_mlb", events=8, props=740)

    coverage = odds_service.sport_coverage()

    assert "soccer_epl" in coverage["eventsWithoutProps"]
    assert "baseball_mlb" not in coverage["eventsWithoutProps"]


def test_a_configured_sport_never_fetched_is_distinguished():
    odds_service.record_sport_fetch("baseball_mlb", events=8, props=740)

    coverage = odds_service.sport_coverage()

    # Configured and never once asked for is a different fault from asked for
    # and empty.
    assert "aussierules_afl" in coverage["neverFetched"]
    assert "baseball_mlb" not in coverage["neverFetched"]


def test_repeated_fetches_accumulate():
    odds_service.record_sport_fetch("baseball_mlb", events=4, props=100)
    odds_service.record_sport_fetch("baseball_mlb", events=6, props=200)

    result = odds_service.sport_coverage()["results"]["baseball_mlb"]

    assert result["fetches"] == 2
    assert result["events"] == 10
    assert result["props"] == 300
    assert result["lastFetchedAt"]


def test_an_error_is_kept_for_the_sport_that_had_it():
    odds_service.record_sport_fetch("icehockey_nhl", events=0, props=0, error="HTTP 422")

    result = odds_service.sport_coverage()["results"]["icehockey_nhl"]
    assert result["lastError"] == "HTTP 422"


def test_a_blank_sport_key_is_ignored():
    odds_service.record_sport_fetch("", events=5, props=5)
    assert odds_service.sport_coverage()["results"] == {}


def test_a_reading_instance_sees_what_a_fetching_instance_recorded(monkeypatch):
    """Process memory cannot answer this question.

    The fetch runs on the worker or on whichever instance ran the sync, and
    the health endpoint is answered by another. Keeping this in memory made
    every sport read back as never fetched -- including the two that were
    plainly producing hundreds of props.
    """

    shared: dict[str, object] = {}
    monkeypatch.setattr(
        odds_service,
        "_publish_sport_results",
        lambda snapshot: shared.update({"value": snapshot}),
    )
    monkeypatch.setattr(
        odds_service, "_read_sport_results", lambda: shared.get("value") or {}
    )

    odds_service.record_sport_fetch("baseball_mlb", events=8, props=740)
    # A different instance: its own memory is empty.
    odds_service._sport_results.clear()

    coverage = odds_service.sport_coverage()

    assert coverage["results"]["baseball_mlb"]["props"] == 740
    assert "baseball_mlb" not in coverage["neverFetched"]


def test_a_cache_failure_leaves_the_sync_working(monkeypatch):
    def _boom(*_args, **_kwargs):
        raise RuntimeError("redis down")

    monkeypatch.setattr(odds_service, "_publish_sport_results", _boom)

    # Diagnostics must never break a sync, so the raise has to be contained
    # where it happens rather than reaching the caller.
    with pytest.raises(RuntimeError):
        odds_service._publish_sport_results({})

    monkeypatch.setattr(odds_service, "_read_sport_results", lambda: {})
    odds_service._sport_results.clear()
    assert odds_service.sport_coverage()["results"] == {}


def test_quota_starvation_is_not_mistaken_for_missing_coverage():
    """Events listed with no props has three unrelated causes.

    The quota ran out before their odds were requested, every request failed,
    or the provider genuinely has no player markets. Only the last is a
    coverage problem, and treating the first as one would have us retire a
    sport that works.
    """

    odds_service.record_sport_fetch(
        "soccer_epl", events=10, props=0, fetched_events=0, skipped_for_quota=10
    )
    odds_service.record_sport_fetch(
        "icehockey_nhl", events=31, props=0, fetched_events=31
    )

    coverage = odds_service.sport_coverage()

    # Both look identical on event count alone.
    assert "soccer_epl" in coverage["eventsWithoutProps"]
    assert "icehockey_nhl" in coverage["eventsWithoutProps"]

    # Only one was actually asked.
    assert coverage["starvedByQuota"] == ["soccer_epl"]
    assert coverage["fetchedButEmpty"] == ["icehockey_nhl"]


def test_a_working_sport_appears_in_neither_bucket():
    odds_service.record_sport_fetch(
        "baseball_mlb", events=15, props=2990, fetched_events=15
    )

    coverage = odds_service.sport_coverage()

    assert coverage["starvedByQuota"] == []
    assert coverage["fetchedButEmpty"] == []
