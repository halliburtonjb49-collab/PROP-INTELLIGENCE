import hmac
import os

from fastapi import APIRouter, Header, HTTPException

from services.subscription_service import apply_subscription_event, has_event_identity
from services.security_event_service import record_security_event

router = APIRouter(prefix="/api/billing", tags=["billing"])


@router.post("/revenuecat/webhook")
def revenuecat_webhook(payload: dict[str, object], authorization: str = Header(default="")) -> dict[str, object]:
    expected = os.getenv("REVENUECAT_WEBHOOK_SECRET", "").strip()
    supplied = authorization.removeprefix("Bearer ").strip()
    if not expected or not hmac.compare_digest(supplied, expected):
        raise HTTPException(status_code=401, detail="Invalid webhook authorization")
    event = payload.get("event")
    if not isinstance(event, dict):
        raise HTTPException(status_code=422, detail="RevenueCat event is missing")
    if not has_event_identity(event):
        raise HTTPException(status_code=422, detail="RevenueCat event identity is missing")
    result = apply_subscription_event(event)
    record_security_event(
        "subscription_event_applied",
        identity=str(event.get("app_user_id") or event.get("original_app_user_id") or ""),
        route="/api/billing/revenuecat/webhook",
        method="POST",
        outcome="applied",
        metadata={
            "eventType": str(event.get("type") or "")[:80],
            "productId": str(event.get("product_id") or "")[:120],
        },
    )
    return result
