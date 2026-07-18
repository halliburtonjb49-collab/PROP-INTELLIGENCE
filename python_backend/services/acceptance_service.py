"""Consolidated, secret-safe production acceptance health snapshot."""

from collections import Counter
from datetime import datetime, timezone
import os

from services.odds_service import quota_snapshot
from services.prop_service import get_props


def _parse_timestamp(value: str) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def production_acceptance_snapshot(now: datetime | None = None) -> dict[str, object]:
    generated_at = now or datetime.now(timezone.utc)
    props = get_props()
    timestamps = [
        parsed for prop in props
        if (parsed := _parse_timestamp(prop.lastUpdatedUtc)) is not None
    ]
    freshest = max(timestamps) if timestamps else None
    age_minutes = (
        max(0, int((generated_at - freshest).total_seconds() // 60))
        if freshest else None
    )
    stale_threshold = max(5, int(os.getenv("PROP_FEED_STALE_MINUTES", "45")))
    quota = quota_snapshot()

    webhook_configured = bool(os.getenv("REVENUECAT_WEBHOOK_SECRET", "").strip())
    core_configured = bool(os.getenv("REVENUECAT_CORE_PRODUCT_IDS", "").strip())
    edge_configured = bool(os.getenv("REVENUECAT_EDGE_PRODUCT_IDS", "").strip())

    issues: list[dict[str, str]] = []
    if not props:
        issues.append({"severity": "critical", "code": "feed_empty", "message": "The production prop feed is empty."})
    elif age_minutes is None or age_minutes > stale_threshold:
        issues.append({"severity": "critical", "code": "feed_stale", "message": f"The prop feed is older than {stale_threshold} minutes."})
    if quota.get("lowQuota") is True:
        issues.append({"severity": "warning", "code": "quota_low", "message": "The odds provider quota is running low."})
    if not webhook_configured:
        issues.append({"severity": "critical", "code": "webhook_unconfigured", "message": "RevenueCat webhook authentication is not configured."})
    if not core_configured or not edge_configured:
        issues.append({"severity": "critical", "code": "products_unconfigured", "message": "Core or Edge billing product mapping is not configured."})

    status = "critical" if any(i["severity"] == "critical" for i in issues) else "warning" if issues else "healthy"
    return {
        "status": status,
        "generatedAt": generated_at.isoformat(),
        "issues": issues,
        "propFeed": {
            "total": len(props),
            "sports": dict(sorted(Counter(prop.sport for prop in props).items())),
            "books": dict(sorted(Counter(prop.sportsbook for prop in props).items())),
            "freshestAt": freshest.isoformat() if freshest else None,
            "ageMinutes": age_minutes,
            "staleAfterMinutes": stale_threshold,
            "healthy": bool(props) and age_minutes is not None and age_minutes <= stale_threshold,
        },
        "providerQuota": quota,
        "billing": {
            "webhookConfigured": webhook_configured,
            "coreProductsConfigured": core_configured,
            "edgeProductsConfigured": edge_configured,
            "webhookDeliveryVerified": False,
            "note": "Configuration is verified here; delivery is verified by a successful test or purchase event.",
        },
    }
