from services.subscription_service import has_event_identity, tier_from_event


def test_edge_entitlement_wins() -> None:
    assert tier_from_event({"type": "RENEWAL", "entitlement_ids": ["core_tier", "edge_tier"]}) == "edge"


def test_core_entitlement_maps_to_core() -> None:
    assert tier_from_event({"type": "INITIAL_PURCHASE", "entitlement_ids": ["core_tier"]}) == "core"


def test_expiration_removes_access() -> None:
    assert tier_from_event({"type": "EXPIRATION", "entitlement_ids": ["edge_tier"]}) == "free"


def test_unknown_product_does_not_grant_access() -> None:
    assert tier_from_event({"type": "INITIAL_PURCHASE", "product_id": "unknown"}) is None


def test_webhook_identity_requires_positive_integer_timestamp() -> None:
    assert has_event_identity({"id": "event-id", "event_timestamp_ms": 1}) is True
    assert has_event_identity({"id": "event-id", "event_timestamp_ms": True}) is False
    assert has_event_identity({"id": "event-id", "event_timestamp_ms": 0}) is False
    assert has_event_identity({"id": "", "event_timestamp_ms": 1}) is False
