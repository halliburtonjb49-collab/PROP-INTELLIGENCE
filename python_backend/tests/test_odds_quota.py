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
