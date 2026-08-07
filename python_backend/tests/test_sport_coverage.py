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
