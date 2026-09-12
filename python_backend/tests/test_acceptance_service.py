from datetime import datetime, timezone
import inspect

import main
from services import acceptance_service


def test_acceptance_snapshot_reports_healthy_feed(monkeypatch):
    now = datetime(2026, 7, 18, 16, 0, tzinfo=timezone.utc)
    monkeypatch.setattr(acceptance_service, "get_distributed_json", lambda _key: {
        "count": 2,
        "lastDataUpdatedAt": "2026-07-18T15:55:00Z",
        "sportCounts": {"NBA": 1, "MLB": 1},
        "sportsbookCounts": {"DRAFTKINGS": 1, "FANDUEL": 1},
    })
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
    monkeypatch.setenv("REVENUECAT_FOUNDING_PRODUCT_IDS", "founding")

    result = acceptance_service.production_acceptance_snapshot(now)

    assert result["status"] == "healthy"
    assert result["propFeed"]["total"] == 2
    assert result["propFeed"]["ageMinutes"] == 5
    assert result["billing"]["webhookDeliveryVerified"] is True
    assert result["billing"]["webhookEventCount"] == 2


def test_acceptance_snapshot_alerts_on_empty_feed_and_missing_billing(monkeypatch):
    monkeypatch.setattr(acceptance_service, "get_distributed_json", lambda _key: None)
    monkeypatch.setattr(
        acceptance_service,
        "catalog_snapshot_metadata",
        lambda: {"exists": False},
    )
    monkeypatch.setattr(acceptance_service, "quota_snapshot", lambda: {"remaining": 5, "lowQuota": True})
    monkeypatch.setattr(
        acceptance_service,
        "_webhook_delivery_snapshot",
        lambda: {"verified": False, "eventCount": 0, "lastReceivedAt": None},
    )
    monkeypatch.delenv("REVENUECAT_WEBHOOK_SECRET", raising=False)
    monkeypatch.delenv("REVENUECAT_CORE_PRODUCT_IDS", raising=False)
    monkeypatch.delenv("REVENUECAT_EDGE_PRODUCT_IDS", raising=False)
    monkeypatch.delenv("REVENUECAT_FOUNDING_PRODUCT_IDS", raising=False)

    result = acceptance_service.production_acceptance_snapshot()

    assert result["status"] == "critical"
    assert {issue["code"] for issue in result["issues"]} == {
        "feed_empty",
        "quota_low",
        "webhook_unconfigured",
        "products_unconfigured",
        "founding_cap_unconfigured",
    }


def test_acceptance_snapshot_uses_metadata_fallback_without_loading_catalog(monkeypatch):
    now = datetime(2026, 7, 18, 16, 0, tzinfo=timezone.utc)
    monkeypatch.setattr(acceptance_service, "get_distributed_json", lambda _key: None)
    monkeypatch.setattr(
        acceptance_service,
        "catalog_snapshot_metadata",
        lambda: {
            "exists": True,
            "propCount": 23783,
            "dataUpdatedAt": "2026-07-18T15:58:00+00:00",
        },
    )
    monkeypatch.setattr(acceptance_service, "quota_snapshot", lambda: {"lowQuota": False})
    monkeypatch.setattr(
        acceptance_service,
        "_webhook_delivery_snapshot",
        lambda: {"verified": True, "eventCount": 1, "lastReceivedAt": None},
    )
    monkeypatch.setenv("REVENUECAT_WEBHOOK_SECRET", "configured")
    monkeypatch.setenv("REVENUECAT_CORE_PRODUCT_IDS", "core")
    monkeypatch.setenv("REVENUECAT_EDGE_PRODUCT_IDS", "edge")
    monkeypatch.setenv("REVENUECAT_FOUNDING_PRODUCT_IDS", "founding")

    result = acceptance_service.production_acceptance_snapshot(now)

    assert result["status"] == "healthy"
    assert result["propFeed"]["total"] == 23783
    assert result["propFeed"]["ageMinutes"] == 2


def test_public_operations_probes_never_hydrate_the_complete_catalog():
    acceptance_source = inspect.getsource(
        acceptance_service.production_acceptance_snapshot
    )
    health_source = inspect.getsource(main.prop_feed_health)

    assert "get_props(" not in acceptance_source
    assert "load_catalog_snapshot(" not in acceptance_source
    assert "_cached_prop_catalog(" not in health_source
