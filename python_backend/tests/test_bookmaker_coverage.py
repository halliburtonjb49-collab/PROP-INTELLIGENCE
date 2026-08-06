from services import odds_service


def _reset():
    odds_service._bookmakers_seen.clear()


def test_a_requested_book_never_returned_is_named(monkeypatch):
    """The difference between "no props today" and "not on our plan".

    The provider omits unknown or uncovered bookmakers without comment, so a
    key can be requested forever and silently produce nothing.
    """

    _reset()
    odds_service.record_bookmakers([
        {"bookmakers": [{"key": "prizepicks", "title": "PrizePicks"}]},
        {"bookmakers": [{"key": "underdog", "title": "Underdog"}]},
    ])

    coverage = odds_service.bookmaker_coverage()

    assert "prizepicks" in coverage["seen"]
    assert "pick6" in coverage["requestedButNeverSeen"]
    assert "prizepicks" not in coverage["requestedButNeverSeen"]


def test_repeat_sightings_accumulate(monkeypatch):
    _reset()
    for _ in range(3):
        odds_service.record_bookmakers([
            {"bookmakers": [{"key": "pick6", "title": "DraftKings Pick6"}]}
        ])

    seen = odds_service.bookmaker_coverage()["seen"]["pick6"]
    assert seen["events"] == 3
    assert seen["title"] == "DraftKings Pick6"
    assert seen["lastSeenAt"] is not None


def test_malformed_responses_are_ignored():
    _reset()
    odds_service.record_bookmakers(None)
    odds_service.record_bookmakers([{"bookmakers": [{"key": ""}]}])
    odds_service.record_bookmakers([{"bookmakers": ["not-a-dict"]}])
    odds_service.record_bookmakers("nonsense")

    # Diagnostics must never be the thing that breaks a provider fetch.
    assert odds_service.bookmaker_coverage()["seen"] == {}


def test_a_single_event_payload_is_accepted():
    _reset()
    odds_service.record_bookmakers({"bookmakers": [{"key": "fanduel"}]})
    assert "fanduel" in odds_service.bookmaker_coverage()["seen"]
