"""Resolve verified RevenueCat events into application subscription tiers."""

import hashlib
import os

from database.postgres import database_is_configured, get_database_pool


def has_event_identity(event: dict[str, object]) -> bool:
    event_id = str(event.get("id") or "").strip()
    timestamp = event.get("event_timestamp_ms")
    return bool(event_id) and isinstance(timestamp, int) and not isinstance(timestamp, bool) and timestamp > 0


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
    event_id = str(event.get("id") or "").strip()
    event_timestamp_ms = event.get("event_timestamp_ms")
    tier = tier_from_event(event)
    if not user_id or not has_event_identity(event) or tier is None:
        return {"updated": False, "reason": "Event has no recognized user or tier"}
    if not database_is_configured():
        return {"updated": False, "reason": "DATABASE_URL is not configured", "tier": tier}
    event_fingerprint = hashlib.sha256(
        f"{event_id}:{user_id}:{event_timestamp_ms}:{tier}".encode("utf-8")
    ).hexdigest()
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """insert into billing_webhook_events(provider,event_id,event_fingerprint,app_user_id,event_timestamp_ms)
            values('revenuecat',%s,%s,%s,%s) on conflict(provider,event_id) do nothing returning event_id""",
            (event_id, event_fingerprint, user_id, event_timestamp_ms),
        )
        if cursor.fetchone() is None:
            connection.commit()
            return {"updated": False, "duplicate": True, "tier": tier}
        cursor.execute("""insert into user_profiles(
                id,subscription_tier,is_premium,subscription_event_at,updated_at)
            values(%s,%s,%s,to_timestamp(%s / 1000.0),now()) on conflict(id) do update set
            subscription_tier=excluded.subscription_tier,
            is_premium=excluded.is_premium,
            subscription_event_at=excluded.subscription_event_at,
            updated_at=now()
            where user_profiles.subscription_event_at is null
               or user_profiles.subscription_event_at <= excluded.subscription_event_at
            returning id""",
            (user_id, tier, tier == "edge", event_timestamp_ms))
        updated = cursor.fetchone() is not None
        connection.commit()
    return {"updated": updated, "stale": not updated, "tier": tier, "userId": user_id}
