from datetime import datetime, timezone
from types import SimpleNamespace

from services import acceptance_service


def test_acceptance_snapshot_reports_healthy_feed(monkeypatch):
    now = datetime(2026, 7, 18, 16, 0, tzinfo=timezone.utc)
    monkeypatch.setattr(acceptance_service, "get_props", lambda: [
        SimpleNamespace(sport="NBA", sportsbook="DRAFTKINGS", lastUpdatedUtc="2026-07-18T15:50:00Z"),
        SimpleNamespace(sport="MLB", sportsbook="FANDUEL", lastUpdatedUtc="2026-07-18T15:55:00Z"),
    ])
    monkeypatch.setattr(acceptance_service, "quota_snapshot", lambda: {"remaining": 800, "lowQuota": False})
    monkeypatch.setattr(
        acceptance_service,
        "_webhook_delivery_snapshot",
        lambda: {
            "verified": True,
            "eventCount": 2,
            "lastReceivedAt": "2026-07-18T15:40:00+00:00",
        },
    )
    monkeypatch.setenv("REVENUECAT_WEBHOOK_SECRET", "configured")
    monkeypatch.setenv("REVENUECAT_CORE_PRODUCT_IDS", "core")
    monkeypatch.setenv("REVENUECAT_EDGE_PRODUCT_IDS", "edge")

    result = acceptance_service.production_acceptance_snapshot(now)

    assert result["status"] == "healthy"
    assert result["propFeed"]["total"] == 2
    assert result["propFeed"]["ageMinutes"] == 5
    assert result["billing"]["webhookDeliveryVerified"] is True
    assert result["billing"]["webhookEventCount"] == 2


def test_acceptance_snapshot_alerts_on_empty_feed_and_missing_billing(monkeypatch):
    monkeypatch.setattr(acceptance_service, "get_props", lambda: [])
    monkeypatch.setattr(acceptance_service, "quota_snapshot", lambda: {"remaining": 5, "lowQuota": True})
    monkeypatch.setattr(
        acceptance_service,
        "_webhook_delivery_snapshot",
        lambda: {"verified": False, "eventCount": 0, "lastReceivedAt": None},
    )
    monkeypatch.delenv("REVENUECAT_WEBHOOK_SECRET", raising=False)
    monkeypatch.delenv("REVENUECAT_CORE_PRODUCT_IDS", raising=False)
    monkeypatch.delenv("REVENUECAT_EDGE_PRODUCT_IDS", raising=False)

    result = acceptance_service.production_acceptance_snapshot()

    assert result["status"] == "critical"
    assert {issue["code"] for issue in result["issues"]} == {
        "feed_empty", "quota_low", "webhook_unconfigured", "products_unconfigured"
    }
