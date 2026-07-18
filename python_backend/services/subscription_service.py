"""Resolve verified RevenueCat events into application subscription tiers."""

import os

from database.postgres import database_is_configured, get_database_pool


def tier_from_event(event: dict[str, object]) -> str | None:
    event_type = str(event.get("type") or "").upper()
    if event_type == "EXPIRATION":
        return "free"
    entitlements = {str(value) for value in (event.get("entitlement_ids") or [])}
    if "edge_tier" in entitlements:
        return "edge"
    if "core_tier" in entitlements:
        return "core"
    product_id = str(event.get("product_id") or "")
    edge_products = {value.strip() for value in os.getenv("REVENUECAT_EDGE_PRODUCT_IDS", "").split(",") if value.strip()}
    core_products = {value.strip() for value in os.getenv("REVENUECAT_CORE_PRODUCT_IDS", "").split(",") if value.strip()}
    if product_id in edge_products:
        return "edge"
    if product_id in core_products:
        return "core"
    return None


def apply_subscription_event(event: dict[str, object]) -> dict[str, object]:
    user_id = str(event.get("app_user_id") or "").strip()
    tier = tier_from_event(event)
    if not user_id or tier is None:
        return {"updated": False, "reason": "Event has no recognized user or tier"}
    if not database_is_configured():
        return {"updated": False, "reason": "DATABASE_URL is not configured", "tier": tier}
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""update user_profiles set subscription_tier=%s,is_premium=%s,updated_at=now()
            where id=%s returning id""", (tier, tier == "edge", user_id))
        updated = cursor.fetchone() is not None
        connection.commit()
    return {"updated": updated, "tier": tier, "userId": user_id}
