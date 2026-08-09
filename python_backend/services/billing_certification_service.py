"""Secret-safe release certification for subscription configuration and delivery."""

from __future__ import annotations

from datetime import datetime, timezone
import os

from database.postgres import database_is_configured, get_database_pool
from services.founding_pro_service import founding_member_limit

EXPECTED_CATALOG = {
    "core": {"monthlyUsd": 24.99, "annualUsd": 249.99, "entitlement": "core_tier"},
    "pro": {"monthlyUsd": 59.99, "annualUsd": 599.99, "entitlement": "edge_tier"},
    "foundingPro": {
        "monthlyUsd": 49.99,
        "annualUsd": 499.99,
        "entitlement": "edge_tier",
        "memberLimit": 100,
    },
    "monthlyTrialDays": 2,
    "annualTrialDays": 7,
}


def _csv_count(name: str) -> int:
    return len({value.strip() for value in os.getenv(name, "").split(",") if value.strip()})


def _delivery_snapshot() -> dict[str, object]:
    result: dict[str, object] = {
        "webhookEventCount": 0,
        "lastWebhookAt": None,
        "foundingActive": 0,
        "foundingReserved": 0,
        "foundingReleased": 0,
    }
    if not database_is_configured():
        return result
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute("select count(*),max(received_at) from billing_webhook_events")
            count, last_received = cursor.fetchone()
            result["webhookEventCount"] = int(count or 0)
            result["lastWebhookAt"] = last_received.isoformat() if last_received else None
            cursor.execute("select status,count(*) from founding_pro_claims group by status")
            for status, status_count in cursor.fetchall():
                key = {
                    "active": "foundingActive",
                    "reserved": "foundingReserved",
                    "released": "foundingReleased",
                }.get(str(status).lower())
                if key:
                    result[key] = int(status_count or 0)
    except Exception as exc:
        result["databaseError"] = type(exc).__name__
    return result


def billing_release_certification() -> dict[str, object]:
    """Return a truthful release gate without returning product IDs or secrets."""
    core_products = _csv_count("REVENUECAT_CORE_PRODUCT_IDS")
    pro_products = _csv_count("REVENUECAT_EDGE_PRODUCT_IDS")
    founding_products = _csv_count("REVENUECAT_FOUNDING_PRODUCT_IDS")
    webhook_configured = bool(os.getenv("REVENUECAT_WEBHOOK_SECRET", "").strip())
    public_key_configured = bool(os.getenv("REVENUECAT_PUBLIC_API_KEY", "").strip())
    external_verified = os.getenv("BILLING_CATALOG_VERIFIED", "").strip().lower() == "true"
    external_verified_at = os.getenv("BILLING_CATALOG_VERIFIED_AT", "").strip() or None
    limit = founding_member_limit()
    delivery = _delivery_snapshot()
    checks: list[dict[str, object]] = []

    def add(key: str, label: str, passed: bool, detail: str, *, warning: bool = False, value: object = None) -> None:
        checks.append({
            "key": key,
            "label": label,
            "status": "PASS" if passed else "WARN" if warning else "FAIL",
            "detail": detail,
            "value": value,
        })

    add("webhook_auth", "Webhook authentication", webhook_configured,
        "RevenueCat webhook authentication is configured." if webhook_configured else "REVENUECAT_WEBHOOK_SECRET is missing.")
    add("public_billing_key", "Web billing key", public_key_configured,
        "The production web billing key is configured." if public_key_configured else "REVENUECAT_PUBLIC_API_KEY is missing from the web deployment.")
    for key, label, count in (
        ("core_packages", "Core monthly + annual products", core_products),
        ("pro_packages", "Pro monthly + annual products", pro_products),
        ("founding_packages", "Founding Pro monthly + annual products", founding_products),
    ):
        add(key, label, count >= 2,
            f"{count} distinct product mapping(s) configured; monthly and annual require at least 2.", value=f"{count}/2")
    add("founding_cap", "Founding Pro cap", limit == 100,
        f"The server-enforced founding-member limit is {limit}; the published limit is 100.", value=limit)
    webhook_count = int(delivery["webhookEventCount"])
    add("webhook_delivery", "Webhook delivery", webhook_count > 0,
        "At least one signed billing event has reached production." if webhook_count else "No signed billing event has been recorded yet; run a sandbox and low-value live purchase.",
        warning=True, value=webhook_count)
    add("checkout_terms", "Stripe / RevenueCat checkout terms", external_verified,
        (f"External checkout prices and trials were certified at {external_verified_at or 'an unrecorded time'}."
         if external_verified else
         "Dashboard prices and trials still require recorded external verification: monthly 2 days, annual 7 days, Core $24.99, Pro $59.99, Founding Pro $49.99."),
        warning=True, value=external_verified_at)
    failures = sum(check["status"] == "FAIL" for check in checks)
    warnings = sum(check["status"] == "WARN" for check in checks)
    passes = len(checks) - failures - warnings
    status = "FAIL" if failures else "WARN" if warnings else "PASS"
    return {
        "status": status,
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "passCount": passes,
        "warningCount": warnings,
        "failureCount": failures,
        "checks": checks,
        "expectedCatalog": EXPECTED_CATALOG,
        "delivery": delivery,
        "releaseReady": status == "PASS",
        "note": "Prices and trial durations are verified externally only after BILLING_CATALOG_VERIFIED=true is recorded following dashboard checkout tests.",
    }