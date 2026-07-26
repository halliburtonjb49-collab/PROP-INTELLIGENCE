from contextlib import contextmanager

from services import subscription_service
from services.subscription_service import (
    apply_subscription_event,
    has_event_identity,
    tier_from_event,
)


def test_edge_entitlement_wins() -> None:
    assert tier_from_event({"type": "RENEWAL", "entitlement_ids": ["core_tier", "edge_tier"]}) == "edge"


def test_core_entitlement_maps_to_core() -> None:
    assert tier_from_event({"type": "INITIAL_PURCHASE", "entitlement_ids": ["core_tier"]}) == "core"


def test_expiration_removes_access() -> None:
    assert tier_from_event({"type": "EXPIRATION", "entitlement_ids": ["edge_tier"]}) == "free"


def test_cancellation_preserves_access_until_expiration() -> None:
    assert tier_from_event({
        "type": "CANCELLATION",
        "entitlement_ids": ["edge_tier"],
    }) == "edge"


def test_failed_payment_preserves_access_during_provider_grace_period() -> None:
    assert tier_from_event({
        "type": "BILLING_ISSUE",
        "entitlement_ids": ["core_tier"],
    }) == "core"


def test_unknown_product_does_not_grant_access() -> None:
    assert tier_from_event({"type": "INITIAL_PURCHASE", "product_id": "unknown"}) is None


def test_webhook_identity_requires_positive_integer_timestamp() -> None:
    assert has_event_identity({"id": "event-id", "event_timestamp_ms": 1}) is True
    assert has_event_identity({"id": "event-id", "event_timestamp_ms": True}) is False
    assert has_event_identity({"id": "event-id", "event_timestamp_ms": 0}) is False
    assert has_event_identity({"id": "", "event_timestamp_ms": 1}) is False


def test_subscription_lifecycle_rejects_duplicates_and_stale_events(
    monkeypatch,
) -> None:
    state = {"event_ids": set(), "tier": None, "timestamp": None}

    class Cursor:
        def __init__(self):
            self.result = None

        def execute(self, query, params):
            if "billing_webhook_events" in query:
                event_id = params[0]
                if event_id in state["event_ids"]:
                    self.result = None
                else:
                    state["event_ids"].add(event_id)
                    self.result = (event_id,)
                return
            user_id, tier, _is_premium, timestamp = params
            if state["timestamp"] is None or state["timestamp"] <= timestamp:
                state["tier"] = tier
                state["timestamp"] = timestamp
                self.result = (user_id,)
            else:
                self.result = None

        def fetchone(self):
            return self.result

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

    class Connection:
        def cursor(self):
            return Cursor()

        def commit(self):
            return None

    class Pool:
        @contextmanager
        def connection(self):
            yield Connection()

    monkeypatch.setattr(subscription_service, "database_is_configured", lambda: True)
    monkeypatch.setattr(subscription_service, "get_database_pool", Pool)

    def event(event_id, timestamp, event_type, entitlement):
        return {
            "id": event_id,
            "event_timestamp_ms": timestamp,
            "type": event_type,
            "app_user_id": "test-user",
            "entitlement_ids": [entitlement],
        }

    assert apply_subscription_event(
        event("core", 100, "INITIAL_PURCHASE", "core_tier")
    )["tier"] == "core"
    assert apply_subscription_event(
        event("edge", 200, "PRODUCT_CHANGE", "edge_tier")
    )["tier"] == "edge"
    assert apply_subscription_event(
        event("cancel", 300, "CANCELLATION", "edge_tier")
    )["tier"] == "edge"
    assert apply_subscription_event(
        event("failure", 400, "BILLING_ISSUE", "edge_tier")
    )["tier"] == "edge"

    stale = apply_subscription_event(
        event("late-core", 150, "RENEWAL", "core_tier")
    )
    assert stale["stale"] is True
    assert state["tier"] == "edge"

    duplicate = apply_subscription_event(
        event("failure", 400, "BILLING_ISSUE", "edge_tier")
    )
    assert duplicate["duplicate"] is True

    expiration = apply_subscription_event(
        event("expired", 500, "EXPIRATION", "edge_tier")
    )
    assert expiration["tier"] == "free"
    assert state["tier"] == "free"
