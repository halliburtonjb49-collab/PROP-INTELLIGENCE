"""Consolidated, secret-safe production acceptance health snapshot."""

from datetime import datetime, timezone
import os

from database.postgres import database_is_configured, get_database_pool
from services.distributed_cache_service import get_json as get_distributed_json
from services.odds_service import quota_snapshot
from services.prop_catalog_snapshot_service import catalog_snapshot_metadata


_PROP_CATALOG_SUMMARY_KEY = "props:catalog:summary:v1"


def _parse_timestamp(value: str) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def _webhook_delivery_snapshot() -> dict[str, object]:
    if not database_is_configured():
        return {"verified": False, "eventCount": 0, "lastReceivedAt": None}
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                "select count(*),max(received_at) from billing_webhook_events"
            )
            count, last_received = cursor.fetchone()
        return {
            "verified": int(count or 0) > 0,
            "eventCount": int(count or 0),
            "lastReceivedAt": (
                last_received.isoformat() if last_received is not None else None
            ),
        }
    except Exception:
        return {"verified": False, "eventCount": 0, "lastReceivedAt": None}


def production_acceptance_snapshot(now: datetime | None = None) -> dict[str, object]:
    generated_at = now or datetime.now(timezone.utc)
    # Release automation calls this route while customers are using the API.
    # Loading the complete provider catalog (and then the full PostgreSQL gzip
    # fallback) here duplicated tens of thousands of rows in the web process.
    # On Render that could exhaust the instance and make the *health check*
    # restart the API, interrupting the mobile board with a 502. Publication
    # already records the only facts this gate needs in a tiny Redis summary.
    summary = get_distributed_json(_PROP_CATALOG_SUMMARY_KEY)
    if not isinstance(summary, dict):
        summary = {}
    total_props = int(summary.get("count") or 0)
    freshest = _parse_timestamp(str(summary.get("lastDataUpdatedAt") or ""))
    snapshot = catalog_snapshot_metadata() if total_props <= 0 else {}
    if total_props <= 0 and snapshot.get("exists") is True:
        total_props = int(snapshot.get("propCount") or 0)
        freshest = _parse_timestamp(str(snapshot.get("dataUpdatedAt") or ""))
    sports = summary.get("sportCounts")
    books = summary.get("sportsbookCounts")
    age_minutes = (
        max(0, int((generated_at - freshest).total_seconds() // 60))
        if freshest else None
    )
    stale_threshold = max(5, int(os.getenv("PROP_FEED_STALE_MINUTES", "45")))
    quota = quota_snapshot()

    webhook_configured = bool(os.getenv("REVENUECAT_WEBHOOK_SECRET", "").strip())
    core_configured = bool(os.getenv("REVENUECAT_CORE_PRODUCT_IDS", "").strip())
    edge_configured = bool(os.getenv("REVENUECAT_EDGE_PRODUCT_IDS", "").strip())
    founding_configured = bool(os.getenv("REVENUECAT_FOUNDING_PRODUCT_IDS", "").strip())
    webhook_delivery = _webhook_delivery_snapshot()

    issues: list[dict[str, str]] = []
    if total_props <= 0:
        issues.append({"severity": "critical", "code": "feed_empty", "message": "The production prop feed is empty."})
    elif age_minutes is None or age_minutes > stale_threshold:
        issues.append({"severity": "critical", "code": "feed_stale", "message": f"The prop feed is older than {stale_threshold} minutes."})
    if quota.get("lowQuota") is True:
        issues.append({"severity": "warning", "code": "quota_low", "message": "The odds provider quota is running low."})
    if not webhook_configured:
        issues.append({"severity": "critical", "code": "webhook_unconfigured", "message": "RevenueCat webhook authentication is not configured."})
    if not core_configured or not edge_configured:
        issues.append({"severity": "critical", "code": "products_unconfigured", "message": "Core or Pro billing product mapping is not configured."})
    if not founding_configured:
        issues.append({"severity": "critical", "code": "founding_cap_unconfigured", "message": "Founding Pro product mapping is not configured; the member cap cannot be enforced."})

    status = "critical" if any(i["severity"] == "critical" for i in issues) else "warning" if issues else "healthy"
    return {
        "status": status,
        "generatedAt": generated_at.isoformat(),
        "issues": issues,
        "propFeed": {
            "total": total_props,
            "sports": dict(sorted(sports.items())) if isinstance(sports, dict) else {},
            "books": dict(sorted(books.items())) if isinstance(books, dict) else {},
            "freshestAt": freshest.isoformat() if freshest else None,
            "ageMinutes": age_minutes,
            "staleAfterMinutes": stale_threshold,
            "healthy": total_props > 0 and age_minutes is not None and age_minutes <= stale_threshold,
        },
        "providerQuota": quota,
        "billing": {
            "webhookConfigured": webhook_configured,
            "coreProductsConfigured": core_configured,
            "edgeProductsConfigured": edge_configured,
            "foundingProductsConfigured": founding_configured,
            "webhookDeliveryVerified": webhook_delivery["verified"],
            "webhookEventCount": webhook_delivery["eventCount"],
            "lastWebhookReceivedAt": webhook_delivery["lastReceivedAt"],
            "note": "Configuration is verified here; delivery is verified by a successful test or purchase event.",
        },
    }
