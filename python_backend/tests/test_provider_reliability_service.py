from datetime import datetime, timedelta, timezone

from services.provider_reliability_service import (
    build_provider_reliability,
    provider_key,
)


def _prop(
    *,
    provider: str,
    event: str,
    starts_in_hours: int,
    updated_minutes_ago: int,
    category: str = "HITS",
) -> dict[str, object]:
    now = datetime(2026, 8, 8, 18, tzinfo=timezone.utc)
    return {
        "sportsbook": provider,
        "eventId": event,
        "sport": "MLB",
        "category": category,
        "startTimeUtc": (now + timedelta(hours=starts_in_hours)).isoformat(),
        "lastUpdatedUtc": (
            now - timedelta(minutes=updated_minutes_ago)
        ).isoformat(),
    }


def test_provider_aliases_are_stable() -> None:
    assert provider_key("betr_us_dfs") == "BETR"
    assert provider_key("Prize Picks") == "PRIZEPICKS"
    assert provider_key("pick-6") == "PICK6"


def test_three_day_report_tracks_freshness_and_expected_providers() -> None:
    now = datetime(2026, 8, 8, 18, tzinfo=timezone.utc)
    report = build_provider_reliability(
        [
            _prop(
                provider="PrizePicks",
                event="today",
                starts_in_hours=3,
                updated_minutes_ago=4,
            ),
            _prop(
                provider="DraftKings",
                event="tomorrow",
                starts_in_hours=27,
                updated_minutes_ago=70,
            ),
            _prop(
                provider="DraftKings",
                event="too-far",
                starts_in_hours=80,
                updated_minutes_ago=1,
            ),
        ],
        expected_sites=("prizepicks", "draftkings", "underdog"),
        now_utc=now,
        horizon_days=3,
        stale_after_minutes=45,
    )

    assert report["status"] == "DEGRADED"
    assert report["totalProps"] == 2
    assert report["eventCount"] == 2
    assert report["providerCount"] == 2
    assert report["expectedProviderCount"] == 3
    assert report["providerCoveragePercent"] == 67
    assert report["latestAgeMinutes"] == 4
    assert report["staleProviderCount"] == 1
    assert report["missingProviderCount"] == 1
    assert report["recoveryRecommended"] is True
    assert [day["propCount"] for day in report["days"]] == [1, 1, 0]
    rows = {row["provider"]: row for row in report["providers"]}
    assert rows["PRIZEPICKS"]["status"] == "LIVE"
    assert rows["DRAFTKINGS"]["status"] == "STALE"
    assert rows["UNDERDOG"]["status"] == "MISSING"


def test_empty_three_day_report_requests_recovery() -> None:
    report = build_provider_reliability(
        [],
        expected_sites=("prizepicks",),
        now_utc=datetime(2026, 8, 8, tzinfo=timezone.utc),
    )
    assert report["status"] == "EMPTY"
    assert report["recoveryRecommended"] is True
