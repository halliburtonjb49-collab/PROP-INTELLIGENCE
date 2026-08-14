from services import odds_service


def test_quota_headers_are_recorded_and_warn_at_threshold(monkeypatch) -> None:
    monkeypatch.setattr(odds_service, "ODDS_API_LOW_QUOTA_THRESHOLD", 100)
    result = odds_service.record_quota_headers({
        "x-requests-remaining": "75",
        "x-requests-used": "925",
        "x-requests-last": "15",
    })
    assert result["remaining"] == 75
    assert result["used"] == 925
    assert result["lastRequestCost"] == 15
    assert result["lowQuota"] is True


def test_missing_quota_headers_degrade_to_unknown_not_low() -> None:
    result = odds_service.record_quota_headers({})
    assert result["remaining"] is None
    assert result["lowQuota"] is False


def test_quota_guard_preserves_reserve(monkeypatch) -> None:
    monkeypatch.setattr(odds_service, "ODDS_API_QUOTA_RESERVE", 25)
    monkeypatch.setattr(odds_service, "quota_snapshot", lambda: {"remaining": 40})
    assert odds_service.quota_allows(14)["allowed"] is True
    denied = odds_service.quota_allows(16)
    assert denied["allowed"] is False
    assert denied["reserve"] == 25


def test_cost_estimate_multiplies_unique_markets_by_regions(monkeypatch) -> None:
    monkeypatch.setattr(odds_service, "ODDS_REGIONS", "us,us2")
    assert odds_service.estimate_event_odds_cost(["points", "points", "assists"]) == 4


def test_afl_and_nrl_props_use_the_australian_bookmaker_region() -> None:
    assert odds_service.regions_for_sport("aussierules_afl") == "au"
    assert odds_service.regions_for_sport("rugbyleague_nrl") == "au"
    assert odds_service.regions_for_sport("soccer_epl") == odds_service.ODDS_REGIONS
    assert odds_service.estimate_event_odds_cost(
        ["one", "two"], regions="au"
    ) == 2
    assert odds_service.bookmakers_for_sport("aussierules_afl") == (
        odds_service.AU_PROP_BOOKMAKERS_CSV
    )
    assert odds_service.bookmakers_for_sport("rugbyleague_nrl") == (
        odds_service.AU_PROP_BOOKMAKERS_CSV
    )
    assert odds_service.bookmakers_for_sport("americanfootball_nfl") == (
        odds_service.PREFERRED_BOOKMAKERS_CSV
    )


def test_afl_event_request_uses_the_australian_region(monkeypatch) -> None:
    captured: dict[str, object] = {}

    class Response:
        @staticmethod
        def raise_for_status() -> None:
            return None

        @staticmethod
        def json() -> dict[str, object]:
            return {"bookmakers": []}

    def request(_url: str, params: dict[str, object]):
        captured.update(params)
        return Response()

    monkeypatch.setattr(odds_service, "_request_with_failover", request)
    monkeypatch.setattr(odds_service, "record_bookmakers", lambda _payload: None)

    odds_service.fetch_event_odds(
        sport_key="aussierules_afl",
        event_id="event-1",
        markets=["player_disposals_over"],
    )

    assert captured["regions"] == "au"
    assert captured["bookmakers"] == odds_service.AU_PROP_BOOKMAKERS_CSV
